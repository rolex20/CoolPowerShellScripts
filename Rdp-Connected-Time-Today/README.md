# RDP Connected Time Today (session‑scoped)

This PowerShell script reports **how long the current user’s Remote Desktop session has been connected today** (from local midnight to now). It uses Windows event logs to compute time between **logon/reconnect** and **disconnect** events, and ignores anything before today’s 00:00.

Recruiter‑friendly highlights: built with **Get‑WinEvent** using **FilterHashtable** over the **TerminalServices Local Session Manager (Operational)** log; **session scoping** via the current process **SessionId** plus extraction of **EventRecord.Properties** (with a robust **regex fallback**) to match only the active session; a small deterministic **state machine** over the event stream; **edge‑aware day‑boundary logic** with a pre‑midnight look‑back; **cross‑build event coverage** (24/40); careful **error handling** when no events are found; and human‑readable diagnostics that include **event IDs**.

---

## What it does
- Calculates **today’s connected time** for the **current user’s active RDP session** only.
- Uses Local time. If a connection started yesterday and continues past midnight, only **today’s portion** is counted.
- Displays the user being filtered, the current session ID, a chronological event list (with **IDs**), and a summary.

## What it intentionally does **not** do
- Does **not** sum across other users or sessions.
- Does **not** count pre‑logon handshakes (e.g., **RemoteConnectionManager** **Event 1149**). That keeps totals aligned with “logged in” time, which is what timekeeping systems typically use.

## Event sources & IDs
- **Log:** `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`
- **Connect‑like:** **21** (Session logon succeeded), **25** (Session reconnection succeeded)
- **Disconnect‑like:** **24** and **40** (disconnected variants observed across builds)

## How it works (brief)
1. Determines **local midnight → now** time window.
2. Resolves the **current session ID** via the running process (`Get-Process -Id $PID`).
3. Reads LSM events (IDs 21/25/24/40) within the window, then **filters to this session** by reading the event’s session ID (from `EventRecord.Properties` or by regex from the message).
4. Looks **just before midnight** to infer whether the session was already connected at 00:00.
5. Walks events with a simple **connected/disconnected** state machine and sums intervals entirely within today.
6. Prints a concise summary.

## Requirements
- Windows with the **TerminalServices LSM Operational** log enabled (default on most systems).
- PowerShell 5.1+ or PowerShell 7+. Administrator permissions may be required to read the log in some environments.

## Usage
```powershell
# Default (shows diagnostics):
./Rdp-Connected-Time-Today.ps1

# Quiet run (hide event list):
./Rdp-Connected-Time-Today.ps1 -ShowEvents:$false
```

## Example output
```
Filtering events for user: CONTOSO\jdoe
User's current RDP session ID: 2
Analyzing session: 2
Date: 2025-08-25
Now:  13:40:34
Events (this session only):
  07:03:12 - Connect (ID 21)
  13:08:16 - Disconnect (ID 24)
  13:08:23 - Disconnect (ID 40)
  13:09:36 - Disconnect (ID 24)
  13:09:37 - Connect (ID 25)
—
Connected time today (session 2): 6h 36m (Total minutes: 396)
```

## Notes on accuracy
- Multiple **Disconnect** events may appear near the same time. They don’t change totals; the state machine avoids double‑counting.
- If no relevant events exist for the window, the script cleanly returns **0h 0m**.
- Totals reflect **logged‑in session time**, not idle time and not pre‑logon transport/authentication.

### Why not Event 1149?
- Event 1149 (TerminalServices-RemoteConnectionManager/Operational) indicates "User authentication succeeded" during the RDP handshake.
- It occurs **before** Local Session Manager logs a real **session logon** (Event 21) or **reconnect** (Event 25), and sometimes appears even when a session never fully establishes.
- Counting from 1149 can **inflate connected time** by including pre-logon minutes and edge cases; for payroll and audit, "connected" should align with an actual **logged-in session**.
- For diagnostics you may surface 1149 in the event dump, but it is intentionally **excluded from totals**.

## Is there a built‑in equivalent?
There isn’t a single Windows command or built‑in report that totals **“RDP connected time today”** for a single session while handling multiple disconnect/reconnect cycles and the midnight boundary.

Closest options and why they’re not equivalent:
- **`query user` / `quser` / `qwinsta`** — Snapshot of session state with *Logon Time*; does not subtract time spent **Disconnected**, so totals can overcount across drop/reconnect cycles.
- **Event Viewer / `Get-WinEvent` / `wevtutil`** — Provide the raw events (LSM 21/25 for logon/reconnect, 24/40 for disconnect), but you still need logic to correlate and sum intervals.
- **Remote Desktop Services Manager (TSAdmin)** — Legacy UI (older Server editions). Not available on modern Windows/Server; even when present, it doesn’t compute “today’s total.”
- **Task Manager → Users tab** — Snapshot view of current sessions, not a day-total.

This script exists to fill that gap: a small, deterministic calculation that scopes to **your session** and sums intervals within **today** only.

## Customization ideas
- Threshold alert (e.g., warn under/over **8 hours**).
- Optional export to CSV/JSON.
- Parameters for a different **user/session** (defaults to current).
- Support a **date argument** to report a prior day.

## Troubleshooting
- **“No events were found…”** — The window may be empty for those IDs, or the log is disabled. Ensure the `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational` log exists and you have read access.
- **Totals look too high** — Confirm you don’t have long, unattended connections spanning midnight; only today is counted, but verify duplicate user sessions aren’t running.

## Security & privacy
- Reads local Windows event logs; no network calls. Output includes the current **DOMAIN\User** string for clarity.

## License
Add a `LICENSE` file (e.g., MIT) suitable for your project. This repository currently does not include one.

