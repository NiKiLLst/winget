# === Funzione di Log per scrivere su schermo e su file ===
function Write-Log {
    param (
        [string]$message
    )
    Write-Output $message
    $message | Out-File -FilePath $outputFile -Encoding UTF8 -Append
}

# === Sezione 0: Installazione Applicazioni ===
<#
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
#>
$result = Install-WinGetPackage Google.Chrome | Select-Object -Property Name,Status,InstallerErrorCode | Out-String
Write-Log "Risultato di Install-WinGetPackag:`n$result"

# === Sezione 1: Scrittura delle informazioni di sistema ===

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
Write-Output ""

# === Sezione 2: Abilitare "Ottieni gli ultimi aggiornamenti non appena sono disponibili" ===

Write-Log "`n=== Abilitazione aggiornamenti rapidi ==="
Write-Output "`n=== Abilitazione aggiornamenti rapidi ==="
Try {
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsContinuousInnovationOptedIn /t REG_DWORD /d 1 /f
    Write-Log "Impostazione completata: aggiornamenti rapidi abilitati."
    Write-Output "Impostazione completata: aggiornamenti rapidi abilitati."
} Catch {
    Write-Log "Errore durante la modifica dell'impostazione degli aggiornamenti rapidi: $_"
    Write-Output "Errore durante la modifica dell'impostazione degli aggiornamenti rapidi: $_"
}
Write-Output ""

# === Sezione 3: Configurazione per installare automaticamente aggiornamenti facoltativi ===

Write-Log "`n=== Configurazione aggiornamenti facoltativi ==="
Try {
    reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v AllowOptionalContent /t REG_DWORD /d 1 /f
    Write-Log "Impostazione completata: aggiornamenti facoltativi saranno installati automaticamente."
    Write-Output "Impostazione completata: aggiornamenti facoltativi saranno installati automaticamente."
} Catch {
    Write-Log "Errore durante la configurazione degli aggiornamenti facoltativi: $_"
    Write-Output "Errore durante la configurazione degli aggiornamenti facoltativi: $_"
}
Write-Output ""

# === Sezione 4: Abilitare "Ottieni aggiornamenti per altri prodotti Microsoft" ===

Write-Log "`n=== Abilitazione aggiornamenti per altri prodotti Microsoft ==="
Write-Output "`n=== Abilitazione aggiornamenti per altri prodotti Microsoft ==="
Try {
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v EnableMicrosoftUpdate /t REG_DWORD /d 1 /f
    Write-Log "Impostazione completata: aggiornamenti per altri prodotti Microsoft abilitati."
    Write-Output "Impostazione completata: aggiornamenti per altri prodotti Microsoft abilitati."
} Catch {
    Write-Log "Errore durante l'abilitazione degli aggiornamenti per altri prodotti Microsoft: $_"
    Write-Output "Impostazione completata: aggiornamenti per altri prodotti Microsoft abilitati."
}
Write-Output ""

# === Sezione 5: Modifica del motore di ricerca predefinito di Edge in Google ===
Write-Log "`n=== Modifica del motore di ricerca di Edge ==="
Write-Output "`n=== Modifica del motore di ricerca di Edge ==="
Try {
    $edgeKey = "HKCU:\Software\Microsoft\Edge\SearchEngines"
    If (-not (Test-Path $edgeKey)) {
        New-Item -Path $edgeKey -Force
    }
    Set-ItemProperty -Path $edgeKey -Name "DefaultSearchProviderSearchURL" -Value "https://www.google.com/search?q={searchTerms}"
    Set-ItemProperty -Path $edgeKey -Name "DefaultSearchProviderName" -Value "Google"
    Write-Log "Motore di ricerca di Edge modificato con successo in Google."
    Write-Output "Motore di ricerca di Edge modificato con successo in Google."
} Catch {
    Write-Log "Errore durante la modifica del motore di ricerca in Edge: $_"
    Write-Output "Errore durante la modifica del motore di ricerca in Edge: $_"
}
Write-Output ""

# === Sezione 6: Impostazioni di risparmio energetico ===
Write-Log "`n=== Configurazione delle impostazioni di risparmio energetico ==="
Write-Output "`n=== Configurazione delle impostazioni di risparmio energetico ==="
Try {
    powercfg /change disk-timeout-ac 0
    powercfg /change disk-timeout-dc 0
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    Write-Log "Impostazioni di risparmio energetico configurate su 'Mai' con successo."
    Write-Output "Impostazioni di risparmio energetico configurate su 'Mai' con successo."
} Catch {
    Write-Log "Errore durante la configurazione delle impostazioni di risparmio energetico: $_"
    Write-Output "Errore durante la configurazione delle impostazioni di risparmio energetico: $_"
}
Write-Output ""

# === Sezione 7: Avvio manuale di Windows Update ===
Write-Log "`n=== Avvio di Windows Update ==="
Write-Output "`n=== Avvio di Windows Update ==="
Try {
    UsoClient StartScan
    Write-Log "Windows Update avviato con successo."
    Write-Output "Windows Update avviato con successo."
} Catch {
    Write-Log "Errore durante l'avvio di Windows Update: $_"
    Write-Output "Errore durante l'avvio di Windows Update: $_"
}

# === Chiusura dello Script ===
Write-Log "`nScript completato con successo."
Write-Output "`nScript completato con successo."