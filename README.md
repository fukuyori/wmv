# wmv

[日本語版はこちら](README.ja.md)

A small tray-resident Windows utility that lets you move any window by dragging it with the **middle mouse button**, and resize it with **Shift + middle drag**. No modifier key is needed for moving.

Built as a replacement for the PowerToys "Grab and Move" module (Alt + left drag).

## Features

- **Move**: press the middle button anywhere on a window and drag. The top-level window under the cursor moves.
- **Resize**: hold Shift, then middle-drag. The edge or corner closest to the grab point (8 handles) follows the cursor while the opposite side stays fixed. Minimum size is 150×50 px.
- **Plain middle clicks still work**: if you release without moving past the OS drag threshold (`SM_CXDRAG` / `SM_CYDRAG`, 4 px by default), the middle click is replayed to the target application, so "open link in new tab" and similar features keep working.
- **Maximized windows** are restored to their normal size when a drag starts and repositioned so the grab point keeps its relative position, just like dragging the title bar.
- **Excluded**: minimized windows, the desktop, taskbar, task view, tooltips, popup menus and other shell windows.
- Resizing only applies to windows that have a sizing border (`WS_THICKFRAME`); other windows and maximized windows fall back to moving.
- Windows running elevated cannot be moved unless wmv itself runs elevated (UIPI restriction, same as Grab and Move).

## Usage

- wmv has no main window. It lives in the notification area (system tray).
- Right-click the tray icon for **Enable** (toggle), **Start at sign-in** (toggle) and **Exit**. Double-clicking the icon also toggles enable/disable.
- "Start at sign-in" writes the value `wmv` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. The installer's option uses the same value, so the menu always shows the current state.
- Only one instance runs at a time; launching it again does nothing.
- If you also use PowerToys Grab and Move, disable that module to avoid double handling.
- To change the resize modifier (Ctrl or Alt instead of Shift), edit the `ResizeModifierKey` constant in `WindowMover.cs`.

## Installation

Run `wmv_Setup_<version>.exe`. The installer is per-user (no administrator rights needed) and offers:

- "Start automatically at sign-in" (registers the `Run` registry value; removed on uninstall)
- Desktop shortcut (unchecked by default)

The installer closes a running wmv before updating, and the uninstaller stops it before removing files.

## Building

Requirements: .NET 10 SDK. For the installer, Inno Setup 6. For signing, signtool.exe from the Windows SDK.

```powershell
# Debug/Release build
dotnet build -c Release

# Self-contained single-file publish (bin\Release\net10.0-windows\win-x64\publish\wmv.exe)
.\scripts\build-release.ps1

# Installer (installer_output\wmv_Setup_<version>.exe)
.\scripts\build-installer.ps1

# Signed installer: signs wmv.exe, the installer and the uninstaller
$env:CODESIGN_CERT = "<thumbprint | subject name | path\to\cert.pfx>"
$env:CODESIGN_PASSWORD = "<pfx password, only for .pfx>"          # optional
$env:CODESIGN_TIMESTAMP_URL = "http://timestamp.digicert.com"     # optional (default)
.\scripts\build-installer.ps1 -Sign
```

`build-installer.ps1` options:

| Option | Description |
|---|---|
| `-Sign` | Sign wmv.exe with signtool, then let Inno Setup sign the installer and uninstaller (`SignTool` / `SignedUninstaller`). Verifies signatures afterwards. |
| `-SkipPublish` | Reuse the existing publish output instead of running `build-release.ps1`. |
| `-IsccPath` | Path to `ISCC.exe` if it is not in PATH or the default install location. |
| `-SignToolPath` | Path to `signtool.exe` if it is not in PATH or the Windows SDK. |
| `-UiAccess` | Experimental. Embed a `uiAccess="true"` manifest so wmv can act on windows of elevated (administrator) processes. Requires `-Sign`. The installer then installs per-machine under Program Files (administrator rights needed), because Windows only starts uiAccess executables that are signed with a machine-trusted certificate and located in a secure location. |

The version is read from `<Version>` in `wmv.csproj` and passed to Inno Setup, so it only needs to be updated in one place (see `docs/version-update-checklist.md`).

## Implementation notes

- A low-level mouse hook (`WH_MOUSE_LL`) captures middle-button press, move and release.
- The hook callback only records state; the actual `SetWindowPos` (with `SWP_ASYNCWINDOWPOS`) runs from the message loop via a message-only window, so a slow or hung target cannot stall the hook.
- Replayed middle clicks are injected with `SendInput`; a marker in `dwExtraInfo` plus `LLMHF_INJECTED` lets the hook pass its own events through.
- The list of excluded shell window classes and the maximized-window restore behaviour follow PowerToys Grab and Move (MIT License, Microsoft Corporation). No code was copied.
