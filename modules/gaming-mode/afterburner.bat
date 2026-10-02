@echo off
rem ============================================================================
rem  TidyWin - Gaming Mode                                             v1.0.6
rem  Part of TidyWin: tools for cleaning and optimizing Windows.
rem ----------------------------------------------------------------------------
rem  PURPOSE
rem    Apply a reversible Windows gaming profile and, optionally, a small
rem    NVIDIA global profile preset through NVIDIA Profile Inspector.
rem
rem  REQUIREMENTS
rem    Windows 10 or Windows 11, administrator rights (requested for you),
rem    and the matching afterburner-helper.ps1 file in this folder.
rem
rem  SAFETY
rem    Original Windows settings and the NVIDIA global profile are backed up
rem    before changes. Choose Restore to return to that saved state.
rem    HAGS, monitor refresh rate, and per-game GPU selection are guided only.
rem ============================================================================

setlocal EnableExtensions DisableDelayedExpansion

set "SELF=%~f0"
set "SELF_DIR=%~dp0"
set "SYS32=%SystemRoot%\System32"
if defined PROCESSOR_ARCHITEW6432 set "SYS32=%SystemRoot%\Sysnative"
set "PATH=%SYS32%;%SystemRoot%;%SYS32%\Wbem;%SYS32%\WindowsPowerShell\v1.0\"
cd /d "%SYS32%" 2>nul
set "TW_VERSION=1.0.6"
set "TW_EXIT=0"
set "IS_ELEVATED=0"
set "TARGET_SID="
set "STATE_DIR="
set "ACTION="
set "CAPTURE_CHOICE=0"
set "WIN_BUILD=0"
set "WIN_NAME=Windows 10"
set "COLOR_FALLBACK=0"
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

:ParseArgs
if "%~1"=="" goto :ArgsDone
if /i "%~1"=="/apply" set "ACTION=APPLY"
if /i "%~1"=="/restore" set "ACTION=RESTORE"
if /i "%~1"=="/check" set "ACTION=CHECK"
if /i "%~1"=="/elevated" set "IS_ELEVATED=1"
if /i "%~1"=="/sid" goto :ArgSid
if /i "%~1"=="/state" goto :ArgState
if /i "%~1"=="/help" goto :Help
if /i "%~1"=="/?" goto :Help
if /i "%~1"=="-h" goto :Help
shift
goto :ParseArgs

:ArgSid
shift
set "TARGET_SID=%~1"
shift
goto :ParseArgs

:ArgState
shift
set "STATE_DIR=%~1"
shift
goto :ParseArgs

:ArgsDone
call :DetectWindows
if %WIN_BUILD% LSS 10240 goto :UnsupportedOS
if not defined TARGET_SID (
    for /f "tokens=2 delims=," %%S in ('whoami /user /fo csv /nh 2^>nul') do set "TARGET_SID=%%~S"
)
if not defined STATE_DIR set "STATE_DIR=%LOCALAPPDATA%\TidyWin\GamingMode"
if not defined TARGET_SID goto :MissingSid

rem Check the actual Windows administrator token before showing the menu.
powershell.exe -NoLogo -NoProfile -Command "$identity = [Security.Principal.WindowsIdentity]::GetCurrent(); $principal = New-Object Security.Principal.WindowsPrincipal($identity); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 goto :NeedAdmin
set "IS_ELEVATED=1"

title TidyWin - Gaming Mode
call :InitColors
cls
call :Banner

if not exist "%SELF_DIR%afterburner-helper.ps1" goto :MissingHelper

if /i "%ACTION%"=="APPLY" goto :ConfirmApply
if /i "%ACTION%"=="RESTORE" goto :RunRestore
if /i "%ACTION%"=="CHECK" goto :RunCheck
goto :Menu

:Menu
echo(
echo(%C_WHITE%   Choose an action%C_RESET%
echo(
echo(%C_BLUE%   [1]%C_RESET%  %C_WHITE%APPLY GAMING MODE%C_RESET%  %C_GREEN%recommended%C_RESET%
echo(%C_DIM%        Windows Game Mode, high-performance power plan if available,%C_RESET%
echo(%C_DIM%        mouse acceleration off, and optional NVIDIA / capture settings.%C_RESET%
echo(%C_DIM%        Restore an active snapshot before applying again.%C_RESET%
echo(
echo(%C_BLUE%   [2]%C_RESET%  %C_WHITE%RESTORE SAVED SETTINGS%C_RESET%
echo(%C_DIM%        Return Windows and NVIDIA settings to the snapshot from Apply.%C_RESET%
echo(
echo(%C_BLUE%   [3]%C_RESET%  %C_WHITE%CHECK CURRENT SETUP%C_RESET%
echo(%C_DIM%        Read-only report; it does not change Windows or NVIDIA settings.%C_RESET%
echo(
echo(%C_BLUE%   [4]%C_RESET%  %C_WHITE%Exit without changing anything%C_RESET%
echo(
<nul set /p "=%C_BLUE%   Select an option [1-4]: %C_RESET%"
choice /c 1234 /n >nul
set "PICK=%errorlevel%"
echo(
if "%PICK%"=="4" goto :UserExit
if "%PICK%"=="3" goto :RunCheck
if "%PICK%"=="2" goto :RunRestore
goto :ConfirmApply

:ConfirmApply
echo(
echo(%C_YELLOW%   If available, the NVIDIA helper sets Prefer Maximum Performance globally.%C_RESET%
echo(%C_DIM%   This can increase power use, fan noise, and temperature while 3D apps run.%C_RESET%
echo(%C_DIM%   On a laptop, connect the power adapter before gaming.%C_RESET%
echo(
<nul set /p "=%C_WHITE%   Disable Xbox Game Bar capture and background recording too? [Y/N]: %C_RESET%"
choice /c YN /n
set "CAPTURE_PICK=%errorlevel%"
echo(
if "%CAPTURE_PICK%"=="1" set "CAPTURE_CHOICE=1"
echo(%C_YELLOW%   Apply the saved, reversible Gaming Mode settings now? [Y/N]: %C_RESET%
choice /c YN /n
set "CONFIRM_PICK=%errorlevel%"
echo(
if "%CONFIRM_PICK%"=="2" goto :UserExit
set "ACTION=APPLY"

:RunApply
echo(%C_BLUE%   Starting Gaming Mode setup. Keep this window open.%C_RESET%
echo(
if "%CAPTURE_CHOICE%"=="1" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%afterburner-helper.ps1" -Action Apply -TargetSid "%TARGET_SID%" -StateDirectory "%STATE_DIR%" -ScriptDirectory "%SELF_DIR%." -DisableCapture
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%afterburner-helper.ps1" -Action Apply -TargetSid "%TARGET_SID%" -StateDirectory "%STATE_DIR%" -ScriptDirectory "%SELF_DIR%."
)
set "TW_EXIT=%errorlevel%"
goto :Finish

:RunRestore
set "ACTION=RESTORE"
echo(
echo(%C_YELLOW%   Restore returns this user and the active power plan to the saved snapshot.%C_RESET%
echo(%C_DIM%   Settings changed after that snapshot may also be replaced.%C_RESET%
echo(
<nul set /p "=%C_WHITE%   Continue with Restore? [Y/N]: %C_RESET%"
choice /c YN /n
set "CONFIRM_PICK=%errorlevel%"
echo(
if "%CONFIRM_PICK%"=="2" goto :UserExit
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%afterburner-helper.ps1" -Action Restore -TargetSid "%TARGET_SID%" -StateDirectory "%STATE_DIR%" -ScriptDirectory "%SELF_DIR%."
set "TW_EXIT=%errorlevel%"
goto :Finish

:RunCheck
echo(%C_BLUE%   Checking your setup. This report does not change Windows or NVIDIA settings.%C_RESET%
echo(
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SELF_DIR%afterburner-helper.ps1" -Action Check -TargetSid "%TARGET_SID%" -StateDirectory "%STATE_DIR%" -ScriptDirectory "%SELF_DIR%."
set "TW_EXIT=%errorlevel%"
goto :Finish

:NeedAdmin
if "%IS_ELEVATED%"=="1" goto :AdminFailed
echo(
echo(%C_WHITE%   Administrator permission is needed for Gaming Mode.%C_RESET%
echo(%C_DIM%   A Windows prompt will appear - choose Yes and use the same Windows account.%C_RESET%
set "TW_SELF=%SELF%"
set "TW_ARGS=/elevated /sid %TARGET_SID% /state "%STATE_DIR%""
if /i "%ACTION%"=="APPLY" set "TW_ARGS=%TW_ARGS% /apply"
if /i "%ACTION%"=="RESTORE" set "TW_ARGS=%TW_ARGS% /restore"
if /i "%ACTION%"=="CHECK" set "TW_ARGS=%TW_ARGS% /check"
powershell.exe -NoLogo -NoProfile -Command "try { $cmdline = '/d /c ' + [char]34 + [char]34 + $env:TW_SELF + [char]34 + ' ' + $env:TW_ARGS + [char]34; Start-Process -FilePath $env:ComSpec -ArgumentList $cmdline -Verb RunAs -WindowStyle Normal -ErrorAction Stop } catch { exit 1 }" >nul 2>&1
if errorlevel 1 goto :AdminFailed
exit /b 0

:AdminFailed
echo(
echo(%C_RED%   Administrator rights were not granted.%C_RESET%
echo(%C_WHITE%   Windows did not grant administrator access. Choose Yes in the UAC prompt to continue.%C_RESET%
set "TW_EXIT=1"
goto :Finish

:MissingHelper
echo(
echo(%C_RED%   afterburner-helper.ps1 was not found beside this BAT file.%C_RESET%
echo(%C_WHITE%   Keep both files together, then run this module again.%C_RESET%
set "TW_EXIT=1"
goto :Finish

:MissingSid
echo(
echo(%C_RED%   TidyWin could not identify the Windows account to configure.%C_RESET%
set "TW_EXIT=1"
goto :Finish

:UnsupportedOS
echo(
echo(  TidyWin Gaming Mode needs Windows 10 or Windows 11.
echo(  This computer reports Windows build %WIN_BUILD%.
set "TW_EXIT=1"
goto :Finish

:UserExit
echo(%C_DIM%   Nothing was changed. Goodbye!%C_RESET%
set "TW_EXIT=2"
goto :Finish

:Help
echo(
echo(  TidyWin - Gaming Mode  v%TW_VERSION%
echo(
echo(  Usage:  afterburner.bat [/apply ^| /restore ^| /check ^| /help]
echo(
echo(  Without an option an interactive menu is shown.
echo(  Administrator rights are requested automatically.
echo(  Apply saves a Windows and NVIDIA snapshot; Restore uses that snapshot.
echo(  Check reports current settings without changing them.
echo(  HAGS, refresh rate, and per-game GPU selection are guided in Settings.
echo(
exit /b 0

:Finish
if defined C_RESET <nul set /p "=%C_RESET%"
if "%COLOR_FALLBACK%"=="1" color
echo(
<nul set /p "=   Press any key to close this window..."
pause >nul
echo(
exit /b %TW_EXIT%

:DetectWindows
set "WIN_BUILD=0"
for /f "tokens=3" %%B in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| find "CurrentBuildNumber"') do set "WIN_BUILD=%%B"
if %WIN_BUILD% GEQ 22000 set "WIN_NAME=Windows 11"
exit /b 0

:InitColors
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
echo(%C_WHITE%   Windows Cleaner and Optimizer%C_RESET%                 %C_BLUE%Gaming Mode  v%TW_VERSION%%C_RESET%
echo(%C_DIM%   Reversible gaming setup for Windows and supported NVIDIA GPUs.%C_RESET%
echo(%C_BLUE%  ------------------------------------------------------------------%C_RESET%
echo(%C_BLUE%   System   %C_RESET%%C_WHITE%%WIN_NAME% build %WIN_BUILD%%C_RESET%
exit /b 0
