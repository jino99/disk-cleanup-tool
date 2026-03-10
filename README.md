Windows Advanced Disk Cleanup Tools

This repository contains two PowerShell scripts designed for advanced Windows disk cleanup and cache removal. They are tailored for different deployment scenarios: one for interactive IT Service Desk usage and another for silent deployment via Microsoft Intune.

🛠️ Scripts Overview
1. Service Desk Edition (cleandisk-sde.ps1)
The Service Desk Edition (v2.3) is an advanced, system-wide, and multi-user cleanup tool. It is designed for IT administrators who need deep cleaning capabilities on a target machine.

Key Features:

Process Management: Automatically force-closes active applications like Edge, Chrome, Firefox, Teams, and Office apps before cleaning.

System Restore: Can optionally create a System Restore Point before proceeding.

Deep System Cleaning: Can invoke native Windows cleanmgr.exe (via SageRun) and DISM Component Cleanup.

Driver Cleanup: Allows for the removal of obsolete drivers using pnputil.exe under the "High" risk level.

Multi-User Profiling: Iterates through C:\Users to clean browser caches, Teams, Office, and graphical caches for all users.

Parameters:

-Mode: Choose between QuickClean (standard cache/temp), FullClean (deep system clean), or AnalyzeOnly (simulates operations without deleting).

-RiskLevel: Choose Low (safe temps), Medium (app caches like Teams/Office), or High (enables driver removal and component compression).

-UseDism: Enables DISM Component Cleanup.

-UseCleanMgr: Forces all registry options and invokes cleanmgr.exe.

-EnableBackup: Creates a System Restore Point before cleaning.

2. Intune Version (cleandisk-intune.ps1)
The Intune Version is optimized for silent deployment via Microsoft Intune. It runs in the user context and focuses on safely removing application caches without disrupting the user's workflow.

Key Features:

Non-Disruptive: Active processes are not interrupted, and files currently in use are simply skipped.

Targeted Cache Removal: Performs deep cleaning of Microsoft Teams (Classic & New), Microsoft Office/Outlook, and Browsers (Chrome & Edge).

Aggressive Temp Cleanup: Removes user temporary files that are older than 3 days.

Intune Reporting: Outputs a formatted string (e.g., CleanupFinished;FreedGB:X;FinalFreeGB:Y) designed for Intune detection rules and reporting.

🚀 Usage Examples
Running the Service Desk Edition
For a standard, safe cleanup:

PowerShell
.\cleandisk-sde.ps1 -Mode QuickClean -RiskLevel Low
For a deep system cleanup with a backup restore point:

PowerShell
.\cleandisk-sde.ps1 -Mode FullClean -RiskLevel High -UseDism -UseCleanMgr -EnableBackup
To simulate a cleanup without deleting anything:

PowerShell
.\cleandisk-sde.ps1 -Mode AnalyzeOnly

Running the Intune Version
This script is designed to be deployed via Intune, but can be run locally in the user context:

PowerShell
.\cleandisk-intune.ps1
📝 Logging
Both scripts generate detailed logs to track the cleanup process and the amount of space freed.

SDE Log Path: $env:ProgramData\ServiceDeskCleanup\Logs

Intune Log Path: $env:LOCALAPPDATA\IntuneCleanup\Logs