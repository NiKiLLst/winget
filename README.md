# winget

PER USARE LO SCRIPT:
modificare in alto i percorsi dove mettere i file di log
modificare eventuali programmi che non si vogliono mettendo un # a sinistra
modificare eventuali programmi che si vogliono togliendo il carattere #

TODO:
loggare installazione dei moduli
andare a prendere lo script in rete?
Modificare Notepad++ usando ID invece di nome?
Visualizza le estensioni dei file
Loggare gli aggiornamenti non riusciti
Verificare perche' non prendere le versioni dei file

V1.5
! Effettuata pulizia del codice e utilizzo Write-Log invece di Write-Output per function Crea-UtenteAdmin
- Rimosso file winget.ps1 in favore di wingetV4.ps1

V1.4
!Varie modifiche per try/catch errori regedit
+Aggiunta creazione utenti locali

V1.3
+ verificare a runtime path di JoinDomainState e se non c'e' crearlo
! Rivista versione logfile aggiungendo controlli alla creazione/scrittura del file e timestamp
! Vari fix al joining

V1.2
Fix per join al dominio

V1.1
SPAZIATURA
Controllare modulo Notepad++
Vuoi aggiungere al dominio?
Nome del pc

