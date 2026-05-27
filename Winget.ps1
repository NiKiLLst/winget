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

# URL del repository GitHub ufficiale, usato per il bootstrap quando la cartella
# locale non e' un clone git (tipico caso: download ZIP da GitHub, "winget-main").
$script:GitHubRepoUrl = "https://github.com/NiKiLLst/winget.git"

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

function Initialize-RepoFromGitHub {
    param(
        [string]$repoPath,
        [string]$repoUrl,
        [string]$scriptToRun
    )

    # Bootstrap: se la cartella non e' un clone (tipico "winget-main" da ZIP)
    # cloniamo il repo in una temp, copiamo .git nella cartella corrente e
    # riallineamo i file alla versione GitHub. Cosi' i rilanci successivi
    # avranno auto-update funzionante senza intervento manuale.

    Write-Host ""
    Write-Host "[INFO] Repository git non trovato in $repoPath (probabile download ZIP)."
    $answer = Read-Host "Inizializzo la cartella come clone di $repoUrl per abilitare l'auto-update? Le eventuali modifiche locali a Winget.ps1 verranno sovrascritte. (S/N, default S)"
    if ($answer -match '^[nN]$') {
        Write-Host "[INFO] Bootstrap saltato: auto-update disabilitato per questa esecuzione."
        return
    }

    $tempClone = Join-Path ([System.IO.Path]::GetTempPath()) ("winget-clone-" + [Guid]::NewGuid().ToString("N"))
    try {
        Write-Host "[INFO] Clonazione di $repoUrl in $tempClone..."
        & git clone --quiet $repoUrl $tempClone 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $tempClone ".git"))) {
            Write-Host "[ATTENZIONE] git clone fallito (controlla connettivita' e URL): skip auto-update."
            return
        }

        Write-Host "[INFO] Inizializzazione .git locale e allineamento file alla versione GitHub..."
        Copy-Item -Recurse -Force -Path (Join-Path $tempClone ".git") -Destination $repoPath
        & git -C $repoPath reset --hard HEAD 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ATTENZIONE] git reset --hard fallito dopo bootstrap: skip auto-update."
            return
        }

        Write-Host "[OK] Repository inizializzato. Riavvio dello script aggiornato..."
        $env:WINGET_SELFUPDATED = "1"
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptToRun`""
        exit
    } catch {
        Write-Host "[ATTENZIONE] Errore durante bootstrap repository: $_"
    } finally {
        if (Test-Path $tempClone) {
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $tempClone
        }
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
        Initialize-RepoFromGitHub -repoPath $repoPath -repoUrl $script:GitHubRepoUrl -scriptToRun $scriptToRun
        # Se siamo ancora qui il bootstrap e' stato saltato o e' fallito.
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
# Credenziali dell'utente di dominio finale (usate per autologon e provisioning post-join)
$domainUserCredentialFile = "$PSScriptRoot\logs\DomainUserCredential.xml"
# Chiave di registro usata per l'autologon temporaneo post-join
$autologonRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

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
    #"Amazon.AWSCLI",
    "PuTTY.PuTTY",
    #"Postman.Postman",
    "Microsoft.PowerShell",
    "Microsoft.WindowsTerminal",
    "Microsoft.VisualStudioCode",
    "Microsoft.AzureCLI",
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
    # -User permette di registrare il task per un utente diverso da quello corrente
    # (es. l'utente di dominio dopo il join, per riprendere il provisioning nel suo contesto).
    param ([string]$User)
    Write-Log "Registrazione attivita' pianificata '$resumeTaskName' in corso..."
    try {
        $scriptPath  = $PSCommandPath
        $taskUser = if (-not [string]::IsNullOrWhiteSpace($User)) { $User } else { "$env:USERDOMAIN\$env:USERNAME" }
        $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                        -Argument "-WindowStyle Normal -ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
        $principal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                        -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        Register-ScheduledTask -TaskName $resumeTaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        Write-Log "[OK] Attivita' pianificata '$resumeTaskName' registrata. Trigger: AtLogOn, Utente: $taskUser, Script: $scriptPath"
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

# Garantisce che il task di resume sia attivo durante TUTTA l'esecuzione, non solo
# nei brevi istanti che precedono un Restart-Computer pianificato. In questo modo,
# qualsiasi interruzione non controllata (riavvio manuale dell'operatore, BSOD,
# riavvio imposto da Windows Update, crash dello script) viene comunque ripresa al
# logon successivo. Idempotente: se il task esiste gia' (eredita' di una sessione
# precedente) non rifa' la registrazione. Da chiamare appena lo script ha caricato
# il piano d'esecuzione, prima di iniziare qualunque attivita' di provisioning.
function Ensure-ResumeTaskActive {
    param ([string]$User)
    try {
        if (Get-ScheduledTask -TaskName $resumeTaskName -ErrorAction SilentlyContinue) {
            Write-Log "[OK] Attivita' pianificata '$resumeTaskName' gia' attiva: resume garantito ad ogni riavvio."
            return
        }
    } catch {}
    Write-Log "[INFO] Attivita' pianificata '$resumeTaskName' non presente: registrazione preventiva per garantire il resume."
    if ([string]::IsNullOrWhiteSpace($User)) {
        Register-ResumeTask
    } else {
        Register-ResumeTask -User $User
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

function Confirm-Choice {
    param([string]$message)

    $confirm = Read-Host $message
    return [string]::IsNullOrWhiteSpace($confirm) -or ($confirm -match '^[sSyY]$')
}

# === X.8 - Funzioni per join al dominio: verifica credenziali/nome, autologon ===

# Verifica le credenziali contro il dominio.
# Ritorna: $true valide, $false errate, $null dominio non raggiungibile.
function Test-DomainCredential {
    param (
        [string]$domainName,
        [System.Management.Automation.PSCredential]$credential
    )
    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
        $netCred = $credential.GetNetworkCredential()
        $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain, $domainName)
        $valid = $ctx.ValidateCredentials($netCred.UserName, $netCred.Password)
        $ctx.Dispose()
        return [bool]$valid
    } catch {
        Write-Log "[ATTENZIONE] Impossibile contattare il dominio '$domainName' per la verifica credenziali: $_"
        return $null
    }
}

# Chiede le credenziali e le verifica sul dominio, in loop finche' valide.
# Ritorna la PSCredential verificata, oppure $null se l'utente annulla.
function Get-TestedDomainCredential {
    param (
        [string]$domainName,
        [string]$promptMessage
    )
    while ($true) {
        $cred = Get-Credential -Message $promptMessage
        if ($null -eq $cred) { return $null }

        $check = Test-DomainCredential -domainName $domainName -credential $cred
        if ($check -eq $true) {
            Write-Host "  -> Credenziali verificate sul dominio '$domainName'."
            return $cred
        } elseif ($null -eq $check) {
            # Dominio non raggiungibile: non si puo' verificare, si lascia decidere all'operatore.
            if (Confirm-Choice -message "Impossibile verificare le credenziali (dominio non raggiungibile). Proseguire comunque? (Y/S o Invio)") {
                return $cred
            }
        } else {
            Write-Host "  -> Credenziali errate per il dominio '$domainName'. Riprova."
        }
    }
}

# Legge una PSCredential da un file Clixml, se presente.
function Import-CredentialFile {
    param ([string]$path)
    if ($path -and (Test-Path $path)) {
        try {
            return Import-Clixml -Path $path
        } catch {
            Write-Log "[ATTENZIONE] Impossibile leggere il file credenziali '$path': $_"
        }
    }
    return $null
}

# Verifica se un nome PC e' gia' in uso.
# Ritorna: 'Free', 'Exists' oppure 'Unknown' (verifica non riuscita).
function Test-ComputerNameAvailable {
    param (
        [string]$computerName,
        [bool]$joinDomain,
        [string]$domainName,
        [System.Management.Automation.PSCredential]$credential
    )

    if ($joinDomain -and $null -ne $credential) {
        # Ricerca dell'oggetto computer in Active Directory
        try {
            $netCred = $credential.GetNetworkCredential()
            $ldapUser = if ($netCred.Domain) { "$($netCred.Domain)\$($netCred.UserName)" } else { $netCred.UserName }
            $entry    = New-Object System.DirectoryServices.DirectoryEntry(
                "LDAP://$domainName", $ldapUser, $netCred.Password)
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
            $searcher.Filter = "(&(objectCategory=computer)(cn=$computerName))"
            $searcher.PageSize = 1
            $result = $searcher.FindOne()
            $searcher.Dispose()
            $entry.Dispose()
            if ($null -ne $result) { return 'Exists' } else { return 'Free' }
        } catch {
            Write-Log "[ATTENZIONE] Impossibile verificare il nome PC in Active Directory: $_"
            return 'Unknown'
        }
    }

    # Fallback senza dominio: ping ICMP
    try {
        if (Test-Connection -ComputerName $computerName -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            return 'Exists'
        }
        return 'Free'
    } catch {
        return 'Unknown'
    }
}

# Verifica se il PC e' gia' membro del dominio indicato.
function Test-AlreadyJoinedToDomain {
    param ([string]$domainName)
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if (-not $cs.PartOfDomain) { return $false }
        if ([string]::IsNullOrWhiteSpace($domainName)) { return $true }
        # Confronto tollerante: $cs.Domain puo' essere DNS o NetBIOS
        $currentShort = ($cs.Domain  -split '\.')[0]
        $wantShort    = ($domainName -split '\.')[0]
        return ($cs.Domain -eq $domainName) -or ($currentShort -eq $wantShort)
    } catch {
        return $false
    }
}

# Esegue il join al dominio; su errore propone di reinserire le credenziali e riprova.
# Ritorna $true se il join e' riuscito, $false se rimandato.
function Join-ComputerToDomain {
    param (
        [string]$domainName,
        [System.Management.Automation.PSCredential]$credential,
        [string]$credentialFile
    )

    $cred = $credential
    while ($true) {
        try {
            Add-Computer -DomainName $domainName -Credential $cred -Force -ErrorAction Stop
            Write-Log "[OK] PC aggiunto al dominio '$domainName' con successo."
            return $true
        } catch {
            Write-Log "[ERRORE] Errore durante l'aggiunta al dominio '$domainName': $_"
        }

        $retry = Read-Host "Join al dominio fallito. Vuoi reinserire le credenziali e riprovare ora? (S/N)"
        if ($retry -notmatch '^[sSyY]$') {
            Write-Log "[INFO] Join rimandato. Lo script ripartira' dal join al prossimo accesso o rilancio."
            return $false
        }

        $cred = Get-Credential -Message "Credenziali amministratore di dominio per $domainName"
        if ($null -eq $cred) {
            Write-Log "[INFO] Nessuna credenziale fornita. Join rimandato."
            return $false
        }
        if ($credentialFile) {
            try {
                $cred | Export-Clixml -Path $credentialFile -Force
                Write-Log "[OK] Credenziali dominio aggiornate per i tentativi successivi."
            } catch {
                Write-Log "[ATTENZIONE] Impossibile salvare le nuove credenziali dominio: $_"
            }
        }
    }
}

# Aggiunge un account (es. utente di dominio) al gruppo Amministratori locali.
function Add-DomainUserToLocalAdmins {
    param ([string]$account)
    try {
        # SID S-1-5-32-544 = gruppo Administrators (robusto rispetto alla lingua del sistema)
        $adminGroup = (Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction Stop).Name
        $shortName  = $account -replace '^.*\\', ''
        $alreadyMember = Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $account -or ($_.Name -replace '^.*\\', '') -ieq $shortName }
        if ($alreadyMember) {
            Write-Log "[INFO] L'utente '$account' e' gia' negli Amministratori locali."
            return $true
        }
        Add-LocalGroupMember -Group $adminGroup -Member $account -ErrorAction Stop
        Write-Log "[OK] Utente di dominio '$account' aggiunto agli Amministratori locali."
        return $true
    } catch {
        Write-Log "[ERRORE] Impossibile aggiungere '$account' agli Amministratori locali: $_"
        return $false
    }
}

# Configura un autologon temporaneo per l'utente di dominio (con tetto AutoLogonCount).
function Set-OneShotAutologon {
    param (
        [System.Management.Automation.PSCredential]$credential,
        [string]$domainName
    )
    try {
        $netCred    = $credential.GetNetworkCredential()
        $userDomain = if ($netCred.Domain) { $netCred.Domain } else { $domainName }
        Set-ItemProperty -Path $autologonRegPath -Name "AutoAdminLogon"    -Value "1"               -Type String -Force
        Set-ItemProperty -Path $autologonRegPath -Name "DefaultUserName"   -Value $netCred.UserName -Type String -Force
        Set-ItemProperty -Path $autologonRegPath -Name "DefaultDomainName" -Value $userDomain       -Type String -Force
        Set-ItemProperty -Path $autologonRegPath -Name "DefaultPassword"   -Value $netCred.Password -Type String -Force
        # Tetto di sicurezza: l'autologon si esaurisce da solo dopo alcuni accessi
        Set-ItemProperty -Path $autologonRegPath -Name "AutoLogonCount"    -Value 5                 -Type DWord  -Force
        Write-Log "[OK] Autologon temporaneo configurato per '$userDomain\$($netCred.UserName)'."
        return $true
    } catch {
        Write-Log "[ERRORE] Impossibile configurare l'autologon: $_"
        return $false
    }
}

# Rimuove l'autologon temporaneo (in particolare la password in chiaro).
function Clear-Autologon {
    try {
        foreach ($name in @("DefaultPassword", "AutoLogonCount")) {
            $prop = Get-ItemProperty -Path $autologonRegPath -Name $name -ErrorAction SilentlyContinue
            if ($null -ne $prop) {
                Remove-ItemProperty -Path $autologonRegPath -Name $name -ErrorAction SilentlyContinue
            }
        }
        Set-ItemProperty -Path $autologonRegPath -Name "AutoAdminLogon" -Value "0" -Type String -Force -ErrorAction SilentlyContinue
        Write-Log "[OK] Autologon temporaneo rimosso."
    } catch {
        Write-Log "[ATTENZIONE] Impossibile rimuovere completamente l'autologon: $_"
    }
}

# === X.9 - Orchestrazione della fase di join al dominio ===

# Salva il savepoint Progress, registra il task di resume e riavvia: al prossimo
# accesso il provisioning (sezioni 1-9) riprende da capo. Non ritorna mai.
function Restart-ForProgressResume {
    param ([string]$User)
    Write-StateFile @{ Action = "Progress"; Step = "" }
    if ([string]::IsNullOrWhiteSpace($User)) {
        Register-ResumeTask
    } else {
        Register-ResumeTask -User $User
    }
    Write-Log "*****************Riavvio per eseguire il provisioning.*****************"
    Start-Sleep -Seconds 3
    Restart-Computer -Force
    Start-Sleep -Seconds 120
    exit
}

# Configurazione post-join: aggiunge l'utente di dominio agli Amministratori locali,
# imposta l'autologon temporaneo e riavvia per eseguire il provisioning come quell'utente.
# -allowRebootRetry: se l'aggiunta agli admin fallisce, riprova dopo un riavvio.
# Non ritorna mai: riavvia il sistema e termina lo script.
function Invoke-PostJoinSetup {
    param (
        [string]$domainName,
        $plan,
        [bool]$allowRebootRetry
    )

    $domainUser     = [string]$plan.DomainUserName
    $domainUserCred = Import-CredentialFile -path $domainUserCredentialFile

    # Senza utente di dominio valido il provisioning prosegue come utente corrente.
    if ([string]::IsNullOrWhiteSpace($domainUser) -or $null -eq $domainUserCred) {
        Write-Log "[ATTENZIONE] Utente di dominio non disponibile: il provisioning proseguira' come utente corrente."
        Restart-ForProgressResume
    }

    if (-not (Add-DomainUserToLocalAdmins -account $domainUser)) {
        if ($allowRebootRetry) {
            Write-Log "[INFO] Aggiunta agli Amministratori locali non riuscita: verra' ritentata dopo il riavvio."
            Write-StateFile @{ Action = "JoinDomain"; Step = "Joined"; DesiredComputerName = $env:COMPUTERNAME; Domain = $domainName }
            Register-ResumeTask
            Write-Log "*****************Sistema in riavvio per completare la configurazione del join.*****************"
            Start-Sleep -Seconds 3
            Restart-Computer -Force
            Start-Sleep -Seconds 120
            exit
        }
        Write-Log "[ATTENZIONE] Impossibile aggiungere l'utente di dominio agli Amministratori locali: provisioning come utente corrente."
        Restart-ForProgressResume
    }

    # Autologon temporaneo: il provisioning ripartira' nel contesto dell'utente di dominio.
    Set-OneShotAutologon -credential $domainUserCred -domainName $domainName | Out-Null
    Write-Log "[OK] Configurazione post-join completata per '$domainUser'."
    Restart-ForProgressResume -User $domainUser
}

# Esegue il join al dominio e, in caso di successo, la configurazione post-join.
# Su errore mantiene savepoint e task di resume cosi' un rilancio riprende dal join.
# Non ritorna mai: riavvia il sistema oppure termina lo script.
function Invoke-DomainJoinPhase {
    param (
        [string]$domainName,
        $plan
    )

    # Se il PC e' gia' a dominio (tentativo precedente riuscito) si passa al post-join.
    if (Test-AlreadyJoinedToDomain -domainName $domainName) {
        Write-Log "[OK] PC gia' membro del dominio '$domainName'. Proseguo con la configurazione post-join."
        Write-StateFile @{ Action = "JoinDomain"; Step = "Joined"; DesiredComputerName = $env:COMPUTERNAME; Domain = $domainName }
        Invoke-PostJoinSetup -domainName $domainName -plan $plan -allowRebootRetry $true
        return
    }

    # Savepoint: pronti al join (nome PC gia' corretto). Mantenuto in caso di errore.
    Write-StateFile @{ Action = "JoinDomain"; Step = "Renamed"; DesiredComputerName = $env:COMPUTERNAME; Domain = $domainName }
    Register-ResumeTask

    $joinCred = Import-CredentialFile -path $domainCredentialFile
    if ($null -eq $joinCred) {
        Write-Log "[ATTENZIONE] Credenziali di join non disponibili: richiesta interattiva."
        $joinCred = Get-Credential -Message "Credenziali di amministratore di dominio per $domainName"
        if ($null -eq $joinCred) {
            Write-Log "[INFO] Nessuna credenziale fornita. Join rimandato (savepoint e task mantenuti)."
            exit
        }
        try { $joinCred | Export-Clixml -Path $domainCredentialFile -Force } catch {}
    }

    $joined = Join-ComputerToDomain -domainName $domainName -credential $joinCred -credentialFile $domainCredentialFile
    if (-not $joined) {
        Write-Log "[INFO] Join non completato. Savepoint e task mantenuti: lo script ripartira' dal join al prossimo avvio."
        exit
    }

    Write-Log "[ATTENZIONE] RICORDATI DI SPOSTARE IL PC NELL'UNITA' ORGANIZZATIVA CORRETTA"
    Write-StateFile @{ Action = "JoinDomain"; Step = "Joined"; DesiredComputerName = $env:COMPUTERNAME; Domain = $domainName }
    Invoke-PostJoinSetup -domainName $domainName -plan $plan -allowRebootRetry $true
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
    # Ordine: il dominio e le credenziali servono per verificare il nome PC in AD,
    # quindi vengono richiesti prima del nome PC.
    New-LocalAdminUser
    Write-Host "`n"

    # --- Join al dominio e dominio di destinazione ---
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

    # --- Credenziali di dominio (verificate subito, prima di salvarle) ---
    $joinCred       = $null
    $domainUserCred = $null
    $domainUserName = $null
    if ($planJoin) {
        # 1) Credenziali dell'amministratore che esegue il join al dominio
        $joinCred = Get-TestedDomainCredential -domainName $planDomain `
            -promptMessage "Credenziali di amministratore di dominio per il join a $planDomain"
        if ($null -eq $joinCred) {
            Write-Log "[ERRORE] Credenziali di join non fornite. Annullamento esecuzione."
            exit 1
        }

        # 2) Credenziali dell'utente di dominio che utilizzera' il PC
        Write-Host ""
        Write-Host "[ATTENZIONE] L'utente di dominio finale verra' aggiunto al gruppo Amministratori"
        Write-Host "             locali di questo PC: serve per eseguire app/tweak/Windows Update"
        Write-Host "             dopo il join, nel contesto di quell'utente."
        $domainUserCred = Get-TestedDomainCredential -domainName $planDomain `
            -promptMessage "Credenziali dell'utente di dominio che utilizzera' il PC"
        if ($null -eq $domainUserCred) {
            Write-Log "[ERRORE] Credenziali utente di dominio non fornite. Annullamento esecuzione."
            exit 1
        }
        # Normalizza il nome utente. Se gia' qualificato (DOMINIO\utente o utente@dominio)
        # si mantiene; altrimenti si antepone il nome NetBIOS del dominio (forma piu'
        # compatibile con Add-LocalGroupMember, task pianificato e autologon).
        $rawDomainUser = $domainUserCred.UserName
        if ($rawDomainUser -match '[\\@]') {
            $domainUserName = $rawDomainUser
        } else {
            $netbiosDomain  = ($planDomain -split '\.')[0].ToUpper()
            $domainUserName = "$netbiosDomain\$rawDomainUser"
        }
    }

    # --- Nome PC (con verifica disponibilita') ---
    $currentPCName = $env:COMPUTERNAME
    Write-Host ""
    Write-Host "Nome PC attuale: $currentPCName"
    do {
        $planPCName = Read-Host "Inserisci il nuovo nome PC (lascia vuoto per mantenere '$currentPCName')"
        if ([string]::IsNullOrWhiteSpace($planPCName)) { $planPCName = $currentPCName }
        if (-not (Confirm-Choice -message "Hai inserito '$planPCName' come nome PC, confermi? (Y/S o Invio)")) {
            Write-Host "  -> Reinserisci il nome PC."
            $pcNameAccepted = $false
            continue
        }
        if ($planPCName -ieq $currentPCName) {
            # Mantiene il nome attuale: nessun nome nuovo da verificare.
            $pcNameAccepted = $true
        } else {
            $nameStatus = Test-ComputerNameAvailable -computerName $planPCName -joinDomain $planJoin `
                -domainName $planDomain -credential $joinCred
            if ($nameStatus -eq 'Exists') {
                if (Confirm-Choice -message "Esiste gia' un pc con questo nome. Vuoi cambiare il nome? (Y/S o Invio)") {
                    Write-Host "  -> Reinserisci il nome PC."
                    $pcNameAccepted = $false
                } else {
                    $pcNameAccepted = $true
                }
            } elseif ($nameStatus -eq 'Free') {
                Write-Host "  -> Non esiste attualmente un pc con questo nome."
                $pcNameAccepted = $true
            } else {
                Write-Host "  -> Impossibile verificare il nome PC: si prosegue con '$planPCName'."
                $pcNameAccepted = $true
            }
        }
    } while (-not $pcNameAccepted)

    # --- Selezione applicazioni ---
    $selectedApps = Select-AppsForInstallation -candidateApps $availableApps

    # --- Salvataggio credenziali e piano di esecuzione ---
    $executionPlan = [ordered]@{
        DesiredComputerName      = $planPCName
        JoinDomain               = $planJoin
        Domain                   = $planDomain
        Apps                     = @($selectedApps)
        DomainCredentialFile     = $null
        DomainUserCredentialFile = $null
        DomainUserName           = $domainUserName
    }

    if ($planJoin) {
        try {
            $joinCred       | Export-Clixml -Path $domainCredentialFile -Force
            $domainUserCred | Export-Clixml -Path $domainUserCredentialFile -Force
            $executionPlan.DomainCredentialFile     = $domainCredentialFile
            $executionPlan.DomainUserCredentialFile = $domainUserCredentialFile
            Write-Log "[OK] Credenziali di dominio salvate per la fase automatica di join."
        } catch {
            Write-Log "[ERRORE] Impossibile salvare le credenziali di dominio: $_"
            exit 1
        }
    }

    Write-ExecutionPlan -plan $executionPlan
}

$desiredComputerName = if ($executionPlan.DesiredComputerName) { [string]$executionPlan.DesiredComputerName } else { $env:COMPUTERNAME }
$joinRequested = [bool]$executionPlan.JoinDomain
$domain = if ($executionPlan.Domain) { [string]$executionPlan.Domain } else { $domain }
$apps = @($executionPlan.Apps)
$domainUserName = if ($executionPlan.DomainUserName) { [string]$executionPlan.DomainUserName } else { $null }
# Dominio di destinazione stabile: la Sezione 1 (SysInfo) sovrascrive $domain con il
# dominio corrente del PC, quindi join e verifiche usano $plannedDomain.
$plannedDomain = $domain

# Resume always-on: il task di resume viene attivato SUBITO, appena conosciamo il
# piano d'esecuzione, e rimosso solo agli stati realmente terminali (ShowSummary o
# chiusura finale). Questo garantisce che qualsiasi riavvio - anche manuale o non
# pianificato (es. utente che riavvia dopo un messaggio di Windows Update, crash,
# kill della finestra PowerShell) - rilanci comunque lo script al logon successivo,
# che riprendera' dal savepoint sul disco.
Ensure-ResumeTaskActive

# === Sezione 0: Resume da savepoint (stateFile JSON) ===
if ($null -ne $resumeState) {
    Write-Log "=== Ripresa da savepoint: Action=$($resumeState.Action), Step=$($resumeState.Step) ==="

    # --- Ripresa dopo rinomina standalone ---
    if ($resumeState.Action -eq "RenameOnly") {
        Write-Log "[OK] Rinomina completata. Rimozione savepoint e proseguimento script normale."
        Remove-Item $stateFile -Force
    }

    # --- Ripresa della fase di join al dominio ---
    elseif ($resumeState.Action -eq "JoinDomain") {
        $currentPCName = $env:COMPUTERNAME
        $savedDomain = if ($resumeState.Domain) { $resumeState.Domain } else { $domain }
        Write-Log "Ripresa fase di join al dominio '$savedDomain' (Step=$($resumeState.Step))."

        if ($resumeState.Step -eq "Joined") {
            # Join gia' eseguito: manca solo la configurazione post-join.
            Invoke-PostJoinSetup -domainName $savedDomain -plan $executionPlan -allowRebootRetry $false
        } else {
            # Step "Renamed" (o sconosciuto): il nome PC deve essere corretto, poi join.
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
            }
            # Esegue join + configurazione post-join (la funzione riavvia o esce).
            Invoke-DomainJoinPhase -domainName $savedDomain -plan $executionPlan
        }
    }

    # --- Riepilogo post-riavvio aggiornamenti ---
    elseif ($resumeState.Action -eq "ShowSummary") {
        Unregister-ResumeTask
        Clear-Autologon
        if ($resumeState.SummaryFile -and (Test-Path $resumeState.SummaryFile)) {
            Write-Log "[OK] Apertura scheda installazione: $($resumeState.SummaryFile)"
            Start-Process notepad.exe -ArgumentList "`"$($resumeState.SummaryFile)`""
        } else {
            Write-Log "[ATTENZIONE] File scheda non trovato: $($resumeState.SummaryFile)"
        }
        # Stato terminale: pulizia finale dei file di stato e credenziali.
        if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
        if (Test-Path $planFile) { Remove-Item $planFile -Force }
        if (Test-Path $domainCredentialFile) { Remove-Item $domainCredentialFile -Force }
        if (Test-Path $domainUserCredentialFile) { Remove-Item $domainUserCredentialFile -Force }
        exit
    }

    # --- Ripresa savepoint di progresso ---
    elseif ($resumeState.Action -eq "Progress") {
        Write-Log "Ripresa da savepoint progresso: Step=$($resumeState.Step)"
        # Il task di resume resta volutamente registrato finche' lo script non
        # raggiunge la chiusura finale: se l'esecuzione si interrompe di nuovo
        # in mezzo (riavvio manuale, crash, Windows Update che impone reboot),
        # al logon successivo verra' rilanciato dal task e ripartira' da qui.
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

# === Sezione Join al dominio (anticipata) ===
# Il join viene eseguito come PRIMO passo, cosi' il provisioning (app/tweak/Windows
# Update) gira poi nel contesto dell'utente di dominio. Questo blocco copre il caso
# senza rinomina; con rinomina il join e' gestito dal ramo di resume dopo il riavvio.
if ($joinRequested -and ($null -eq $resumeState) -and -not (Test-AlreadyJoinedToDomain -domainName $plannedDomain)) {
    Write-Log "`n=== Join al dominio '$plannedDomain' ==="
    # La funzione esegue join + configurazione post-join e poi riavvia (non ritorna).
    Invoke-DomainJoinPhase -domainName $plannedDomain -plan $executionPlan
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

# === Sezione 10: Join al dominio (verifica) ===
# Il join vero e' eseguito come primo passo (sezione anticipata o ramo di resume):
# qui resta solo un controllo di sicurezza.
if (-not $joinRequested) {
    Write-Log "[INFO] Join al dominio non richiesto."
} elseif (Test-AlreadyJoinedToDomain -domainName $plannedDomain) {
    Write-Log "[OK] PC gia' membro del dominio '$plannedDomain'."
} else {
    Write-Log "[ATTENZIONE] Join al dominio '$plannedDomain' non ancora eseguito: esecuzione ora."
    # La funzione esegue join + configurazione post-join e poi riavvia (non ritorna).
    Invoke-DomainJoinPhase -domainName $plannedDomain -plan $executionPlan
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
Clear-Autologon
if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
if (Test-Path $planFile) { Remove-Item $planFile -Force }
if (Test-Path $domainCredentialFile) { Remove-Item $domainCredentialFile -Force }
if (Test-Path $domainUserCredentialFile) { Remove-Item $domainUserCredentialFile -Force }
Unregister-ResumeTask
Write-Summary -OpenFile
Write-Log "`n*****************Script completato con successo.*****************"
Write-Log "[PRONTO] PC pronto per l'utente."
