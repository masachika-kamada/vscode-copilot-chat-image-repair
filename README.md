# VS Code Copilot Chat Image Repair

[![Test](https://github.com/masachika-kamada/vscode-copilot-chat-image-repair/actions/workflows/test.yml/badge.svg)](https://github.com/masachika-kamada/vscode-copilot-chat-image-repair/actions/workflows/test.yml)

Repair a VS Code Copilot Chat session that is stuck with this error:

```text
An image attached earlier in this conversation is no longer accessible, so the request failed.

Reason: Request Failed: 400 {"error":{"message":"one or more attachments was not accessible","code":"vision_attachment_not_accessible"}}
```

The tool finds the original failed session from its `Client Request Id`, removes historical image attachments, and preserves the text conversation, responses, and tool history.

> [!WARNING]
> This is an unofficial recovery tool that modifies VS Code's internal chat storage. It removes **all image attachments** from the matched session, not only the expired image.

[日本語版 README](README.ja.md)

## Download

Download `CopilotChatImageRepair-v1.0.0.zip` from the [latest release](https://github.com/masachika-kamada/vscode-copilot-chat-image-repair/releases/latest).

## Quick start

1. Copy the complete `vision_attachment_not_accessible` error message from VS Code.
2. Close every VS Code Stable and VS Code Insiders window.
3. Extract the release ZIP.
4. Double-click `Repair-CopilotChatFromClipboard.cmd`.
5. Start VS Code and retry the repaired chat.

The script creates and validates a temporary repaired file before replacing the session. By default, it does not retain a persistent backup or temporary copy.

## PowerShell usage

Preview the target session without changing it:

```powershell
& '.\Repair-CopilotChatImageAttachments.ps1' -FromClipboard
```

Apply the repair:

```powershell
& '.\Repair-CopilotChatImageAttachments.ps1' -FromClipboard -Apply
```

You can also provide the ID directly:

```powershell
& '.\Repair-CopilotChatImageAttachments.ps1' `
  -ClientRequestId '11111111-2222-4333-8444-555555555555' `
  -Apply
```

To keep a timestamped copy of the original JSONL file, add `-KeepBackup`:

```powershell
& '.\Repair-CopilotChatImageAttachments.ps1' `
  -FromClipboard `
  -Apply `
  -KeepBackup
```

The backup does not appear in the VS Code sessions list and may contain the complete conversation and image data. Manage it according to your data-retention requirements.

## How it works

The script:

1. Extracts the `Client Request Id` from the clipboard or command line.
2. Searches VS Code Stable and Insiders chat session storage.
3. Distinguishes the original failed session from chats where the same error was pasted as text.
4. Replays the JSONL mutation log to reconstruct the current request list.
5. Removes image entries from `result.metadata.renderedUserMessage` and `variableData.variables`.
6. Validates the repaired temporary file and atomically replaces the original session.

The script does not use the network and does not require administrator rights or additional PowerShell modules.

## Limitations

- Windows only. The default paths cover VS Code Stable and VS Code Insiders.
- VS Code must be closed while applying the repair.
- Every historical image attachment in the matched session is removed.
- The JSONL format is an internal implementation detail and can change in future VS Code releases.
- Use this tool only when the official options such as starting, forking, compacting, or exporting a session do not solve the problem.

## Development

Run the self-contained test with Windows PowerShell or PowerShell 7:

```powershell
.\tests\Test-Repair.ps1
```

## Related issues

- [microsoft/vscode#253136](https://github.com/microsoft/vscode/issues/253136)
- [microsoft/vscode#268511](https://github.com/microsoft/vscode/issues/268511)
- [microsoft/vscode#325232](https://github.com/microsoft/vscode/issues/325232)

## License

[MIT](LICENSE)
