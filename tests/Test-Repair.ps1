[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$repairScript = Join-Path $repositoryRoot 'Repair-CopilotChatImageAttachments.ps1'
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function New-TestSession {
    param(
        [Parameter(Mandatory)]
        [string]$StorageRoot,

        [Parameter(Mandatory)]
        [string]$SessionId
    )

    $sessionDirectory = Join-Path $StorageRoot 'workspace\chatSessions'
    New-Item -ItemType Directory -Path $sessionDirectory -Force | Out-Null
    $sessionPath = Join-Path $sessionDirectory "$SessionId.jsonl"

    $request = [ordered]@{
        requestId = 'request_test'
        message = [ordered]@{
            text = 'Describe the attached image.'
        }
        variableData = [ordered]@{
            variables = @(
                [ordered]@{
                    kind = 'image'
                    value = [ordered]@{
                        '$base64' = 'dGVzdA=='
                    }
                }
            )
        }
        result = [ordered]@{
            metadata = [ordered]@{
                renderedUserMessage = @(
                    [ordered]@{
                        type = 0
                        text = 'Describe the attached image.'
                    },
                    [ordered]@{
                        type = 1
                        imageUrl = [ordered]@{
                            url = 'https://github.com/github-copilot/chat/attachments/expired-test-image'
                            detail = 'high'
                        }
                    }
                )
            }
        }
    }

    $initialRecord = [ordered]@{
        kind = 0
        v = [ordered]@{
            sessionId = $SessionId
            requests = @($request)
        }
    }

    $json = $initialRecord | ConvertTo-Json -Compress -Depth 100
    [System.IO.File]::WriteAllText($sessionPath, $json + [Environment]::NewLine, $utf8WithoutBom)
    return $sessionDirectory
}

function Test-RepairMode {
    param(
        [Parameter(Mandatory)]
        [string]$TestRoot,

        [Parameter(Mandatory)]
        [bool]$KeepBackup
    )

    $sessionId = [guid]::NewGuid().ToString()
    $modeName = if ($KeepBackup) { 'KeepBackup' } else { 'Default' }
    $storageRoot = Join-Path $TestRoot $modeName
    $sessionDirectory = New-TestSession -StorageRoot $storageRoot -SessionId $sessionId

    $arguments = @{
        SessionId = $sessionId
        StorageRoot = $storageRoot
        Apply = $true
        Force = $true
    }
    if ($KeepBackup) {
        $arguments.KeepBackup = $true
    }

    & $repairScript @arguments

    $postRepairOutput = & $repairScript `
        -SessionId $sessionId `
        -StorageRoot $storageRoot 6>&1 | Out-String

    Assert-True `
        -Condition $postRepairOutput.Contains('No image attachments need repair.') `
        -Message "$modeName repair left image attachments in the reconstructed session."

    $backupCount = @(Get-ChildItem -LiteralPath $sessionDirectory -File -Filter '*.backup-*').Count
    $expectedBackupCount = if ($KeepBackup) { 1 } else { 0 }
    Assert-True `
        -Condition ($backupCount -eq $expectedBackupCount) `
        -Message "$modeName repair created $backupCount persistent backups; expected $expectedBackupCount."

    $temporaryCount = @(Get-ChildItem -LiteralPath $sessionDirectory -File -Filter '.repair-*').Count
    Assert-True `
        -Condition ($temporaryCount -eq 0) `
        -Message "$modeName repair left $temporaryCount temporary files."
}

if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) {
    throw "Repair script was not found: $repairScript"
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('copilot-chat-image-repair-test-' + [guid]::NewGuid())
try {
    Test-RepairMode -TestRoot $testRoot -KeepBackup $false
    Test-RepairMode -TestRoot $testRoot -KeepBackup $true
    Write-Host 'All repair tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
