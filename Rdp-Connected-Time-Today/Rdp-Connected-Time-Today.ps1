<#
RDP Connected Time Today (session‑scoped)

What it does
- Computes how long **the current session** has been CONNECTED today (local time).
- Filters Terminal Services Local Session Manager events (LSM) to **this session only**.
- Counts only time between midnight today and now, even if the connection started yesterday.

How it works
- Treats Event IDs 21 and 25 as **connect-like**; 24 and 40 as **disconnect-like**.
- Infers the state at midnight by peeking just before midnight for this session.
- Sums intervals within [today 00:00, now].

Usage
- Save as .ps1 and run in PowerShell. Admin may be required to read the LSM log on some systems.
- Add -ShowEvents to see the per-event timeline used for the calculation.

#>
[CmdletBinding()]
param(
    [switch]$ShowEvents
)

# Default: show events unless explicitly disabled (keep switch syntax)
$ShowEventsEnabled = $true
if ($PSBoundParameters.ContainsKey('ShowEvents')) { $ShowEventsEnabled = $ShowEvents.IsPresent }
$ErrorActionPreference = 'Stop'

# --- Configuration ---
$logName       = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
$connectIds    = @(21, 25)      # Logon/connect & reconnect
$disconnectIds = @(24, 40)      # Disconnect variants seen across builds
$allIds        = $connectIds + $disconnectIds

# --- Time window (local) ---
$now        = Get-Date
$startOfDay = $now.Date

# --- Find current session ID ---
try {
    $currentSessionId = (Get-Process -Id $PID).SessionId
} catch {
    throw "Unable to determine current session ID: $($_.Exception.Message)"
}

function Get-SessionIdFromEvent {
    param([System.Diagnostics.Eventing.Reader.EventRecord]$Event)

    # 1) Many LSM events have SessionID as first property
    if ($Event.Properties -and $Event.Properties.Count -gt 0) {
        try {
            $candidate = $Event.Properties[0].Value
            if ($candidate -ne $null -and $candidate.ToString() -match '^[0-9]+$') {
                return [int]$candidate
            }
        } catch {}
    }
    # 2) Fallback: parse from Message text (handles localized formats that still include "Session ID:")
    $m = [regex]::Match($Event.Message, 'Session\s*ID\s*:\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return [int]$m.Groups[1].Value }

    $m2 = [regex]::Match($Event.Message, 'SessionID\s*:\s*(\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m2.Success) { return [int]$m2.Groups[1].Value }

    return $null
}

function Read-SessionEvents {
    param(
        [DateTime]$From,
        [DateTime]$To
    )
    # Use a guarded fetch so absence of events doesn't throw
    $events = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = ([int[]]$allIds); StartTime = $From; EndTime = $To } -ErrorAction Stop
    } catch {
        # No matching events or log unavailable in this window; treat as empty
        $events = @()
    }

    if (-not $events) { return @() }

    $events |
        Where-Object { ($sid = Get-SessionIdFromEvent $_) -ne $null -and $sid -eq $currentSessionId } |
        ForEach-Object {
            [pscustomobject]@{
                Time = $_.TimeCreated
                Id   = $_.Id
                Kind = if ($connectIds -contains $_.Id) { 'Connect' } else { 'Disconnect' }
                Raw  = $_
            }
        } |
        Sort-Object Time
}


# Pull today's events for THIS session
$todayEvents = Read-SessionEvents -From $startOfDay -To $now

# Peek before midnight to infer midnight state (limit lookback for performance)
$lookbackStart = $startOfDay.AddDays(-2)
$prevEvent = Read-SessionEvents -From $lookbackStart -To $startOfDay | Sort-Object Time -Descending | Select-Object -First 1

$connected = $false
$lastConnectTime = $null
$total = [TimeSpan]::Zero

# Determine state at 00:00 local for this session
if ($todayEvents.Count -eq 0) {
    if ($prevEvent -and $prevEvent.Kind -eq 'Connect') {
        # Connected crossing midnight; count from midnight to now
        $connected = $true
        $lastConnectTime = $startOfDay
        $total = $now - $startOfDay
    }
} else {
    $first = $todayEvents[0]
    if ($first.Kind -eq 'Disconnect') {
        # We were connected at midnight only if the last pre-midnight event was a Connect
        if ($prevEvent -and $prevEvent.Kind -eq 'Connect') {
            $connected = $true
            $lastConnectTime = $startOfDay
        }
    } else {
        # First event is Connect; implies we were disconnected at midnight
        $connected = $false
    }

    foreach ($ev in $todayEvents) {
        if ($ev.Kind -eq 'Connect') {
            if (-not $connected) {
                $connected = $true
                $lastConnectTime = $ev.Time
            }
        } else { # Disconnect
            if ($connected -and $lastConnectTime) {
                $total += ($ev.Time - $lastConnectTime)
                $connected = $false
                $lastConnectTime = $null
            }
        }
    }

    if ($connected -and $lastConnectTime) {
        $total += ($now - $lastConnectTime)
    }
}

# Optional event dump for debugging
# Determine display user (domain\user when possible)
try { $userDisplay = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } catch { $userDisplay = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME } }

if ($ShowEventsEnabled) {
    Write-Host ("Filtering events for user: {0}" -f $userDisplay) -ForegroundColor Yellow
Write-Host ("User's current RDP session ID: {0}" -f $currentSessionId) -ForegroundColor Yellow
Write-Host ("Analyzing session: {0}" -f $currentSessionId) -ForegroundColor Cyan
    Write-Host ("Date: {0}" -f $startOfDay.ToString('yyyy-MM-dd'))
    Write-Host ("Now:  {0}" -f $now.ToString('HH:mm:ss'))
    Write-Host 'Events (this session only):'
    if ($todayEvents.Count -gt 0) {
        $todayEvents | ForEach-Object { Write-Host ("  {0} - {1} (ID {2})" -f $_.Time.ToString('HH:mm:ss'), $_.Kind, $_.Id) }
    } else {
        Write-Host '  (no events today)'
    }
    if ($prevEvent) {
        Write-Host ("Last event before midnight: {0} - {1} (ID {2})" -f $prevEvent.Time.ToString('yyyy-MM-dd HH:mm:ss'), $prevEvent.Kind, $prevEvent.Id)
    } else {
        Write-Host 'No events found before midnight for this session.'
    }
    Write-Host '—'
}

# Final output
$hours   = [int][math]::Floor($total.TotalHours)
$minutes = $total.Minutes
$summary = "Connected time today (session $currentSessionId): {0}h {1}m (Total minutes: {2})" -f $hours, $minutes, [int][math]::Floor($total.TotalMinutes)
Write-Output $summary
