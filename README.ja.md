# wmv

[English version is here](README.md)

マウスの**ミドルボタン**を押しながらドラッグすると任意のウインドウを移動でき、**Shift＋ミドルドラッグ**でサイズ変更できる Windows 用の常駐アプリです。移動に修飾キーは不要です。

PowerToys の「Grab and Move」モジュール（Alt＋左ドラッグ）の代替として作成しています。

## 機能

- **移動**: ウインドウ上の任意の位置でミドルボタンを押してドラッグすると、カーソル直下のトップレベルウインドウが移動します。
- **サイズ変更**: Shift を押しながらミドルドラッグします。掴んだ位置に最も近い辺または角（8 方向）がカーソルに追従し、反対側の辺は固定されます。最小サイズは 150×50px です。
- **通常のミドルクリックはそのまま使えます**: OS のドラッグ閾値（`SM_CXDRAG` / `SM_CYDRAG`、既定 4px）を超えずに離した場合は、ミドルクリックを対象アプリに再送します。ブラウザの「新しいタブで開く」などは従来どおり動作します。
- **最大化中のウインドウ**は、ドラッグ開始時に元のサイズへ復元し、掴んだ位置の相対関係を保って移動します（タイトルバーをドラッグしたときと同じ挙動）。
- **対象外**: 最小化中のウインドウ、デスクトップ、タスクバー、タスクビュー、ツールチップ、ポップアップメニューなどのシステムウインドウ。
- サイズ変更はサイズ変更可能なウインドウ（`WS_THICKFRAME` あり）のみ対象です。それ以外や最大化中のウインドウは通常の移動になります。
- 管理者権限で動いているウインドウは、wmv を通常権限で起動している場合は移動できません（UIPI の制限。Grab and Move も同じです）。

## 使い方

- wmv にウインドウはありません。起動するとタスクトレイに常駐します。
- トレイアイコンの右クリックメニューから「有効」の切り替えと「終了」ができます。アイコンのダブルクリックでも有効／無効を切り替えられます。
- 二重起動はしません（既に起動中なら何もせず終了します）。
- PowerToys の Grab and Move と併用する場合は、そちらを無効にしておくことを推奨します。
- サイズ変更の修飾キーを Ctrl や Alt に変えたい場合は `WindowMover.cs` の定数 `ResizeModifierKey` を変更してください。

## インストール

`wmv_Setup_<version>.exe` を実行してください。インストーラーはユーザー単位（管理者権限不要）で、次のオプションがあります。

- 「サインイン時に自動起動する」（スタートアップフォルダーにショートカットを作成）
- デスクトップアイコン（既定ではオフ）

インストーラーは更新前に起動中の wmv を終了させ、アンインストーラーはファイル削除前に wmv を終了させます。

## ビルド

必要なもの: .NET 10 SDK。インストーラー作成には Inno Setup 6、署名には Windows SDK の signtool.exe。

```powershell
# 通常のビルド
dotnet build -c Release

# 自己完結・単一ファイルの publish（bin\Release\net10.0-windows\win-x64\publish\wmv.exe）
.\scripts\build-release.ps1

# インストーラー作成（installer_output\wmv_Setup_<version>.exe）
.\scripts\build-installer.ps1

# 署名付きインストーラー: wmv.exe、インストーラー、アンインストーラーに署名する
$env:CODESIGN_CERT = "<拇印 | サブジェクト名 | path\to\cert.pfx>"
$env:CODESIGN_PASSWORD = "<pfx のパスワード（.pfx の場合のみ）>"     # 任意
$env:CODESIGN_TIMESTAMP_URL = "http://timestamp.digicert.com"        # 任意（既定値）
.\scripts\build-installer.ps1 -Sign
```

`build-installer.ps1` のオプション:

| オプション | 説明 |
|---|---|
| `-Sign` | signtool で wmv.exe に署名し、Inno Setup の `SignTool` / `SignedUninstaller` でインストーラーとアンインストーラーにも署名する。完了後に署名を検証する。 |
| `-SkipPublish` | `build-release.ps1` を実行せず、既存の publish 出力を使う。 |
| `-IsccPath` | `ISCC.exe` が PATH や既定のインストール先にない場合のパス指定。 |
| `-SignToolPath` | `signtool.exe` が PATH や Windows SDK にない場合のパス指定。 |

バージョンは `wmv.csproj` の `<Version>` から読み取って Inno Setup に渡すため、更新箇所は 1 か所です（`docs/version-update-checklist.md` 参照）。

## 実装

- `WH_MOUSE_LL` の低レベルマウスフックでミドルボタンの押下・移動・解放を捕捉します。
- フック内では状態を記録するだけにし、実際の `SetWindowPos`（`SWP_ASYNCWINDOWPOS` 付き）は自前のメッセージ専用ウインドウ経由でメッセージループから実行します。応答しないアプリがあってもフックが詰まりません。
- 再送するミドルクリックは `SendInput` で注入し、`dwExtraInfo` のマーカーと `LLMHF_INJECTED` で自分の注入イベントを識別して素通しします。
- 除外するシステムウインドウのクラス名一覧と、最大化ウインドウの復元処理は PowerToys Grab and Move（MIT License、Microsoft Corporation）の挙動を参考にしています。コードの複製はしていません。
