#Version: 1.4

# Percorso del file di log
$logpath = "C:\Temp\LogsWinget.txt"

# Percorso del file di stato per join al dominio
$stateFile = "C:\Temp\JoinDomainState.txt"

# Dominio a cui aggiungere il pc
$domain = "test.local"  

# Lista delle applicazioni da installare/aggiornare
$apps = @(
    #"Se Non vuoi installare qualcosa, basta che ci metti un # davanti"
    "Microsoft.Edge"
    "Microsoft.Office"
    "Adobe.Acrobat.Reader.64-bit"
    "7zip.7zip"
    "VideoLAN.VLC"
    #"Google.Chrome"
    #"Mozilla.Firefox"
    #"Amazon.AWSCLI"
    #"PuTTY.PuTTY"
    #"Postman.Postman"
    #"Microsoft.PowerShell"
    #"Microsoft.WindowsTerminal"
    #"Microsoft.VisualStudioCode"
    #"Git.Git"
    #"FlipperDevicesInc.qFlipper"
)

$appbynames = @(
    #"Notepad++.Notepad++"
)

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

    Write-Output "✅ File di log e stato verificati e inizializzati correttamente."
}

# === X.1 - Funzione di Log per scrivere su schermo e su file ===

function Write-Log {
    param (
        [string]$message
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $message" | Out-File -Append -FilePath $logPath -Encoding UTF8
    Write-Output $message
}

# === X.2 - Funzione per controllare e installare un modulo se non presente ===
function Ensure-Module {
    param ([string]$moduleName)
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Log "Modulo $moduleName non installato. Installazione in corso..."
        Install-Module -Name $moduleName -Force -Confirm:$false
    } else {
        Write-Log "✅ Modulo $moduleName gia' installato."
    }
    Import-Module $moduleName
    Write-Log "✅ Modulo $moduleName importato."
}

# === X.3 - Funzione per installare o aggiornare applicativi con WinGet ===
function Install-Or-Update-WinGetPackage {
    param ([string]$packageId)

    Write-Log "Verifica dello stato del pacchetto: $packageId"

    # Controlla se l'applicazione e' gia' installata
    $installedPackage = Get-WinGetPackage | Where-Object { $_.Id -eq $packageId }

    if ($installedPackage) {
        Write-Log "Il pacchetto $packageId e' gia' installato (Versione: $($installedPackage.Version))."

        # Controlla se e' disponibile un aggiornamento
        $updateAvailable = winget upgrade --id $packageId --accept-source-agreements | Out-String
        if ($updateAvailable -match $packageId) {
            Write-Log "Aggiornamento disponibile per $packageId. Avvio aggiornamento..."
            $result = winget upgrade --id $packageId --accept-source-agreements | Out-String
        } else {
            Write-Log "Nessun aggiornamento disponibile per $packageId."
            return
        }
    } else {
        Write-Log "Il pacchetto $packageId non e' installato. Avvio installazione..."
        $result = Install-WinGetPackage $packageId | Select-Object -Property Name,Status,InstallerErrorCode | Out-String
    }

    Write-Log "Risultato dell'operazione su $packageId :`n$result"
    Write-Host "`n"
}

# === X.4 - Funzione con escape per i caratteri speciali per la match ===
# COMMENTATA PER VEDERE SE TORNA A FUNZIONARE IL CONTROLLO DELLE VERSIONI
# Escapa i caratteri speciali nella stringa
#$escapedPackageId = [regex]::Escape($packageId) 

# QUESTA LA VERSIONE ORIGINALE
# Usa la versione escapata per il confronto
#if ($updateAvailable -match $escapedPackageId) {
#if ($updateAvailable -match $packageId) {

# === X.4 - Funzione di creazione utenti amministratori locali ===
function Crea-UtenteAdmin {
    do {
        $response = Read-Host "Vuoi creare un nuovo utente locale? (S/N)"
        
        if ($response -match "^[sS]$") {
            $username = Read-Host "Inserisci il nome del nuovo utente"
            $password = Read-Host "Inserisci la password" -AsSecureString

            # Controllo se l'utente esiste già
            if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
                Write-Log "❌ L'utente '$username' esiste già!"
            } else {
                try {
                    # Creazione utente
                    New-LocalUser -Name $username -Password $password -FullName $username -Description "Utente creato via script" -ErrorAction Stop
                    Write-Log "✅ Utente '$username' creato con successo."

                    # Aggiunta al gruppo amministratori
                    $adminGroup = [System.Security.Principal.WindowsBuiltInRole]::Administrator
                    Add-LocalGroupMember -Group $adminGroup -Member $username -ErrorAction Stop
                    Write-Log "🔑 L'utente '$username' è stato aggiunto agli amministratori."
                    Write-Host "`n"
                    Write-Log "⚠️ Riavvia il PC ed esegui lo script sotto il nuovo utente '$username'."
                    Write-Host "`n"

                } catch {
                    Write-Log "❌ Errore durante la creazione dell'utente: $_"
                }
            }

            # Pausa per leggere eventuali errori
            Start-Sleep -Seconds 5
            
        } else {
            Write-Log "❌ Creazione utente annullata."
            Add-Content -Path $logPath -Value "$(Get-Date) - ❌ Creazione utente annullata."
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

# Richiesta creazione utenti locali
Crea-UtenteAdmin
Write-Host "`n"

# Installato modulo Powershell Winget per loggare andamento installazione e update
# Installato modulo PSWindowsUpdate per la gestione degli aggiornamenti di Windows
# Controllo e installazione dei moduli solo se necessario
Ensure-Module "Microsoft.WinGet.Client"
Ensure-Module "PSWindowsUpdate"
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
        $cred = Get-Credential
        Add-Computer -DomainName $domain -Credential $cred -Force
        Write-Log "`nPC aggiunto al dominio con successo. Riavvio tra 60 secondi."
        Write-Log "`nRICORDATI DI SPOSTARE IL PC NELL'UNITA' ORGANIZZATIVA CORRETTA"
        Start-Sleep -Seconds 60
        Restart-Computer -Force
    }
        Write-Log "`n*****************Script completato con successo.*****************"
        exit
}

# === Sezione 1: Scrittura delle informazioni di sistema ===

# Ottieni le informazioni richieste
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
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
<# VA TROVATA UNA SOLUZIONE PER NOTEPAD++
foreach ($appbyname in $appbynames) {
    Install-Or-Update-WinGetPackage -packageId $appbyname
    Write-Host "`n"
}
#>

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
    Write-Log "Errore durante la configurazione degli aggiornamenti facoltativi:. Codice errore: $LASTEXITCODE"
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
    Write-Output "✅ Impostazione completata con successo."
} else {
    Write-Output "❌ Errore durante la modifica del registro. Codice: $LASTEXITCODE"
    Write-Output "Dettagli errore: $regSet"
}
<#
Write-Log "`n=== Abilitazione aggiornamenti per altri prodotti Microsoft ==="
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v EnableMicrosoftUpdate /t REG_DWORD /d 1 /f
if ($LASTEXITCODE -eq 0) {
    Write-Log "Impostazione completata: aggiornamenti per altri prodotti Microsoft abilitati."
} else {
    Write-Log "Errore durante l'abilitazione degli aggiornamenti per altri prodotti Microsoft: Codice errore: $LASTEXITCODE"
}
Write-Log "Aggiornamenti altri prodotti microsoft  $LASTEXITCODE"
Write-Host "`n"
#>

$preferencesPath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"

# Controlla se il file esiste
if (Test-Path $preferencesPath) {
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

    Write-Output "✅ Motore di ricerca di Edge modificato con successo in Google."
} else {
    Write-Output "❌ Errore: il file delle preferenze di Edge non esiste."
}


<#
Write-Log "`n=== Modifica del motore di ricerca di Edge ==="
Try {
    $edgeKey = "HKCU:\Software\Microsoft\Edge\SearchEngines"
    If (-not (Test-Path $edgeKey)) {
        New-Item -Path $edgeKey -Force
    }
    Set-ItemProperty -Path $edgeKey -Name "DefaultSearchProviderSearchURL" -Value "https://www.google.com/search?q={searchTerms}"
    Set-ItemProperty -Path $edgeKey -Name "DefaultSearchProviderName" -Value "Google"
    Write-Log "Motore di ricerca di Edge modificato con successo in Google."
    Write-Host "`n"
} Catch {
    Write-Log "Errore durante la modifica del motore di ricerca in Edge: $_"
    Write-Host "`n"
}
#>

# === Sezione 7: Modifica impostazione Visualizza estensioni file ===
# Percorso del Registro di Sistema
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$regName = "HideFileExt"

# Abilita la visualizzazione delle estensioni
Set-ItemProperty -Path $regPath -Name $regName -Value 0
Write-Log "Le estensioni dei file ora sono visibili."

# Per rendere effettiva la modifica, riavviare Explorer
Stop-Process -Name explorer -Force
Start-Process explorer


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
    Write-Log "Errore durante la configurazione delle impostazioni di risparmio energetico: $_"
    Write-Host "`n"
}

# === Sezione 9: Avvio manuale di Windows Update ===

# Cerca gli aggiornamenti disponibili
Write-Log "Ricerca degli aggiornamenti disponibili..."
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
    $cred = Get-Credential
    Add-Computer -DomainName $domain -Credential $cred -Force
    Write-Log "`nPC aggiunto al dominio con successo. Il sistema si riavviera' tra 1 minuto..."
    Start-Sleep -Seconds 60
    Restart-Computer -Force
}

# Controlla se e' necessario un riavvio per eseguire gli aggiornamenti di Windows Update
if (Get-WURebootStatus) {
    Write-Log "Riavvio richiesto. Il sistema si riavviera' tra 1 minuto..."
    Start-Sleep -Seconds 60
    Restart-Computer -Force
} else {
    Write-Log "Riavvio non necessario."
    Write-Host "`n"
}

# === Chiusura dello Script ===
Write-Log "`n*****************Script completato con successo.*****************"