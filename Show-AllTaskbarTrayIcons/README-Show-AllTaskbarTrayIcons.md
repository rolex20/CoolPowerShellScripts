# Show All Taskbar Tray Icons

`Show-AllTaskbarTrayIcons.ps1` is a Windows PowerShell 5.1 script for Windows 11 that promotes all current notification-area icons so they appear directly on the taskbar instead of being hidden under the taskbar overflow arrow.

Windows 11 often recreates notification icon entries when apps update. When that happens, icons for apps such as ChatGPT, OpenAI, Teams, Discord, VPN clients, or sync tools may become hidden again. This script reapplies the per-user registry setting that marks each tray icon as visible.

## What It Changes

The script updates the current user's registry settings only:

```powershell
HKCU:\Control Panel\NotifyIconSettings\*\IsPromoted = 1
HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\EnableAutoTray = 0
```

It does not change machine-wide policy settings and does not require administrator rights for the normal apply operation.

## Requirements

- Windows 11
- Windows PowerShell 5.1
- Run as the Windows user whose taskbar icons you want to show

## Usage

Promote all current notification-area icons:

```powershell
.\Show-AllTaskbarTrayIcons.ps1
```

Promote all current icons and restart Explorer so the taskbar refreshes immediately:

```powershell
.\Show-AllTaskbarTrayIcons.ps1 -RestartExplorer
```

Install a per-user scheduled task that runs the script at every sign-in:

```powershell
.\Show-AllTaskbarTrayIcons.ps1 -InstallAtLogon
```

Remove the scheduled task:

```powershell
.\Show-AllTaskbarTrayIcons.ps1 -RemoveLogonTask
```

Preview changes without applying them:

```powershell
.\Show-AllTaskbarTrayIcons.ps1 -WhatIf
```

## Notes

`-RestartExplorer` stops and starts `explorer.exe`. This refreshes the taskbar immediately, but it can also close open File Explorer windows.

The logon task is useful because Windows 11 may create new tray icon registry entries after an app update. Running the script at sign-in catches those new entries and promotes them again.

## Troubleshooting

If an icon does not appear immediately, run the script with `-RestartExplorer`, sign out and back in, or restart Windows.

If the script reports that `HKCU:\Control Panel\NotifyIconSettings` does not exist, Windows has not created notification-area entries for that user yet. Open or launch the tray apps once, then run the script again.

## License

Use, modify, and publish this script however you like.
