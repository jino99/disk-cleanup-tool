<#
.SYNOPSIS
  Disk Cleanup Tool - Service Desk Edition (SDE) v3.1
.DESCRIPTION
  Advanced system-wide, multi-user disk cleanup tool for technician use.
  Requires Local Administrator privileges for full functionality.
  Run without parameters to launch the interactive menu.

.PARAMETER Mode
  Clean   : Full cleanup — Windows Update cache, Recycle Bin, SSD ReTrim (Default).
  Analyze : Simulates all operations without deleting any files.

.PARAMETER Scope
  Low    : User caches only (browsers, GPU, temp, third-party apps).
  Medium : Adds system cache, Windows Update logs, and CleanMgr (Default).
  Full   : Everything — also runs DISM component cleanup and removes obsolete drivers.

.PARAMETER ForceCleanMgr
  Forces CleanMgr to run regardless of -Scope.

.PARAMETER ForceDism
  Forces DISM StartComponentCleanup to run regardless of -Scope.

.PARAMETER CreateRestorePoint
  Creates a System Restore Point before starting the cleanup.

.PARAMETER Help
  Displays this help message and exits.

.EXAMPLE
  .\disk-cleanup.ps1
.EXAMPLE
  .\disk-cleanup.ps1 -Mode Clean -Scope Full -CreateRestorePoint
.EXAMPLE
  .\disk-cleanup.ps1 -Mode Analyze -Scope Medium
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Clean", "Analyze")]
    [string]$Mode,

    [Parameter(Mandatory=$false)]
    [ValidateSet("Low", "Medium", "Full")]
    [string]$Scope,

    [switch]$SuppressConfirmation,
    [switch]$ForceCleanMgr,
    [switch]$ForceDism,
    [switch]$CreateRestorePoint,
    [switch]$Help,

    [string]$LogFile
)

# ---------------------------------------------------------------------------
# 0. Environment
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'SilentlyContinue'
if ($Help) { Get-Help $MyInvocation.MyCommand.Path -Full; exit 0 }
if ($SuppressConfirmation) { $ConfirmPreference = 'None' }

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$LogDir = "$env:ProgramData\ServiceDeskCleanup\Logs"
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Write-Log([string]$Message, [string]$Severity = 'INFO') {
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$Timestamp] [$Severity] $Message" | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
    $Color = switch ($Severity) {
        'START'  { 'Cyan'    }
        'WARN'   { 'Yellow'  }
        'ERROR'  { 'Red'     }
        'FINISH' { 'Green'   }
        'SYSTEM' { 'Magenta' }
        default  { 'Gray'    }
    }
    Write-Host "  [$Severity] $Message" -ForegroundColor $Color
}

function Remove-DirContents([string]$Path) {
    if (!(Test-Path -LiteralPath $Path)) { return }
    if ($script:Mode -eq 'Analyze') {
        $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $sizeStr = if ($size) { "$([math]::Round($size/1MB, 1)) MB" } else { '0 MB' }
        $script:SimulatedFreedBytes += $size
        Write-Log "[SIMULATE] Would clean: $Path  ($sizeStr)" 'INFO'
        return
    }
    try {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log "Cleaned: $Path" 'INFO'
    } catch {
        Write-Log "Could not clean (in use or access denied): $Path" 'WARN'
    }
}

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
function Write-Sep([string]$Color = 'DarkGray') {
    Write-Host "  $('─' * 50)" -ForegroundColor $Color
}

function Write-Option([string]$Key, [string]$Label, [string]$Desc, [bool]$Selected) {
    if ($Selected) {
        Write-Host "  " -NoNewline
        Write-Host " ● " -NoNewline -ForegroundColor Cyan
        Write-Host "[$Key]  " -NoNewline -ForegroundColor Cyan
        Write-Host $Label -NoNewline -ForegroundColor White
        Write-Host "  $Desc" -ForegroundColor DarkGray
    } else {
        Write-Host "  " -NoNewline
        Write-Host "   " -NoNewline
        Write-Host "[$Key]  " -NoNewline -ForegroundColor DarkGray
        Write-Host $Label -NoNewline -ForegroundColor Gray
        Write-Host "  $Desc" -ForegroundColor DarkGray
    }
}

function Write-Toggle([string]$Key, [string]$Label, [bool]$On) {
    $badge      = if ($On) { ' ON  ' } else { ' OFF ' }
    $badgeFg    = if ($On) { 'Black'    } else { 'DarkGray' }
    $badgeBg    = if ($On) { 'DarkGreen'} else { 'DarkGray' }
    $labelColor = if ($On) { 'White'    } else { 'Gray'     }
    Write-Host "     [$Key]  " -NoNewline -ForegroundColor DarkGray
    Write-Host $Label -NoNewline -ForegroundColor $labelColor
    Write-Host "  " -NoNewline
    Write-Host $badge -BackgroundColor $badgeBg -ForegroundColor $badgeFg
}

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------
function Show-Menu {
    $drive      = Get-PSDrive ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if (-not $drive) { $drive = [PSCustomObject]@{ Free = 0; Used = 0 } }
    $freeGB     = [math]::Round($drive.Free / 1GB, 1)
    $totalGB    = [math]::Round(($drive.Used + $drive.Free) / 1GB, 1)
    $totalBytes = $drive.Used + $drive.Free
    $usedPct    = if ($totalBytes -gt 0) { [math]::Round(($drive.Used / $totalBytes) * 100) } else { 0 }
    $adminTag   = if ($IsAdmin) { 'Administrator' } else { 'Standard User (limited)' }
    $adminColor = if ($IsAdmin) { 'Green' } else { 'Yellow' }

    Clear-Host
    Write-Host ""
    Write-Host "  Disk Cleanup Tool  " -NoNewline -ForegroundColor White
    Write-Host "·  Service Desk Edition" -ForegroundColor DarkGray
    Write-Host "  " -NoNewline
    Write-Host $adminTag -NoNewline -ForegroundColor $adminColor
    Write-Host "   C: $freeGB GB free of $totalGB GB  ($usedPct% used)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Sep

    # MODE
    Write-Host ""
    Write-Host "  MODE" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Option '1' 'Clean  ' '  full cleanup: caches, WU, Recycle Bin, ReTrim' ($script:Mode -eq 'Clean')
    Write-Option '2' 'Analyze' '  simulate only — nothing will be deleted       ' ($script:Mode -eq 'Analyze')
    Write-Host ""
    Write-Sep

    # LEVEL
    Write-Host ""
    Write-Host "  LEVEL" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Option '3' 'Low   ' '  user caches only (browsers, GPU, temp, apps)  ' ($script:Scope -eq 'Low')
    Write-Option '4' 'Medium' '  + system cache, Windows Update, CleanMgr      ' ($script:Scope -eq 'Medium')
    Write-Option '5' 'Full  ' '  + DISM component cleanup, obsolete drivers     ' ($script:Scope -eq 'Full')
    Write-Host ""
    Write-Sep

    # OPTIONS
    Write-Host ""
    Write-Host "  OPTIONS" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Toggle '6' 'Force CleanMgr        ' $script:ForceCleanMgr
    Write-Toggle '7' 'Force DISM            ' $script:ForceDism
    Write-Toggle '8' 'System Restore Point  ' $script:CreateRestorePoint
    Write-Host ""
    Write-Sep
    Write-Host ""

    # RUN / QUIT
    $runLabel = if ($script:Mode -eq 'Analyze') { 'Run Simulation' } else { 'Run Cleanup' }
    Write-Host "  " -NoNewline
    Write-Host " [R]  $runLabel " -NoNewline -ForegroundColor Black -BackgroundColor DarkCyan
    Write-Host "   [Q]  Quit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Press a number to change a setting, R to run, Q to quit." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  › " -NoNewline -ForegroundColor Cyan
}

function Show-ConfirmScreen {
    $freeGB = [math]::Round((Get-PSDrive ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue).Free / 1GB, 1)

    Clear-Host
    Write-Host ""
    Write-Host "  Confirm Cleanup" -ForegroundColor Yellow
    Write-Host ""
    Write-Sep
    Write-Host ""
    Write-Host "  Mode   " -NoNewline -ForegroundColor DarkGray
    Write-Host $script:Mode -ForegroundColor White
    Write-Host "  Scope  " -NoNewline -ForegroundColor DarkGray
    Write-Host $script:Scope -ForegroundColor White

    $extras = @()
    if ($script:ForceCleanMgr)  { $extras += 'Force CleanMgr' }
    if ($script:ForceDism)      { $extras += 'Force DISM' }
    if ($script:CreateRestorePoint) { $extras += 'System Restore Point' }
    if ($extras.Count) {
        Write-Host "  Extras " -NoNewline -ForegroundColor DarkGray
        Write-Host ($extras -join '  ·  ') -ForegroundColor Cyan
    }

    Write-Host "  Free   " -NoNewline -ForegroundColor DarkGray
    Write-Host "$freeGB GB available before cleanup" -ForegroundColor Gray
    Write-Host ""
    Write-Sep
    Write-Host ""
    Write-Host "  ⚠  Active applications will be force-closed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [Y]  Proceed    [N]  Back" -ForegroundColor White
    Write-Host ""
    Write-Host "  › " -NoNewline -ForegroundColor Cyan
}

function Start-InteractiveMenu {
    $script:Mode         = 'Clean'
    $script:Scope        = 'Medium'
    $script:ForceCleanMgr  = $false
    $script:ForceDism      = $false
    $script:CreateRestorePoint = $false

    while ($true) {
        Show-Menu
        $key = (Read-Host).Trim().ToUpper()

        $feedback = $null
        switch ($key) {
            '1' { $script:Mode  = 'Clean';   $feedback = 'Mode set to Clean'   }
            '2' { $script:Mode  = 'Analyze'; $feedback = 'Mode set to Analyze' }
            '3' { $script:Scope = 'Low';     $feedback = 'Scope set to Low'    }
            '4' { $script:Scope = 'Medium';  $feedback = 'Scope set to Medium' }
            '5' { $script:Scope = 'Full';    $feedback = 'Scope set to Full'   }
            '6' { $script:ForceCleanMgr  = !$script:ForceCleanMgr;  $feedback = "Force CleanMgr: $(if ($script:ForceCleanMgr) {'ON'} else {'OFF'})"  }
            '7' { $script:ForceDism      = !$script:ForceDism;      $feedback = "Force DISM: $(if ($script:ForceDism) {'ON'} else {'OFF'})"           }
            '8' { $script:CreateRestorePoint = !$script:CreateRestorePoint; $feedback = "System Restore Point: $(if ($script:CreateRestorePoint) {'ON'} else {'OFF'})" }
            'R' {
                if ($script:Mode -eq 'Analyze') { return }
                Show-ConfirmScreen
                $confirm = (Read-Host).Trim().ToUpper()
                if ($confirm -eq 'Y') { return }
            }
            'Q' {
                Clear-Host
                Write-Host ""
                Write-Host "  Goodbye." -ForegroundColor DarkGray
                Write-Host ""
                exit 0
            }
            default { $feedback = "Unknown key '$key' - use 1-8, R, or Q" }
        }

        if ($feedback) {
            Write-Host "  ✔ $feedback" -ForegroundColor Cyan
            Start-Sleep -Milliseconds 350
        }
    }
}

# ---------------------------------------------------------------------------
# CLI vs Interactive detection
# ---------------------------------------------------------------------------
$cliMode = $PSBoundParameters.ContainsKey('Mode')        -or
           $PSBoundParameters.ContainsKey('Scope')       -or
           $PSBoundParameters.ContainsKey('ForceCleanMgr') -or
           $PSBoundParameters.ContainsKey('ForceDism')     -or
           $PSBoundParameters.ContainsKey('CreateRestorePoint')

if ($cliMode) {
    $script:Mode         = if ($PSBoundParameters.ContainsKey('Mode'))  { $Mode  } else { 'Clean'  }
    $script:Scope        = if ($PSBoundParameters.ContainsKey('Scope')) { $Scope } else { 'Medium' }
    $script:ForceCleanMgr  = $ForceCleanMgr.IsPresent
    $script:ForceDism      = $ForceDism.IsPresent
    $script:CreateRestorePoint = $CreateRestorePoint.IsPresent
} else {
    Start-InteractiveMenu
}

$script:LogFile = if (![string]::IsNullOrEmpty($LogFile)) { $LogFile } else {
    "$LogDir\SDE_Cleanup_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
}

# ---------------------------------------------------------------------------
# 1. Startup header
# ---------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  Disk Cleanup Tool  " -NoNewline -ForegroundColor White
Write-Host "·  Service Desk Edition" -ForegroundColor DarkGray
Write-Host ""
Write-Sep
Write-Host ""
Write-Host "  Mode   " -NoNewline -ForegroundColor DarkGray; Write-Host $script:Mode  -ForegroundColor White
Write-Host "  Scope  " -NoNewline -ForegroundColor DarkGray; Write-Host $script:Scope -ForegroundColor White
Write-Host "  Log    " -NoNewline -ForegroundColor DarkGray; Write-Host $script:LogFile -ForegroundColor DarkGray
Write-Host ""
Write-Sep
Write-Host ""

Write-Log "STARTING SERVICE DESK CLEANUP - Mode: $($script:Mode) | Scope: $($script:Scope)" 'START'
if (!$IsAdmin) {
    Write-Log "WARNING: Running without Administrator privileges. System cleanup and Backup are disabled." 'WARN'
}

# 1.1 System Restore Point
if ($script:CreateRestorePoint -and $IsAdmin -and $script:Mode -ne 'Analyze') {
    Write-Log "Creating System Restore Point..." 'SYSTEM'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "SDE_Cleanup_$(Get-Date -Format 'yyyyMMdd')" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "System Restore Point created successfully." 'SYSTEM'
    } catch {
        Write-Log "Could not create Restore Point. Continuing anyway." 'WARN'
    }
}

$SystemDrive = $env:SystemDrive.TrimEnd(':')
$DriveInfo   = Get-PSDrive $SystemDrive -ErrorAction SilentlyContinue
if (-not $DriveInfo) {
    Write-Log "Cannot read system drive '$SystemDrive'. Aborting." 'ERROR'
    return "CleanupFailed;Reason:DriveNotFound"
}
$InitialFree = [math]::Round(($DriveInfo.Free / 1GB), 2)
$script:SimulatedFreedBytes = 0

# ---------------------------------------------------------------------------
# 2. Process Termination
# ---------------------------------------------------------------------------
if ($script:Mode -ne 'Analyze') {
    Write-Host ""
    Write-Log "Checking for running processes..." 'SYSTEM'
    foreach ($App in @("msedge","chrome","firefox","ms-teams","Teams","outlook","excel","winword","powerpnt","onedrive")) {
        if (Get-Process -Name $App -ErrorAction SilentlyContinue) {
            Write-Log "Force-closing: $App" 'WARN'
            Stop-Process -Name $App -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
} else {
    Write-Host ""
    Write-Log "Checking for running processes (simulate)..." 'SYSTEM'
    foreach ($App in @("msedge","chrome","firefox","ms-teams","Teams","outlook","excel","winword","powerpnt","onedrive")) {
        if (Get-Process -Name $App -ErrorAction SilentlyContinue) {
            Write-Log "[SIMULATE] Would force-close: $App" 'WARN'
        }
    }
}

# ---------------------------------------------------------------------------
# 3. System-Wide Cleanup
# ---------------------------------------------------------------------------
if ($IsAdmin -and ($script:Scope -ne 'Low' -or $script:ForceCleanMgr -or $script:ForceDism)) {
    Write-Host ""
    Write-Log "--- SYSTEM CLEANUP ---" 'SYSTEM'

    if ($script:Mode -eq 'Clean') {
        Write-Log "Stopping Windows Update service temporarily..." 'SYSTEM'
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        foreach ($P in @(
            "$env:windir\Logs\CBS",
            "$env:windir\Logs\DISM",
            "$env:windir\SoftwareDistribution\Download"
        )) { Remove-DirContents -Path $P }
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    } elseif ($script:Mode -eq 'Analyze') {
        Write-Log "[SIMULATE] Would clean Windows Update cache and logs" 'INFO'
    }

    if ($script:ForceCleanMgr -or $script:Scope -ne 'Low') {
        if ($script:Mode -eq 'Analyze') {
            Write-Log "[SIMULATE] Would run CleanMgr (SageRun: 69)" 'INFO'
        } else {
            Write-Log "Running CleanMgr (SageRun: 69)..." 'SYSTEM'
            try {
                $RegPath   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
                $SageRunID = 69
                Get-ChildItem $RegPath -ErrorAction SilentlyContinue | ForEach-Object {
                    New-ItemProperty -Path $_.PSPath -Name "StateFlags$SageRunID" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
                }
                Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:$SageRunID" -Wait -WindowStyle Hidden
                Write-Log "CleanMgr completed." 'SYSTEM'
            } catch {
                Write-Log "CleanMgr error: $_" 'ERROR'
            }
        }
    }

    if ($script:ForceDism -or $script:Scope -eq 'Full') {
        if ($script:Mode -eq 'Analyze') {
            Write-Log "[SIMULATE] Would run DISM StartComponentCleanup" 'INFO'
        } else {
            Write-Log "Running DISM StartComponentCleanup (this may take a while)..." 'SYSTEM'
            try {
                $proc = Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /startcomponentcleanup" -Wait -PassThru -NoNewWindow
                if ($proc.ExitCode -eq 0) {
                    Write-Log "DISM completed successfully." 'SYSTEM'
                } else {
                    Write-Log "DISM exited with code: $($proc.ExitCode)." 'ERROR'
                }
            } catch {
                Write-Log "DISM critical error: $_" 'ERROR'
            }
        }
    }

    if ($script:Scope -eq 'Full') {
        if ($script:Mode -eq 'Analyze') {
            Write-Log "[SIMULATE] Would remove obsolete OEM drivers" 'INFO'
        } else {
            Write-Log "Removing obsolete drivers..." 'WARN'
            try {
                $OemDrivers      = @(pnputil.exe /enum-drivers | Select-String -Pattern '^Published Name\s*:\s*(oem\d+\.inf)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
                $ActiveDrivers   = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.InfName } | ForEach-Object { [System.IO.Path]::GetFileName($_.InfName).ToLower() })
                $DriversToRemove = @($OemDrivers | Where-Object { $_.ToLower() -notin $ActiveDrivers })
                foreach ($Driver in $DriversToRemove) {
                    Write-Log "Removing: $Driver" 'WARN'
                    $proc = Start-Process "pnputil.exe" -ArgumentList @("/delete-driver", $Driver, "/uninstall", "/force") -Wait -PassThru -NoNewWindow
                    if ($proc.ExitCode -eq 0) { Write-Log "Removed: $Driver" 'SYSTEM' }
                    else { Write-Log "Could not remove $Driver (ExitCode: $($proc.ExitCode))" 'WARN' }
                }
                Write-Log "Driver cleanup done. Removed: $($DriversToRemove.Count)" 'SYSTEM'
            } catch {
                Write-Log "pnputil error: $_" 'ERROR'
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 4. Multi-User Profile Cleanup
# ---------------------------------------------------------------------------
Write-Host ""
Write-Log "--- USER PROFILE CLEANUP ---" 'START'

$UserProfiles = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users") }

foreach ($Profile in $UserProfiles) {
    Write-Log "Profile: $($Profile.Name)" 'INFO'
    $U = $Profile.FullName

    foreach ($P in @(
        "$U\AppData\Local\Google\Chrome\User Data\Default\Cache",
        "$U\AppData\Local\Google\Chrome\User Data\Default\Code Cache",
        "$U\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
        "$U\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache"
    )) { Remove-DirContents -Path $P }

    if ($script:Scope -ne 'Low') {
        foreach ($P in @(
            "$U\AppData\Roaming\Microsoft\Teams\Cache",
            "$U\AppData\Roaming\Microsoft\Teams\blob_storage",
            "$U\AppData\Roaming\Microsoft\Teams\IndexedDB",
            "$U\AppData\Roaming\Microsoft\Teams\GPUCache",
            "$U\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache",
            "$U\AppData\Local\Microsoft\Office\16.0\OfficeFileCache",
            "$U\AppData\Local\Microsoft\Office\15.0\OfficeFileCache",
            "$U\AppData\Local\Microsoft\OneDrive\logs",
            "$U\AppData\Local\Microsoft\Office\OTele",
            "$U\AppData\Local\Microsoft\Outlook\Offline Address Books",
            "$U\AppData\Local\Microsoft\Office\SolutionPackages",
            "$U\AppData\Local\Microsoft\Office\WebWebView2Cache"
        )) { Remove-DirContents -Path $P }
    }

    foreach ($P in @(
        "$U\AppData\Local\D3DSCache",
        "$U\AppData\Local\NVIDIA\DXCache",
        "$U\AppData\Local\NVIDIA\GLCache",
        "$U\AppData\Local\NVIDIA Corporation\NV_Cache",
        "$U\AppData\Local\AMD\DXCache",
        "$U\AppData\Local\Temp",
        "$U\AppData\Roaming\WhatsApp\Cache",
        "$U\AppData\Local\WhatsApp\Cache",
        "$U\AppData\Local\Spotify\Data",
        "$U\AppData\Local\Spotify\Storage",
        "$U\AppData\LocalLow\Sun\Java\Deployment\cache",
        "$U\AppData\Local\VMware\VDM\logs",
        "$U\AppData\Local\VMware\VDM\cache"
    )) { Remove-DirContents -Path $P }

    $VSBase = "$U\AppData\Local\Microsoft\VisualStudio"
    if (Test-Path -LiteralPath $VSBase) {
        foreach ($VSVer in (Get-ChildItem -LiteralPath $VSBase -Directory -ErrorAction SilentlyContinue)) {
            foreach ($VSCache in @("ComponentModelCache", "Designer\ShadowCache")) {
                Remove-DirContents -Path (Join-Path $VSVer.FullName $VSCache)
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Final Operations
# ---------------------------------------------------------------------------
Write-Host ""
Write-Log "--- FINAL OPERATIONS ---" 'START'

if ($IsAdmin -and $script:Scope -ne 'Low' -and (Test-Path "$env:windir\Temp")) {
    if ($script:Mode -eq 'Analyze') {
        Write-Log "[SIMULATE] Would clean global Temp (files older than 7 days)" 'INFO'
    } else {
        Get-ChildItem -Path "$env:windir\Temp" -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Log "Global Temp cleaned." 'INFO'
    }
}

if ($script:Mode -ne 'Analyze') {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Log "Recycle Bin emptied." 'INFO'
    if ($IsAdmin -and $script:Mode -eq 'Clean') {
        Write-Log "Running SSD ReTrim..." 'SYSTEM'
        Optimize-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ReTrim -ErrorAction SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
    Write-Log "DNS cache flushed." 'INFO'
} else {
    Write-Log "[SIMULATE] Would empty Recycle Bin" 'INFO'
    if ($IsAdmin) { Write-Log "[SIMULATE] Would run SSD ReTrim" 'INFO' }
    Write-Log "[SIMULATE] Would flush DNS cache" 'INFO'
}

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
$FinalFree  = [math]::Round(((Get-PSDrive ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue).Free / 1GB), 2)
$TotalFreed = [math]::Round(($FinalFree - $InitialFree), 2)
if ($TotalFreed -lt 0) { $TotalFreed = 0 }

$logSpaceLabel = if ($script:Mode -eq 'Analyze') { "$([math]::Round($script:SimulatedFreedBytes/1GB, 2)) GB (estimated)" } else { "$TotalFreed GB" }
$logFinishMsg  = if ($script:Mode -eq 'Analyze') { "SIMULATION COMPLETE [DRY RUN — no files were deleted]. Est. savings: $logSpaceLabel" } else { "CLEANUP COMPLETE. Space freed: $logSpaceLabel" }
Write-Log $logFinishMsg 'FINISH'

$resultLabel = if ($script:Mode -eq 'Analyze') { 'Simulation complete.' } else { 'Cleanup complete.' }
$resultColor = if ($script:Mode -eq 'Analyze') { 'Yellow' } else { 'Green' }

Write-Host ""
Write-Sep
Write-Host ""
Write-Host "  $resultLabel" -ForegroundColor $resultColor
Write-Host ""
Write-Host "  Mode          " -NoNewline -ForegroundColor DarkGray
Write-Host "$($script:Mode)  ·  Scope: $($script:Scope)" -ForegroundColor White
Write-Host "  Restore Point " -NoNewline -ForegroundColor DarkGray
Write-Host "$(if ($script:CreateRestorePoint -and $script:Mode -ne 'Analyze') { 'Created' } else { 'Skipped' })" -ForegroundColor White
$spaceKey   = if ($script:Mode -eq 'Analyze') { "  Est. Savings  " } else { "  Space Freed   " }
$spaceLabel = if ($script:Mode -eq 'Analyze') { "$([math]::Round($script:SimulatedFreedBytes/1GB, 2)) GB (estimated)" } else { "$TotalFreed GB" }
Write-Host $spaceKey -NoNewline -ForegroundColor DarkGray
Write-Host $spaceLabel -ForegroundColor Green
Write-Host "  Log           " -NoNewline -ForegroundColor DarkGray
Write-Host $script:LogFile -ForegroundColor DarkGray
Write-Host ""
Write-Sep
Write-Host ""

exit 0
