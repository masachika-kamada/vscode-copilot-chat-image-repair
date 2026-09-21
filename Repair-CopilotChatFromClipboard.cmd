@echo off
setlocal
title Repair Copilot Chat Image Attachments
echo Copy the full vision_attachment_not_accessible error before running this file.
echo VS Code Stable and Insiders must be completely closed before repair.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-CopilotChatImageAttachments.ps1" -FromClipboard -Apply
echo.
if errorlevel 1 (
    echo Repair failed. Review the message above.
) else (
    echo Repair finished. You can start VS Code again.
)
pause