<#
.SYNOPSIS
Shows all Windows 11 notification-area icons on the taskbar.

.DESCRIPTION
Windows 11 stores per-application taskbar corner overflow preferences under
the current user's NotifyIconSettings registry key. When an application is
updated or reinstalled, Windows can create a new notification icon entry and
hide it under the taskbar overflow arrow again.

This script promotes every existing notification-area icon for the current
user by setting IsPromoted to 1 on each entry under:

    HKCU:\Control Panel\NotifyIconSettings

It also sets the legacy Explorer EnableAutoTray value to 0 under:

    HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer

The script only changes settings for the current Windows user. It does not
require elevation for the normal apply operation.

.PARAMETER RestartExplorer
Restarts explorer.exe after applying the registry changes so the taskbar
reloads the notification-area settings immediately.

This can close open File Explorer windows. Leave this switch off if you prefer
the settings to take effect after the next Explorer restart or sign-in.

.PARAMETER InstallAtLogon
Creates or updates a per-user scheduled task that runs this script at logon.
This is useful because Windows 11 can recreate tray icon entries after app
updates, which may hide icons again.

.PARAMETER RemoveLogonTask
Removes the per-user scheduled task created by this script.

.PARAMETER TaskName
Name of the scheduled task used with InstallAtLogon or RemoveLogonTask.

.EXAMPLE
.\Show-AllTaskbarTrayIcons.ps1

Promotes all currently registered tray icons for the current user.

.EXAMPLE
.\Show-AllTaskbarTrayIcons.ps1 -RestartExplorer

Promotes all currently registered tray icons and restarts Explorer so the
taskbar refreshes immediately.

.EXAMPLE
.\Show-AllTaskbarTrayIcons.ps1 -InstallAtLogon

Installs a per-user scheduled task that runs this script at every sign-in.

.EXAMPLE
.\Show-AllTaskbarTrayIcons.ps1 -RemoveLogonTask

Removes the scheduled task created by this script.

.NOTES
Author: Your Name
Requires: Windows PowerShell 5.1
Applies to: Windows 11

Registry values changed:
  - HKCU:\Control Panel\NotifyIconSettings\*\IsPromoted = 1
  - HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\EnableAutoTray = 0

This script is intentionally scoped to HKCU so it affects only the signed-in
user and avoids machine-wide policy changes.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [switch]$RestartExplorer,

    [switch]$InstallAtLogon,

    [switch]$RemoveLogonTask,

    [ValidateNotNullOrEmpty()]
    [string]$TaskName = 'Show All Taskbar Tray Icons'
)

Set-StrictMode -Version 2.0

$ErrorActionPreference = 'Stop'

function Set-AllTrayIconsVisible {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $explorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    $notifyRoot = 'HKCU:\Control Panel\NotifyIconSettings'

    if ($PSCmdlet.ShouldProcess($explorerKey, 'Set EnableAutoTray to 0')) {
        New-Item -Path $explorerKey -Force | Out-Null
        New-ItemProperty `
            -Path $explorerKey `
            -Name 'EnableAutoTray' `
            -PropertyType DWord `
            -Value 0 `
            -Force | Out-Null
    }

    if (-not (Test-Path -Path $notifyRoot)) {
        Write-Warning "The registry path '$notifyRoot' was not found. Windows may not have created notification icon entries yet."
        return
    }

    $items = Get-ChildItem -Path $notifyRoot
    $processedCount = 0

    foreach ($item in $items) {
        $processedCount++

        if ($PSCmdlet.ShouldProcess($item.PSPath, 'Set IsPromoted to 1')) {
            New-ItemProperty `
                -Path $item.PSPath `
                -Name 'IsPromoted' `
                -PropertyType DWord `
                -Value 1 `
                -Force | Out-Null
        }
    }

    Write-Host "Processed $processedCount notification-area icon entr$(if ($processedCount -eq 1) { 'y' } else { 'ies' })."
}

function Restart-ExplorerShell {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('explorer.exe', 'Restart Windows Explorer')) {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Process explorer.exe
        Write-Host 'Explorer restarted.'
    }
}

function Install-LogonTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'InstallAtLogon requires the script to be run from a saved .ps1 file.'
    }

    $scriptPath = (Resolve-Path -Path $PSCommandPath).Path
    $quotedScriptPath = '"' + $scriptPath.Replace('"', '\"') + '"'
    $argument = "-NoProfile -ExecutionPolicy Bypass -File $quotedScriptPath"

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtLogOn

    if ($PSCmdlet.ShouldProcess($Name, 'Create or update per-user scheduled task')) {
        Register-ScheduledTask `
            -TaskName $Name `
            -Action $action `
            -Trigger $trigger `
            -Description 'Promotes all Windows 11 notification-area icons so they appear on the taskbar.' `
            -Force | Out-Null

        Write-Host "Scheduled task '$Name' installed."
    }
}

function Remove-LogonTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue

    if ($null -eq $task) {
        Write-Host "Scheduled task '$Name' was not found."
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Remove scheduled task')) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
        Write-Host "Scheduled task '$Name' removed."
    }
}

if ($InstallAtLogon -and $RemoveLogonTask) {
    throw 'Use either InstallAtLogon or RemoveLogonTask, not both.'
}

if ($RemoveLogonTask) {
    Remove-LogonTask -Name $TaskName
    return
}

Set-AllTrayIconsVisible

if ($InstallAtLogon) {
    Install-LogonTask -Name $TaskName
}

if ($RestartExplorer) {
    Restart-ExplorerShell
}
