@echo off
rem ============================================================================
rem  TidyWin - Storage Cleanup                                           v1.0.1
rem  Part of TidyWin: tools for cleaning and optimizing Windows.
rem ----------------------------------------------------------------------------
rem  PURPOSE
rem    Free up disk space by removing temporary files, caches and leftovers.
rem
rem  REQUIREMENTS
rem    Windows 10 or Windows 11, and administrator rights (requested for you).
rem    No internet connection is used. Nothing is downloaded or uploaded.
rem
rem  USAGE
rem    Double-click                          interactive menu
rem    TidyWin-StorageCleanup.bat /standard  Standard Clean, no questions asked
rem    TidyWin-StorageCleanup.bat /deep      Deep Clean, no questions asked
rem    TidyWin-StorageCleanup.bat /help      show help
rem
rem  EXIT CODES
rem    0  finished
rem    1  unsupported Windows version, or administrator rights not granted
rem    2  cancelled by the user
rem    3  script was started from a temporary folder (for example inside a ZIP)
rem
rem  STANDARD CLEAN removes
rem    - User temp folder, Windows temp folder, INetCache, app TempState folders
rem    - Recycle Bin (all drives)
rem    - Shader caches: DirectX, NVIDIA, AMD, Intel
rem    - Browser caches only: Edge, Chrome, Brave, Firefox
rem    - Windows Update download cache and Delivery Optimization cache
rem    - Windows Error Reporting files, crash dumps, minidumps, MEMORY.DMP
rem    - Windows Disk Cleanup items: thumbnails, setup and upgrade logs, etc.
rem    - Windows component store cleanup with DISM (never uses ResetBase)
rem
rem  DEEP CLEAN removes everything above, plus
rem    - All System Restore points and Shadow Copies on the system drive
rem    - The previous Windows installation folder (Windows.old)
rem
rem  NEVER TOUCHED
rem    - Documents, Desktop, Downloads, Pictures, Videos, Music, OneDrive
rem    - Installed programs, user settings, passwords, cookies, history
rem    - Prefetch, WinSxS (only DISM may shrink it), Windows Installer folder,
rem      the hibernation file and the page file
rem
rem  SAFETY DESIGN
rem    - Only empties folders that are listed in this file. The folders stay.
rem    - Refuses to empty drive roots, user profile folders or odd TEMP paths.
rem    - Never follows junctions or symbolic links.
rem    - Uses the real Windows tools only (clean PATH, runs from System32).
rem    - Writes a log to ProgramData\TidyWin\Logs
rem ============================================================================

setlocal EnableExtensions DisableDelayedExpansion

set "SELF=%~f0"
set "SELF_DIR=%~dp0"
set "TW_VERSION=1.0.1"
set "TW_EXIT=0"
set "MODE="
set "UNATTENDED=0"
set "IS_ELEVATED=0"
set "STEP_NO=0"
set "STEP_TOTAL=9"
set "SKIP_COUNT=0"
set "LOG_FILE=nul"
set "HAVE_PS=0"
set "COLOR_FALLBACK=0"
set "SAGE=4747"

rem Binary-planting protection: only ever run the real Windows tools.
set "SYS32=%SystemRoot%\System32"
if defined PROCESSOR_ARCHITEW6432 set "SYS32=%SystemRoot%\Sysnative"
set "PATH=%SYS32%;%SystemRoot%;%SYS32%\Wbem;%SYS32%\WindowsPowerShell\v1.0\"
cd /d "%SYS32%" 2>nul

:ParseArgs
if "%~1"=="" goto :ArgsDone
if /i "%~1"=="/standard" set "MODE=STANDARD"
if /i "%~1"=="/deep" set "MODE=DEEP"
if /i "%~1"=="/elevated" set "IS_ELEVATED=1"
if /i "%~1"=="/?" goto :Help
if /i "%~1"=="/help" goto :Help
if /i "%~1"=="-h" goto :Help
shift
goto :ParseArgs

:ArgsDone
if defined MODE set "UNATTENDED=1"

call :DetectWindows
if %WIN_BUILD% LSS 10240 goto :UnsupportedOS

title TidyWin - Storage Cleanup
call :InitColors
cls
call :Banner

call :CheckScriptLocation
if "%LOC_BAD%"=="1" goto :BadLocation

fltmc >nul 2>&1
if errorlevel 1 goto :NeedAdmin

call :Prepare
call :ShowSystemInfo
if defined MODE goto :ModeReady

:Menu
echo(
echo(%C_WHITE%   Choose a cleanup mode%C_RESET%
echo(
echo(%C_BLUE%   [1]%C_RESET%  %C_WHITE%STANDARD CLEAN%C_RESET%  %C_GREEN%recommended%C_RESET%
echo(%C_DIM%        Temp files, caches, shader caches, browser caches, error reports,%C_RESET%
echo(%C_DIM%        Recycle Bin - emptied for good - update leftovers and old components.%C_RESET%
echo(%C_DIM%        Keeps your restore points and your previous Windows version.%C_RESET%
echo(
echo(%C_BLUE%   [2]%C_RESET%  %C_WHITE%DEEP CLEAN%C_RESET%  %C_YELLOW%maximum space - cannot be undone%C_RESET%
echo(%C_DIM%        Everything in Standard, plus:%C_RESET%
echo(%C_YELLOW%        - all System Restore points and Shadow Copies%C_RESET%
echo(%C_YELLOW%        - the old Windows installation folder, Windows.old%C_RESET%
echo(
echo(%C_BLUE%   [3]%C_RESET%  %C_WHITE%Exit without changing anything%C_RESET%
echo(
echo(%C_DIM%   Never touched: Documents, Desktop, Downloads, Pictures, Videos, Music,%C_RESET%
echo(%C_DIM%   installed apps, settings, saved passwords, cookies and browser history.%C_RESET%
echo(%C_DIM%   Tip: close your browsers and games first for the most complete clean.%C_RESET%
echo(
<nul set /p "=%C_BLUE%   Select an option [1-3]: %C_RESET%"
choice /c 123 /n >nul
set "PICK=%errorlevel%"
echo(
if "%PICK%"=="3" goto :UserExit
if "%PICK%"=="2" goto :ConfirmDeep
set "MODE=STANDARD"
goto :ModeReady

:ConfirmDeep
echo(%C_YELLOW%   DEEP CLEAN cannot be undone.%C_RESET%
echo(%C_WHITE%   It permanently deletes:%C_RESET%
echo(%C_WHITE%     - every System Restore point and Shadow Copy on %SystemDrive%%C_RESET%
echo(%C_WHITE%     - the previous Windows installation, if one exists%C_RESET%
echo(%C_DIM%   Your own files are not affected. Windows creates new restore points later.%C_RESET%
echo(
<nul set /p "=%C_YELLOW%   Continue with Deep Clean? [Y/N]: %C_RESET%"
choice /c YN /n >nul
set "PICK=%errorlevel%"
echo(
if "%PICK%"=="2" goto :Menu
set "MODE=DEEP"

:ModeReady
if "%UNATTENDED%"=="1" echo(%C_DIM%   Mode %MODE% was chosen on the command line - starting without questions.%C_RESET%
call :RunCleanup
call :Summary
goto :Finish

rem ----------------------------------------------------------------------------
rem  Exits of the main flow
rem ----------------------------------------------------------------------------

:UserExit
echo(%C_DIM%   Nothing was changed. Goodbye!%C_RESET%
set "TW_EXIT=2"
goto :Finish

:NeedAdmin
if "%IS_ELEVATED%"=="1" goto :AdminFailed
echo(
echo(%C_WHITE%   Administrator permission is needed to clean system files.%C_RESET%
echo(%C_DIM%   A Windows prompt will appear - please choose Yes.%C_RESET%
set "TW_SELF=%SELF%"
set "TW_ARGS=/elevated %*"
powershell -NoProfile -Command "try { Start-Process -FilePath $env:TW_SELF -ArgumentList $env:TW_ARGS -Verb RunAs -ErrorAction Stop } catch { exit 1 }" >nul 2>&1
if errorlevel 1 goto :AdminFailed
exit /b 0

:AdminFailed
echo(
echo(%C_RED%   Administrator rights were not granted.%C_RESET%
echo(%C_WHITE%   Right-click the file, choose Run as administrator, and try again.%C_RESET%
set "TW_EXIT=1"
goto :Finish

:BadLocation
echo(
echo(%C_YELLOW%   Please extract TidyWin first.%C_RESET%
echo(%C_WHITE%   This file is running from a temporary folder - usually straight out of a ZIP.%C_RESET%
echo(%C_WHITE%   Right-click the ZIP, choose Extract All, and run the script from the new folder.%C_RESET%
set "TW_EXIT=3"
goto :Finish

:UnsupportedOS
echo(
echo(  TidyWin needs Windows 10 or Windows 11.
echo(  This computer reports Windows build %WIN_BUILD%.
set "TW_EXIT=1"
goto :Finish

:Help
echo(
echo(  TidyWin - Storage Cleanup  v%TW_VERSION%
echo(
echo(  Usage:  TidyWin-StorageCleanup.bat [option]
echo(
echo(    /standard   Standard Clean without questions - safe for everyday use
echo(    /deep       Deep Clean without questions - also removes all restore
echo(                points and the previous Windows installation
echo(    /help       Show this help
echo(
echo(  Without an option an interactive menu is shown.
echo(  Administrator rights are requested automatically.
echo(
exit /b 0

:Finish
if defined C_RESET <nul set /p "=%C_RESET%"
if "%COLOR_FALLBACK%"=="1" color
set "DO_PAUSE=0"
if "%UNATTENDED%"=="0" set "DO_PAUSE=1"
if "%IS_ELEVATED%"=="1" set "DO_PAUSE=1"
if "%DO_PAUSE%"=="1" (
    echo(
    <nul set /p "=   Press any key to close this window..."
    pause >nul
    echo(
)
exit /b %TW_EXIT%

rem ============================================================================
rem  SUBROUTINES - everything below is only reached through CALL or GOTO
rem ============================================================================

:DetectWindows
set "WIN_BUILD=0"
set "WIN_DISPLAY="
for /f "tokens=3" %%B in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| find "CurrentBuildNumber"') do set "WIN_BUILD=%%B"
for /f "tokens=3" %%V in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2^>nul ^| find "DisplayVersion"') do set "WIN_DISPLAY=%%V"
set "WIN_NAME=Windows 10"
if %WIN_BUILD% GEQ 22000 set "WIN_NAME=Windows 11"
exit /b 0

:InitColors
set "ESC="
set "C_RESET="
set "C_DIM="
set "C_WHITE="
set "C_BLUE="
set "C_GREEN="
set "C_YELLOW="
set "C_RED="
set "BN1="
set "BN2="
set "BN3="
set "BN4="
set "BN5="
set "BN6="
set "BN7="
rem ANSI colors need the Windows 10 1903 console or newer.
if %WIN_BUILD% LSS 18362 goto :InitColorsFallback
for /f %%A in ('echo prompt $E^| cmd') do set "ESC=%%A"
if not defined ESC goto :InitColorsFallback
if not "%ESC:~1%"=="" goto :InitColorsFallback
set "C_RESET=%ESC%[0m"
set "C_DIM=%ESC%[90m"
set "C_WHITE=%ESC%[97m"
set "C_BLUE=%ESC%[38;5;39m"
set "C_GREEN=%ESC%[92m"
set "C_YELLOW=%ESC%[93m"
set "C_RED=%ESC%[91m"
set "BN1=%ESC%[38;5;27m"
set "BN2=%ESC%[38;5;27m"
set "BN3=%ESC%[38;5;33m"
set "BN4=%ESC%[38;5;33m"
set "BN5=%ESC%[38;5;39m"
set "BN6=%ESC%[38;5;39m"
set "BN7=%ESC%[38;5;45m"
exit /b 0
:InitColorsFallback
set "ESC="
set "COLOR_FALLBACK=1"
color 09
exit /b 0

:Banner
echo(
echo(%BN1%  ########  ####  ########   ##    ##     ##      ##  ####  ##    ##%C_RESET%
echo(%BN2%     ##      ##   ##     ##   ##  ##      ##  ##  ##   ##   ###   ##%C_RESET%
echo(%BN3%     ##      ##   ##     ##    ####       ##  ##  ##   ##   ####  ##%C_RESET%
echo(%BN4%     ##      ##   ##     ##     ##        ##  ##  ##   ##   ## ## ##%C_RESET%
echo(%BN5%     ##      ##   ##     ##     ##        ##  ##  ##   ##   ##  ####%C_RESET%
echo(%BN6%     ##      ##   ##     ##     ##        ##  ##  ##   ##   ##   ###%C_RESET%
echo(%BN7%     ##     ####  ########      ##         ###  ###   ####  ##    ##%C_RESET%
echo(
echo(%C_BLUE%  ------------------------------------------------------------------%C_RESET%
echo(%C_WHITE%   Windows Cleaner and Optimizer%C_RESET%             %C_BLUE%Storage Cleanup  v%TW_VERSION%%C_RESET%
echo(%C_DIM%   Free up disk space safely. Fully offline - nothing leaves your PC.%C_RESET%
echo(%C_BLUE%  ------------------------------------------------------------------%C_RESET%
exit /b 0

:CheckScriptLocation
rem Running straight from a ZIP means running from a temp folder, which this
rem script is about to empty. Detect it and ask the user to extract first.
setlocal EnableDelayedExpansion
set "LOC_FLAG=0"
for %%P in ("%TEMP%" "%LOCALAPPDATA%\Temp" "%SystemRoot%\Temp") do (
    if not "%%~P"=="" (
        set "LOC_CHK=!SELF_DIR:%%~P\=!"
        if /i not "!LOC_CHK!"=="!SELF_DIR!" set "LOC_FLAG=1"
    )
)
endlocal & set "LOC_BAD=%LOC_FLAG%"
exit /b 0

:Prepare
set "LOG_DIR=%ProgramData%\TidyWin\Logs"
if not exist "%LOG_DIR%\" md "%LOG_DIR%" >nul 2>&1
call :Snapshot
set "T_START=%SNAP_EPOCH%"
set "FREE_BEFORE=%SNAP_FREE%"
set "TOTAL_SPACE=%SNAP_TOTAL%"
if not "%SNAP_EPOCH%"=="0" set "HAVE_PS=1"
if exist "%LOG_DIR%\" set "LOG_FILE=%LOG_DIR%\StorageCleanup_%SNAP_STAMP%.log"
call :Log "TidyWin Storage Cleanup v%TW_VERSION% started"
call :Log "Windows build %WIN_BUILD% - elevated=%IS_ELEVATED% unattended=%UNATTENDED%"
call :Log "Free space at launch: %FREE_BEFORE% bytes"
exit /b 0

:Snapshot
rem Sets SNAP_STAMP, SNAP_EPOCH (unix seconds), SNAP_FREE and SNAP_TOTAL (bytes).
set "SNAP_STAMP=run%RANDOM%"
set "SNAP_EPOCH=0"
set "SNAP_FREE=0"
set "SNAP_TOTAL=0"
for /f "usebackq tokens=1-4" %%A in (`powershell -NoProfile -Command "$d=New-Object -TypeName System.IO.DriveInfo -ArgumentList $env:SystemDrive; '{0} {1} {2} {3}' -f (Get-Date).ToString('yyyyMMdd_HHmmss',[cultureinfo]::InvariantCulture),[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(),$d.AvailableFreeSpace,$d.TotalSize" 2^>nul`) do (
    set "SNAP_STAMP=%%A"
    set "SNAP_EPOCH=%%B"
    set "SNAP_FREE=%%C"
    set "SNAP_TOTAL=%%D"
)
exit /b 0

:FmtBytes
rem usage: call :FmtBytes "number or simple expression" ResultVariable
set "%~2=n/a"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$b=[double](%~1); if($b -lt 0){$b=0}; $c=[cultureinfo]::InvariantCulture; if($b -ge 1GB){[string]::Format($c,'{0:N2} GB',$b/1GB)}elseif($b -ge 1MB){[string]::Format($c,'{0:N1} MB',$b/1MB)}else{[string]::Format($c,'{0:N0} KB',$b/1KB)}" 2^>nul`) do set "%~2=%%A"
exit /b 0

:ElapsedText
set /a "EL_SEC=T_END-T_START"
if %EL_SEC% LSS 0 set "EL_SEC=0"
set /a "EL_M=EL_SEC/60"
set /a "EL_S=EL_SEC%%60"
if %EL_M% LSS 10 set "EL_M=0%EL_M%"
if %EL_S% LSS 10 set "EL_S=0%EL_S%"
set "TIME_TXT=%EL_M%:%EL_S%"
exit /b 0

:FreeMB
rem Sets FREE_MB to the free space of the system drive in whole megabytes.
set "FREE_MB=0"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "[int64][math]::Floor((New-Object -TypeName System.IO.DriveInfo -ArgumentList $env:SystemDrive).AvailableFreeSpace/1MB)" 2^>nul`) do set "FREE_MB=%%A"
exit /b 0

:MeasureStep
rem Approximate space gained since the previous step. Background activity on the
rem PC can add noise, so it is shown as "about" and only when it is positive.
set "STEP_GAIN_TXT="
set "STEP_GAIN_LOG="
if not "%HAVE_PS%"=="1" exit /b 0
call :FreeMB
if "%FREE_MB%"=="0" exit /b 0
if "%LAST_FREE_MB%"=="0" set "LAST_FREE_MB=%FREE_MB%"
set /a "STEP_GAIN=FREE_MB-LAST_FREE_MB"
set "LAST_FREE_MB=%FREE_MB%"
if %STEP_GAIN% LSS 1 exit /b 0
set "STEP_GAIN_TXT=  %C_DIM%freed about %STEP_GAIN% MB%C_RESET%"
set "STEP_GAIN_LOG= - freed about %STEP_GAIN% MB"
exit /b 0

:ShowSystemInfo
set "FREE_TXT=n/a"
set "TOTAL_TXT=n/a"
if "%HAVE_PS%"=="1" call :FmtBytes "%FREE_BEFORE%" FREE_TXT
if "%HAVE_PS%"=="1" call :FmtBytes "%TOTAL_SPACE%" TOTAL_TXT
echo(
echo(%C_BLUE%   System   %C_RESET%%C_WHITE%%WIN_NAME% %WIN_DISPLAY% - build %WIN_BUILD%%C_RESET%
echo(%C_BLUE%   Drive    %C_RESET%%C_WHITE%%SystemDrive% - %FREE_TXT% free of %TOTAL_TXT%%C_RESET%
echo(%C_BLUE%   Log      %C_RESET%%C_DIM%%LOG_FILE%%C_RESET%
exit /b 0

:Log
rem usage: call :Log "plain text without special characters"
>>"%LOG_FILE%" echo(%time:~0,8%  %~1
exit /b 0

:RunCleanup
if /i "%MODE%"=="DEEP" (set "STEP_TOTAL=10") else (set "STEP_TOTAL=9")
call :Log "Mode: %MODE%"
call :Snapshot
if not "%SNAP_EPOCH%"=="0" set "T_START=%SNAP_EPOCH%"
if not "%SNAP_EPOCH%"=="0" set "FREE_BEFORE=%SNAP_FREE%"
call :Log "Free space when cleaning started: %FREE_BEFORE% bytes"
set "LAST_FREE_MB=0"
if "%HAVE_PS%"=="1" call :FreeMB
set "LAST_FREE_MB=%FREE_MB%"
echo(
echo(%C_BLUE%   Starting %MODE% clean. This usually takes a few minutes - please keep this window open.%C_RESET%
echo(
call :Step_UserTemp
call :Step_WindowsTemp
call :Step_RecycleBin
call :Step_ShaderCaches
call :Step_BrowserCaches
call :Step_WindowsUpdate
call :Step_ErrorReports
if /i "%MODE%"=="DEEP" call :Step_RestorePoints
call :Step_DiskCleanup
call :Step_Dism
exit /b 0

:Summary
call :Snapshot
set "FREE_AFTER=%SNAP_FREE%"
set "T_END=%SNAP_EPOCH%"
set "FREED_TXT=n/a"
set "NOW_TXT=n/a"
set "TIME_TXT=n/a"
if "%HAVE_PS%"=="1" call :FmtBytes "%FREE_AFTER%-%FREE_BEFORE%" FREED_TXT
if "%HAVE_PS%"=="1" call :FmtBytes "%FREE_AFTER%" NOW_TXT
if "%HAVE_PS%"=="1" call :ElapsedText
call :Log "Free space after: %FREE_AFTER% bytes"
call :Log "Space freed: %FREED_TXT% - time taken: %TIME_TXT%"
echo(
echo(%C_BLUE%  ------------------------------------------------------------------%C_RESET%
echo(%C_GREEN%   CLEANUP COMPLETE%C_RESET%
echo(%C_BLUE%  ------------------------------------------------------------------%C_RESET%
echo(
echo(%C_BLUE%   Space freed      %C_RESET%%C_WHITE%%FREED_TXT%%C_RESET%
echo(%C_BLUE%   Free space now   %C_RESET%%C_WHITE%%NOW_TXT% of %TOTAL_TXT% on %SystemDrive%%C_RESET%
echo(%C_BLUE%   Time taken       %C_RESET%%C_WHITE%%TIME_TXT%%C_RESET%
echo(%C_BLUE%   Log file         %C_RESET%%C_DIM%%LOG_FILE%%C_RESET%
if not "%SKIP_COUNT%"=="0" echo(%C_YELLOW%   Steps skipped    %SKIP_COUNT% - see the messages above%C_RESET%
echo(
echo(%C_DIM%   Files that Windows is using right now cannot be deleted.%C_RESET%
echo(%C_DIM%   Restart your PC and run TidyWin again for an even deeper clean.%C_RESET%
exit /b 0

rem ----------------------------------------------------------------------------
rem  Progress output
rem ----------------------------------------------------------------------------

:StepStart
rem usage: call :StepStart "Label" [long]
set /a STEP_NO+=1
set "STEP_STATUS=OK"
set "STEP_NOTE="
set "STEP_LONG=0"
if /i "%~2"=="long" set "STEP_LONG=1"
set "STEP_TAG=[%STEP_NO%/%STEP_TOTAL%]        "
set "STEP_TAG=%STEP_TAG:~0,8%"
set "STEP_LBL=%~1 ............................................................"
call set "STEP_LBL=%%STEP_LBL:~0,50%%"
if "%STEP_LONG%"=="1" echo(   %C_DIM%%STEP_TAG%%C_RESET%%C_WHITE%%~1%C_RESET%
if "%STEP_LONG%"=="0" <nul set /p "=   %C_DIM%%STEP_TAG%%C_RESET%%C_WHITE%%STEP_LBL%%C_RESET% "
call :Log "STEP %STEP_NO%/%STEP_TOTAL% - %~1"
exit /b 0

:StepEnd
call :MeasureStep
if "%STEP_LONG%"=="1" <nul set /p "=           "
if /i "%STEP_STATUS%"=="SKIP" goto :StepEnd_Skip
echo(%C_GREEN%OK%C_RESET%%STEP_GAIN_TXT%
call :Log "  result: OK%STEP_GAIN_LOG%"
exit /b 0
:StepEnd_Skip
set /a SKIP_COUNT+=1
echo(%C_YELLOW%SKIPPED%C_RESET%
if defined STEP_NOTE echo(           %C_DIM%%STEP_NOTE%%C_RESET%
call :Log "  result: SKIPPED - %STEP_NOTE%"
exit /b 0

rem ----------------------------------------------------------------------------
rem  Folder helpers
rem ----------------------------------------------------------------------------

:CleanDir
rem usage: call :CleanDir "C:\full\path"
rem Empties the folder but keeps the folder itself. Junctions are never followed.
set "CLEAN_TARGET=%~1"
if not defined CLEAN_TARGET exit /b 1
if not "%CLEAN_TARGET:~1,2%"==":\" exit /b 1
if "%CLEAN_TARGET:~3%"=="" exit /b 1
for %%X in ("%SystemDrive%" "%SystemRoot%" "%SYS32%" "%ProgramData%" "%ProgramFiles%" "%USERPROFILE%" "%USERPROFILE%\Desktop" "%USERPROFILE%\Documents" "%USERPROFILE%\Downloads" "%USERPROFILE%\Pictures" "%USERPROFILE%\Videos" "%USERPROFILE%\Music" "%PUBLIC%") do if /i "%CLEAN_TARGET%"=="%%~X" exit /b 1
if not exist "%CLEAN_TARGET%\" exit /b 0
del /f /q "%CLEAN_TARGET%\*" >nul 2>&1
del /f /q /a:h "%CLEAN_TARGET%\*" >nul 2>&1
del /f /q /a:s "%CLEAN_TARGET%\*" >nul 2>&1
for /f "usebackq delims=" %%D in (`dir /b /a:d-l "%CLEAN_TARGET%" 2^>nul`) do rd /s /q "%CLEAN_TARGET%\%%D" >nul 2>&1
exit /b 0

:CleanTempDir
rem usage: call :CleanTempDir "path"
rem Only cleans folders whose name contains temp or tmp, so a TEMP variable that
rem points somewhere unexpected can never wipe a real data folder.
set "TEMPDIR_PATH=%~1"
if not defined TEMPDIR_PATH exit /b 1
set "TEMPDIR_NAME="
for %%I in ("%TEMPDIR_PATH%") do set "TEMPDIR_NAME=%%~nxI"
if not defined TEMPDIR_NAME exit /b 1
echo "%TEMPDIR_NAME%" | findstr /i /c:"temp" /c:"tmp" >nul
if errorlevel 1 exit /b 1
call :CleanDir "%TEMPDIR_PATH%"
exit /b 0

:CleanChromium
rem usage: call :CleanChromium "...\User Data"
rem Cache folders only. Cookies, history, passwords and bookmarks are not touched.
if not exist "%~1\" exit /b 0
for /d %%P in ("%~1\Default" "%~1\Profile *" "%~1\Guest Profile") do if exist "%%~fP\" call :CleanChromiumProfile "%%~fP"
call :CleanDir "%~1\ShaderCache"
call :CleanDir "%~1\GrShaderCache"
call :CleanDir "%~1\GraphiteDawnCache"
exit /b 0

:CleanChromiumProfile
call :CleanDir "%~1\Cache"
call :CleanDir "%~1\Code Cache"
call :CleanDir "%~1\GPUCache"
exit /b 0

rem ----------------------------------------------------------------------------
rem  Disk Cleanup (cleanmgr) helpers
rem ----------------------------------------------------------------------------

:SageClear
rem Remove our flag from every Disk Cleanup handler, so an interrupted earlier
rem run can never leave an unwanted item selected.
for /f "delims=" %%K in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches" 2^>nul') do reg delete "%%K" /v StateFlags%SAGE% /f >nul 2>&1
exit /b 0

:SageSet
rem usage: call :SageSet "Handler name" - selects the item if it exists on this PC
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\%~1" >nul 2>&1 || exit /b 0
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\%~1" /v StateFlags%SAGE% /t REG_DWORD /d 2 /f >nul 2>&1
exit /b 0

:WaitForProcess
rem usage: call :WaitForProcess image.exe max-seconds
set "WFP_LEFT=%~2"
:WaitForProcess_Loop
tasklist /fi "imagename eq %~1" 2>nul | find /i "%~1" >nul
if errorlevel 1 exit /b 0
if %WFP_LEFT% LEQ 0 exit /b 1
ping -n 4 127.0.0.1 >nul
set /a WFP_LEFT-=3
goto :WaitForProcess_Loop

rem ============================================================================
rem  CLEANUP STEPS
rem ============================================================================

:Step_UserTemp
call :StepStart "User temporary files and app caches"
call :CleanTempDir "%TEMP%"
if /i not "%TMP%"=="%TEMP%" call :CleanTempDir "%TMP%"
call :CleanTempDir "%LOCALAPPDATA%\Temp"
call :CleanDir "%LOCALAPPDATA%\Microsoft\Windows\INetCache"
for /d %%P in ("%LOCALAPPDATA%\Packages\*") do if exist "%%~fP\TempState\" call :CleanDir "%%~fP\TempState"
call :StepEnd
exit /b 0

:Step_WindowsTemp
call :StepStart "Windows temporary files"
call :CleanDir "%SystemRoot%\Temp"
call :CleanDir "%SystemRoot%\SystemTemp"
call :StepEnd
exit /b 0

:Step_RecycleBin
call :StepStart "Recycle Bin"
if "%HAVE_PS%"=="0" (
    set "STEP_STATUS=SKIP"
    set "STEP_NOTE=PowerShell is not available on this PC"
) else (
    powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
)
call :StepEnd
exit /b 0

:Step_ShaderCaches
call :StepStart "Shader caches (DirectX, NVIDIA, AMD, Intel)"
call :CleanDir "%LOCALAPPDATA%\D3DSCache"
call :CleanDir "%LOCALAPPDATA%\Microsoft\D3DSCache"
call :CleanDir "%LOCALAPPDATA%\NVIDIA\DXCache"
call :CleanDir "%LOCALAPPDATA%\NVIDIA\GLCache"
call :CleanDir "%LOCALAPPDATA%\NVIDIA\ComputeCache"
call :CleanDir "%APPDATA%\NVIDIA\ComputeCache"
call :CleanDir "%USERPROFILE%\AppData\LocalLow\NVIDIA\PerDriverVersion\DXCache"
call :CleanDir "%LOCALAPPDATA%\NVIDIA Corporation\NV_Cache"
call :CleanDir "%ProgramData%\NVIDIA Corporation\NV_Cache"
call :CleanDir "%LOCALAPPDATA%\AMD\DxCache"
call :CleanDir "%LOCALAPPDATA%\AMD\GLCache"
call :CleanDir "%LOCALAPPDATA%\AMD\VkCache"
call :CleanDir "%LOCALAPPDATA%\Intel\ShaderCache"
call :CleanDir "%USERPROFILE%\AppData\LocalLow\Intel\ShaderCache"
call :StepEnd
exit /b 0

:Step_BrowserCaches
call :StepStart "Browser caches (Edge, Chrome, Brave, Firefox)"
call :CleanChromium "%LOCALAPPDATA%\Microsoft\Edge\User Data"
call :CleanChromium "%LOCALAPPDATA%\Google\Chrome\User Data"
call :CleanChromium "%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data"
for /d %%P in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*") do call :CleanDir "%%~fP\cache2"
call :StepEnd
exit /b 0

:Step_WindowsUpdate
call :StepStart "Windows Update and Delivery Optimization cache"
tasklist /fi "imagename eq TiWorker.exe" 2>nul | find /i "TiWorker.exe" >nul
if not errorlevel 1 (
    set "STEP_STATUS=SKIP"
    set "STEP_NOTE=Windows is installing updates right now - run TidyWin again later"
    call :StepEnd
    exit /b 0
)
set "WU_WAS=0"
set "BITS_WAS=0"
sc query wuauserv 2>nul | find "RUNNING" >nul && set "WU_WAS=1"
sc query bits 2>nul | find "RUNNING" >nul && set "BITS_WAS=1"
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
sc query wuauserv 2>nul | find "STOPPED" >nul
if errorlevel 1 (
    set "STEP_STATUS=SKIP"
    set "STEP_NOTE=Windows Update is busy - restart your PC and run TidyWin again"
) else (
    call :CleanDir "%SystemRoot%\SoftwareDistribution\Download"
)
if "%WU_WAS%"=="1" net start wuauserv >nul 2>&1
if "%BITS_WAS%"=="1" net start bits >nul 2>&1
if "%HAVE_PS%"=="1" powershell -NoProfile -Command "Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue" >nul 2>&1
call :StepEnd
exit /b 0

:Step_ErrorReports
call :StepStart "Error reports and crash dumps"
call :CleanDir "%ProgramData%\Microsoft\Windows\WER\ReportArchive"
call :CleanDir "%ProgramData%\Microsoft\Windows\WER\ReportQueue"
call :CleanDir "%ProgramData%\Microsoft\Windows\WER\Temp"
call :CleanDir "%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive"
call :CleanDir "%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue"
call :CleanDir "%LOCALAPPDATA%\CrashDumps"
call :CleanDir "%SystemRoot%\Minidump"
call :CleanDir "%SystemRoot%\LiveKernelReports"
if exist "%SystemRoot%\MEMORY.DMP" del /f /q "%SystemRoot%\MEMORY.DMP" >nul 2>&1
call :StepEnd
exit /b 0

:Step_RestorePoints
call :StepStart "System Restore points and Shadow Copies"
vssadmin delete shadows /for=%SystemDrive% /all /quiet >nul 2>&1
set "VSS_RC=%errorlevel%"
call :Log "  vssadmin exit code %VSS_RC%"
if not "%VSS_RC%"=="0" (
    set "STEP_STATUS=SKIP"
    set "STEP_NOTE=Nothing was removed - no restore points found or the service is off"
)
call :StepEnd
exit /b 0

:Step_DiskCleanup
call :StepStart "Windows built-in cleanup (Disk Cleanup)" long
if not exist "%SYS32%\cleanmgr.exe" (
    set "STEP_STATUS=SKIP"
    set "STEP_NOTE=Disk Cleanup is not included in this version of Windows"
    call :StepEnd
    exit /b 0
)
echo(           %C_DIM%A Disk Cleanup progress window may appear - that is normal.%C_RESET%
call :SageClear
call :SageSet "Active Setup Temp Folders"
call :SageSet "BranchCache"
call :SageSet "D3D Shader Cache"
call :SageSet "Diagnostic Data Viewer database Files"
call :SageSet "Downloaded Program Files"
call :SageSet "Internet Cache Files"
call :SageSet "Old ChkDsk Files"
call :SageSet "RetailDemo Offline Content"
call :SageSet "Setup Log Files"
call :SageSet "System error memory dump files"
call :SageSet "System error minidump files"
call :SageSet "Temporary Setup Files"
call :SageSet "Thumbnail Cache"
call :SageSet "Upgrade Discarded Files"
call :SageSet "Windows Error Reporting Archive Files"
call :SageSet "Windows Error Reporting Queue Files"
call :SageSet "Windows Error Reporting System Archive Files"
call :SageSet "Windows Error Reporting System Queue Files"
call :SageSet "Windows Error Reporting Temp Files"
call :SageSet "Windows Reset Log Files"
call :SageSet "Windows Upgrade Log Files"
if /i "%MODE%"=="DEEP" call :SageSet "Previous Installations"
start "" /wait "%SYS32%\cleanmgr.exe" /sagerun:%SAGE%
call :WaitForProcess cleanmgr.exe 3600
call :SageClear
call :StepEnd
exit /b 0

:Step_Dism
call :StepStart "Windows component store cleanup (DISM)" long
echo(           %C_DIM%This can take several minutes. Please keep this window open.%C_RESET%
"%SYS32%\Dism.exe" /Online /Cleanup-Image /StartComponentCleanup
set "DISM_RC=%errorlevel%"
call :Log "  DISM exit code %DISM_RC%"
if "%DISM_RC%"=="0" goto :Step_Dism_Done
if "%DISM_RC%"=="3010" goto :Step_Dism_Done
set "STEP_STATUS=SKIP"
set "STEP_NOTE=DISM returned code %DISM_RC% - restart Windows and run TidyWin again"
:Step_Dism_Done
call :StepEnd
exit /b 0
