# VS Code Copilot Chat Image Repair

VS Code Copilot Chat で次のエラーが繰り返され、会話を続けられなくなった場合に、ローカルのチャット履歴から過去の画像添付を除去します。

```text
An image attached earlier in this conversation is no longer accessible, so the request failed.

Reason: Request Failed: 400 {"error":{"message":"one or more attachments was not accessible","code":"vision_attachment_not_accessible"}}
```

このツールは、エラーに表示された `Client Request Id` から元の失敗セッションを特定します。テキストの依頼、応答、ツール実行履歴は維持します。

> [!WARNING]
> VS Code の内部保存形式を変更する非公式な回避策です。失効した画像だけではなく、対象セッション内の **すべての画像添付** を除去します。

[English README](README.md)

## ダウンロード

[最新の Release](https://github.com/masachika-kamada/vscode-copilot-chat-image-repair/releases/latest) から `CopilotChatImageRepair-v1.0.1.zip` をダウンロードします。

## 簡単な使い方

1. VS Code に表示されたエラーメッセージ全文をコピーします。
2. VS Code Stable と VS Code Insiders をすべて終了します。
3. Release の ZIP を展開します。
4. `Repair-CopilotChatFromClipboard.cmd` をダブルクリックします。
5. `Repair completed.` と表示されたら VS Code を起動し、元のチャットを再試行します。

スクリプトは修復候補を一時ファイルへ作成して検証してから、元のセッションと置換します。既定では永続バックアップや一時コピーを残しません。

## PowerShell から使う

ファイルを変更せず、対象セッションと画像件数だけを確認します。

```powershell
& '.\Repair-CopilotChatImageAttachments.ps1' -FromClipboard
```

修復を実行します。

```powershell
& '.\Repair-CopilotChatImageAttachments.ps1' -FromClipboard -Apply
```

元の JSONL ファイルを日時付きで残す場合は、`-KeepBackup` を指定します。

```powershell
& '.\Repair-CopilotChatImageAttachments.ps1' `
  -FromClipboard `
  -Apply `
  -KeepBackup
```

`-KeepBackup` で作成したファイルは VS Code のセッション一覧に表示されず、会話全文や画像データを含む場合があります。データ保持方針に合わせて管理してください。

## 注意事項

- Windows の VS Code Stable / Insiders を対象にしています。
- 修復時は VS Code を完全に終了してください。
- 対象セッション内の画像添付をすべて除去します。
- JSONL は VS Code の内部保存形式であり、将来の更新で動作しなくなる可能性があります。
- 管理者権限、ネットワーク通信、追加の PowerShell モジュールは不要です。

## 関連 Issue

- [microsoft/vscode#253136](https://github.com/microsoft/vscode/issues/253136)
- [microsoft/vscode#268511](https://github.com/microsoft/vscode/issues/268511)
- [microsoft/vscode#325232](https://github.com/microsoft/vscode/issues/325232)

## ライセンス

[MIT](LICENSE)
