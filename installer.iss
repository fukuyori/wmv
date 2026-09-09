; wmv Inno Setup Script
;
; 通常は scripts\build-installer.ps1 から呼び出す。スクリプトは次の定義を渡す:
;   /DMyAppVersion=<version>  wmv.csproj の <Version>（省略時は 0.0.0）
;   /DSIGN                    署名を有効化（SignTool / SignedUninstaller）
;   /Swmvsign=<command>       署名コマンド（$f が対象ファイル、$q が二重引用符）

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "wmv"
#define MyAppPublisher "fukuyori"
#define MyAppExeName "wmv.exe"
#define MyAppDescription "Move and resize windows by middle-button dragging"
#define MyPublishDir "bin\Release\net10.0-windows\win-x64\publish"

[Setup]
AppId={{C55A968E-1E26-4F7A-87E0-1E5778486B62}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppDescription}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=installer_output
OutputBaseFilename={#MyAppName}_Setup_{#MyAppVersion}
SetupIconFile=wmv.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 起動中の wmv.exe を Restart Manager 経由で終了させてから上書きする。
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no
#ifdef SIGN
SignTool=wmvsign
SignedUninstaller=yes
#endif

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "サインイン時に自動起動する"; GroupDescription: "自動起動:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyPublishDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{#MyAppName} をアンインストール"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startup

[InstallDelete]
; 自動起動タスクを外して再インストールした場合に古いショートカットを残さない。
Type: files; Name: "{userstartup}\{#MyAppName}.lnk"

[UninstallDelete]
Type: files; Name: "{userstartup}\{#MyAppName}.lnk"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{#MyAppName} を起動"; Flags: nowait postinstall skipifsilent

[Code]
// アンインストール時は常駐中の wmv.exe を終了させる（Restart Manager はアンインストールでは使われないため）。
function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#MyAppExeName} /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
