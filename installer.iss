; wmv Inno Setup Script
;
; Normally invoked from scripts\build-installer.ps1, which passes these definitions:
;   /DMyAppVersion=<version>  <Version> from wmv.csproj (defaults to 0.0.0)
;   /DSIGN                    enable signing (SignTool / SignedUninstaller)
;   /Swmvsign=<command>       sign command ($f = file to sign, $q = double quote)
;   /DNOUIACCESS              the exe has no uiAccess manifest: install per-user without
;                             administrator rights. By default the exe carries a uiAccess manifest
;                             and must live under Program Files (a secure location), so the
;                             installer is per-machine and requires administrator rights.

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
#ifdef NOUIACCESS
PrivilegesRequired=lowest
#else
; uiAccess executables only start from a secure location such as {commonpf}, so install per-machine.
PrivilegesRequired=admin
#endif
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
; shellexec: a uiAccess executable cannot be started with CreateProcess (error 740,
; ERROR_ELEVATION_REQUIRED); it must go through ShellExecute so AppInfo can launch it.
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent shellexec

[Code]
// Stop a resident wmv.exe: ask it to close (WM_CLOSE via taskkill), give it a moment,
// then force-kill anything that is still running. Restart Manager alone is not enough
// because wmv has no visible main window.
procedure StopRunningApp();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1500);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#MyAppExeName} /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(500);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningApp();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopRunningApp();
  Result := True;
end;
