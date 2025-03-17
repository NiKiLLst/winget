set-executionpolicy remotesigned

# === Funzione di Log per scrivere su schermo e su file ===
function Write-Log {
    param (
        [string]$message
    )
    Write-Output $message
    $message | Out-File -FilePath $outputFile -Encoding UTF8 -Append
}

# === Sezione 0: Installazione Applicazioni ===

winget install --id=Mozilla.Firefox -e  --accept-source-agreements --accept-package-agreements 
winget install --id=Google.Chrome -e
#winget install --id=Adobe.Acrobat.Reader.64-bit -e 
winget install --id=7zip.7zip -e
winget install --id=Microsoft.Edge -e
winget install --id=VideoLAN.VLC -e
winget install --id=Notepad++.Notepad++ -e
winget install --id=Microsoft.Office -e
#winget install --id=Amazon.AWSCLI -e
winget install --id=PuTTY.PuTTY -e
winget install --id=Microsoft.PowerShell -e
winget install --id=Microsoft.WindowsTerminal -e
winget install --id=Postman.Postman  -e
winget install --id=Microsoft.VisualStudioCode  -e
winget install --id=FlipperDevicesInc.qFlipper  -e

#$Serial = Get-WmiObject -Class Win32_BIOS | Select-Object -Property SerialNumber | Format-List
#Add-Content -Path .\*.txt -Exclude help* -Value 'End of file'

# Ottieni la directory dello script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Definisci il percorso del file di output
$outputFile = Join-Path -Path $scriptDir -ChildPath "Seriali.txt"

# Ottieni le informazioni richieste
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$computerModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
$serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
$domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
$user = whoami

# Crea la stringa di output
$output = @"
Timestamp: $timestamp
Modello: $computerModel
Seriale: $serialNumber
Dominio: $domain
Utente: $user
"@

# Scrivi nel file (aggiungendo se esiste già)
$output | Out-File -FilePath $outputFile -Encoding UTF8 -Append

# Stampa conferma a schermo
Write-Output ""
Write-Output "Scritto Seriale, Modello, Nome Pc e utente nel file 'Seriali.txt'."
Write-Output ""

Read-Host -Prompt "Premi un tasto per terminare..."
# Ottieni la directory dello script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Definisci il percorso del file di output
$outputFile = Join-Path -Path $scriptDir -ChildPath "Seriali.txt"

# Ottieni le informazioni richieste
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$computerModel = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
$serialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
$domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
$user = whoami

# Scrivi informazioni di sistema nel file
Write-Log "`n=== Informazioni di Sistema ==="
Write-Log "Timestamp: $timestamp"
Write-Log "Modello: $computerModel"
Write-Log "Seriale: $serialNumber"
Write-Log "Dominio: $domain"
Write-Log "Utente: $user"
Write-Log "Informazioni di sistema scritte correttamente nel file."

# === Sezione 2: Abilitare "Ottieni gli ultimi aggiornamenti non appena sono disponibili" ===
Write-Log "`n=== Abilitazione aggiornamenti rapidi ==="
Try {
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsContinuousInnovationOptedIn /t REG_DWORD /d 1 /f
    Write-Log "Impostazione completata: aggiornamenti rapidi abilitati."
} Catch {
    Write-Log "Errore durante la modifica dell'impostazione degli aggiornamenti rapidi: $_"
}