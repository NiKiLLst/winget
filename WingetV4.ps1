# Percorso del file di log
$logpath = "D:\LogsWinget.txt"

# Lista delle applicazioni da installare/aggiornare
$apps = @(
    "Microsoft.Edge"
    "Microsoft.Office"
    "Adobe.Acrobat.Reader.64-bit"
    "7zip.7zip"
    "VideoLAN.VLC"
    # "Google.Chrome"
    #"Mozilla.Firefox"
    "Notepad++.Notepad++"
    "Amazon.AWSCLI"
    "PuTTY.PuTTY"
    "Postman.Postman"
    "Microsoft.PowerShell"
    "Microsoft.WindowsTerminal"
    "Microsoft.VisualStudioCode"
    "Git.Git"
    "FlipperDevicesInc.qFlipper"
)
 
#winget install --id=Mozilla.Firefox -e  --accept-source-agreements --accept-package-agreements 

# === Sezione X: Funzioni utilizzate nello script ===
# === X.1 - Funzione di Log per scrivere su schermo e su file ===
function Write-Log {
    param (
        [string]$message
    )
    Write-Output $message
	$message | Out-File -Append -FilePath $logPath -Encoding UTF8
}

# === X.2 - Funzione per controllare e installare un modulo se non presente ===
function Ensure-Module {
    param ([string]$moduleName)
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Log "Modulo $moduleName non installato. Installazione in corso..."
        Install-Module -Name $moduleName -Force -Confirm:$false
        Write-Host "`n"
    } else {
        Write-Log "Modulo $moduleName gia' installato."
        Write-Host "`n"
    }
    Import-Module $moduleName
}

# === X.3 - Funzione per installare o aggiornare applicativi con WinGet ===
function Install-Or-Update-WinGetPackage {
    param ([string]$packageId)

    Write-Log "Verifica dello stato del pacchetto: $packageId"

    # Controlla se l'applicazione e' già installata
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

Write-Log "*****************INZIO ESECUZIONE SCRIPT*****************"

# Installato modulo Powershell Winget per loggare andamento installazione e update
# Installato modulo PSWindowsUpdate per la gestione degli aggiornamenti di Windows
# Controllo e installazione dei moduli solo se necessario
Ensure-Module "Microsoft.WinGet.Client"
Ensure-Module "PSWindowsUpdate"

# === Sezione 0: Scrittura delle informazioni di sistema ===

# Ottieni le informazioni richieste
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$computerModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
$serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
$domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
$user = whoami

# Scrivi informazioni di sistema nel file
Write-Log "=== Informazioni di Sistema ==="
Write-Log "Timestamp: $timestamp"
Write-Log "Modello: $computerModel"
Write-Log "Seriale: $serialNumber"
Write-Log "Dominio: $domain"
Write-Log "Utente: $user"
Write-Log "Informazioni di sistema scritte correttamente nel file."
Write-Host "`n"

# === Sezione 1: Installazione Applicazioni ===

# Installazione o aggiornamento delle applicazioni necessarie
foreach ($app in $apps) {
    Install-Or-Update-WinGetPackage -packageId $app
}

# Attesa dell'utente prima di continuare
Write-Host "Premi un tasto per continuare..."
[System.Console]::ReadKey($true) | Out-Null
Write-Host "`n"

# === Sezione 2: Abilitare "Ottieni gli ultimi aggiornamenti non appena sono disponibili" ===

Write-Log "`n=== Abilitazione aggiornamenti rapidi ==="
Try {
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsContinuousInnovationOptedIn /t REG_DWORD /d 1 /f
    Write-Log "Impostazione completata: aggiornamenti rapidi abilitati."
    Write-Host "`n"
} Catch {
    Write-Log "Errore durante la modifica dell'impostazione degli aggiornamenti rapidi: $_"
    Write-Host "`n"
}

# === Sezione 3: Configurazione per installare automaticamente aggiornamenti facoltativi ===

Write-Log "`n=== Configurazione aggiornamenti facoltativi ==="
Try {
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v AllowOptionalContent /t REG_DWORD /d 1 /f
    Write-Log "Impostazione completata: aggiornamenti facoltativi saranno installati automaticamente."
    Write-Host "`n"
} Catch {
    Write-Log "Errore durante la configurazione degli aggiornamenti facoltativi: $_"
    Write-Host "`n"
}

# === Sezione 4: Abilitare "Ottieni aggiornamenti per altri prodotti Microsoft" ===

Write-Log "`n=== Abilitazione aggiornamenti per altri prodotti Microsoft ==="
Try {
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v EnableMicrosoftUpdate /t REG_DWORD /d 1 /f
    Write-Log "Impostazione completata: aggiornamenti per altri prodotti Microsoft abilitati."
    Write-Host "`n"
} Catch {
    Write-Log "Errore durante l'abilitazione degli aggiornamenti per altri prodotti Microsoft: $_"
    Write-Host "`n"
}

# === Sezione 5: Modifica del motore di ricerca predefinito di Edge in Google ===
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

# === Sezione 6: Impostazioni di risparmio energetico ===
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

# === Sezione 7: Avvio manuale di Windows Update ===
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
Write-Host "Premi un tasto per continuare..."
[System.Console]::ReadKey($true) | Out-Null
Write-Host "`n"

# === Chiusura dello Script ===
Write-Log "`n*****************Script completato con successo.*****************"

# Percorso del file di stato
$stateFile = "C:\Temp\JoinDomainState.txt"

# Controlla se lo script è stato eseguito prima del riavvio
if (Test-Path $stateFile) {
    # Legge il nome del PC dal file
    $newPCName = Get-Content $stateFile
    Remove-Item $stateFile -Force
    
    # Richiesta delle credenziali di dominio
    $domain = "tuodominio.local"  # Sostituisci con il tuo dominio
    $cred = Get-Credential -Message "Inserisci le credenziali di amministratore di dominio"

    # Esegui il join a dominio
    Add-Computer -DomainName $domain -Credential $cred -Restart

    exit
}

# Prompt per l'utente
$answer = Read-Host "Vuoi inserire il pc a dominio? (y/n)"

if ($answer -eq 'y') {
    # Richiedi il nuovo nome del PC
    $newPCName = Read-Host "Inserisci il nuovo nome del computer"

    # Salva il nome del PC nel file di stato
    $newPCName | Out-File -FilePath $stateFile -Force

    # Rinominare il computer
    Rename-Computer -NewName $newPCName -Force

    # Riavvio necessario
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