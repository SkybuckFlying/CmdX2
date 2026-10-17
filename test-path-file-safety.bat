@echo off
REM ============================================================
REM CmdX2 --path-file Safety Test
REM
REM Tests that:
REM   1. --path-file loads PATH from a file, not the registry
REM   2. The child receives the full PATH (length >= 20000)
REM   3. The first, middle, and last PATH entries are intact
REM   4. HKCU\Environment is UNCHANGED before/after
REM
REM If cmdx2 ever changes to touch the registry during --path-file,
REM check 4 fails with exit code 6 and a CRITICAL FAILURE message.
REM
REM Exit codes:
REM   0 = all checks passed
REM   1 = cmdx2.exe or cmdx2_pathtest.exe not found
REM   2 = setup failed (scratch dir, test file)
REM   3 = child PATH length check failed
REM   4 = content check failed (truncation or wrong PATH)
REM   5 = PATH origin wrong (child PATH does not start with file entry)
REM   6 = REGISTRY WAS MODIFIED (critical regression)
REM
REM Requirements:
REM   - Windows 7 or later
REM   - reg.exe, findstr.exe, fc.exe (all ship with Windows)
REM   - cmdx2.exe and cmdx2_pathtest.exe (same directory or via env vars)
REM ============================================================

setlocal

REM --- Locate binaries ---
if defined CMDX2_EXE (
    set "CMDX2=%CMDX2_EXE%"
) else (
    set "CMDX2=%~dp0cmdx2.exe"
)
if not exist "%CMDX2%" (
    echo [ERROR] cmdx2.exe not found at %CMDX2%
    echo Set CMDX2_EXE or place this batch next to cmdx2.exe.
    exit /b 1
)

if defined PATHTEST_EXE (
    set "PATHTEST=%PATHTEST_EXE%"
) else (
    set "PATHTEST=%~dp0cmdx2_pathtest.exe"
)
if not exist "%PATHTEST%" (
    echo [ERROR] cmdx2_pathtest.exe not found at %PATHTEST%
    echo Set PATHTEST_EXE or place this batch next to cmdx2_pathtest.exe.
    exit /b 1
)

echo [INFO] cmdx2:    %CMDX2%
echo [INFO] pathtest: %PATHTEST%

REM --- Scratch directory ---
set "SCRATCH=%TEMP%\cmdx2-safety-%RANDOM%%RANDOM%"
mkdir "%SCRATCH%" 2>nul
if not exist "%SCRATCH%" (
    echo [ERROR] Could not create scratch directory: %SCRATCH%
    exit /b 2
)
echo [INFO] Scratch:  %SCRATCH%
echo.

set "BEFORE_REG=%SCRATCH%\before.reg"
set "AFTER_REG=%SCRATCH%\after.reg"
set "TESTFILE=%SCRATCH%\testpath.txt"
set "LENFILE=%SCRATCH%\len.txt"

set "FAILCODE=0"

REM ============================================================
REM Step 1: Snapshot HKCU\Environment BEFORE
REM ============================================================
reg export "HKCU\Environment" "%BEFORE_REG%" /y >nul 2>&1
if exist "%BEFORE_REG%" (set "BEFORE=1") else (set "BEFORE=0")
echo [STEP 1] HKCU\Environment snapshot: exists=%BEFORE%

REM ============================================================
REM Step 2: Build synthetic PATH file (~22,700 chars)
REM ============================================================
echo C:\Fake\CMDX2-TEST-FIRST-ENTRY>"%TESTFILE%"
(for /L %%i in (1,1,1398) do @echo C:\Fake\Tool%%i)>>"%TESTFILE%"
echo C:\Fake\CMDX2-TEST-LAST-ENTRY>>"%TESTFILE%"

for %%A in ("%TESTFILE%") do set "FILESIZE=%%~zA"
if not defined FILESIZE (
    echo [ERROR] Could not stat test file.
    set "FAILCODE=2"
    goto :fail
)
echo [STEP 2] Test file created: %FILESIZE% bytes

REM ============================================================
REM Step 3: Verify child receives long PATH
REM ============================================================
"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" >"%LENFILE%" 2>&1
set "CMDX2_EXIT=%ERRORLEVEL%"
if not "%CMDX2_EXIT%"=="0" (
    echo [FAIL] cmdx2 exit code %CMDX2_EXIT%
    type "%LENFILE%"
    set "FAILCODE=3"
    goto :fail
)

set "LEN="
for /f "usebackq delims=" %%L in ("%LENFILE%") do set "LEN=%%L"
echo %LEN%| findstr /R "^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo [FAIL] Child output not numeric: "%LEN%"
    set "FAILCODE=3"
    goto :fail
)
if %LEN% LSS 20000 (
    echo [FAIL] Child PATH length %LEN% ^< 20000
    set "FAILCODE=3"
    goto :fail
)
echo [STEP 3] PASS: child PATH length %LEN% ^>= 20000

REM ============================================================
REM Step 4: Verify PATH content (start, middle, end canaries)
REM ============================================================
"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" check-start "C:\Fake\CMDX2-TEST-FIRST-ENTRY" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] First entry canary not at start of child PATH
    echo       (PATH was not loaded from file, or was truncated at start)
    set "FAILCODE=5"
    goto :fail
)
echo [STEP 4a] PASS: child PATH starts with file's first entry

"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" check ";C:\Fake\Tool700;" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Middle entry canary (Tool700) not present in child PATH
    echo       (PATH was truncated)
    set "FAILCODE=4"
    goto :fail
)
echo [STEP 4b] PASS: middle entry present in child PATH

"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" check-end "C:\Fake\CMDX2-TEST-LAST-ENTRY" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Last entry canary not at end of child PATH
    echo       (PATH was truncated at end, or extra entries were appended)
    set "FAILCODE=4"
    goto :fail
)
echo [STEP 4c] PASS: child PATH ends with file's last entry

REM ============================================================
REM Step 5: Snapshot HKCU\Environment AFTER
REM ============================================================
reg export "HKCU\Environment" "%AFTER_REG%" /y >nul 2>&1
if exist "%AFTER_REG%" (set "AFTER=1") else (set "AFTER=0")
echo [STEP 5] HKCU\Environment snapshot: exists=%AFTER%

REM ============================================================
REM Step 6: Compare registry before/after
REM ============================================================
if "%BEFORE%"=="1" if "%AFTER%"=="1" (
    fc /b "%BEFORE_REG%" "%AFTER_REG%" >nul 2>&1
    if errorlevel 1 (
        echo.
        echo ============================================================
        echo [CRITICAL FAILURE] HKCU\Environment WAS MODIFIED
        echo ============================================================
        echo.
        echo --path-file must not touch the registry. A regression has
        echo been introduced. Before/after snapshots differ.
        echo.
        echo --- BEFORE ---
        type "%BEFORE_REG%"
        echo --- AFTER ---
        type "%AFTER_REG%"
        echo.
        echo Please report this immediately.
        set "FAILCODE=6"
        goto :fail
    )
)
if "%BEFORE%"=="0" if "%AFTER%"=="1" (
    echo [CRITICAL] --path-file CREATED HKCU\Environment
    set "FAILCODE=6"
    goto :fail
)
if "%BEFORE%"=="1" if "%AFTER%"=="0" (
    echo [CRITICAL] --path-file DELETED HKCU\Environment
    set "FAILCODE=6"
    goto :fail
)
echo [STEP 6] PASS: HKCU\Environment unchanged

REM ============================================================
REM All checks passed
REM ============================================================
echo.
echo ============================================================
echo ALL CHECKS PASSED
echo ============================================================
echo   Child PATH length:  %LEN% chars
echo   First entry:        present at start
echo   Middle entry:       present
echo   Last entry:         present at end
echo   Registry:           HKCU\Environment unchanged
echo.
set "FAILCODE=0"
goto :cleanup

REM ============================================================
:fail
echo.
echo ============================================================
echo TEST FAILED (exit code %FAILCODE%)
echo ============================================================
echo   Scratch directory: %SCRATCH%

:cleanup
REM Best-effort cleanup. Never fails.
cd /d "%TEMP%" 2>nul
rmdir /s /q "%SCRATCH%" 2>nul
exit /b %FAILCODE%