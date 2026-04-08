# Windows Advanced Disk Cleanup Scripts

**Created by jino99**

[![PowerShell](https://img.shields.io/badge/PowerShell-5%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/en-us/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Maintained](https://img.shields.io/badge/Maintained-yes-success)](https://github.com/jino99)

Two PowerShell scripts for Windows endpoint maintenance and disk space recovery, each tailored to a different deployment scenario:

| Script | Edition | Use Case |
|---|---|---|
| `disk-cleanup.ps1` | Service Desk (SDE) | Interactive, system-wide deep cleaning for technicians |
| `disk-cleanup-intune.ps1` | Intune | Silent, non-intrusive cleanup deployed via Microsoft Intune in user context |

---

## Requirements

| Requirement | SDE (`disk-cleanup.ps1`) | Intune (`disk-cleanup-intune.ps1`) |
|---|---|---|
| PowerShell | 5.0+ | 5.0+ |
| Windows | 10 / 11 | 10 / 11 |
| Admin rights | Required for full scope | Not required |
| Execution Policy | Must allow local scripts | Must allow local scripts |

> **Execution Policy:** If you get a script blocked error, run this once in an elevated PowerShell session:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
> ```

---

## Getting Started

**1. Clone or download the repository:**
```powershell
git clone https://github.com/jino99/disk-cleanup-tool.git
cd disk-cleanup-tool
```

**2. Unblock scripts if downloaded from the internet:**
```powershell
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
```

**3. Run the appropriate script for your scenario:**
- For the SDE script → launch PowerShell **as Administrator**
- For the Intune script → no elevation needed

---

## disk-cleanup.ps1 — Service Desk Edition

Designed for direct technical intervention. Runs system-wide and iterates over all user profiles on the machine. Runs with reduced scope if executed as a standard user (system-level operations are skipped).

### Interactive Menu

Launch the script without parameters to open the interactive menu:

```powershell
.\disk-cleanup.ps1
```

The menu looks like this:

```
  Disk Cleanup Tool  ·  Service Desk Edition
  Administrator   C: 42.3 GB free of 237.5 GB  (82% used)
  ──────────────────────────────────────────────────────

  MODE

   ● [1]  Clean    full cleanup: caches, WU, Recycle Bin, ReTrim
     [2]  Analyze  simulate only — nothing will be deleted

  ──────────────────────────────────────────────────────

  LEVEL

     [3]  Low     user caches only (browsers, GPU, temp, apps)
   ● [4]  Medium  + system cache, Windows Update, CleanMgr
     [5]  Full    + DISM component cleanup, obsolete drivers

  ──────────────────────────────────────────────────────

  OPTIONS

     [6]  Force CleanMgr        OFF
     [7]  Force DISM            OFF
     [8]  System Restore Point  OFF

  ──────────────────────────────────────────────────────

  [R]  Run Cleanup    [Q]  Quit

  Press a number to change a setting, R to run, Q to quit.
  ›
```

Press a number key to toggle or change a setting. `●` marks the active selection. When running in `Clean` mode, a confirmation screen is shown before any changes are made. `Analyze` mode runs immediately since it makes no changes.

| Key | Action |
|---|---|
| `1` | Set Mode: Clean |
| `2` | Set Mode: Analyze |
| `3` / `4` / `5` | Set Scope: Low / Medium / Full |
| `6` / `7` / `8` | Toggle Force CleanMgr / Force DISM / System Restore Point |
| `R` | Run with current settings |
| `Q` | Quit without running |

**Example flow:**
1. Run `.\disk-cleanup.ps1`
2. Press `5` to set Scope to Full
3. Press `8` to enable System Restore Point
4. Press `R` → review the confirmation screen → press `Y` to start

### Parameters (CLI)

Skip the menu and run directly with parameters:

| Parameter | Values | Default | Description |
|---|---|---|---|
| `-Mode` | `Clean`, `Analyze` | `Clean` | Whether to delete files or only simulate |
| `-Scope` | `Low`, `Medium`, `Full` | `Medium` | Depth of cleanup operations |
| `-ForceCleanMgr` | switch | off | Force CleanMgr regardless of `-Scope` |
| `-ForceDism` | switch | off | Force DISM component cleanup regardless of `-Scope` |
| `-CreateRestorePoint` | switch | off | Create a System Restore Point before cleaning |
| `-SuppressConfirmation` | switch | off | Skip the confirmation prompt in Clean mode |
| `-LogFile` | path | auto | Override the default log file path |
| `-Help` | switch | off | Display full help and exit |

**`-Mode` details:**
- `Clean` — performs the full cleanup: caches, Windows Update, Recycle Bin, SSD ReTrim.
- `Analyze` — simulates all operations without deleting anything. Logs every path that would be cleaned with its estimated size, lists processes that would be force-closed, and reports total estimated space that would be freed.

**`-Scope` details:**
- `Low` — user caches only (browsers, GPU, temp, third-party apps).
- `Medium` — adds Teams/Office caches, system cache, Windows Update logs, and CleanMgr.
- `Full` — additionally runs DISM component cleanup and removes obsolete OEM drivers.

### Usage Examples

```powershell
# Launch interactive menu
.\disk-cleanup.ps1

# Display full help
.\disk-cleanup.ps1 -Help

# Standard safe run (Clean, Medium) — no prompts
.\disk-cleanup.ps1 -Mode Clean -Scope Medium

# Full deep clean with a restore point created first
.\disk-cleanup.ps1 -Mode Clean -Scope Full -CreateRestorePoint

# Simulate what would be cleaned at Medium level — safe to run anytime
.\disk-cleanup.ps1 -Mode Analyze -Scope Medium
```

### What It Cleans

**System-level** (Admin required):

| Target | Scope |
|---|---|
| Windows Update download cache (`SoftwareDistribution\Download`) | Medium+ |
| Windows CBS and DISM logs | Medium+ |
| Windows global Temp folder (files older than 7 days) | Medium+ |
| Disk Cleanup utility (`cleanmgr.exe`) | Medium+ |
| WinSxS component store via DISM | Full |
| Obsolete OEM drivers not in use via `pnputil` | Full |
| Recycle Bin | Clean mode |
| SSD ReTrim | Clean mode |

**Per user profile** (iterates all profiles under `C:\Users`):

| Target | Details |
|---|---|
| Google Chrome & Microsoft Edge | `Cache`, `Code Cache`, `GPUCache` |
| Microsoft Teams (Classic & New) | `Cache`, `blob_storage`, `IndexedDB`, `GPUCache` |
| Office 365/2016 & 2013 | `OfficeFileCache` (16.0 and 15.0) |
| Office telemetry & misc | `OTele`, `SolutionPackages`, `WebWebView2Cache` |
| OneDrive | Diagnostic logs |
| Outlook | Offline Address Books |
| GPU shader caches | NVIDIA `DXCache`, `GLCache`, `NV_Cache` — AMD `DXCache` — D3D `D3DSCache` |
| WhatsApp | Cache |
| Spotify | `Data`, `Storage` |
| Java | Deployment cache (`Sun\Java\Deployment\cache`) |
| VMware | VDM logs and cache |
| Visual Studio | `ComponentModelCache`, `Designer\ShadowCache` |
| User Temp | All temp files |

> **Process management:** The script force-closes browsers, Teams, and Office apps before cleaning to avoid locked files. Warn users before running interactively.

### Logging

Logs are written to:
```
C:\ProgramData\ServiceDeskCleanup\Logs\SDE_Cleanup_<hostname>_<date>.log
```

The log captures every operation attempted, files removed, space freed, and any errors encountered. Errors are non-fatal — the script continues and logs the failure.

---

## disk-cleanup-intune.ps1 — Intune Edition

Designed for silent mass deployment via Microsoft Intune. Runs entirely in the logged-in user's context — no elevation required or attempted.

### Key Behaviors

- **No process termination** — files in use are silently skipped.
- **No personal file access** — Documents, Pictures, Desktop are never touched.
- **Non-interactive** — produces no UI or prompts.
- **Returns a status string** suitable for Intune detection rules and reporting.

### Deploying via Intune

1. In the [Intune admin center](https://intune.microsoft.com), go to **Devices → Scripts and remediations → Platform scripts**
2. Click **Add → Windows 10 and later**
3. Upload `disk-cleanup-intune.ps1`
4. Set **Run this script using the logged on credentials** → **Yes**
5. Set **Run script in 64-bit PowerShell** → **Yes**
6. Assign to a device or user group and save

No parameters are needed. The script runs silently and exits with the return value below.

### Return Value

On completion, the script outputs:
```
CleanupFinished;FreedGB:<n>;FinalFreeGB:<n>
```

**Using this in an Intune detection rule:**
```powershell
$result = .\disk-cleanup-intune.ps1
if ($result -like "CleanupFinished*") {
    Write-Host "Detected"
    exit 0
}
exit 1
```

### What It Cleans

| Category | Details |
|---|---|
| Microsoft Teams | Classic (`%APPDATA%\Microsoft\Teams`) and New Teams (`MSTeams_8wekyb3d8bbwe`) — Cache, Code Cache, GPUCache, IndexedDB, databases, tmp, Service Worker |
| Office 365/2016 | `OfficeFileCache` (16.0), `OTele`, `SolutionPackages`, `WebWebView2Cache` |
| Office 2013 | `OfficeFileCache` (15.0) |
| OneDrive | Diagnostic logs |
| Outlook | Offline Address Books |
| Chrome | `Cache`, `Code Cache`, `GPUCache` |
| Edge | `Cache`, `Code Cache`, `GPUCache` |
| NVIDIA | `DXCache`, `GLCache`, `NV_Cache` |
| AMD | `DXCache` |
| D3D | `D3DSCache` |
| Explorer | `thumbcache_*.db` thumbnail databases |
| WhatsApp | `Cache` (Roaming and Local) |
| Spotify | `Data`, `Storage` |
| Java | `Sun\Java\Deployment\cache` |
| VMware | VDM `logs` and `cache` |
| Visual Studio | `ComponentModelCache`, `Designer\ShadowCache` (all installed versions) |
| User Temp | Files older than 3 days |
| DNS | Resolver cache flush (`ipconfig /flushdns`) |

### Logging

Logs are written to the user's local profile:
```
%LOCALAPPDATA%\IntuneCleanup\Logs\Cleanup_<username>_<date>.log
```

---

## Troubleshooting

**Script is blocked and won't run**
```powershell
# Unblock the specific file
Unblock-File -Path .\disk-cleanup.ps1

# Or allow local scripts machine-wide (run as Admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

**"Access denied" errors in the log**
- Make sure you launched PowerShell as Administrator for the SDE script.
- Some paths may be locked by running processes. The script logs these and continues — this is expected behavior.

**CleanMgr or DISM hangs**
- These are Windows built-in tools and can be slow on first run. Wait at least 10–15 minutes before assuming a hang.
- DISM requires a working Windows Update service. If it fails, check `Windows Update` service status.

**Intune script shows as failed**
- Confirm the script is assigned to run in **user context**, not system context.
- Check `%LOCALAPPDATA%\IntuneCleanup\Logs\` on the affected device for details.

---

## Safety Notes

- Always run `Analyze` mode first on unfamiliar machines to preview what will be removed.
- Test in a pilot environment before wide deployment.
- The SDE script force-closes active applications — warn users before running interactively.
- Review included paths before deploying in environments with non-standard app installations.
- `-CreateRestorePoint` creates a System Restore Point before cleaning — recommended for unattended full runs.

---

## License

Released under the **MIT License**. See [`LICENSE`](LICENSE) for details.

---

## Credits

Authored by **jino99**. Contributions and improvements are welcome via pull requests.
