@echo off
REM ============================================================
REM  Launcher per Matrix-YouTube-Downloader.ps1
REM  Versione: 1.0 (Matrix Edition)
REM ============================================================
title Matrix-YouTube-Downloader - Matrix Edition
setlocal
cd /d "%~dp0"

REM --- 1. Controllo PowerShell 7 ---
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  [ERRORE] PowerShell 7 non trovato!
    echo  Scaricalo da: https://aka.ms/powershell
    echo.
    pause
    exit /b 1
)
REM --- 2. Controllo FFmpeg ---
where ffmpeg.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if not exist "C:\ffmpeg\bin\ffmpeg.exe" (
        echo.
        echo  [ATTENZIONE] FFmpeg non trovato nel PATH ne' in C:\ffmpeg\bin\
        echo  Il tool potrebbe non funzionare.
        echo.
        echo  Installa con: winget install Gyan.FFmpeg
        echo  oppure scaricalo da: https://ffmpeg.org/download.html
        echo.
        pause
    )
)
REM --- 3. Avvio del tool ---
echo.
echo  ============================================================
echo   Matrix-YouTube-Downloader - MATRIX EDITION
echo  ============================================================
echo   Avvio in corso...
echo.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Matrix-YouTube-Downloader.ps1"

REM --- 4. Gestione eventuale errore ---
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  [ERRORE] Esecuzione terminata con codice %ERRORLEVEL%.
    pause
)
endlocal
