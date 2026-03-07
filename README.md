# Winget Automated Deployment Script - V6

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

**6. Rinomina PC all'avvio**
- Prompt iniziale per scegliere un nuovo nome PC prima di qualsiasi installazione
- Rinomina immediata con riavvio automatico
- Task pianificato per riprendere lo script dopo il riavvio

**7. Join Dominio Active Directory**
- Join dominio con credenziali admin real-time
- Rinomina PC opzionale prima del join
- Task pianificato per riprendere dopo il riavvio
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
2. **Rinomina PC iniziale**: Propone il nome attuale e chiede se rinominare (subito, prima delle installazioni)
3. **Nome PC per Join**: Al momento del join dominio, chiede nuovamente conferma/modifica del nome
4. **Dominio**: Permette di confermare o modificare il dominio di destinazione
5. **Join Dominio**: Chiede conferma e credenziali admin di dominio real-time

### Flusso di Esecuzione

```
┌─────────────────────────────────┐
│ Verifica Privilegi Admin        │ (avviso se non admin)
├─────────────────────────────────┤
│ Inizializzazione File/Funzioni  │ (log, stateFile, helper functions)
├─────────────────────────────────┤
│ Creazione Utenti Locali         │ (opzionale)
├─────────────────────────────────┤
│ *** RINOMINA PC INIZIALE ***    │ propone nome attuale, chiede nuovo nome
│                                 │ → se cambia: Rename + Task + Riavvio 1
├─────────────────────────────────┤
│ Installazione Moduli PowerShell │ (Microsoft.WinGet.Client, PSWindowsUpdate)
├─────────────────────────────────┤
│ Sezione 0: Resume da Savepoint  │ legge stateFile JSON:
│ ├─ RenameOnly completata        │ → rimuove task, prosegue normalmente
│ ├─ JoinDomain/Renamed           │ → chiede conferma, esegue join + Riavvio 2
│ └─ Progress (step intermedio)   │ → riprende dall'ultimo step completato
├─────────────────────────────────┤
│ Sez.1 Raccolta Info Sistema     │ savepoint: SysInfo
├─────────────────────────────────┤
│ Sez.2 Installazione Applicazioni│ savepoint: AppsInstalled
├─────────────────────────────────┤
│ Sez.3-8 Tweaks Windows/Registry │ savepoint: TweaksApplied
│  (Update settings, Edge, Ext,   │
│   Risparmio Energetico)         │
├─────────────────────────────────┤
│ Sez.9 Windows Update            │ savepoint: WindowsUpdate
├─────────────────────────────────┤
│ Sez.10 Join Dominio             │ chiede conferma nome + dominio + credenziali
│ ├─ Nome cambiato                │ → Rename + Task + Riavvio 2 (poi resume join)
│ └─ Nome ok                     │ → Add-Computer + Riavvio 3
├─────────────────────────────────┤
│ Pulizia (stateFile + Task)      │
└─────────────────────────────────┘
```

### Meccanismo Savepoint e Resume

A partire da V6 lo script salva lo stato di avanzamento in `C:\Temp\JoinDomainState.txt` come JSON. In caso di interruzione imprevista o riavvio, alla prossima esecuzione lo script legge il savepoint e riprende dall'ultimo step completato.

**Struttura savepoint:**
```json
{ "Action": "Progress", "Step": "AppsInstalled" }
```

**Valori `Action` possibili:**

| Action | Step | Significato |
|---|---|---|
| `Progress` | `SysInfo` / `AppsInstalled` / `TweaksApplied` / `WindowsUpdate` | Ripresa dall'ultimo step completato |
| `RenameOnly` | `Renamed` | Riavvio post-rinomina iniziale: riprende normalmente |
| `JoinDomain` | `Renamed` | Riavvio post-rinomina pre-join: riprende con il join |

**Task pianificato:** `WingetResumeTask` — registrato su SYSTEM prima di ogni riavvio; rimosso automaticamente alla ripresa.

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
5. **Riavvii**: I riavvii ora hanno un delay di 5 secondi (ridotto da 60s) con task pianificato per la ripresa automatica
6. **Savepoint**: Lo script riprende automaticamente dall'ultimo step completato; rimuovere manualmente `C:\Temp\JoinDomainState.txt` solo se si vuole ripartire da zero

### Storico Versioni

**V6** (Marzo 2026)
- Prompt iniziale per rinomina PC all'avvio dello script (prima delle installazioni)
- Sistema savepoint JSON per ripresa automatica dopo interruzioni impreviste
- Task pianificato (`WingetResumeTask`) su SYSTEM per rilancio automatico post-riavvio
- Sezione 0 riscritta: gestisce `RenameOnly`, `JoinDomain/Renamed`, `Progress` (step intermedi)
- Sezione 10 join dominio aggiornata: usa `Write-StateFile` e `Register-ResumeTask`
- Delay riavvio ridotto da 60s a 5s (task pianificato garantisce la ripresa)
- Funzioni helper: `Register-ResumeTask`, `Unregister-ResumeTask`, `Write-StateFile`, `Read-StateFile`, `Should-RunStep`

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

