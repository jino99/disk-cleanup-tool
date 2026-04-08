<#
.SYNOPSIS
  Disk Cleanup Tool - Intune Version v1.2
.DESCRIPTION
  Optimized for silent deployment via Microsoft Intune (user context).
  Cleans application caches, browser data, Office files, GPU caches, and
  third-party app caches for the currently logged-in user.
  Running processes are never terminated; files in use are silently skipped.
  Does not access personal files (Documents, Pictures, Desktop).
#>

param(
    [string]$LogFile
)

# --- 1. Environment Setup ---
$ErrorActionPreference = 'SilentlyContinue'

$LogDir = "$env:LOCALAPPDATA\IntuneCleanup\Logs"
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if ([string]::IsNullOrEmpty($LogFile)) {
    $LogFile = "$LogDir\Cleanup_$($env:USERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
}

function Write-Log([string]$Message, [string]$Severity = 'INFO') {
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$Timestamp] [$Severity] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host "[$Timestamp] [$Severity] $Message"
}

function Clear-DirContents([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log "Cleaned: $Path"
    }
}

# --- 2. Startup ---
Write-Log "STARTING INTUNE CLEANUP (USER CONTEXT)" 'START'
$SysDrive    = $env:SystemDrive.TrimEnd(':')
$DriveInfo   = Get-PSDrive $SysDrive -ErrorAction SilentlyContinue
if (-not $DriveInfo) {
    Write-Log "Cannot read system drive '$SysDrive'. Aborting." 'ERROR'
    return "CleanupFailed;Reason:DriveNotFound"
}
$InitialFree = [math]::Round(($DriveInfo.Free / 1GB), 2)

# --- 3. Microsoft Teams (Classic & New) ---
Write-Log "Cleaning Microsoft Teams cache..."
$TeamsSubFolders = @("Cache", "Code Cache", "GPUCache", "databases", "IndexedDB", "Local Storage", "tmp", "Service Worker")
foreach ($Base in @(
    "$env:APPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
)) {
    if (Test-Path -LiteralPath $Base) {
        foreach ($Sub in $TeamsSubFolders) {
            Clear-DirContents -Path (Join-Path $Base $Sub)
        }
    }
}

# --- 4. Microsoft Office & Outlook ---
Write-Log "Cleaning Office cache..."
foreach ($P in @(
    "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
    "$env:LOCALAPPDATA\Microsoft\Office\15.0\OfficeFileCache",
    "$env:LOCALAPPDATA\Microsoft\Office\OTele",
    "$env:LOCALAPPDATA\Microsoft\Outlook\Offline Address Books",
    "$env:LOCALAPPDATA\Microsoft\Office\SolutionPackages",
    "$env:LOCALAPPDATA\Microsoft\Office\WebWebView2Cache",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\logs"
)) { Clear-DirContents -Path $P }

# --- 5. Browser Cache (Chrome & Edge) ---
Write-Log "Cleaning browser cache..."
foreach ($P in @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
)) { Clear-DirContents -Path $P }

# --- 6. GPU Shader Caches & Explorer Thumbnails ---
Write-Log "Cleaning GPU shader caches..."
foreach ($P in @(
    "$env:LOCALAPPDATA\D3DSCache",
    "$env:LOCALAPPDATA\NVIDIA\DXCache",
    "$env:LOCALAPPDATA\NVIDIA\GLCache",
    "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache",
    "$env:LOCALAPPDATA\AMD\DXCache"
)) { Clear-DirContents -Path $P }

$ExplorerCache = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path -LiteralPath $ExplorerCache) {
    Get-ChildItem -LiteralPath $ExplorerCache -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "Cleaned: Explorer thumbnail cache"
}

# --- 7. Third-party App Caches ---
Write-Log "Cleaning third-party app caches..."
foreach ($P in @(
    "$env:APPDATA\WhatsApp\Cache",
    "$env:LOCALAPPDATA\WhatsApp\Cache",
    "$env:LOCALAPPDATA\Spotify\Data",
    "$env:LOCALAPPDATA\Spotify\Storage",
    "$env:USERPROFILE\AppData\LocalLow\Sun\Java\Deployment\cache",
    "$env:LOCALAPPDATA\VMware\VDM\logs",
    "$env:LOCALAPPDATA\VMware\VDM\cache"
)) { Clear-DirContents -Path $P }

# Visual Studio — enumerate version folders explicitly
$VSBase = "$env:LOCALAPPDATA\Microsoft\VisualStudio"
if (Test-Path -LiteralPath $VSBase) {
    foreach ($VSVer in (Get-ChildItem -LiteralPath $VSBase -Directory -ErrorAction SilentlyContinue)) {
        foreach ($VSCache in @("ComponentModelCache", "Designer\ShadowCache")) {
            Clear-DirContents -Path (Join-Path $VSVer.FullName $VSCache)
        }
    }
}

# --- 8. User Temp Files (older than 3 days) ---
Write-Log "Cleaning user temp files older than 3 days..."
if (Test-Path -LiteralPath $env:TEMP) {
    Get-ChildItem -LiteralPath $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { !$_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "User temp cleaned."
}

ipconfig /flushdns | Out-Null
Write-Log "DNS cache flushed."

# --- 9. Summary ---
$FinalFree  = [math]::Round(((Get-PSDrive $SysDrive -ErrorAction SilentlyContinue).Free / 1GB), 2)
$TotalFreed = [math]::Round(($FinalFree - $InitialFree), 2)
if ($TotalFreed -lt 0) { $TotalFreed = 0 }

Write-Log "CLEANUP COMPLETE. Space freed: $TotalFreed GB" 'DONE'

return "CleanupFinished;FreedGB:$TotalFreed;FinalFreeGB:$FinalFree"
