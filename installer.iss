; wmv Inno Setup Script
;
; Normally invoked from scripts\build-installer.ps1, which passes these definitions:
;   /DMyAppVersion=<version>  <Version> from wmv.csproj (defaults to 0.0.0)
;   /DSIGN                    enable signing (SignTool / SignedUninstaller)
;   /Swmvsign=<command>       sign command ($f = file to sign, $q = double quote)

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
; Close a running wmv.exe via Restart Manager before overwriting it.
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
Name: "startup"; Description: "Start {#MyAppName} automatically at sign-in"; GroupDescription: "Startup:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyPublishDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Startup uses the same HKCU\...\Run value "wmv" as the app's tray menu. Removed on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Flags: uninsdeletevalue; Tasks: startup
; Remove the value when reinstalling with the startup task unchecked.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "{#MyAppName}"; Flags: deletevalue; Tasks: not startup

[InstallDelete]
; Remove the Startup-folder shortcut created by an earlier installer version.
Type: files; Name: "{userstartup}\{#MyAppName}.lnk"

[UninstallDelete]
Type: files; Name: "{userstartup}\{#MyAppName}.lnk"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Terminate a resident wmv.exe on uninstall (Restart Manager is not used for uninstalls).
function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#MyAppExeName} /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
