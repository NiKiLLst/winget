@ECHO OFF
:: Mappa il percorso UNC a un'unità temporanea
pushd %~dp0

:: Salva il percorso attuale dopo il mapping
SET ThisScriptsDirectory=%CD%
SET PowerShellScriptPath=%ThisScriptsDirectory%\wingetV4.ps1

:: Esegui PowerShell con privilegi elevati
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& {Start-Process PowerShell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%PowerShellScriptPath%""' -Verb RunAs}"

:: Rilascia l'unità temporanea assegnata a UNC
popd