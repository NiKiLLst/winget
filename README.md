# Winget Automated Deployment Script - V5

## Descrizione

Script PowerShell automatizzato per il provisioning e la configurazione di workstation Windows. Ideale per IT sistemisti che devono configurare rapidamente nuovi PC aziendali con software standard, aggiornamenti e impostazioni di sicurezza.

### Funzionalità Principali

**1. Gestione Utenti Locali**
- Creazione di utenti amministratori locali interattivi
- Aggiunta automatica al gruppo Amministratori
- Controllo di esistenza utente prima della creazione

**2. Installazione Software**
- Installazione e aggiornamento automatico di applicazioni via WinGet
- Lista configurabile di software (Edge, Office, VS Code, Git, ecc.)
- Gestione fallback se modulo WinGet non disponibile

**3. Gestione Aggiornamenti Windows**
- Abilitazione aggiornamenti rapidi
- Aggiornamenti facoltativi automatici
- Aggiornamenti prodotti Microsoft aggiuntivi
- Verifica stato riavvio e riavvio automatico se necessario

**4. Configurazione Browser**
- Modifica motore di ricerca Edge da Bing a Google
- Gestione file preferenze Edge in JSON

**5. Configurazione Sistema**
- Visualizzazione estensioni file
- Disabilitazione risparmio energetico (disco e standby)
- Logging completo in `C:\Temp\LogsWinget.txt`

**6. Join Dominio Active Directory**
- Rinomine PC con verifica e riavvio
- Join dominio con credenziali admin
- Gestione stato tra riavvi
- Promemoria spostamento OU

## Guida per Sistemisti IT

### Prerequisiti

- **Windows 10/11** (Home, Pro, Enterprise)
- **PowerShell 5.0+** (incluso di default)
- **WinGet** (installato di default su Windows 11, disponibile da Microsoft Store su Windows 10)
- **Privilegi Amministrativi** (almeno per installazioni moduli e modifiche registro)

### Installazione

1. Clonare o scaricare lo script:
   ```powershell
   git clone https://github.com/NiKiLLst/winget.git
   cd script
   ```

2. Aprire PowerShell come Amministratore

3. Eseguire lo script:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
   .\Winget.ps1
   ```

### Configurazione

#### 1. Modifica Variabili Principali

Nel file `Winget.ps1`, sezione all'inizio:

```powershell
# Percorso del file di log (modificare se necessario)
$logpath = "C:\Temp\LogsWinget.txt"

# Dominio per join (modificare con il vostro dominio)
$domain = "tuodominio.local"
```

#### 2. Personalizza Lista Software

Modifica l'array `$apps` per includere solo il software necessario:

```powershell
$apps = @(
    "Microsoft.Edge",
    "Microsoft.Office",
    "7zip.7zip",
    "VideoLAN.VLC",
    "Google.Chrome",
    "Mozilla.Firefox",
    "PuTTY.PuTTY",
    "Microsoft.PowerShell",
    "Microsoft.WindowsTerminal",
    "Microsoft.VisualStudioCode",
    "Git.Git",
    "FlipperDevicesInc.qFlipper"
)
```

**Nota**: Commenta le app non desiderate con `#` davanti:
```powershell
#"Adobe.Acrobat.Reader.64-bit"
```

### Esecuzione Interattiva

Lo script guida l'utente attraverso le seguenti decisioni:

1. **Creazione Utente Locale**: Consente di creare uno o più utenti admin locali
2. **Nome PC**: Permette di confermare o modificare il nome del computer
3. **Dominio**: Permette di confermare o modificare il dominio di destinazione
4. **Join Dominio**: Chiede conferma e credenziali admin di dominio

### Flusso di Esecuzione

```
┌─────────────────────────────────┐
│ Verifica Privilegi Admin        │ (avviso se non admin)
├─────────────────────────────────┤
│ Creazione Utenti Locali         │ (opzionale)
├─────────────────────────────────┤
│ Installazione Moduli PowerShell  │ (Microsoft.WinGet.Client, PSWindowsUpdate)
├─────────────────────────────────┤
│ Controllo Join Dominio Precedente│ (se in ripresa dopo riavvio)
├─────────────────────────────────┤
│ Raccolta Info Sistema           │ (modello, seriale, dominio, utente)
├─────────────────────────────────┤
│ Installazione Applicazioni      │ (via WinGet)
├─────────────────────────────────┤
│ Configurazione Windows Update   │ (aggiornamenti rapidi e facoltativi)
├─────────────────────────────────┤
│ Configurazione Edge             │ (motore ricerca Google)
├─────────────────────────────────┤
│ Visualizzazione Estensioni File │
├─────────────────────────────────┤
│ Disabilitazione Risparmio Energy│
├─────────────────────────────────┤
│ Ricerca e Installazione Updates │
├─────────────────────────────────┤
│ Rinomine PC (se necessario)     │ + Riavvio 1
├─────────────────────────────────┤
│ Join Dominio (se necessario)    │ + Riavvio 2
├─────────────────────────────────┤
│ Verifica Riavvio Updates        │ + Riavvio 3 (se necessario)
└─────────────────────────────────┘
```

### Gestione Log

Tutte le operazioni vengono registrate in:
```
C:\Temp\LogsWinget.txt
```

Formato log:
```
2025-12-08 10:24:55 - [OK] WinGet disponibile: v1.9.25200
2025-12-08 10:25:03 - Modello: 20VD
2025-12-08 10:25:03 - [OK] Installazione completata con successo per Microsoft.Edge
```

### Gestione Errori e Troubleshooting

#### Errore: "Questo script dovrebbe essere eseguito con privilegi amministrativi"
**Soluzione**: Aprire PowerShell come Amministratore (Esegui come amministratore)

#### Errore: "WinGet non è installato o non è in PATH"
**Soluzione**: 
- Windows 11: Installare da Microsoft Store
- Windows 10: https://github.com/microsoft/winget-cli/releases

#### Errore: "Impossibile installare moduli in C:\Program Files\WindowsPowerShell\Modules"
**Soluzione**: Eseguire come Amministratore o installare con `-Scope CurrentUser`

#### Moduli Microsoft.WinGet.Client o PSWindowsUpdate non disponibili
**Informazione**: Lo script continua automaticamente con fallback a CLI winget. Funzionalità ridotta ma comunque operativa.

### Personalizzazione Avanzata

#### Modifica Motore Ricerca Edge

Modifica la sezione 6:
```powershell
$json.default_search_provider_data.template_url_data = @{
    url = "https://www.google.com/search?q={searchTerms}"  # Cambiar URL qui
}
$json.default_search_provider_data.short_name = "Google"  # Nome qui
```

#### Aggiunta Software Aggiuntivo

Aggiungi alla lista `$apps`:
```powershell
$apps = @(
    # ... software esistente ...
    "NuovoSoftware.ID"  # Nuovo software da installare
)
```

Trova ID software disponibili con:
```powershell
winget search "nome software"
```

#### Disabilitare Sezioni Specifiche

Commentare le sezioni nel codice principale:
```powershell
# Write-Log "Installazione aggiornamenti completata."  # Disabilita sezione aggiornamenti
```

### Best Practices

1. **Test su VM**: Testare sempre su macchina virtuale prima di usare in produzione
2. **Backup log**: Archiviare regolarmente i log in `C:\Temp\LogsWinget.txt`
3. **Documenta Personalizzazioni**: Registrare modifiche fatte per poter replicare
4. **Credenziali**: Non hardcodare credenziali nel file; usare Get-Credential
5. **Timeout**: Verificare timeout di 60 secondi prima di riavvii, possono essere modificati

### Storico Versioni

**V5** (Dicembre 2025)
- Aggiunto controllo privilegi admin con warning
- Migliorate gestione errori e fallback
- Aggiunto Try-Catch su tutte le operazioni critiche
- Migliorato logging con gestione file
- Rinominate funzioni con verbi PowerShell approvati
- Documentazione estesa

**V4**
- Creazione utenti amministratori locali
- Miglioramenti Try/Catch per regedit

**V3**
- Verifica runtime path JoinDomainState
- Logging migliorato

**V2**
- Fix per join dominio

**V1**
- Versione iniziale

### Supporto e Contributi

Se riscontri problemi:
1. Controlla il log in `C:\Temp\LogsWinget.txt`
2. Esegui PowerShell come Amministratore
3. Verifica i prerequisiti
4. Apri una issue su GitHub

### Licenza

Script sviluppato per uso interno aziendale.

