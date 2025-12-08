#========================================
# Winget Automated Deployment Script
# Version: V5 (December 2025)
#========================================
# Provisioning automatico workstation Windows
# con software, aggiornamenti e configurazioni
#========================================

#Version: 1.4

# === VERIFICA PRIVILEGI AMMINISTRATORI ===
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "[ATTENZIONE] Questo script dovrebbe essere eseguito con privilegi amministrativi!"
    Write-Host "[INFO] Alcune operazioni (installazione moduli, modifiche registro) richiederanno admin."
    Write-Host "[INFO] Continuando con funzionalita' limitate..."
    $adminWarningIssued = $true
} else {
    Write-Host "[OK] Script eseguito con privilegi amministrativi."
    $adminWarningIssued = $false
}

# Percorso del file di log
$logpath = "C:\Temp\LogsWinget.txt"

# Percorso del file di stato per join al dominio
$stateFile = "C:\Temp\JoinDomainState.txt"

# Dominio a cui aggiungere il pc
$domain = "test.local"  

# Lista delle applicazioni da installare/aggiornare
$apps = @(
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
        # Prova a usare Get-WinGetPackage se disponibile, altrimenti usa winget CLI direttamente
        $installedPackage = $null
        try {
            $installedPackage = Get-WinGetPackage | Where-Object { $_.Id -eq $packageId }
        } catch {
            # Se il cmdlet non è disponibile, usa winget CLI
            Write-Log "[INFO] Cmdlet Get-WinGetPackage non disponibile, usando CLI winget..."
        }

        if ($installedPackage) {
            Write-Log "Il pacchetto $packageId e' gia' installato (Versione: $($installedPackage.Version))."

            # Controlla se e' disponibile un aggiornamento
            Write-Log "Verifica disponibilita' aggiornamento per $packageId..."
            $output = & winget upgrade --id $packageId --accept-source-agreements 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "[OK] Aggiornamento completato per $packageId"
            } else {
                Write-Log "Nessun aggiornamento disponibile per $packageId."
            }
        } else {
            Write-Log "Il pacchetto $packageId non e' installato. Avvio installazione..."
            $output = & winget install --id $packageId --accept-source-agreements --accept-package-agreements 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "[OK] Installazione completata con successo per $packageId"
            } else {
                Write-Log "[ERRORE] Errore durante l'installazione di $packageId. Codice: $LASTEXITCODE"
            }
        }
    } catch {
        Write-Log "[ERRORE] Errore durante l'operazione su $packageId : $_"
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
            Write-Log "[ERRORE] Creazione utente annullata."
            Add-Content -Path $logPath -Value "$(Get-Date) - [ERRORE] Creazione utente annullata."
            Write-Host "`n"
            break
        }

        # Chiede se si vuole creare un altro utente
        $repeat = Read-Host "Vuoi creare un altro utente? (S/N)"
        Write-Host "`n"
    } while ($repeat -match "^[sS]$")
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

# Richiesta creazione utenti locali
New-LocalAdminUser
Write-Host "`n"

# Installato modulo Powershell Winget per loggare andamento installazione e update
# Installato modulo PSWindowsUpdate per la gestione degli aggiornamenti di Windows
# Controllo e installazione dei moduli solo se necessario
Install-ModuleIfMissing "Microsoft.WinGet.Client"
Install-ModuleIfMissing "PSWindowsUpdate"
Write-Host "`n"

# === Sezione 0: Verifica se e' iniziata la procedura di join a dominio ===
# Controlla se lo script è stato eseguito prima del riavvio
if ((Test-Path $stateFile) -and ((Get-Content $stateFile) -match '\S')) {
    # Legge il nome del PC dal file
    $currentPCName = $env:COMPUTERNAME
    Write-Log "Ripresa del processo di Join al dominio"
    Write-Log "`nNome PC attuale: $currentPCName"
    $confirmPCName = Read-Host "Confermi il nome PC? (y/n)"
    if ($confirmPCName -ne 'y') {
        $newPCName = Read-Host "Inserisci il nuovo nome PC"
    } else {
            $newPCName = $currentPCName
        }
    
    Write-Log "`nDominio attuale: $domain"
    $confirmDomain = Read-Host "Confermi il dominio? (y/n)"
    if ($confirmDomain -ne 'y') {
        $domain = Read-Host "Inserisci il nuovo dominio"
    }
    Write-Log "Dominio impostato: $domain"

    if ($newPCName -ne $currentPCName) {
        Write-Log "`nNome PC cambiato. Riavvio tra 60 secondi. Rieseguire lo script dopo il riavvio."
        Rename-Computer -NewName $newPCName -Force
        Start-Sleep -Seconds 60
        Restart-Computer -Force
    } else {
        Write-Log "`nNome PC invariato. Procedo con la join al dominio."
        Write-Log "Inserisci le credenziali di amministratore di dominio"
        Remove-Item $stateFile -Force
        try {
            $cred = Get-Credential -Message "Inserisci le credenziali di amministratore di dominio per $domain"
            if ($null -eq $cred) {
                Write-Log "[ERRORE] Credenziali non fornite. Annullamento join al dominio."
                exit 1
            }
            Add-Computer -DomainName $domain -Credential $cred -Force
            Write-Log "`n[OK] PC aggiunto al dominio con successo. Riavvio tra 60 secondi."
        } catch {
            Write-Log "[ERRORE] Errore durante l'aggiunta al dominio: $_"
            exit 1
        }
        Write-Log "`n[ATTENZIONE] RICORDATI DI SPOSTARE IL PC NELL'UNITA' ORGANIZZATIVA CORRETTA"
        Start-Sleep -Seconds 60
        Restart-Computer -Force
    }
    Write-Log "`n*****************Script completato con successo.*****************"
    exit
}

# === Sezione 1: Scrittura delle informazioni di sistema ===

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

# === Sezione 2: Installazione Applicazioni ===

# Installazione o aggiornamento delle applicazioni necessarie
foreach ($app in $apps) {
    Install-Or-Update-WinGetPackage -packageId $app
    Write-Host "`n"
}

# === Sezione 3: Abilitare "Ottieni gli ultimi aggiornamenti non appena sono disponibili" ===

Write-Log "`n=== Abilitazione aggiornamenti rapidi ==="
# Esegui il comando e reindirizza eventuali errori
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsContinuousInnovationOptedIn /t REG_DWORD /d 1 /f 2>&1 | Out-Null
# Controlla se il comando è andato a buon fine
if ($LASTEXITCODE -eq 0) {
    Write-Log "Impostazione completata: aggiornamenti rapidi abilitati."
} else {
    Write-Log "Errore durante la modifica dell'impostazione degli aggiornamenti rapidi. Codice errore: $LASTEXITCODE"
}
Write-Host "`n"

# === Sezione 4: Configurazione per installare automaticamente aggiornamenti facoltativi ===

Write-Log "`n=== Configurazione aggiornamenti facoltativi ==="
reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v AllowOptionalContent /t REG_DWORD /d 1 /f
if ($LASTEXITCODE -eq 0) {
    Write-Log "Impostazione completata: aggiornamenti facoltativi saranno installati automaticamente."
} else {
    Write-Log "Errore durante la configurazione degli aggiornamenti facoltativi. Codice errore: $LASTEXITCODE"
}
Write-Host "`n"

# === Sezione 5: Abilitare "Ottieni aggiornamenti per altri prodotti Microsoft" ===
$regPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
$regName = "EnableMicrosoftUpdate"

# Controlla se la chiave esiste
if (-Not (Test-Path "Registry::$regPath")) {
    Write-Output "Errore: La chiave di registro non esiste. Creazione della chiave..."
    New-Item -Path "Registry::$regPath" -Force | Out-Null
}

# Imposta il valore nel Registro di sistema
$regSet = reg add $regPath /v $regName /t REG_DWORD /d 1 /f 2>&1

# Verifica il risultato con $LASTEXITCODE
if ($LASTEXITCODE -eq 0) {
    Write-Output "[OK] Impostazione completata con successo."
} else {
    Write-Output "[ERRORE] Errore durante la modifica del registro. Codice: $LASTEXITCODE"
    Write-Output "Dettagli errore: $regSet"
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
    } catch {
        Write-Log "[ERRORE] Errore durante la modifica del motore di ricerca Edge: $_"
    }
} else {
    Write-Log "[ATTENZIONE] Avviso: il file delle preferenze di Edge non esiste (Edge non è stato ancora eseguito)."
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
} catch {
    Write-Log "[ERRORE] Errore durante la modifica delle estensioni file: $_"
}

# === Sezione 8: Impostazioni di risparmio energetico ===
Write-Log "`n=== Configurazione delle impostazioni di risparmio energetico ==="
Try {
    powercfg /change disk-timeout-ac 0
    powercfg /change disk-timeout-dc 0
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    Write-Log "Impostazioni di risparmio energetico configurate su 'Mai' con successo."
    Write-Host "`n"
} Catch {
    Write-Log "[ERRORE] Errore durante la configurazione delle impostazioni di risparmio energetico: $_"
    Write-Host "`n"
}

# === Sezione 9: Avvio manuale di Windows Update ===

# Cerca gli aggiornamenti disponibili
Write-Log "Ricerca degli aggiornamenti disponibili..."
try {
    $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll

    if ($updates) {
        Write-Log "Trovati $(($updates | Measure-Object).Count) aggiornamenti. Avvio installazione..."
        
        # Installa gli aggiornamenti e registra l'output nel log
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot | Out-File -Append -FilePath $logPath

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

$answer = Read-Host "Vuoi inserire il pc a dominio? (y/n)"
if ($answer -ne 'y') {
    Write-Log "Operazione annullata dall'utente."
    exit
}

$currentPCName = $env:COMPUTERNAME
Write-Host "`nNome PC attuale: $currentPCName"

$confirmPCName = Read-Host "Confermi il nome PC? (y/n)"
if ($confirmPCName -ne 'y') {
    $newPCName = Read-Host "Inserisci il nuovo nome PC"
} else {
        $newPCName = $currentPCName
    }
Write-Log "Nome PC impostato: $newPCName"

# Salva il nome del PC nel file di stato
$newPCName | Out-File -FilePath $stateFile -Force

Write-Host "`nDominio attuale: $domain"
$confirmDomain = Read-Host "Confermi il dominio? (y/n)"
if ($confirmDomain -ne 'y') {
    $domain = Read-Host "Inserisci il nuovo dominio"
}
Write-Log "Dominio impostato: $domain"

if ($newPCName -ne $currentPCName) {
    Write-Log "`nNome PC cambiato. Riavvio tra 60 secondi. Rieseguire lo script dopo il riavvio."
    Rename-Computer -NewName $newPCName -Force
    Start-Sleep -Seconds 60
    Restart-Computer -Force
} else {
    Write-Log "`nNome PC invariato. Procedo con la join al dominio."
    Write-Log "Inserisci le credenziali di amministratore di dominio"
    try {
        $cred = Get-Credential -Message "Inserisci le credenziali di amministratore di dominio per $domain"
        if ($null -eq $cred) {
            Write-Log "[ERRORE] Credenziali non fornite. Annullamento join al dominio."
            exit 1
        }
        Add-Computer -DomainName $domain -Credential $cred -Force
        Write-Log "`n[OK] PC aggiunto al dominio con successo. Riavvio tra 60 secondi."
    } catch {
        Write-Log "[ERRORE] Errore durante l'aggiunta al dominio: $_"
        exit 1
    }
    Start-Sleep -Seconds 60
    Restart-Computer -Force
}

# Controlla se e' necessario un riavvio per eseguire gli aggiornamenti di Windows Update
try {
    if (Get-WURebootStatus) {
        Write-Log "Riavvio richiesto per completare gli aggiornamenti. Il sistema si riavviera' tra 1 minuto..."
        Start-Sleep -Seconds 60
        Restart-Computer -Force
    } else {
        Write-Log "[OK] Riavvio non necessario."
        Write-Host "`n"
    }
} catch {
    Write-Log "[ATTENZIONE] Impossibile verificare lo stato di riavvio. Controlla manualmente se e' necessario riavviare."
    Write-Log "[INFO] Se necessario, esegui: Restart-Computer -Force"
}

# === Chiusura dello Script ===
Write-Log "`n*****************Script completato con successo.*****************"
