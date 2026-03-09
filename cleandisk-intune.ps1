<#
.SYNOPSIS
  Disk Cleanup Tool - Intune Version (User Context) - Enhanced Cache Removal
.DESCRIPTION
  Script ottimizzato per Microsoft Intune. 
  Esegue una pulizia profonda delle cache applicative (Office, Teams, Browser, Temp) 
  nel contesto dell'utente loggato.
  I processi attivi non vengono interrotti; i file in uso vengono saltati.
#>

param(
    [string]$LogPath
)

# --- 1. Inizializzazione Ambiente ---
$ErrorActionPreference = 'SilentlyContinue'

$LogDir = "$env:LOCALAPPDATA\IntuneCleanup\Logs"
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if ([string]::IsNullOrEmpty($LogPath)) { 
    $LogPath = "$LogDir\Cleanup_$(Get-Date -Format 'yyyyMMdd_HHmm').log" 
}

function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogLine = "[$Timestamp] [$Level] $Message"
    $LogLine | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host $LogLine
}

# --- 2. Avvio ---
Write-Log "AVVIO PULIZIA POTENZIATA (USER CONTEXT)" 'START'
$InitialFree = [math]::Round(((Get-PSDrive C).Free / 1GB), 2)

# --- 3. Pulizia Microsoft Teams (Classico & New) ---
Write-Log "Pulizia cache Microsoft Teams..."
$TeamsPaths = @(
    "$env:APPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
)

$TeamsSubFolders = @("Cache", "Code Cache", "GPUCache", "databases", "IndexedDB", "Local Storage", "tmp", "Service Worker")

foreach ($Base in $TeamsPaths) {
    if (Test-Path $Base) {
        foreach ($Sub in $TeamsSubFolders) {
            $Target = Join-Path $Base $Sub
            if (Test-Path $Target) {
                Get-ChildItem -Path "$Target\*" -Recurse -Force | Remove-Item -Force -Recurse
            }
        }
    }
}

# --- 4. Pulizia Microsoft Office & Outlook ---
Write-Log "Pulizia profonda Office Cache..."
$OfficePaths = @(
    # Office File Cache (La più pesante)
    "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
    "$env:LOCALAPPDATA\Microsoft\Office\OTele",
    # Outlook Temp/Cache
    "$env:LOCALAPPDATA\Microsoft\Outlook\Offline Address Books",
    "$env:LOCALAPPDATA\Microsoft\Office\SolutionPackages",
    "$env:LOCALAPPDATA\Microsoft\Office\WebWebView2Cache"
    "$env:LOCALAPPDATA\Microsoft\OneDrive\logs"
)

foreach ($Path in $OfficePaths) {
    if (Test-Path $Path) {
        Get-ChildItem -Path "$Path\*" -Recurse -Force | Remove-Item -Force -Recurse
        Write-Log "Rimossi contenuti in: $Path"
    }
}

# --- 5. Browser Cache (Chrome & Edge) ---
Write-Log "Pulizia cache Browser..."
$BrowserPaths = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
)

foreach ($Path in $BrowserPaths) {
    if (Test-Path $Path) {
        Get-ChildItem -Path "$Path\*" -Recurse -Force | Remove-Item -Force -Recurse
    }
}

# --- 6. Cache Grafica & Windows ---
Write-Log "Pulizia Shader Cache e Temp Windows..."
$MiscPaths = @(
    "$env:LOCALAPPDATA\D3DSCache",
    "$env:LOCALAPPDATA\NVIDIA\DXCache"
)

foreach ($Path in $MiscPaths) {
    if (Test-Path $Path) { 
        Remove-Item -Path "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue 
    }
}

# Explorer Thumbnails (solo se non in uso)
$ExplorerCache = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path $ExplorerCache) {
    Get-ChildItem -Path $ExplorerCache -Filter "thumbcache_*.db" -Force | Remove-Item -Force -ErrorAction SilentlyContinue
}

# --- 7. File Temporanei Utente (> 3 giorni) ---
# Ridotto a 3 giorni per essere più aggressivo
$LimitDate = (Get-Date).AddDays(-3)
if (Test-Path $env:TEMP) {
    Get-ChildItem -Path "$env:TEMP\*" -Recurse | 
        Where-Object { $_.LastWriteTime -lt $LimitDate } | 
        Remove-Item -Force -Recurse
    Write-Log "Puliti file temporanei più vecchi di 3 giorni."
}

ipconfig /flushdns | Out-Null

# --- 8. Conclusione ---
$FinalFree = [math]::Round(((Get-PSDrive C).Free / 1GB), 2)
$TotalFreed = [math]::Round(($FinalFree - $InitialFree), 2)
if ($TotalFreed -lt 0) { $TotalFreed = 0 }

Write-Log "PULIZIA COMPLETATA. Spazio recuperato: $TotalFreed GB" 'DONE'

# Output per Intune Detection/Reporting
return "CleanupFinished;FreedGB:$TotalFreed;FinalFreeGB:$FinalFree"