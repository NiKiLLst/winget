# Winget Automated Deployment Script - V6

## Scopo
Script PowerShell per provisioning workstation Windows in ambito aziendale: software standard, update, tweak di sistema, eventuale join dominio e report finale.

Target: colleghi sistemisti (anche junior) che devono eseguire onboarding PC in modo ripetibile e tracciato.

## Cosa fa
- Auto-elevazione amministrativa se lanciato senza privilegi.
- Controllo aggiornamento script da repository Git locale (con prompt per installare Git se manca).
- Gestione log configurabile con persistenza in `winget-config.json`.
- Raccolta input iniziale in un'unica fase (dominio, credenziali, nome PC, app da installare, join).
- Verifica delle credenziali di dominio prima di salvarle e verifica del nome PC inserito.
- Quando richiesto, join al dominio come primo passo; il provisioning successivo gira nel contesto dell'utente di dominio (autologon temporaneo).
- Installazione/upgrade app via WinGet con fallback per Firefox locale.
- Configurazioni OS e Windows Update.
- Savepoint JSON + task schedulato per riprendere automaticamente dopo i riavvii.
- Report finale (`Scheda_*.txt`) e messaggio di completamento.

## Prerequisiti
- Windows 10/11.
- PowerShell 5.1+.
- Esecuzione come amministratore (lo script si rilancia in autonomia).
- WinGet disponibile in PATH.
- Accesso rete se vuoi auto-update da GitHub e installazione pacchetti/moduli.

## Avvio rapido
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\Winget.ps1
```

## Flusso operativo reale
1. Verifica privilegi admin.
2. Prompt opzionale installazione `Git.Git` se `git` non e' presente.
3. Check aggiornamento script da repo Git locale (`fetch/pull`).
4. Lettura/normalizzazione percorso log.
5. Inizializzazione file runtime (`logs\...`).
6. Verifica WinGet.
7. Fase domande iniziale.
8. Esecuzione step tecnici con savepoint.
9. Eventuali riavvii e resume automatico.
10. Report finale e cleanup stato/task.

## Domande iniziali (una sola fase)
In assenza di resume, lo script chiede, in quest'ordine:
- Creazione utente locale admin (opzionale).
- Join dominio (`y/n`).
- Dominio target (se join attivo) con conferma esplicita.
- Credenziali dell'amministratore di dominio per il join (se join attivo): verificate
  subito sul dominio, in loop finche' valide.
- Credenziali dell'utente di dominio che usera' il PC (se join attivo): verificate sul
  dominio. Avviso: questo utente verra' aggiunto agli Amministratori locali del PC.
- Nuovo nome PC con conferma esplicita:
    - esempio: `Hai inserito 'MARIO' come nome PC, confermi? (Y/S o Invio)`
    - se il nome e' diverso da quello attuale viene verificata la disponibilita'
      (ricerca in Active Directory se si joina, altrimenti ping ICMP):
        - libero → `Non esiste attualmente un pc con questo nome`
        - occupato → `Esiste gia' un pc con questo nome. Vuoi cambiare il nome?`
- Selezione app una per una:
    - `Invio`, `S`, `Y` = includi
    - `N` = escludi

Le credenziali (join attivo) vengono salvate in XML locale (cifrato DPAPI) per il resume.

## Savepoint e resume
File runtime usati:
- `logs\JoinDomainState.txt`
- `logs\ExecutionPlan.json`
- `logs\DomainJoinCredential.xml` (credenziali admin di join)
- `logs\DomainUserCredential.xml` (credenziali utente di dominio finale)

Action principali nel savepoint:
- `RenameOnly`
- `JoinDomain` (sotto-stato `Step`: `Renamed` = pronto al join, `Joined` = join fatto,
  manca la configurazione post-join)
- `Progress`
- `ShowSummary`

Fase di join (quando richiesto): rinomina PC → join al dominio → aggiunta dell'utente di
dominio agli Amministratori locali + autologon temporaneo → riavvio → provisioning
(app/tweak/Windows Update) nel contesto dell'utente di dominio. Se il join si interrompe
dopo un riavvio, al rilancio lo script riparte dallo step indicato dal savepoint.

Task schedulato usato per resume:
- `WingetResumeTask`

## Log e report
- Log operativo: percorso scelto a runtime (default `logs\LogsWinget.txt`).
- Config log persistente: `winget-config.json` (`LogPath`).
- Report finale: `Scheda_<COMPUTERNAME>_<yyyy-MM-dd>.txt` nella stessa cartella del log.

## Software gestito
Lista base nello script (`$availableApps`):
- `Microsoft.Edge`
- `Microsoft.Office`
- `7zip.7zip`
- `VideoLAN.VLC`
- `Google.Chrome`
- `Mozilla.Firefox` (fallback `Mozilla.Firefox.it`)
- `PuTTY.PuTTY`
- `Microsoft.PowerShell`
- `Microsoft.WindowsTerminal`
- `Microsoft.VisualStudioCode`
- `Git.Git`
- `FlipperDevicesInc.qFlipper`

Comandi WinGet usati:
- `winget list -e --id <ID> --source winget`
- `winget upgrade -e --id <ID> --source winget`
- `winget install -e --id <ID> --source winget`

## Configurazioni applicate
- Windows Update:
    - aggiornamenti rapidi
    - contenuti facoltativi
    - Microsoft Update (COM/registro)
    - notifica riavvio
- Edge: motore ricerca default su Google (se file Preferences disponibile).
- Explorer: estensioni file visibili.
- Power settings: timeout su `Mai`.
- Windows Terminal: profilo default PowerShell 7 (se `settings.json` disponibile).

## Troubleshooting rapido
- Errore WinGet non disponibile:
    - installare/aggiornare App Installer.
- Moduli non installabili:
    - verificare connettivita, TLS/proxy, policy PSGallery.
- Resume anomalo:
    - controllare `logs\JoinDomainState.txt`.
- Auto-update script non eseguito:
    - verificare `git` disponibile e repository inizializzato (`.git`).

## Note operative per il team
- Non committare file runtime/log (`logs/` e savepoint sono ignorati).
- Prima di roll-out su produzione, test completo in VM.
- Se personalizzi app/dominio, aggiorna questo README insieme al codice.
- Join al dominio: per il provisioning post-join lo script imposta un autologon
  temporaneo dell'utente di dominio (password in chiaro nel registro `Winlogon`).
  Viene rimosso automaticamente al termine; in caso di interruzione anomala verificare
  che `AutoAdminLogon`/`DefaultPassword` siano stati ripuliti.

## Supporto
In caso di problemi condividere:
1. log completo (`LogsWinget.txt`)
2. report finale (`Scheda_*.txt`)
3. output errore PowerShell

Repository: `https://github.com/NiKiLLst/winget`

