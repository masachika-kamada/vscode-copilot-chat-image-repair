<#
.SYNOPSIS
    Removes inaccessible historical image attachments from a Copilot Chat session.

.DESCRIPTION
    Locates a Copilot Chat JSONL session by session ID or Client Request Id,
    replays its request journal, and identifies requests that still contain image
    variables or rendered image URLs.

    By default, the script only reports what it would change. Specify -Apply to create
    and validate a temporary repaired file, then atomically replace the JSONL file.

    Close VS Code before using -Apply. An open VS Code process can overwrite
    the repaired session with its in-memory copy.

.PARAMETER SessionId
    The Copilot Chat session ID. This is normally the JSONL file name without extension.

.PARAMETER ClientRequestId
    The Client Request Id shown in the vision_attachment_not_accessible error.

.PARAMETER ErrorMessage
    The complete error message. The Client Request Id is extracted automatically.

.PARAMETER FromClipboard
    Reads the complete error message or Client Request Id from the clipboard.

.PARAMETER Apply
    Applies the repair. Without this switch, the script performs a dry run.

.PARAMETER KeepBackup
    Keeps a timestamped copy of the original JSONL file. By default, no persistent
    backup is retained.

.PARAMETER StorageRoot
    One or more storage directories to search. By default, the script searches the
    current user's VS Code Stable and Insiders workspace storage directories.

.PARAMETER Force
    Allows the repair while VS Code Stable or Insiders is running. This is not recommended.

.EXAMPLE
    & '.\Repair-CopilotChatImageAttachments.ps1' `
        -SessionId 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'

.EXAMPLE
    & '.\Repair-CopilotChatImageAttachments.ps1' `
        -SessionId 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' -Apply

.EXAMPLE
    & '.\Repair-CopilotChatImageAttachments.ps1' `
        -ClientRequestId '11111111-2222-4333-8444-555555555555' -Apply

.EXAMPLE
    $errorText = Get-Clipboard -Raw
    & '.\Repair-CopilotChatImageAttachments.ps1' `
        -ErrorMessage $errorText -Apply

.EXAMPLE
    & '.\Repair-CopilotChatImageAttachments.ps1' `
        -FromClipboard -Apply
#>

[CmdletBinding(DefaultParameterSetName = 'Clipboard')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Session', Position = 0)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SessionId,

    [Parameter(Mandatory, ParameterSetName = 'ClientRequest')]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ClientRequestId,

    [Parameter(Mandatory, ParameterSetName = 'ErrorMessage', ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string]$ErrorMessage,

    [Parameter(ParameterSetName = 'Clipboard')]
    [switch]$FromClipboard,

    [switch]$Apply,

    [switch]$KeepBackup,

    [string[]]$StorageRoot,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Property {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function Get-RecordKey {
    param([object]$Record)

    if (-not (Test-Property -InputObject $Record -Name 'k') -or $null -eq $Record.k) {
        return ''
    }

    return (@($Record.k) -join '.')
}

function Get-ImageParts {
    param([object[]]$Parts)

    return @($Parts | Where-Object {
        $null -ne $_ -and (Test-Property -InputObject $_ -Name 'imageUrl')
    })
}

function Get-NonImageParts {
    param([object[]]$Parts)

    return @($Parts | Where-Object {
        $null -eq $_ -or -not (Test-Property -InputObject $_ -Name 'imageUrl')
    })
}

function Get-ImageVariables {
    param([object[]]$Variables)

    return @($Variables | Where-Object {
        $null -ne $_ -and (Test-Property -InputObject $_ -Name 'kind') -and $_.kind -eq 'image'
    })
}

function Get-NonImageVariables {
    param([object[]]$Variables)

    return @($Variables | Where-Object {
        $null -eq $_ -or -not (Test-Property -InputObject $_ -Name 'kind') -or $_.kind -ne 'image'
    })
}

function Get-FinalRequests {
    param([Parameter(Mandatory)][string]$Path)

    $requests = @()

    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $record = $line | ConvertFrom-Json
        $key = Get-RecordKey -Record $record

        if ($record.kind -eq 0 -and (Test-Property -InputObject $record -Name 'v')) {
            if ($null -ne $record.v -and (Test-Property -InputObject $record.v -Name 'requests')) {
                $requests = @($record.v.requests)
            }
            continue
        }

        if ($record.kind -eq 2 -and $key -eq 'requests' -and $null -ne $record.v) {
            $values = @($record.v)

            if (Test-Property -InputObject $record -Name 'i') {
                $index = [int]$record.i
                if ($index -lt 0 -or $index -gt $requests.Count) {
                    throw "Invalid requests replacement index $index in $Path."
                }

                $before = if ($index -gt 0) { @($requests[0..($index - 1)]) } else { @() }
                $requests = @($before) + @($values)
            }
            else {
                $requests = @($requests) + @($values)
            }
            continue
        }

        if ($record.kind -eq 1 -and $key -match '^requests\.(\d+)\.result$') {
            $index = [int]$Matches[1]
            if ($index -lt $requests.Count) {
                $requests[$index] | Add-Member -NotePropertyName result -NotePropertyValue $record.v -Force
            }
            continue
        }

        if ($record.kind -eq 1 -and $key -match '^requests\.(\d+)\.result\.metadata\.renderedUserMessage$') {
            $index = [int]$Matches[1]
            if ($index -lt $requests.Count) {
                if (-not (Test-Property -InputObject $requests[$index] -Name 'result')) {
                    $requests[$index] | Add-Member -NotePropertyName result -NotePropertyValue ([pscustomobject]@{})
                }
                if (-not (Test-Property -InputObject $requests[$index].result -Name 'metadata')) {
                    $requests[$index].result | Add-Member -NotePropertyName metadata -NotePropertyValue ([pscustomobject]@{})
                }
                $requests[$index].result.metadata | Add-Member `
                    -NotePropertyName renderedUserMessage -NotePropertyValue $record.v -Force
            }
            continue
        }

        if ($record.kind -eq 1 -and $key -match '^requests\.(\d+)\.variableData\.variables$') {
            $index = [int]$Matches[1]
            if ($index -lt $requests.Count) {
                if (-not (Test-Property -InputObject $requests[$index] -Name 'variableData')) {
                    $requests[$index] | Add-Member -NotePropertyName variableData -NotePropertyValue ([pscustomobject]@{})
                }
                $requests[$index].variableData | Add-Member `
                    -NotePropertyName variables -NotePropertyValue $record.v -Force
            }
        }
    }

    return @($requests)
}

function Get-ClientRequestIdFromText {
    param([Parameter(Mandatory)][string]$Text)

    $idPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $labeledMatch = [regex]::Match(
        $Text,
        "(?im)(?:Client|Copilot)\s+Request\s+Id\s*:\s*(?<id>$idPattern)"
    )
    if ($labeledMatch.Success) {
        return $labeledMatch.Groups['id'].Value
    }

    $trimmed = $Text.Trim()
    if ($trimmed -match "^$idPattern$") {
        return $trimmed
    }

    throw 'The input does not contain a Client Request Id.'
}

function Get-DefaultStorageRoots {
    $roots = @(
        (Join-Path $env:APPDATA 'Code\User\workspaceStorage'),
        (Join-Path $env:APPDATA 'Code - Insiders\User\workspaceStorage'),
        (Join-Path $env:APPDATA 'Code\User\globalStorage\emptyWindowChatSessions'),
        (Join-Path $env:APPDATA 'Code - Insiders\User\globalStorage\emptyWindowChatSessions')
    )

    return @($roots | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
}

function Get-AllSessionFiles {
    param([Parameter(Mandatory)][string[]]$Roots)

    $files = foreach ($root in $Roots) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
            Where-Object { $_.Directory.Name -in @('chatSessions', 'emptyWindowChatSessions') }
    }

    return @($files | Sort-Object FullName -Unique)
}

function Test-ResultHasClientRequestId {
    param(
        [object]$Result,
        [Parameter(Mandatory)][string]$Id
    )

    if ($null -eq $Result) {
        return $false
    }

    $hasMetadata = (Test-Property -InputObject $Result -Name 'metadata') -and $null -ne $Result.metadata
    if ($hasMetadata) {
        $hasMetadataResponseId = $hasMetadata -and
            (Test-Property -InputObject $Result.metadata -Name 'responseId') -and
            $Result.metadata.responseId -eq $Id
        if ($hasMetadataResponseId) {
            return $true
        }
    }

    $hasErrorDetails = (Test-Property -InputObject $Result -Name 'errorDetails') -and $null -ne $Result.errorDetails
    $hasErrorMessage = $hasErrorDetails -and (Test-Property -InputObject $Result.errorDetails -Name 'message')
    if ($hasErrorMessage -and ([string]$Result.errorDetails.message).IndexOf($Id, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return $true
    }

    return $false
}

function Test-SessionFileHasClientRequestId {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Id
    )

    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.IndexOf($Id, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            continue
        }

        $record = $line | ConvertFrom-Json
        $key = Get-RecordKey -Record $record

        if ($record.kind -eq 1 -and $key -match '^requests\.\d+\.result$' -and
            (Test-ResultHasClientRequestId -Result $record.v -Id $Id)) {
            return $true
        }

        if ($record.kind -eq 0 -and $null -ne $record.v -and
            (Test-Property -InputObject $record.v -Name 'requests')) {
            foreach ($request in @($record.v.requests)) {
                if ((Test-Property -InputObject $request -Name 'result') -and
                    (Test-ResultHasClientRequestId -Result $request.result -Id $Id)) {
                    return $true
                }
            }
        }

        if ($record.kind -eq 2 -and $key -eq 'requests') {
            foreach ($request in @($record.v)) {
                if ((Test-Property -InputObject $request -Name 'responseId') -and $request.responseId -eq $Id) {
                    return $true
                }
                if ((Test-Property -InputObject $request -Name 'result') -and
                    (Test-ResultHasClientRequestId -Result $request.result -Id $Id)) {
                    return $true
                }
            }
        }
    }

    return $false
}

if (-not $StorageRoot -or $StorageRoot.Count -eq 0) {
    $StorageRoot = @(Get-DefaultStorageRoots)
}

if ($StorageRoot.Count -eq 0) {
    throw 'No VS Code Stable or Insiders chat storage directory was found.'
}

$invalidRoots = @($StorageRoot | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) })
if ($invalidRoots.Count -gt 0) {
    throw "Storage directory was not found: $($invalidRoots -join ', ')"
}

if ($PSCmdlet.ParameterSetName -eq 'ErrorMessage') {
    $ClientRequestId = Get-ClientRequestIdFromText -Text $ErrorMessage
}
elseif ($PSCmdlet.ParameterSetName -eq 'Clipboard') {
    if (-not (Get-Command Get-Clipboard -ErrorAction SilentlyContinue)) {
        throw 'Get-Clipboard is not available. Use -ErrorMessage or -ClientRequestId instead.'
    }
    $clipboardText = Get-Clipboard -Raw
    $ClientRequestId = Get-ClientRequestIdFromText -Text ([string]$clipboardText)
}

if ($PSCmdlet.ParameterSetName -eq 'Session') {
    $sessionFiles = @(Get-AllSessionFiles -Roots $StorageRoot |
        Where-Object { $_.BaseName -eq $SessionId })
}
else {
    Write-Host "Searching for Client Request Id: $ClientRequestId"
    $textMatches = @(Get-AllSessionFiles -Roots $StorageRoot |
        Select-String -SimpleMatch $ClientRequestId -List |
        ForEach-Object { Get-Item -LiteralPath $_.Path })

    $sessionFiles = @($textMatches | Where-Object {
        Test-SessionFileHasClientRequestId -Path $_.FullName -Id $ClientRequestId
    })
}

if ($sessionFiles.Count -eq 0) {
    if ($PSCmdlet.ParameterSetName -eq 'Session') {
        throw "Session $SessionId was not found under: $($StorageRoot -join ', ')"
    }
    throw "No original failed session was found for Client Request Id $ClientRequestId."
}

if ($sessionFiles.Count -gt 1) {
    $paths = $sessionFiles.FullName -join [Environment]::NewLine
    throw "More than one original failed session was found. Use -SessionId or specify -StorageRoot more narrowly:$([Environment]::NewLine)$paths"
}

$sessionPath = $sessionFiles[0].FullName
$requests = @(Get-FinalRequests -Path $sessionPath)
$targets = @()

for ($index = 0; $index -lt $requests.Count; $index++) {
    $request = $requests[$index]
    $renderedParts = @()
    $variables = @()

    $hasResult = (Test-Property -InputObject $request -Name 'result') -and $null -ne $request.result
    $hasMetadata = $hasResult -and (Test-Property -InputObject $request.result -Name 'metadata') -and $null -ne $request.result.metadata
    $hasRenderedMessage = $hasMetadata -and (Test-Property -InputObject $request.result.metadata -Name 'renderedUserMessage')
    if ($hasRenderedMessage) {
        $renderedParts = @($request.result.metadata.renderedUserMessage)
    }

    $hasVariableData = (Test-Property -InputObject $request -Name 'variableData') -and $null -ne $request.variableData
    $hasVariables = $hasVariableData -and (Test-Property -InputObject $request.variableData -Name 'variables')
    if ($hasVariables) {
        $variables = @($request.variableData.variables)
    }

    $imageParts = @(Get-ImageParts -Parts $renderedParts)
    $imageVariables = @(Get-ImageVariables -Variables $variables)

    if ($imageParts.Count -eq 0 -and $imageVariables.Count -eq 0) {
        continue
    }

    $urls = @($imageParts | ForEach-Object {
        if ($null -ne $_.imageUrl -and (Test-Property -InputObject $_.imageUrl -Name 'url')) {
            [string]$_.imageUrl.url
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $targets += [pscustomobject]@{
        Index          = $index
        RequestId      = if (Test-Property -InputObject $request -Name 'requestId') { $request.requestId } else { '' }
        ImageParts     = $imageParts.Count
        ImageVariables = $imageVariables.Count
        Urls           = $urls -join ', '
        TextParts      = @(Get-NonImageParts -Parts $renderedParts)
        Variables      = @(Get-NonImageVariables -Variables $variables)
    }
}

Write-Host "Session file: $sessionPath"
Write-Host "Requests: $($requests.Count)"
Write-Host "Requests containing images: $($targets.Count)"

if ($targets.Count -eq 0) {
    Write-Host 'No image attachments need repair.'
    return
}

$targets | Select-Object Index, RequestId, ImageParts, ImageVariables | Format-Table -AutoSize

if (-not $Apply) {
    Write-Host 'Dry run only. Close VS Code, then run again with -Apply to repair the session.'
    return
}

if (-not $Force) {
    $runningCode = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in @('Code', 'Code - Insiders')
    })

    if ($runningCode.Count -gt 0) {
        throw 'VS Code is running. Close every VS Code Stable and Insiders window before using -Apply.'
    }
}

$repairRecords = @()
foreach ($target in $targets) {
    $repairRecords += [ordered]@{
        kind = 1
        k    = @('requests', $target.Index, 'result', 'metadata', 'renderedUserMessage')
        v    = @($target.TextParts)
    }
    $repairRecords += [ordered]@{
        kind = 1
        k    = @('requests', $target.Index, 'variableData', 'variables')
        v    = @($target.Variables)
    }
}

$jsonLines = @($repairRecords | ForEach-Object {
    $_ | ConvertTo-Json -Compress -Depth 100
})

$sessionDirectory = Split-Path -Parent $sessionPath
$temporaryPath = Join-Path $sessionDirectory ('.repair-' + [guid]::NewGuid().ToString('N') + '.jsonl.tmp')
$backupPath = if ($KeepBackup) {
    "$sessionPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}
else {
    $null
}
$replacementBackupPath = if ($KeepBackup) {
    $backupPath
}
else {
    Join-Path $sessionDirectory ('.repair-' + [guid]::NewGuid().ToString('N') + '.backup.tmp')
}

try {
    Copy-Item -LiteralPath $sessionPath -Destination $temporaryPath

    $fileBytes = [System.IO.File]::ReadAllBytes($temporaryPath)
    $needsLeadingNewline = $fileBytes.Length -gt 0 -and $fileBytes[-1] -ne [byte][char]"`n"
    $prefix = if ($needsLeadingNewline) { [Environment]::NewLine } else { '' }
    $payload = $prefix + ($jsonLines -join [Environment]::NewLine) + [Environment]::NewLine
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::AppendAllText($temporaryPath, $payload, $utf8WithoutBom)

    $remainingRequests = @(Get-FinalRequests -Path $temporaryPath)
    $remainingImages = 0
    foreach ($request in $remainingRequests) {
        $hasResult = (Test-Property -InputObject $request -Name 'result') -and $null -ne $request.result
        $hasMetadata = $hasResult -and (Test-Property -InputObject $request.result -Name 'metadata') -and $null -ne $request.result.metadata
        $hasRenderedMessage = $hasMetadata -and (Test-Property -InputObject $request.result.metadata -Name 'renderedUserMessage')
        if ($hasRenderedMessage) {
            $remainingImages += @(Get-ImageParts -Parts @($request.result.metadata.renderedUserMessage)).Count
        }

        $hasVariableData = (Test-Property -InputObject $request -Name 'variableData') -and $null -ne $request.variableData
        $hasVariables = $hasVariableData -and (Test-Property -InputObject $request.variableData -Name 'variables')
        if ($hasVariables) {
            $remainingImages += @(Get-ImageVariables -Variables @($request.variableData.variables)).Count
        }
    }

    if ($remainingImages -ne 0) {
        throw "Validation found $remainingImages remaining image references. The original session was not changed."
    }

    [System.IO.File]::Replace($temporaryPath, $sessionPath, $replacementBackupPath)
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
    if (-not $KeepBackup -and (Test-Path -LiteralPath $replacementBackupPath)) {
        Remove-Item -LiteralPath $replacementBackupPath -Force
    }
}

if ($KeepBackup) {
    Write-Host "Repair completed. Backup: $backupPath"
}
else {
    Write-Host 'Repair completed. No persistent backup was retained.'
}
Write-Host 'Start VS Code and retry the repaired chat session.'