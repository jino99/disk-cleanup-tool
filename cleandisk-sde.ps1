<#
.SYNOPSIS
  Disk Cleanup Tool - Service Desk Edition (SDE) v2.3
.DESCRIPTION
  Strumento di pulizia avanzata System-wide e Multi-user.
  
.PARAMETER Mode
  QuickClean: Pulizia standard cache e temp.
  FullClean: Include pulizia profonda sistema.
  AnalyzeOnly: Simula le operazioni senza cancellare.
  
.PARAMETER RiskLevel
  Low: Solo file temporanei sicuri.
  Medium: Include cache applicative (Teams/Office).
  High: Abilita rimozione driver obsoleti e compressione componenti (Richiede cautela).

.PARAMETER UseDism
  Abilita DISM Component Cleanup. (Se specificato, ignora il controllo RiskLevel).

.PARAMETER UseCleanMgr
  Invoca cleanmgr.exe con SageRun dopo aver forzato la selezione di tutte le opzioni nel registro.

.PARAMETER EnableBackup
  Crea un Punto di Ripristino del Sistema prima di procedere con la pulizia.

.example
  .\cleandisk-sde.ps1 -Mode FullClean -UseDism -UseCleanMgr -EnableBackup
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("QuickClean", "FullClean", "AnalyzeOnly")]
    [string]$Mode = "QuickClean",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Low", "Medium", "High")]
    [string]$RiskLevel = "Medium",

    [switch]$Force,
    [switch]$UseDism,
    [switch]$UseCleanMgr,
    [switch]$EnableBackup,
    [switch]$NoPrompt,
    
    [string]$LogPath
)

# --- 0. Inizializzazione Ambiente ---
$ErrorActionPreference = 'SilentlyContinue'
if ($Force -or $NoPrompt) { $ConfirmPreference = 'None' }

# Verifica Privilegi Admin
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Configurazione Log
$LogDir = "$env:ProgramData\ServiceDeskCleanup\Logs"
if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if ([string]::IsNullOrEmpty($LogPath)) { 
    $LogPath = "$LogDir\SDE_Cleanup_$(Get-Date -Format 'yyyyMMdd_HHmm').log" 
}

# --- FUNZIONI DI SUPPORTO ---

function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogLine = "[$Timestamp] [$Level] $Message"
    $LogLine | Out-File -FilePath $LogPath -Append -Encoding UTF8
    
    $Color = switch ($Level) {
        'START'  { 'Cyan' }
        'WARN'   { 'Yellow' }
        'ERROR'  { 'Red' }
        'FINISH' { 'Green' }
        'SYSTEM' { 'Magenta' }
        default  { 'Gray' }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $Color
}

function Remove-FileSafe {
    param([string]$Path, [bool]$Recurse = $true)
    
    if ($Mode -eq 'AnalyzeOnly') {
        Write-Log "[SIMULAZIONE] Rimozione: $Path" 'INFO'
        return
    }

    if (Test-Path $Path) {
        try {
            if ($Recurse) {
                Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            } else {
                Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
            }
            Write-Log "Pulito: $Path" 'INFO'
        } catch {
            Write-Log "Impossibile rimuovere (in uso/permessi): $Path" 'WARN'
        }
    }
}

# --- 1. AVVIO OPERAZIONI ---
Clear-Host
Write-Log "AVVIO SERVICE DESK CLEANUP - Mode: $Mode | Risk: $RiskLevel" 'START'
if (!$IsAdmin) { 
    Write-Log "ATTENZIONE: Script eseguito senza privilegi Admin. Pulizia sistema e Backup disabilitati." 'WARN' 
}

# 1.1 Gestione Backup (System Restore)
if ($EnableBackup -and $IsAdmin -and $Mode -ne 'AnalyzeOnly') {
    Write-Log "Creazione Punto di Ripristino del Sistema (EnableBackup attivo)..." 'SYSTEM'
    try {
        # Abilita ripristino su C: se disabilitato
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        # Crea il punto di ripristino
        Checkpoint-Computer -Description "SDE_Cleanup_Backup_$(Get-Date -Format 'yyyyMMdd')" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Punto di Ripristino creato con successo." 'SYSTEM'
    } catch {
        Write-Log "Impossibile creare punto di ripristino. Lo script continuerà comunque." 'WARN'
    }
}

# Memorizzazione spazio iniziale
$Drive = Get-PSDrive C
$InitialFree = [math]::Round(($Drive.Free / 1GB), 2)

# --- 2. CHIUSURA PROCESSI ---
if ($Mode -ne 'AnalyzeOnly') {
    $AppsToClose = @("msedge", "chrome", "firefox", "ms-teams", "Teams", "outlook", "excel", "winword", "powerpnt", "onedrive")
    Write-Host "`nVerifica processi attivi..." -ForegroundColor Yellow
    foreach ($App in $AppsToClose) {
        if (Get-Process -Name $App -ErrorAction SilentlyContinue) {
            Write-Log "Chiusura forzata: $App" 'WARN'
            Stop-Process -Name $App -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
}

# --- 3. PULIZIA SYSTEM-WIDE (Richiede Admin) ---
if ($IsAdmin) {
    Write-Log "--- INIZIO PULIZIA SISTEMA ---" 'SYSTEM'

    # 3.1 Windows Update & Logs
    if ($Mode -eq 'FullClean') {
        $SystemPaths = @(
            "$env:windir\Logs\CBS\*",
            "$env:windir\Logs\DISM\*",
            "$env:windir\Temp\*",
            "$env:windir\SoftwareDistribution\Download\*"
        )
        
        if ($Mode -ne 'AnalyzeOnly') { 
            Write-Log "Arresto temporaneo wuauserv..." 'SYSTEM'
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue 
        }
        
        foreach ($P in $SystemPaths) { Remove-FileSafe -Path $P }
        
        if ($Mode -ne 'AnalyzeOnly') { 
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue 
        }
    }

    # 3.2 Gestione CleanMgr (Nativo con SageRun)
    if (($UseCleanMgr -or $RiskLevel -eq 'High') -and $Mode -ne 'AnalyzeOnly') {
        Write-Log "Configurazione ed esecuzione CleanMgr (SageRun: 69)..." 'SYSTEM'
        try {
            $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
            $SageRunID = 69 
            $Handlers = Get-ChildItem $RegPath -ErrorAction SilentlyContinue
            foreach ($Handler in $Handlers) {
                $PropertyArgs = @{
                    Path         = $Handler.PSPath
                    Name         = "StateFlags$SageRunID"
                    Value        = 2
                    PropertyType = "DWord"
                    Force        = $true
                }
                New-ItemProperty @PropertyArgs -ErrorAction SilentlyContinue | Out-Null
            }

            Write-Log "Avvio cleanmgr.exe /sagerun:$SageRunID (Attendere...)" 'SYSTEM'
            $ProcessInfo = Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:$SageRunID" -Wait -PassThru -WindowStyle Hidden
            Write-Log "CleanMgr completato." 'SYSTEM'
        } catch {
            Write-Log "Errore durante esecuzione CleanMgr: $_" 'ERROR'
        }
    }

    # 3.3 DISM & Component Cleanup
    if (($UseDism -or $RiskLevel -eq 'High') -and $Mode -ne 'AnalyzeOnly') {
        Write-Log "Avvio DISM StartComponentCleanup. Potrebbe richiedere molto tempo..." 'SYSTEM'
        try {
            $DismArgs = "/online /cleanup-image /startcomponentcleanup"
            $Process = Start-Process -FilePath "dism.exe" -ArgumentList $DismArgs -Wait -PassThru -NoNewWindow
            
            if ($Process.ExitCode -eq 0) {
                Write-Log "DISM Component Cleanup completato con successo." 'SYSTEM'
            } else {
                Write-Log "DISM terminato con codice: $($Process.ExitCode)." 'ERROR'
            }
        } catch {
            Write-Log "Errore critico durante DISM: $_" 'ERROR'
        }
    }

    # 3.4 Driver Obsoleti
    if ($RiskLevel -eq 'High' -and $Mode -eq 'FullClean' -and $Mode -ne 'AnalyzeOnly') {
        Write-Log "Rimozione Driver Obsoleti (Pnputil)..." 'WARN'
        try {
             Start-Process "pnputil.exe" -ArgumentList "/delete-driver oem*.inf /force" -Wait -NoNewWindow
             Write-Log "Pnputil completato." 'SYSTEM'
        } catch {
             Write-Log "Errore Pnputil: $_" 'ERROR'
        }
    }
}

# --- 4. PULIZIA MULTI-UTENTE ---
Write-Log "--- INIZIO PULIZIA PROFILI UTENTE ---" 'START'

$UserProfiles = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notin @("Public", "Default", "All Users") }

foreach ($Profile in $UserProfiles) {
    Write-Log "Analisi profilo: $($Profile.Name)" 'INFO'
    $UserPath = $Profile.FullName
    $Targets = @()

    # Browser
    $Targets += "$UserPath\AppData\Local\Google\Chrome\User Data\Default\Cache"
    $Targets += "$UserPath\AppData\Local\Google\Chrome\User Data\Default\Code Cache"
    $Targets += "$UserPath\AppData\Local\Microsoft\Edge\User Data\Default\Cache"
    $Targets += "$UserPath\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache"

    # Teams & Office
    if ($RiskLevel -ne 'Low') {
        $Targets += "$UserPath\AppData\Roaming\Microsoft\Teams\Cache"
        $Targets += "$UserPath\AppData\Roaming\Microsoft\Teams\blob_storage"
        $Targets += "$UserPath\AppData\Roaming\Microsoft\Teams\IndexedDB"
        $Targets += "$UserPath\AppData\Roaming\Microsoft\Teams\GPUCache"
        $Targets += "$UserPath\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
        $Targets += "$UserPath\AppData\Local\Microsoft\Office\16.0\OfficeCache"
        $Targets += "$UserPath\AppData\Local\Microsoft\OneDrive\logs"
	$Targets += "$UserPath\AppData\Local\Microsoft\Office\OTele"
	$Targets += "$UserPath\AppData\Local\Microsoft\Outlook\Offline Address Books"
	$Targets += "$UserPath\AppData\Local\Microsoft\Office\SolutionPackages"
	$Targets += "$UserPath\AppData\Local\Microsoft\Office\WebWebView2Cache"
    }

    # Grafica & Temp
    $Targets += "$UserPath\AppData\Local\D3DSCache"
    $Targets += "$UserPath\AppData\Local\NVIDIA\DXCache"
    $Targets += "$UserPath\AppData\Local\AMD\DXCache"
    $Targets += "$UserPath\AppData\Local\Temp\*"

    foreach ($T in $Targets) { Remove-FileSafe -Path $T }
}

# --- 5. FINALI ---
Write-Log "--- OPERAZIONI FINALI ---" 'START'

# Temp Globali (> 7 giorni)
$LimitDate = (Get-Date).AddDays(-7)
$GlobalTemp = "$env:windir\Temp"
if ($IsAdmin -and (Test-Path $GlobalTemp)) {
    Get-ChildItem -Path "$GlobalTemp\*" -Recurse -ErrorAction SilentlyContinue | 
        Where-Object { $_.LastWriteTime -lt $LimitDate } | 
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

# Cestino & Trim
if ($Mode -ne 'AnalyzeOnly') {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    if ($IsAdmin -and $Mode -eq 'FullClean') {
        Write-Log "Esecuzione ReTrim SSD..."
        Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
    }
}

ipconfig /flushdns | Out-Null

# Report Finale
$FinalFree = [math]::Round(((Get-PSDrive C).Free / 1GB), 2)
$TotalFreed = [math]::Round(($FinalFree - $InitialFree), 2)
if ($TotalFreed -lt 0) { $TotalFreed = 0 }

Write-Host ("`n" + ("="*50)) -ForegroundColor Gray
Write-Host "RIEPILOGO SERVICE DESK CLEANUP" -ForegroundColor White
Write-Host "Backup (Punto Ripristino): $(if($EnableBackup){'ESEGUITO'}else{'SALTATO'})"
Write-Host "Spazio Liberato:           $TotalFreed GB" -ForegroundColor Green
Write-Host "Log File:                  $LogPath" -ForegroundColor Gray
Write-Host ("="*50) -ForegroundColor Gray

Write-Log "PULIZIA COMPLETATA. Spazio liberato: $TotalFreed GB" 'FINISH'

exit 0