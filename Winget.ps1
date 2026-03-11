#========================================
# Winget Automated Deployment Script
# Version: V6 (March 2026)
#========================================
# Provisioning automatico workstation Windows
# con software, aggiornamenti e configurazioni
#========================================

# === VERIFICA PRIVILEGI AMMINISTRATORI (auto-elevazione) ===
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "[INFO] Privilegi insufficienti. Riavvio come amministratore..."
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
} else {
    Write-Host "[OK] Script eseguito con privilegi amministrativi."
}

$scriptPath = $MyInvocation.MyCommand.Path

function Ensure-GitPrerequisiteForAutoUpdate {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        return
    }

    Write-Host ""
    $answer = Read-Host "Git non trovato. Vuoi installare Git come pre-requisito di auto-update di questo script? (S/N)"
    if ($answer -notmatch '^[sSyY]$') {
        Write-Host "[INFO] Git non installato: auto-update disabilitato per questa esecuzione."
        return
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "[ATTENZIONE] WinGet non disponibile: impossibile installare Git automaticamente."
        return
    }

    try {
        Write-Host "[INFO] Installazione Git in corso..."
        & winget install -e --id "Git.Git" --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "[OK] Git installato correttamente."
        } else {
            Write-Host "[ATTENZIONE] Installazione Git non completata (codice: $LASTEXITCODE)."
        }
    } catch {
        Write-Host "[ATTENZIONE] Errore durante installazione Git: $_"
    }
}

function Ensure-LatestScriptFromGitHub {
    param(
        [string]$repoPath,
        [string]$scriptToRun
    )

    # Evita loop nel caso di rilancio successivo a un aggiornamento riuscito.
    if ($env:WINGET_SELFUPDATED -eq "1") {
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "[INFO] Git non disponibile: skip controllo aggiornamenti da GitHub."
        return
    }

    if (-not (Test-Path (Join-Path $repoPath ".git"))) {
        Write-Host "[INFO] Repository git non trovato in $($repoPath): skip auto-update."
        return
    }

    try {
        $branch = (& git -C $repoPath rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq "HEAD") {
            $branch = "main"
        }

        & git -C $repoPath fetch origin $branch --prune 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ATTENZIONE] Impossibile contattare GitHub per il controllo aggiornamenti."
            return
        }

        $localHash = (& git -C $repoPath rev-parse HEAD 2>$null).Trim()
        $remoteHash = (& git -C $repoPath rev-parse ("origin/{0}" -f $branch) 2>$null).Trim()

        if ($localHash -eq $remoteHash) {
            Write-Host "[OK] Script gia' all'ultima versione GitHub (origin/$branch)."
            return
        }

        Write-Host "[INFO] Nuova versione trovata su GitHub (origin/$branch). Aggiornamento in corso..."
        & git -C $repoPath pull --ff-only origin $branch 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ATTENZIONE] Aggiornamento automatico non riuscito (forse modifiche locali). Continuo con la versione corrente."
            return
        }

        Write-Host "[OK] Script aggiornato da GitHub. Riavvio automatico..."
        $env:WINGET_SELFUPDATED = "1"
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptToRun`""
        exit
    } catch {
        Write-Host "[ATTENZIONE] Errore durante auto-update da GitHub: $_"
    }
}

# Chiede se installare Git quando manca, per abilitare l'auto-update da GitHub.
Ensure-GitPrerequisiteForAutoUpdate

# Tenta sempre il sync con GitHub prima di proseguire con il provisioning.
Ensure-LatestScriptFromGitHub -repoPath $PSScriptRoot -scriptToRun $scriptPath

# Percorso del file di stato per join al dominio (fisso, relativo allo script)
$stateFile = "$PSScriptRoot\logs\JoinDomainState.txt"
$planFile = "$PSScriptRoot\logs\ExecutionPlan.json"
$domainCredentialFile = "$PSScriptRoot\logs\DomainJoinCredential.xml"

# === Configurazione percorso log ===
$configFile = "$PSScriptRoot\winget-config.json"
$defaultLogPath = "$PSScriptRoot\logs\LogsWinget.txt"

# Leggi l'ultimo percorso usato dal file di configurazione
if (Test-Path $configFile) {
    try {
        $cfg = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.LogPath) { $defaultLogPath = $cfg.LogPath }
    } catch {}
}

# Funzione interna: risolve un percorso inserito (cartella o file) in un percorso file .txt valido
function Resolve-LogPath {
    param([string]$inputPath)
    $defaultLogFileName = "LogsWinget.txt"
    $p = $inputPath.TrimEnd('\', '/')
    if (($p -ne "") -and (Test-Path $p -PathType Container)) {
        return Join-Path $p $defaultLogFileName
    } elseif ($p -notmatch '\.[a-zA-Z0-9]+$') {
        return Join-Path $p $defaultLogFileName
    }
    return $p
}

# Normalizza anche il default (potrebbe venire da config con percorso cartella)
$defaultLogPath = Resolve-LogPath $defaultLogPath

# In modalita' resume automatico (savepoint presente) non chiedere: usa il default salvato
$_stateExists = (Test-Path $stateFile) -and ((Get-Content $stateFile -Raw -ErrorAction SilentlyContinue) -match '"Action"\s*:\s*"(?:RenameOnly|JoinDomain|ShowSummary|Progress)"')
if ($_stateExists) {
    $logPath = $defaultLogPath
} else {
    Write-Host ""
    Write-Host "Percorso file di log (file .txt o cartella di destinazione)"
    $userInput = Read-Host "  [Invio per: $defaultLogPath]"
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $logPath = $defaultLogPath
    } else {
        $logPath = Resolve-LogPath $userInput
        if ($logPath -ne $defaultLogPath) {
            Write-Host "  -> Log salvato in: $logPath"
        }
        try {
            @{ LogPath = $logPath } | ConvertTo-Json -Compress | Out-File -FilePath $configFile -Force -Encoding UTF8
        } catch {}
    }
}

# Dominio a cui aggiungere il pc
$domain = "test.local"  

# Lista delle applicazioni da installare/aggiornare
$availableApps = @(
    #"Se Non vuoi installare qualcosa, basta che ci metti un # davanti"
    "Microsoft.Edge",
    "Microsoft.Office",
    #"Adobe.Acrobat.Reader.64-bit"
    "7zip.7zip",
    "VideoLAN.VLC",
    "Google.Chrome",
    "Mozilla.Firefox",
    #"Amazon.AWSCLI"
    "PuTTY.PuTTY",
    #"Postman.Postman"
    "Microsoft.PowerShell",
    "Microsoft.WindowsTerminal",
    "Microsoft.VisualStudioCode",
    "Git.Git",
    "FlipperDevicesInc.qFlipper"
)

$apps = @()
$joinRequested = $false
$desiredComputerName = $env:COMPUTERNAME

# Pacchetti alternativi da provare se l'installazione principale fallisce (es. variante locale)
$appFallbacks = @{
    "Mozilla.Firefox" = "Mozilla.Firefox.it"
}

# Nota: alcuni pacchetti (es. Notepad++) potrebbero non funzionare bene con WinGet
# e richiedono nomi ricerca alternativi - aggiungere qui se necessario
# $appbynames = @(
#     "Notepad++.Notepad++"
# )

# === Sezione X: Funzioni utilizzate nello script ===

# === X - Funzione per inizializzare path e file usati per i log ===
# Funzione per inizializzare i file (da chiamare all'inizio dello script)
function Initialize-Files {
    param (
        [string[]]$filePaths
    )

    foreach ($filePath in $filePaths) {
        $folderPath = Split-Path -Path $filePath -Parent

        # Crea la cartella se non esiste
        if (-Not (Test-Path $folderPath)) {
            New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        }

        # Crea il file se non esiste
        if (-Not (Test-Path $filePath)) {
            New-Item -Path $filePath -ItemType File -Force | Out-Null
        }
    }

    Write-Output "[OK] File di log e stato verificati e inizializzati correttamente."
}

# === X.1 - Funzione di Log per scrivere su schermo e su file ===

function Write-Log {
    param (
        [string]$message
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$TimeStamp - $message"
    Write-Output $logMessage
    
    try {
        $logMessage | Out-File -Append -FilePath $logPath -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Se il log non è accessibile, continua senza loggare
        Write-Output "[AVVISO] Impossibile scrivere sul log: $_"
    }
}

# === X.2 - Funzione per controllare e installare un modulo se non presente ===
function Install-ModuleIfMissing {
    param ([string]$moduleName)
    
    try {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            Write-Log "Modulo $moduleName non installato. Tentativo di installazione..."
            Install-Module -Name $moduleName -Force -Confirm:$false -ErrorAction Stop
            Write-Log "[OK] Modulo $moduleName installato con successo."
        } else {
            Write-Log "[OK] Modulo $moduleName gia' installato."
        }
        
        Import-Module $moduleName -ErrorAction Stop
        Write-Log "[OK] Modulo $moduleName importato."
    } catch {
        Write-Log "[ATTENZIONE] Impossibile installare/importare modulo $moduleName : $_"
        Write-Log "[INFO] Continuando senza il modulo $moduleName (funzionalita' limitate)"
    }
}

# === X.3 - Funzione per installare o aggiornare applicativi con WinGet ===
function Install-Or-Update-WinGetPackage {
    param ([string]$packageId)

    Write-Log "Verifica dello stato del pacchetto: $packageId"

    try {
        $listOutput = & winget list -e --id "$packageId" --source winget --accept-source-agreements 2>&1
        $matchLine  = $listOutput | Where-Object { $_ -match [regex]::Escape($packageId) } | Select-Object -First 1
        $isInstalled = ($null -ne $matchLine)

        if ($isInstalled) {
            $parts = $matchLine -split '\s{2,}'
            $currentVersion = if ($parts.Count -ge 3) { $parts[2].Trim() } else { 'sconosciuta' }
            Write-Log "Il pacchetto $packageId e' gia' installato (Versione: $currentVersion)."

            Write-Log "Verifica disponibilita' aggiornamento per $packageId..."
            $upgradeOutput = & winget upgrade -e --id "$packageId" --source winget --accept-source-agreements --accept-package-agreements 2>&1
            $upgradeText   = $upgradeOutput -join "`n"

            if ($LASTEXITCODE -ne 0) {
                if ($LASTEXITCODE -eq -1978335212 -or $LASTEXITCODE -eq -1978335189) {
                    Write-Log "Nessun aggiornamento disponibile per $packageId."
                    $null = $script:appResults.Add(@{ Id = $packageId; Status = "NoUpdate"; Note = $currentVersion })
                } else {
                    Write-Log "[ATTENZIONE] Aggiornamento $packageId - Codice: $LASTEXITCODE"
                    $null = $script:appResults.Add(@{ Id = $packageId; Status = "ErroreUpdate"; Note = "Codice: $LASTEXITCODE" })
                }
            } elseif ($upgradeText -match 'No applicable upgrade|Nessun aggiornamento applicabile|already installed|gia.*installato') {
                Write-Log "Nessun aggiornamento disponibile per $packageId."
                $null = $script:appResults.Add(@{ Id = $packageId; Status = "NoUpdate"; Note = $currentVersion })
            } else {
                Write-Log "[OK] Aggiornamento completato per $packageId"
                $null = $script:appResults.Add(@{ Id = $packageId; Status = "Aggiornato"; Note = "" })
            }
        } else {
            Write-Log "Il pacchetto $packageId non e' installato. Avvio installazione..."
            & winget install -e --id "$packageId" --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Write-Log "[OK] Installazione completata con successo per $packageId"
                $null = $script:appResults.Add(@{ Id = $packageId; Status = "Installato"; Note = "" })
            } else {
                Write-Log "[ERRORE] Errore durante l'installazione di $packageId. Codice: $LASTEXITCODE"
                $installNote = "Codice: $LASTEXITCODE"
                if ($script:appFallbacks -and $script:appFallbacks.ContainsKey($packageId)) {
                    $fallbackId = $script:appFallbacks[$packageId]
                    Write-Log "[INFO] Tentativo con pacchetto alternativo: $fallbackId"
                    & winget install -e --id "$fallbackId" --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "[OK] Installazione completata con successo per $fallbackId (alternativo)"
                        $null = $script:appResults.Add(@{ Id = $packageId; Status = "Installato"; Note = "via $fallbackId" })
                        return
                    } else {
                        Write-Log "[ERRORE] Errore anche con pacchetto alternativo $fallbackId. Codice: $LASTEXITCODE"
                        $installNote = "Codice: $LASTEXITCODE (alternativo $fallbackId fallito)"
                    }
                }
                $null = $script:appResults.Add(@{ Id = $packageId; Status = "Errore"; Note = $installNote })
            }
        }
    } catch {
        Write-Log "[ERRORE] Errore durante l'operazione su $packageId : $_"
        $null = $script:appResults.Add(@{ Id = $packageId; Status = "Errore"; Note = $_.ToString() })
    }
}

# === X.4 - Funzione di creazione utenti amministratori locali ===
function New-LocalAdminUser {
    do {
        $response = Read-Host "Vuoi creare un nuovo utente locale? (S/N)"
        
        if ($response -match "^[sS]$") {
            $username = Read-Host "Inserisci il nome del nuovo utente"
            $password = Read-Host "Inserisci la password" -AsSecureString

            # Controllo se l'utente esiste già
            if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
                Write-Log "[ERRORE] L'utente '$username' esiste già!"
            } else {
                try {
                    # Creazione utente
                    New-LocalUser -Name $username -Password $password -FullName $username -Description "Utente creato via script" -ErrorAction Stop
                    Write-Log "[OK] Utente '$username' creato con successo."

                    # Aggiunta al gruppo amministratori
                    $adminGroup = [System.Security.Principal.WindowsBuiltInRole]::Administrator
                    Add-LocalGroupMember -Group $adminGroup -Member $username -ErrorAction Stop
                    Write-Log "[ADMIN] L'utente '$username' e' stato aggiunto agli amministratori."
                    Write-Host "`n"
                    Write-Log "[ATTENZIONE] Riavvia il PC ed esegui lo script sotto il nuovo utente '$username'."
                    Write-Host "`n"

                } catch {
                    Write-Log "[ERRORE] Errore durante la creazione dell'utente: $_"
                }
            }

            # Pausa per leggere eventuali errori
            Start-Sleep -Seconds 5
            
        } else {
            Write-Log "[INFO] Creazione utente annullata."
            Write-Host "`n"
            break
        }

        # Chiede se si vuole creare un altro utente
        $repeat = Read-Host "Vuoi creare un altro utente? (S/N)"
        Write-Host "`n"
    } while ($repeat -match "^[sS]$")
}

# === X.5 - Funzioni per gestione attività pianificata di resume ===
$resumeTaskName = "WingetResumeTask"

function Register-ResumeTask {
    Write-Log "Registrazione attivita' pianificata '$resumeTaskName' in corso..."
    try {
        $scriptPath  = $PSCommandPath
        $currentUser = "$env:USERDOMAIN\$env:USERNAME"
        $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                        -Argument "-WindowStyle Normal -ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                        -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        Register-ScheduledTask -TaskName $resumeTaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        Write-Log "[OK] Attivita' pianificata '$resumeTaskName' registrata. Trigger: AtLogOn, Utente: $currentUser, Script: $scriptPath"
    } catch {
        Write-Log "[ERRORE] Impossibile registrare l'attivita' pianificata '$resumeTaskName': $_"
    }
}

function Unregister-ResumeTask {
    Write-Log "Rimozione attivita' pianificata '$resumeTaskName' in corso..."
    try {
        if (Get-ScheduledTask -TaskName $resumeTaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $resumeTaskName -Confirm:$false
            Write-Log "[OK] Attivita' pianificata '$resumeTaskName' rimossa con successo."
        } else {
            Write-Log "[INFO] Attivita' pianificata '$resumeTaskName' non trovata, nessuna rimozione necessaria."
        }
    } catch {
        Write-Log "[ERRORE] Impossibile rimuovere l'attivita' pianificata '$resumeTaskName': $_"
    }
}

# === X.6 - Funzioni per gestione file di stato (JSON con savepoint) ===
function Write-StateFile {
    param ([hashtable]$state)
    try {
        $state | ConvertTo-Json -Compress | Out-File -FilePath $stateFile -Force -Encoding UTF8
        Write-Log "[OK] Savepoint aggiornato: Action=$($state.Action), Step=$($state.Step)"
    } catch {
        Write-Log "[ERRORE] Impossibile scrivere il file di stato: $_"
    }
}

function Read-StateFile {
    try {
        if (Test-Path $stateFile) {
            $content = Get-Content $stateFile -Raw -Encoding UTF8
            if ($content -match '\S') {
                return $content | ConvertFrom-Json
            }
        }
    } catch {
        Write-Log "[ATTENZIONE] File di stato non leggibile come JSON: $_"
    }
    return $null
}

function Write-ExecutionPlan {
    param ([hashtable]$plan)
    try {
        $plan | ConvertTo-Json -Depth 6 | Out-File -FilePath $planFile -Force -Encoding UTF8
    } catch {
        Write-Log "[ERRORE] Impossibile scrivere il piano di esecuzione: $_"
    }
}

function Read-ExecutionPlan {
    try {
        if (Test-Path $planFile) {
            $content = Get-Content $planFile -Raw -Encoding UTF8
            if ($content -match '\S') {
                return $content | ConvertFrom-Json
            }
        }
    } catch {
        Write-Log "[ATTENZIONE] Piano di esecuzione non leggibile: $_"
    }
    return $null
}

function Select-AppsForInstallation {
    param ([string[]]$candidateApps)

    $selected = [System.Collections.ArrayList]::new()
    Write-Host ""
    Write-Host "Selezione applicazioni (Invio/S/Y = installa, N = salta)"
    foreach ($candidate in $candidateApps) {
        $answer = Read-Host "Vuoi installare '$candidate'? (S/N, Invio=S)"
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[sSyY]$') {
            $null = $selected.Add($candidate)
            Write-Host "  -> Aggiunta: $candidate"
        } elseif ($answer -match '^[nN]$') {
            Write-Host "  -> Esclusa:  $candidate"
        } else {
            $null = $selected.Add($candidate)
            Write-Host "  -> Input non riconosciuto, aggiunta di default: $candidate"
        }
    }

    return @($selected)
}

function Get-JoinCredentialFromPlan {
    param($plan)

    if ($plan -and $plan.DomainCredentialFile -and (Test-Path $plan.DomainCredentialFile)) {
        try {
            return Import-Clixml -Path $plan.DomainCredentialFile
        } catch {
            Write-Log "[ATTENZIONE] Impossibile leggere le credenziali salvate per il join dominio: $_"
        }
    }
    return $null
}

function Confirm-Choice {
    param([string]$message)

    $confirm = Read-Host $message
    return [string]::IsNullOrWhiteSpace($confirm) -or ($confirm -match '^[sSyY]$')
}

# === X.7 - Variabili di tracking e funzione di riepilogo ===
$script:appResults      = [System.Collections.ArrayList]::new()
$script:wuResults       = [System.Collections.ArrayList]::new()
$script:wuCount         = 0
$script:tweaks          = [ordered]@{}
$script:summaryFilePath = ""

function Write-Summary {
    param([switch]$OpenFile)
    $summaryDir  = Split-Path $logPath -Parent
    $summaryFile = "$summaryDir\Scheda_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyy-MM-dd').txt"

    $sysInfo  = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $biosInfo = Get-CimInstance Win32_BIOS          -ErrorAction SilentlyContinue
    $sysModel  = if ($sysInfo)  { $sysInfo.Model }        else { "N/D" }
    $sysDomain = if ($sysInfo)  { $sysInfo.Domain }       else { "N/D" }
    $sysSerial = if ($biosInfo) { $biosInfo.SerialNumber } else { "N/D" }
    $sysUser   = try { whoami } catch { "N/D" }

    $sep   = "=" * 56
    $lines = [System.Collections.ArrayList]::new()
    $null = $lines.Add($sep)
    $null = $lines.Add("  SCHEDA INSTALLAZIONE PC")
    $null = $lines.Add("  Generata il: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $null = $lines.Add($sep)
    $null = $lines.Add("")
    $null = $lines.Add("INFORMAZIONI PC")
    $null = $lines.Add("  Nome PC  : $($env:COMPUTERNAME)")
    $null = $lines.Add("  Dominio  : $sysDomain")
    $null = $lines.Add("  Modello  : $sysModel")
    $null = $lines.Add("  Seriale  : $sysSerial")
    $null = $lines.Add("  Utente   : $sysUser")
    $null = $lines.Add("")
    $null = $lines.Add("APPLICAZIONI")
    if ($script:appResults.Count -gt 0) {
        foreach ($r in $script:appResults) {
            $tag = switch ($r.Status) {
                "Installato"   { "[OK] Installato          " }
                "NoUpdate"     { "[--] Gia' aggiornato     " }
                "Aggiornato"   { "[OK] Aggiornato          " }
                "Errore"       { "[KO] Errore installaz.   " }
                "ErroreUpdate" { "[KO] Errore aggiornamento" }
                default        { "[??] Stato sconosciuto   " }
            }
            $note = if ($r.Note) { "  -> $($r.Note)" } else { "" }
            $null = $lines.Add("  $tag  $($r.Id)$note")
        }
    } else {
        $null = $lines.Add("  (nessuna app tracciata in questa sessione)")
    }
    $null = $lines.Add("")
    $null = $lines.Add("AGGIORNAMENTI WINDOWS")
    if ($script:wuCount -gt 0) {
        $null = $lines.Add("  Totale installati: $($script:wuCount)")
        foreach ($wu in $script:wuResults) { $null = $lines.Add("    $wu") }
    } else {
        $null = $lines.Add("  Nessun aggiornamento installato in questa sessione.")
    }
    $null = $lines.Add("")
    $null = $lines.Add("CONFIGURAZIONI APPLICATE")
    if ($script:tweaks.Count -gt 0) {
        foreach ($t in $script:tweaks.GetEnumerator()) {
            $null = $lines.Add("  $($t.Value)  $($t.Key)")
        }
    } else {
        $null = $lines.Add("  (nessuna configurazione tracciata)")
    }
    $null = $lines.Add("")
    $null = $lines.Add($sep)

    try {
        if (-not (Test-Path $summaryDir)) { New-Item -Path $summaryDir -ItemType Directory -Force | Out-Null }
        $lines | Out-File -FilePath $summaryFile -Encoding UTF8 -Force
        Write-Log "[OK] Scheda installazione salvata: $summaryFile"
        $script:summaryFilePath = $summaryFile
        if ($OpenFile) { Start-Process notepad.exe -ArgumentList "`"$summaryFile`"" }
    } catch {
        Write-Log "[ATTENZIONE] Impossibile salvare la scheda installazione: $_"
    }
}

# Inizializza i file all'inizio dello script
Initialize-Files -filePaths @($logPath, $stateFile)

Write-Log "*****************INZIO ESECUZIONE SCRIPT*****************"

# === Sezione Pre-Requisiti: Verifica WinGet e dipendenze ===
Write-Log "`n=== Verifica Prerequisites ==="

# Verifica se WinGet è disponibile
try {
    $wingetVersion = & winget --version 2>&1
    Write-Log "[OK] WinGet disponibile: $wingetVersion"
} catch {
    Write-Log "[CRITICO] Errore critico: WinGet non è installato o non è in PATH."
    Write-Log "Lo script richiede WinGet per funzionare. Installare WinGet da: https://github.com/microsoft/winget-cli"
    exit 1
}

# Carica eventuale stato precedente e piano esecuzione.
$resumeState = Read-StateFile
$executionPlan = Read-ExecutionPlan
if ($null -eq $executionPlan) { $executionPlan = [ordered]@{} }

if ($null -eq $resumeState) {
    Write-Log "`n=== Raccolta input iniziale ==="

    # Tutte le domande utente vengono fatte in una fase unica iniziale.
    New-LocalAdminUser
    Write-Host "`n"

    $currentPCName = $env:COMPUTERNAME
    Write-Host "Nome PC attuale: $currentPCName"
    do {
        $planPCName = Read-Host "Inserisci il nuovo nome PC (lascia vuoto per mantenere '$currentPCName')"
        if ([string]::IsNullOrWhiteSpace($planPCName)) { $planPCName = $currentPCName }
        $pcNameConfirmed = Confirm-Choice -message "Hai inserito '$planPCName' come nome PC, confermi? (Y/S o Invio)"
        if (-not $pcNameConfirmed) {
            Write-Host "  -> Reinserisci il nome PC."
        }
    } while (-not $pcNameConfirmed)

    $joinAnswer = Read-Host "Vuoi inserire il PC a dominio? (y/n)"
    $planJoin = $joinAnswer -match '^[yY]$'
    $planDomain = $domain
    if ($planJoin) {
        Write-Host "Dominio attuale: $domain"
        do {
            $domainAnswer = Read-Host "Inserisci dominio (Invio per mantenere '$domain')"
            if (-not [string]::IsNullOrWhiteSpace($domainAnswer)) { $planDomain = $domainAnswer }
            $domainConfirmed = Confirm-Choice -message "Hai inserito '$planDomain' come dominio, confermi? (Y/S o Invio)"
            if (-not $domainConfirmed) {
                Write-Host "  -> Reinserisci il dominio."
            }
        } while (-not $domainConfirmed)
    }

    $selectedApps = Select-AppsForInstallation -candidateApps $availableApps

    $executionPlan = [ordered]@{
        DesiredComputerName = $planPCName
        JoinDomain = $planJoin
        Domain = $planDomain
        Apps = @($selectedApps)
        DomainCredentialFile = $null
    }

    if ($planJoin) {
        $joinCred = Get-Credential -Message "Inserisci le credenziali di amministratore di dominio per $planDomain"
        if ($null -eq $joinCred) {
            Write-Log "[ERRORE] Credenziali non fornite. Annullamento esecuzione."
            exit 1
        }
        try {
            $joinCred | Export-Clixml -Path $domainCredentialFile -Force
            $executionPlan.DomainCredentialFile = $domainCredentialFile
            Write-Log "[OK] Credenziali dominio salvate per la fase automatica di join."
        } catch {
            Write-Log "[ERRORE] Impossibile salvare le credenziali dominio: $_"
            exit 1
        }
    }

    Write-ExecutionPlan -plan $executionPlan
}

$desiredComputerName = if ($executionPlan.DesiredComputerName) { [string]$executionPlan.DesiredComputerName } else { $env:COMPUTERNAME }
$joinRequested = [bool]$executionPlan.JoinDomain
$domain = if ($executionPlan.Domain) { [string]$executionPlan.Domain } else { $domain }
$apps = @($executionPlan.Apps)

# === Sezione 0: Resume da savepoint (stateFile JSON) ===
if ($null -ne $resumeState) {
    Write-Log "=== Ripresa da savepoint: Action=$($resumeState.Action), Step=$($resumeState.Step) ==="
    Unregister-ResumeTask

    # --- Ripresa dopo rinomina standalone ---
    if ($resumeState.Action -eq "RenameOnly") {
        Write-Log "[OK] Rinomina completata. Rimozione savepoint e proseguimento script normale."
        Remove-Item $stateFile -Force
    }

    # --- Ripresa dopo rinomina pre-join: join automatico senza prompt ---
    elseif ($resumeState.Action -eq "JoinDomain" -and $resumeState.Step -eq "Renamed") {
        Write-Log "Ripresa join al dominio dopo rinomina."
        $currentPCName = $env:COMPUTERNAME
        $savedDomain = if ($resumeState.Domain) { $resumeState.Domain } else { $domain }
        Write-Log "Dominio impostato: $savedDomain"

        if ($desiredComputerName -ne $currentPCName) {
            Write-Log "Nome PC ancora diverso ('$currentPCName' -> '$desiredComputerName'). Rinomina e riavvio."
            Write-StateFile @{ Action = "JoinDomain"; Step = "Renamed"; DesiredComputerName = $desiredComputerName; Domain = $savedDomain }
            try {
                Rename-Computer -NewName $desiredComputerName -Force -ErrorAction Stop
                Register-ResumeTask
                Write-Log "*****************Script in pausa. Sistema in riavvio per rinomina PC.*****************"
                Start-Sleep -Seconds 3
                Restart-Computer -Force
                Start-Sleep -Seconds 120
                exit
            } catch {
                Write-Log "[ERRORE] Impossibile rinominare il PC: $_"
            }
        } else {
            Write-Log "Procedo con il join al dominio '$savedDomain' senza ulteriori prompt."
            try {
                $cred = Get-JoinCredentialFromPlan -plan $executionPlan
                if ($null -eq $cred) {
                    Write-Log "[ERRORE] Credenziali non disponibili nel piano. Annullamento join al dominio."
                    exit 1
                }
                Add-Computer -DomainName $savedDomain -Credential $cred -Force -ErrorAction Stop
                Write-Log "[OK] PC aggiunto al dominio con successo."
            } catch {
                Write-Log "[ERRORE] Errore durante l'aggiunta al dominio: $_"
                exit 1
            }
            Write-Log "[ATTENZIONE] RICORDATI DI SPOSTARE IL PC NELL'UNITA' ORGANIZZATIVA CORRETTA"
            Remove-Item $stateFile -Force
            if (Test-Path $planFile) { Remove-Item $planFile -Force }
            if (Test-Path $domainCredentialFile) { Remove-Item $domainCredentialFile -Force }
            Write-Log "*****************Script completato con successo. Sistema in riavvio per join al dominio.*****************"
            Start-Sleep -Seconds 3
            Restart-Computer -Force
            Start-Sleep -Seconds 120
            exit
        }
    }

    # --- Riepilogo post-riavvio aggiornamenti ---
    elseif ($resumeState.Action -eq "ShowSummary") {
        Unregister-ResumeTask
        Remove-Item $stateFile -Force
        if ($resumeState.SummaryFile -and (Test-Path $resumeState.SummaryFile)) {
            Write-Log "[OK] Apertura scheda installazione: $($resumeState.SummaryFile)"
            Start-Process notepad.exe -ArgumentList "`"$($resumeState.SummaryFile)`""
        } else {
            Write-Log "[ATTENZIONE] File scheda non trovato: $($resumeState.SummaryFile)"
        }
        exit
    }

    # --- Ripresa savepoint di progresso ---
    elseif ($resumeState.Action -eq "Progress") {
        Write-Log "Ripresa da savepoint progresso: Step=$($resumeState.Step)"
        Unregister-ResumeTask
    }

    # --- Stato sconosciuto: pulizia e proseguimento ---
    else {
        Write-Log "[ATTENZIONE] Savepoint non riconosciuto (Action=$($resumeState.Action)). Pulizia e proseguimento."
        Remove-Item $stateFile -Force
    }
}

# === Sezione Iniziale: Rinomina PC ===
if ($null -eq $resumeState) {
    Write-Log "`n=== Rinomina PC ==="
    $currentPCName = $env:COMPUTERNAME
    if ($desiredComputerName -ne $currentPCName) {
        Write-Log "Rinomina PC: '$currentPCName' -> '$desiredComputerName'"
        $renameAction = if ($joinRequested) { "JoinDomain" } else { "RenameOnly" }
        Write-StateFile @{ Action = $renameAction; Step = "Renamed"; DesiredComputerName = $desiredComputerName; Domain = $domain }
        try {
            Rename-Computer -NewName $desiredComputerName -Force -ErrorAction Stop
            Write-Log "[OK] PC rinominato. Registrazione task di resume e riavvio in corso..."
            Register-ResumeTask
            Write-Log "*****************Script in pausa. Sistema in riavvio per rinomina PC.*****************"
            Start-Sleep -Seconds 3
            Restart-Computer -Force
            Start-Sleep -Seconds 120
            exit
        } catch {
            Write-Log "[ERRORE] Impossibile rinominare il PC: $_"
        }
    } else {
        Write-Log "Nome PC invariato: '$currentPCName'. Nessun riavvio necessario."
    }
    Write-Host "`n"
}

# Installato modulo Powershell Winget per loggare andamento installazione e update
# Installato modulo PSWindowsUpdate per la gestione degli aggiornamenti di Windows
# Controllo e installazione dei moduli solo se necessario
Install-ModuleIfMissing "Microsoft.WinGet.Client"
Install-ModuleIfMissing "PSWindowsUpdate"
Write-Host "`n"

# === Savepoint: determina da dove riprendere ===
$stepOrder = @("SysInfo", "AppsInstalled", "TweaksApplied", "WindowsUpdate")
$resumeFromStep = if ($null -ne $resumeState -and $resumeState.Action -eq "Progress") { $resumeState.Step } else { "" }

function Test-StepNeeded {
    param ([string]$thisStep)
    if ([string]::IsNullOrEmpty($script:resumeFromStep)) { return $true }
    $doneIdx = $script:stepOrder.IndexOf($script:resumeFromStep)
    $thisIdx  = $script:stepOrder.IndexOf($thisStep)
    return $thisIdx -gt $doneIdx
}

# === Sezione 1: Scrittura delle informazioni di sistema ===
if (Test-StepNeeded "SysInfo") {
    # Ottieni le informazioni richieste
    $computerModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
    $serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    $domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
    $user = whoami

    # Scrivi informazioni di sistema nel file
    Write-Log "=== Informazioni di Sistema ==="
    Write-Log "Modello: $computerModel"
    Write-Log "Seriale: $serialNumber"
    Write-Log "Dominio: $domain"
    Write-Log "Utente: $user"
    Write-Log "Informazioni di sistema scritte correttamente nel file."
    Write-Host "`n"
    Write-StateFile @{ Action = "Progress"; Step = "SysInfo" }
} else {
    Write-Log "[SKIP] Sezione 1 (SysInfo) gia' completata."
}

# === Sezione 2: Installazione Applicazioni ===
if (Test-StepNeeded "AppsInstalled") {
    # Aggiorna i cataloghi winget prima di qualsiasi operazione
    # Senza questo, winget usa versioni cached e potrebbe non vedere gli ultimi aggiornamenti
    Write-Log "Aggiornamento cataloghi winget in corso..."
    & winget source update 2>&1 | Out-Null
    Write-Log "[OK] Cataloghi winget aggiornati."

    if ($apps.Count -eq 0) {
        Write-Log "[INFO] Nessuna app selezionata dall'utente: sezione installazione saltata."
    } else {
        # Installazione o aggiornamento delle applicazioni selezionate in fase iniziale
        foreach ($app in $apps) {
            Install-Or-Update-WinGetPackage -packageId $app
            Write-Host "`n"
        }
    }
    Write-StateFile @{ Action = "Progress"; Step = "AppsInstalled" }
} else {
    Write-Log "[SKIP] Sezione 2 (AppsInstalled) gia' completata."
}

# === Sezione 3: Abilitare "Ottieni gli ultimi aggiornamenti non appena sono disponibili" ===

Write-Log "`n=== Abilitazione aggiornamenti rapidi ==="
# Esegui il comando e reindirizza eventuali errori
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsContinuousInnovationOptedIn /t REG_DWORD /d 1 /f 2>&1 | Out-Null
# Controlla se il comando è andato a buon fine
if ($LASTEXITCODE -eq 0) {
    Write-Log "Impostazione completata: aggiornamenti rapidi abilitati."
    $script:tweaks["Aggiornamenti rapidi"] = "[OK]"
} else {
    Write-Log "Errore durante la modifica dell'impostazione degli aggiornamenti rapidi. Codice errore: $LASTEXITCODE"
    $script:tweaks["Aggiornamenti rapidi"] = "[KO]"
}
Write-Host "`n"

# === Sezione 4: Configurazione per installare automaticamente aggiornamenti facoltativi ===

Write-Log "`n=== Configurazione aggiornamenti facoltativi ==="
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v AllowOptionalContent /t REG_DWORD /d 1 /f
if ($LASTEXITCODE -eq 0) {
    Write-Log "Impostazione completata: aggiornamenti facoltativi saranno installati automaticamente."
    $script:tweaks["Aggiornamenti facoltativi automatici"] = "[OK]"
} else {
    Write-Log "Errore durante la configurazione degli aggiornamenti facoltativi. Codice errore: $LASTEXITCODE"
    $script:tweaks["Aggiornamenti facoltativi automatici"] = "[KO]"
}
Write-Host "`n"

# === Sezione 5: Abilitare "Ottieni aggiornamenti per altri prodotti Microsoft" ===
Write-Log "`n=== Abilitazione aggiornamenti per altri prodotti Microsoft ==="
try {
    # Metodo principale: registrazione servizio Microsoft Update tramite COM object (affidabile su Win10/11)
    $svcMgr = New-Object -ComObject "Microsoft.Update.ServiceManager"
    $svcMgr.AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "") | Out-Null
    Write-Log "[OK] Aggiornamenti per altri prodotti Microsoft abilitati (Windows Update Service COM)."
    $script:tweaks["Aggiornamenti altri prodotti Microsoft"] = "[OK]"
} catch {
    Write-Log "[ATTENZIONE] Impossibile abilitare tramite COM: $_"
    Write-Log "[INFO] Tentativo tramite registro di sistema..."
    $regPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
    if (-Not (Test-Path "Registry::$regPath")) {
        New-Item -Path "Registry::$regPath" -Force | Out-Null
    }
    $regSet = reg add $regPath /v "EnableMicrosoftUpdate" /t REG_DWORD /d 1 /f 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "[OK] Aggiornamenti per altri prodotti Microsoft abilitati (registro)."
        $script:tweaks["Aggiornamenti altri prodotti Microsoft"] = "[OK]"
    } else {
        Write-Log "[ERRORE] Impossibile abilitare aggiornamenti Microsoft. Codice: $LASTEXITCODE"
        $script:tweaks["Aggiornamenti altri prodotti Microsoft"] = "[KO]"
    }
}

# === Sezione 5b: Abilitare "Avvisami quando e' necessario un riavvio per completare l'aggiornamento" ===
Write-Log "`n=== Attivazione notifica riavvio necessario ==="
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v RestartNotificationsAllowed2 /t REG_DWORD /d 1 /f 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Log "[OK] Notifica riavvio necessario abilitata (HKLM)."
    # Imposta anche per l'utente corrente
    $hkcuPath = "HKCU:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    if (-Not (Test-Path $hkcuPath)) { New-Item -Path $hkcuPath -Force | Out-Null }
    Set-ItemProperty -Path $hkcuPath -Name "RestartNotificationsAllowed2" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Log "[OK] Notifica riavvio necessario abilitata (HKCU)."
} else {
    Write-Log "[ERRORE] Errore durante l'abilitazione della notifica di riavvio. Codice: $LASTEXITCODE"
}

# === Sezione 6: Modifica del motore di ricerca di Edge ===

$preferencesPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"

# Controlla se il file esiste
if (Test-Path $preferencesPath) {
    try {
        # Legge il file JSON
        $json = Get-Content -Raw -Path $preferencesPath | ConvertFrom-Json

        # Controlla se "default_search_provider_data" esiste, altrimenti lo crea
        if (-Not ($json.PSObject.Properties.Name -contains "default_search_provider_data")) {
            $json | Add-Member -MemberType NoteProperty -Name "default_search_provider_data" -Value @{}
        }

        # Modifica il motore di ricerca
        $json.default_search_provider_data.template_url_data = @{
            url = "https://www.google.com/search?q={searchTerms}"
        }
        $json.default_search_provider_data.short_name = "Google"

        # Salva le modifiche nel file JSON
        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $preferencesPath -Force -Encoding UTF8

        Write-Log "[OK] Motore di ricerca di Edge modificato con successo in Google."
        $script:tweaks["Motore ricerca Edge -> Google"] = "[OK]"
    } catch {
        Write-Log "[ERRORE] Errore durante la modifica del motore di ricerca Edge: $_"
        $script:tweaks["Motore ricerca Edge -> Google"] = "[KO]"
    }
} else {
    Write-Log "[ATTENZIONE] Avviso: il file delle preferenze di Edge non esiste (Edge non è stato ancora eseguito)."
    $script:tweaks["Motore ricerca Edge -> Google"] = "[--] Edge non ancora avviato"
}

# === Sezione 7: Modifica impostazione Visualizza estensioni file ===
Write-Log "`n=== Abilitazione visualizzazione estensioni file ==="
try {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $regName = "HideFileExt"

    # Abilita la visualizzazione delle estensioni
    Set-ItemProperty -Path $regPath -Name $regName -Value 0
    Write-Log "[OK] Le estensioni dei file ora sono visibili."

    # Per rendere effettiva la modifica, riavviare Explorer con protezione
    Write-Log "Riavvio explorer in corso..."
    Stop-Process -Name explorer -Force -ErrorAction Stop
    Start-Sleep -Milliseconds 500
    Start-Process explorer
    Write-Log "[OK] Explorer riavviato con successo."
    $script:tweaks["Estensioni file visibili"] = "[OK]"
} catch {
    Write-Log "[ERRORE] Errore durante la modifica delle estensioni file: $_"
    $script:tweaks["Estensioni file visibili"] = "[KO]"
}

# === Sezione 8: Impostazioni di risparmio energetico ===
Write-Log "`n=== Configurazione delle impostazioni di risparmio energetico ==="
Try {
    powercfg /change disk-timeout-ac 0
    powercfg /change disk-timeout-dc 0
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    Write-Log "Impostazioni di risparmio energetico configurate su 'Mai' con successo."
    $script:tweaks["Risparmio energetico -> Mai"] = "[OK]"
    Write-Host "`n"
} Catch {
    Write-Log "[ERRORE] Errore durante la configurazione delle impostazioni di risparmio energetico: $_"
    $script:tweaks["Risparmio energetico -> Mai"] = "[KO]"
    Write-Host "`n"
}
# === Sezione 8b: Imposta PowerShell 7 come profilo default in Windows Terminal ===
Write-Log "`n=== Impostazione PowerShell 7 come profilo default di Windows Terminal ==="
try {
    $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path $wtSettingsPath)) {
        Write-Log "[ATTENZIONE] Windows Terminal non trovato o non ancora avviato. Impostazione saltata."
        $script:tweaks["Windows Terminal: default PS7"] = "[--] Terminal non trovato"
    } else {
        $wtSettings = Get-Content $wtSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        # Cerca il profilo PowerShell 7 tramite source (robusto, non dipende dal GUID)
        $ps7Profile = $wtSettings.profiles.list | Where-Object {
            $_.source -like "*PowershellCore*" -or $_.source -like "*PowerShell*"
        } | Select-Object -First 1

        if ($null -eq $ps7Profile) {
            Write-Log "[ATTENZIONE] Profilo PowerShell 7 non trovato in Windows Terminal."
            $script:tweaks["Windows Terminal: default PS7"] = "[--] Profilo PS7 non trovato"
        } elseif ($wtSettings.defaultProfile -eq $ps7Profile.guid) {
            Write-Log "PowerShell 7 e' gia' il profilo default di Windows Terminal."
            $script:tweaks["Windows Terminal: default PS7"] = "[--] Gia' impostato"
        } else {
            $wtSettings.defaultProfile = $ps7Profile.guid
            $wtSettings | ConvertTo-Json -Depth 20 | Set-Content $wtSettingsPath -Encoding UTF8 -Force
            Write-Log "[OK] PowerShell 7 ($($ps7Profile.guid)) impostato come profilo default di Windows Terminal."
            $script:tweaks["Windows Terminal: default PS7"] = "[OK]"
        }
    }
} catch {
    Write-Log "[ERRORE] Errore durante la configurazione di Windows Terminal: $_"
    $script:tweaks["Windows Terminal: default PS7"] = "[KO]"
}
Write-Host "`n"

Write-StateFile @{ Action = "Progress"; Step = "TweaksApplied" }

# === Sezione 9: Avvio manuale di Windows Update ===
if (Test-StepNeeded "WindowsUpdate") {
    # Cerca gli aggiornamenti disponibili
    Write-Log "Ricerca degli aggiornamenti disponibili..."
    try {
        $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll

        if ($updates) {
            Write-Log "Trovati $(($updates | Measure-Object).Count) aggiornamenti. Avvio installazione..."

            $updateResults = Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot
            $updateResults | ForEach-Object {
                $kb    = if ($_.KB)     { " KB$($_.KB)" } else { "" }
                $size  = if ($_.Size)   { " ($($_.Size))" } else { "" }
                Write-Log ("  [{0}]{1}{2} {3}" -f $_.Result, $kb, $size, $_.Title)
            }
            # Traccia risultati per riepilogo
            $script:wuCount = ($updateResults | Measure-Object).Count
            foreach ($u in $updateResults) {
                $kb   = if ($u.KB)   { "KB$($u.KB) - " } else { "" }
                $size = if ($u.Size) { " ($($u.Size))" } else { "" }
                $null = $script:wuResults.Add("[$($u.Result)] ${kb}$($u.Title)${size}")
            }

            Write-Log "Installazione aggiornamenti completata."
            Write-Host "`n"
        } else {
            Write-Log "Nessun aggiornamento disponibile."
            Write-Host "`n"
        }
    } catch {
        Write-Log "[ATTENZIONE] Modulo PSWindowsUpdate non disponibile o errore nella ricerca aggiornamenti: $_"
        Write-Log "[INFO] Puoi installare gli aggiornamenti manualmente da Impostazioni > Aggiornamento e sicurezza"
        Write-Host "`n"
    }
    Write-StateFile @{ Action = "Progress"; Step = "WindowsUpdate" }
} else {
    Write-Log "[SKIP] Sezione 9 (WindowsUpdate) gia' completata."
}

# === Sezione 10: Join al dominio ===
if (-not $joinRequested) {
    Write-Log "[INFO] Join al dominio annullato dall'utente."
} else {
    $currentPCName = $env:COMPUTERNAME
    Write-Log "Dominio impostato da piano iniziale: $domain"

    if ($desiredComputerName -ne $currentPCName) {
        Write-Log "Nome PC cambiato ('$currentPCName' -> '$desiredComputerName'). Rinomina, salvataggio savepoint e riavvio."
        Write-StateFile @{ Action = "JoinDomain"; Step = "Renamed"; DesiredComputerName = $desiredComputerName; Domain = $domain }
        try {
            Rename-Computer -NewName $desiredComputerName -Force -ErrorAction Stop
            Register-ResumeTask
            Write-Log "*****************Script in pausa. Sistema in riavvio per rinomina PC.*****************"
            Start-Sleep -Seconds 3
            Restart-Computer -Force
            Start-Sleep -Seconds 120
            exit
        } catch {
            Write-Log "[ERRORE] Impossibile rinominare il PC: $_"
        }
    } else {
        Write-Log "Nome PC invariato. Procedo con il join al dominio '$domain' senza ulteriori prompt."
        try {
            $cred = Get-JoinCredentialFromPlan -plan $executionPlan
            if ($null -eq $cred) {
                Write-Log "[ERRORE] Credenziali non disponibili nel piano. Annullamento join al dominio."
                exit 1
            }
            Add-Computer -DomainName $domain -Credential $cred -Force -ErrorAction Stop
            Write-Log "[OK] PC aggiunto al dominio con successo."
        } catch {
            Write-Log "[ERRORE] Errore durante l'aggiunta al dominio: $_"
            exit 1
        }
        Write-Log "[ATTENZIONE] RICORDATI DI SPOSTARE IL PC NELL'UNITA' ORGANIZZATIVA CORRETTA"
        if (Test-Path $planFile) { Remove-Item $planFile -Force }
        if (Test-Path $domainCredentialFile) { Remove-Item $domainCredentialFile -Force }
        Write-Log "*****************Script completato con successo. Sistema in riavvio per join al dominio.*****************"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
        Start-Sleep -Seconds 120
        exit
    }
}

# Controlla se e' necessario un riavvio per eseguire gli aggiornamenti di Windows Update
# Nota: $updates e' valorizzato solo se la sezione WindowsUpdate ha girato in questa sessione
#       e ha trovato aggiornamenti. Se $updates e' null, nessun aggiornamento e' stato installato.
$updatesInstalledThisSession = $null -ne $updates -and ($updates | Measure-Object).Count -gt 0
try {
    $wuRebootRequired = Get-WURebootStatus
    if ($wuRebootRequired -and $updatesInstalledThisSession) {
        Write-Log "Riavvio richiesto per completare gli aggiornamenti."
        Write-Summary
        Write-StateFile @{ Action = "ShowSummary"; SummaryFile = $script:summaryFilePath }
        Register-ResumeTask
        Write-Log "*****************Script completato con successo. Sistema in riavvio per aggiornamenti.*****************"
        Start-Sleep -Seconds 3
        Restart-Computer -Force
        Start-Sleep -Seconds 120
        exit
    } elseif ($wuRebootRequired) {
        Write-Log "[INFO] WURebootStatus segnala riavvio pendente, ma nessun aggiornamento installato in questa sessione: riavvio automatico saltato."
        Write-Host "`n"
    } else {
        Write-Log "[OK] Riavvio non necessario."
        Write-Host "`n"
    }
} catch {
    Write-Log "[ATTENZIONE] Impossibile verificare lo stato di riavvio. Controlla manualmente se e' necessario riavviare."
    Write-Log "[INFO] Se necessario, esegui: Restart-Computer -Force"
}

# === Chiusura dello Script ===
if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
if (Test-Path $planFile) { Remove-Item $planFile -Force }
if (Test-Path $domainCredentialFile) { Remove-Item $domainCredentialFile -Force }
Unregister-ResumeTask
Write-Summary -OpenFile
Write-Log "`n*****************Script completato con successo.*****************"
Write-Log "[PRONTO] PC pronto per l'utente."
