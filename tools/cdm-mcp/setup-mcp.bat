@echo off
setlocal EnableDelayedExpansion

rem ---------------------------------------------------------------------------
rem  C64 Dev Machine - MCP setup helper (Pro edition)
rem
rem  Launched by the MCP-CON button via execute_shell_simple, hidden and
rem  detached. Reports progress by rewriting a small status file the editor
rem  polls, so the editor never blocks while this runs.
rem
rem  Usage:  setup-mcp.bat [status_folder]
rem
rem  Writes into <status_folder>:
rem      mcp-setup-status.txt   line 1 = status token, line 2 = UI detail
rem      mcp-pair.txt           the pairing key, consumed and deleted by the
rem                             editor the moment it is read
rem      mcp-setup-log.txt      verbose log for troubleshooting
rem
rem  Status tokens:
rem      CHECKING           looking for Node.js
rem      NODE_MISSING       Node.js not found
rem      NODE_INSTALLING    winget install running (shows a Windows prompt)
rem      NODE_INSTALL_FAIL  install did not complete
rem      NODE_TOO_OLD       found Node.js, but older than v22
rem      NO_WINGET          no winget available; browser opened at nodejs.org
rem      BRIDGE_MISSING     bridge.mjs not found next to this script
rem      TOKEN_FAILED       could not create the local pairing key
rem      REGISTERING        registering with the assistant CLIs
rem      NO_HOST            ready, but no Codex or Claude CLI was found
rem      DONE               ready to connect
rem
rem  The pairing key is never written to the log.
rem ---------------------------------------------------------------------------

set "SCRIPTDIR=%~dp0"
if "%SCRIPTDIR:~-1%"=="\" set "SCRIPTDIR=%SCRIPTDIR:~0,-1%"
set "BRIDGE=%SCRIPTDIR%\bridge.mjs"

set "STATUSDIR=%~1"
if "%STATUSDIR%"=="" set "STATUSDIR=%LOCALAPPDATA%\C64DevMachine_win"
if "%STATUSDIR:~-1%"=="\" set "STATUSDIR=%STATUSDIR:~0,-1%"
if not exist "%STATUSDIR%" mkdir "%STATUSDIR%" >nul 2>&1

set "STATUS=%STATUSDIR%\mcp-setup-status.txt"
set "LOG=%STATUSDIR%\mcp-setup-log.txt"
set "PAIRFILE=%STATUSDIR%\mcp-pair.txt"
set "VERTMP=%STATUSDIR%\mcp-nodever.tmp"
set "HOSTS="

> "%LOG%" echo [%DATE% %TIME%] MCP setup started
>>"%LOG%" echo script folder: %SCRIPTDIR%
>>"%LOG%" echo status folder: %STATUSDIR%

rem A stale key from an earlier run must never be adopted.
if exist "%PAIRFILE%" del "%PAIRFILE%" >nul 2>&1

call :status CHECKING "Checking for Node.js"

if not exist "%BRIDGE%" (
    call :status BRIDGE_MISSING "bridge.mjs was not found next to setup-mcp.bat"
    goto :finish
)

rem --- locate Node.js -------------------------------------------------------
call :findnode
if defined NODE goto :checkversion
goto :installnode

rem --- install Node.js ------------------------------------------------------
:installnode
call :status NODE_MISSING "Node.js is not installed"
where winget >nul 2>&1
if not errorlevel 1 goto :winget

call :status NO_WINGET "Install Node.js 22 or newer from nodejs.org, then press MCP-CON again"
start "" "https://nodejs.org/en/download"
goto :finish

:winget
call :status NODE_INSTALLING "Installing Node.js - please approve the Windows prompt"
winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements >>"%LOG%" 2>&1
>>"%LOG%" echo winget exit code: %errorlevel%

rem This process inherited the old PATH, so look in the install folder directly.
call :findnode
if defined NODE goto :checkversion
call :status NODE_INSTALL_FAIL "Node.js install did not complete. See mcp-setup-log.txt"
goto :finish

rem --- verify version -------------------------------------------------------
:checkversion
>>"%LOG%" echo node: %NODE%
"%NODE%" --version > "%VERTMP%" 2>>"%LOG%"
set "NVRAW="
if exist "%VERTMP%" set /p NVRAW=<"%VERTMP%"
del "%VERTMP%" >nul 2>&1
>>"%LOG%" echo node version: !NVRAW!

set "NV="
for /f "tokens=1 delims=." %%a in ("!NVRAW!") do set "NV=%%a"
set "NV=!NV:v=!"
set /a NVNUM=0
set /a NVNUM=!NV! 2>nul
if !NVNUM! GEQ 22 goto :maketoken

call :status NODE_TOO_OLD "Found Node.js !NVRAW! - version 22 or newer is required"
goto :finish

rem --- create the local pairing key -----------------------------------------
:maketoken
call :status REGISTERING "Preparing the local pairing key"
"%NODE%" "%BRIDGE%" --pair > "%PAIRFILE%" 2>>"%LOG%"
if errorlevel 1 (
    del "%PAIRFILE%" >nul 2>&1
    call :status TOKEN_FAILED "Could not create the local pairing key. See mcp-setup-log.txt"
    goto :finish
)
>>"%LOG%" echo pairing key written for the editor to collect

rem --- register with whichever assistant CLIs are installed -----------------
where codex >nul 2>&1
if errorlevel 1 goto :trycc
call :status REGISTERING "Registering with Codex CLI"
>>"%LOG%" echo --- codex mcp add ---
codex mcp add c64-dev-machine -- "%NODE%" "%BRIDGE%" >>"%LOG%" 2>&1
>>"%LOG%" echo codex exit code: %errorlevel%
set "HOSTS=!HOSTS! Codex"

:trycc
where claude >nul 2>&1
if errorlevel 1 goto :hostsdone
call :status REGISTERING "Registering with Claude Code"
>>"%LOG%" echo --- claude mcp add ---
claude mcp add --scope user c64-dev-machine -- "%NODE%" "%BRIDGE%" >>"%LOG%" 2>&1
>>"%LOG%" echo claude exit code: %errorlevel%
set "HOSTS=!HOSTS! Claude"

:hostsdone
if "!HOSTS!"=="" goto :nohost
call :status DONE "Ready - restart the MCP connection in!HOSTS!"
goto :finish

:nohost
call :status NO_HOST "Node.js and the pairing key are ready. No assistant CLI was found"
goto :finish

rem --- helpers --------------------------------------------------------------
:findnode
set "NODE="
for /f "delims=" %%i in ('where node 2^>nul') do if not defined NODE set "NODE=%%i"
if defined NODE exit /b 0
if exist "%ProgramFiles%\nodejs\node.exe" set "NODE=%ProgramFiles%\nodejs\node.exe"
if defined NODE exit /b 0
if exist "%ProgramFiles(x86)%\nodejs\node.exe" set "NODE=%ProgramFiles(x86)%\nodejs\node.exe"
if defined NODE exit /b 0
if exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" set "NODE=%LOCALAPPDATA%\Programs\nodejs\node.exe"
exit /b 0

:status
> "%STATUS%" echo %~1
>>"%STATUS%" echo %~2
>>"%LOG%" echo [%TIME%] %~1 - %~2
exit /b 0

:finish
>>"%LOG%" echo [%TIME%] MCP setup finished
endlocal
exit /b 0
