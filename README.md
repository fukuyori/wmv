# wmv

[日本語版はこちら](README.ja.md)

A small tray-resident Windows utility that lets you move any window by dragging it with the **middle mouse button**, and resize it with **Shift + middle drag**. No modifier key is needed for moving.

Built as a replacement for the PowerToys "Grab and Move" module (Alt + left drag).

## Demo

[![wmv demo video](https://img.youtube.com/vi/1C_a8ffqcGs/hqdefault.jpg)](https://www.youtube.com/watch?v=1C_a8ffqcGs)

Watch on YouTube: https://www.youtube.com/watch?v=1C_a8ffqcGs

## Features

- **Move**: press the middle button anywhere on a window and drag. The top-level window under the cursor moves.
- **Resize**: hold Shift, then middle-drag. The edge or corner closest to the grab point (8 handles) follows the cursor while the opposite side stays fixed. Minimum size is 150×50 px.
- **Plain middle clicks still work**: if you release without moving past the OS drag threshold (`SM_CXDRAG` / `SM_CYDRAG`, 4 px by default), the middle click is replayed to the target application, so "open link in new tab" and similar features keep working.
- **Maximized windows** are restored to their normal size when a drag starts and repositioned so the grab point keeps its relative position, just like dragging the title bar.
- **Excluded**: minimized windows, the desktop, taskbar, task view, tooltips, popup menus and other shell windows.
- Resizing only applies to windows that have a sizing border (`WS_THICKFRAME`); other windows and maximized windows fall back to moving.
- **Elevated (administrator) windows** such as Rufus or backup tools can be moved as well. The release build carries a `uiAccess="true"` manifest, which Windows honours only when the executable is code-signed with a machine-trusted certificate and installed under Program Files. A `-NoUiAccess` build, or wmv started from any other location, is subject to UIPI and cannot touch elevated windows (the same limitation PowerToys Grab and Move has).

## Usage

- wmv has no main window. It lives in the notification area (system tray).
- Right-click the tray icon for **Enable** (toggle), **Start at sign-in** (toggle) and **Exit**. Double-clicking the icon also toggles enable/disable.
- "Start at sign-in" writes the value `wmv` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. The installer's option uses the same value, so the menu always shows the current state.
- Only one instance runs at a time; launching it again does nothing.
- If you also use PowerToys Grab and Move, disable that module to avoid double handling.
- To change the resize modifier (Ctrl or Alt instead of Shift), edit the `ResizeModifierKey` constant in `WindowMover.cs`.

## Installation

Run `wmv_Setup_<version>.exe`. The installer is per-machine (installs under Program Files, administrator rights required, see the uiAccess note above) and offers:

- "Start automatically at sign-in" (registers the `Run` registry value; removed on uninstall)
- Desktop shortcut (unchecked by default)

The installer stops a running wmv before updating, and the uninstaller stops it before removing files.

An installer built with `-NoUiAccess` is per-user instead (no administrator rights, installs under `%LOCALAPPDATA%\Programs`) and cannot move elevated windows.

## Building

Requirements: .NET 10 SDK. For the installer, Inno Setup 6. For signing, signtool.exe from the Windows SDK.

```powershell
# Debug/Release build
dotnet build -c Release

# Self-contained single-file publish with the uiAccess manifest
# (bin\Release\net10.0-windows\win-x64\publish\wmv.exe; only starts when signed and under Program Files)
.\scripts\build-release.ps1

# Release installer (installer_output\wmv_Setup_<version>.exe): signs wmv.exe, the installer and the uninstaller
$env:CODESIGN_CERT = "<thumbprint | subject name | path\to\cert.pfx>"
$env:CODESIGN_PASSWORD = "<pfx password, only for .pfx>"          # optional
$env:CODESIGN_TIMESTAMP_URL = "http://timestamp.digicert.com"     # optional (default)
.\scripts\build-installer.ps1 -Sign

# Unsigned per-user installer without uiAccess (cannot move elevated windows)
.\scripts\build-installer.ps1 -NoUiAccess
```

`build-installer.ps1` options:

| Option | Description |
|---|---|
| `-Sign` | Sign wmv.exe with signtool, then let Inno Setup sign the installer and uninstaller (`SignTool` / `SignedUninstaller`). Verifies signatures afterwards. Required unless `-NoUiAccess` is given. |
| `-NoUiAccess` | Build a plain executable without the uiAccess manifest and a per-user installer. Signing is optional. |
| `-SkipPublish` | Reuse the existing publish output instead of running `build-release.ps1`. The script refuses to package an exe whose uiAccess manifest does not match the selected mode. |
| `-IsccPath` | Path to `ISCC.exe` if it is not in PATH or the default install location. |
| `-SignToolPath` | Path to `signtool.exe` if it is not in PATH or the Windows SDK. |

The version is read from `<Version>` in `wmv.csproj` and passed to Inno Setup, so it only needs to be updated in one place (see `docs/version-update-checklist.md`).

## Implementation notes

- A low-level mouse hook (`WH_MOUSE_LL`) captures middle-button press, move and release.
- The hook callback only records state; the actual `SetWindowPos` (with `SWP_ASYNCWINDOWPOS`) runs from the message loop via a message-only window, so a slow or hung target cannot stall the hook.
- Replayed middle clicks are injected with `SendInput`; a marker in `dwExtraInfo` plus `LLMHF_INJECTED` lets the hook pass its own events through.
- `app.manifest` (embedded when built with `-p:UiAccess=true`, which the scripts do by default) declares `uiAccess="true"`. This lets the hook receive input aimed at elevated windows and lets `SetWindowPos` move them, without running wmv itself elevated. `dotnet build` does not embed it, so debug builds run from `bin\` as usual.
- An invisible top-level window (`ShutdownWindow.cs`) accepts `WM_CLOSE` and session-end messages so the installer, Restart Manager and `taskkill` can stop wmv cleanly.
- The list of excluded shell window classes and the maximized-window restore behaviour follow PowerToys Grab and Move (MIT License, Microsoft Corporation). No code was copied.
