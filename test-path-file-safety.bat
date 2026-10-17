@echo off
REM ============================================================
REM CmdX2 --path-file Safety Test
REM
REM Tests that:
REM   1. --path-file loads PATH from a file, not the registry
REM   2. The child receives the full PATH (length >= 20000)
REM   3. The first, middle, and last PATH entries are intact
REM   4. The child's PATH exactly matches the input file
REM   5. The exported registry contents of HKCU\Environment are
REM      unchanged before and after all --path-file test invocations
REM
REM Scope of what this test proves:
REM   - The exported registry contents of HKCU\Environment are
REM     byte-identical before and after all --path-file test
REM     invocations.
REM     (reg export captures key values and subkeys in .reg format.
REM      It does not capture security descriptors or permissions.)
REM   - The child receives a PATH that exactly matches what
REM     CmdX2 is expected to produce from the input file.
REM
REM What this test does NOT prove:
REM   - That no other registry key was touched.
REM   - That no registry write was performed and immediately reverted.
REM   - That no service, file, task, or other system state was modified
REM     by the invoked executables.
REM   - That the security descriptors or permissions on
REM     HKCU\Environment are unchanged.
REM   - That CmdX2 specifically caused any observed registry change.
REM     The test cannot attribute a change to a particular process.
REM   The test is a targeted regression guard for the --path-file code
REM   path, not a general-purpose system integrity check.
REM
REM Trust model:
REM   This batch assumes cmdx2.exe and cmdx2_pathtest.exe are trusted
REM   executables built from reviewed source, and that they reside in
REM   a directory you control.
REM
REM   The CMDX2_EXE and PATHTEST_EXE environment variables are provided
REM   for CI and known-good paths. Do not set them to paths controlled
REM   by another user or by an untrusted process.
REM
REM   A batch script cannot prevent a binary from modifying Windows
REM   settings. Use only executables you trust and control. Run this
REM   test without administrator privileges.
REM
REM Registry verification:
REM   HKCU\Environment is snapshotted before any test runs, and again
REM   after the test step succeeds OR fails. The comparison runs on
REM   every execution path that reaches Step 1, so a registry change
REM   will be reported even if a PATH check fails first.
REM
REM   Snapshot creation is fail-closed. If the BEFORE snapshot cannot
REM   be established, the test aborts with exit code 7 without running
REM   CmdX2. If the AFTER snapshot cannot be established, the test
REM   reports a critical failure with exit code 6 rather than a pass.
REM   An unverifiable registry state is never reported as "unchanged".
REM
REM   The comparison step distinguishes three fc.exe results:
REM     errorlevel 0  = files identical  -> PASS
REM     errorlevel 1  = files differ     -> FAIL  registry changed
REM     errorlevel 2  = comparison error -> FAIL  unverifiable
REM   A comparison error is treated as a failure, not a pass.
REM
REM   When the snapshots differ, the test reports that the exported
REM   contents CHANGED DURING THE TEST. It does not attribute the
REM   change to CmdX2. Other processes running concurrently could
REM   have modified HKCU\Environment.
REM
REM   The full registry export content is NOT printed on mismatch,
REM   because HKCU\Environment may contain sensitive values such as
REM   API keys, credentials, or personal paths. Only the snapshot
REM   file paths are reported, so the user can investigate manually
REM   if desired.
REM
REM Scratch directory safety:
REM   A uniquely-named directory is created under %TEMP%. SCRATCH_CREATED
REM   is set to 1 only after mkdir succeeds. Cleanup is restricted to
REM   the scratch path successfully created by this script; concurrent
REM   replacement of that directory between creation and cleanup
REM   remains a theoretical residual risk.
REM
REM   Cleanup failure is reported as a warning. A stuck temp file does
REM   not change the test exit code, but the user is told the path so
REM   it can be cleaned up manually.
REM
REM Cmd parser safety note:
REM   No echo message inside a parenthesized if-block contains an
REM   unescaped parenthesis. cmd.exe's block parser counts parens
REM   naively and a stray ")" in echo text can close the block early,
REM   turning later commands unconditional. This file deliberately
REM   avoids such text.
REM
REM Exit codes:
REM   0 = all checks passed
REM   1 = cmdx2.exe or cmdx2_pathtest.exe not found
REM   2 = setup failed: scratch dir or test file
REM   3 = child PATH length check failed
REM   4 = content check failed: truncation, insertion, or wrong PATH
REM   5 = PATH origin wrong: child PATH does not start with file entry
REM   6 = REGISTRY CHANGED DURING TEST, OR REGISTRY STATE UNVERIFIABLE
REM   7 = BEFORE-SNAPSHOT FAILED: test aborted, not run
REM ============================================================

setlocal
set "FAILCODE=0"
set "SCRATCH_CREATED=0"

REM --- Locate binaries ---
if defined CMDX2_EXE (
    set "CMDX2=%CMDX2_EXE%"
) else (
    set "CMDX2=%~dp0cmdx2.exe"
)
if not exist "%CMDX2%" (
    echo [ERROR] cmdx2.exe not found at %CMDX2%
    echo Set CMDX2_EXE to a trusted path, or place this batch next to cmdx2.exe.
    exit /b 1
)

if defined PATHTEST_EXE (
    set "PATHTEST=%PATHTEST_EXE%"
) else (
    set "PATHTEST=%~dp0cmdx2_pathtest.exe"
)
if not exist "%PATHTEST%" (
    echo [ERROR] cmdx2_pathtest.exe not found at %PATHTEST%
    echo Set PATHTEST_EXE to a trusted path, or place this batch next to cmdx2_pathtest.exe.
    exit /b 1
)

echo [INFO] cmdx2:    %CMDX2%
echo [INFO] pathtest: %PATHTEST%

REM ============================================================
REM Scratch directory — never reuse an existing path.
REM ============================================================
set "SCRATCH=%TEMP%\cmdx2-safety-%RANDOM%%RANDOM%%RANDOM%"

REM Pre-check: refuse if anything already exists at this path.
if exist "%SCRATCH%" (
    echo [ERROR] Scratch path already exists. Aborting without deletion.
    echo         Path: %SCRATCH%
    echo         Nothing will be deleted.
    exit /b 2
)

REM Atomic creation: mkdir fails if the path exists. Errorlevel catches
REM the collision race that a pre-check alone would miss, plus any
REM permission or disk-full failures.
mkdir "%SCRATCH%" 2>nul
if errorlevel 1 (
    echo [ERROR] Could not create scratch directory.
    echo         Path: %SCRATCH%
    echo         Nothing will be deleted.
    exit /b 2
)
set "SCRATCH_CREATED=1"

if not exist "%SCRATCH%\" (
    echo [ERROR] Scratch directory creation succeeded but directory is missing.
    echo         Path: %SCRATCH%
    set "SCRATCH_CREATED=0"
    set "FAILCODE=2"
    goto :cleanup
)

echo [INFO] Scratch:  %SCRATCH%  created by this script
echo.

set "BEFORE_REG=%SCRATCH%\before.reg"
set "AFTER_REG=%SCRATCH%\after.reg"
set "TESTFILE=%SCRATCH%\testpath.txt"
set "LENFILE=%SCRATCH%\len.txt"

REM ============================================================
REM Step 1: Snapshot HKCU\Environment BEFORE — fail-closed
REM
REM If we cannot establish a reliable baseline, we must not run
REM the test at all. Running it would produce an unverifiable
REM result that could be falsely reported as a pass.
REM ============================================================
reg query "HKCU\Environment" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Cannot access HKCU\Environment.
    echo [ERROR] Registry baseline cannot be established.
    echo [ERROR] Test aborted. CmdX2 was not run.
    set "FAILCODE=7"
    goto :cleanup
)

reg export "HKCU\Environment" "%BEFORE_REG%" /y >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to export HKCU\Environment to "%BEFORE_REG%".
    echo [ERROR] Registry baseline cannot be established.
    echo [ERROR] Test aborted. CmdX2 was not run.
    set "FAILCODE=7"
    goto :cleanup
)

if not exist "%BEFORE_REG%" (
    echo [ERROR] Registry snapshot file was not created: "%BEFORE_REG%".
    echo [ERROR] Test aborted. CmdX2 was not run.
    set "FAILCODE=7"
    goto :cleanup
)

for %%A in ("%BEFORE_REG%") do set "BEFORE_SIZE=%%~zA"
if "%BEFORE_SIZE%"=="" (
    echo [ERROR] Could not stat BEFORE snapshot file.
    echo [ERROR] Test aborted. CmdX2 was not run.
    set "FAILCODE=7"
    goto :cleanup
)
if %BEFORE_SIZE% LSS 16 (
    echo [ERROR] BEFORE snapshot is implausibly small: %BEFORE_SIZE% bytes.
    echo [ERROR] Test aborted. CmdX2 was not run.
    set "FAILCODE=7"
    goto :cleanup
)

set "BEFORE=1"
echo [STEP 1] PASS: HKCU\Environment snapshot successful %BEFORE_SIZE% bytes

REM ============================================================
REM Step 2: Build synthetic PATH file, approx 22700 chars
REM ============================================================
echo C:\Fake\CMDX2-TEST-FIRST-ENTRY>"%TESTFILE%"
(for /L %%i in (1,1,1398) do @echo C:\Fake\Tool%%i)>>"%TESTFILE%"
echo C:\Fake\CMDX2-TEST-LAST-ENTRY>>"%TESTFILE%"

if not exist "%TESTFILE%" (
    echo [ERROR] Could not create test file.
    set "FAILCODE=2"
    goto :verify_registry
)
for %%A in ("%TESTFILE%") do set "FILESIZE=%%~zA"
if "%FILESIZE%"=="" (
    echo [ERROR] Could not stat test file.
    set "FAILCODE=2"
    goto :verify_registry
)
if %FILESIZE% LSS 20000 (
    echo [ERROR] Test file too small: %FILESIZE% bytes.
    set "FAILCODE=2"
    goto :verify_registry
)
echo [STEP 2] PASS: test file created %FILESIZE% bytes

REM ============================================================
REM Step 3: Verify child receives long PATH
REM ============================================================
"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" >"%LENFILE%" 2>&1
set "CMDX2_EXIT=%ERRORLEVEL%"
if not "%CMDX2_EXIT%"=="0" (
    echo [FAIL] cmdx2 exit code %CMDX2_EXIT%
    type "%LENFILE%"
    set "FAILCODE=3"
    goto :verify_registry
)

set "LEN="
for /f "usebackq delims=" %%L in ("%LENFILE%") do set "LEN=%%L"
echo %LEN%| findstr /R "^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo [FAIL] Child output not numeric: "%LEN%"
    set "FAILCODE=3"
    goto :verify_registry
)
if %LEN% LSS 20000 (
    echo [FAIL] Child PATH length %LEN% is less than 20000
    set "FAILCODE=3"
    goto :verify_registry
)
echo [STEP 3] PASS: child PATH length %LEN% at least 20000

REM ============================================================
REM Step 4: Verify PATH content
REM   4a-c are fast canaries that give specific diagnostics on the
REM   common failure modes. 4d is the exhaustive check: exact
REM   string comparison against the expected PATH derived from the
REM   input file.
REM
REM   Note: none of the echo messages below contain parentheses.
REM   cmd.exe's block parser counts parens naively; an unescaped
REM   ")" in echo text inside a parenthesized if-block can close
REM   the block early and turn subsequent commands unconditional.
REM ============================================================
"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" check-start "C:\Fake\CMDX2-TEST-FIRST-ENTRY" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] First entry canary not at start of child PATH
    echo        PATH was not loaded from file, or was truncated at start
    set "FAILCODE=5"
    goto :verify_registry
)
echo [STEP 4a] PASS: child PATH starts with file's first entry

"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" check ";C:\Fake\Tool700;" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Middle entry canary Tool700 not present in child PATH
    echo        PATH was truncated
    set "FAILCODE=4"
    goto :verify_registry
)
echo [STEP 4b] PASS: middle entry present in child PATH

"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" check-end "C:\Fake\CMDX2-TEST-LAST-ENTRY" >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Last entry canary not at end of child PATH
    echo        PATH was truncated at end, or extra entries were appended
    set "FAILCODE=4"
    goto :verify_registry
)
echo [STEP 4c] PASS: child PATH ends with file's last entry

REM Exact string comparison against the expected PATH derived from
REM the input file. Any insertion, truncation, or reordering will
REM fail this check.
"%CMDX2%" --path-file "%TESTFILE%" /c "%PATHTEST%" check-file "%TESTFILE%"
if errorlevel 1 (
    echo [FAIL] Child PATH does not exactly match input file
    echo        diagnostic above shows first differing position
    set "FAILCODE=4"
    goto :verify_registry
)
echo [STEP 4d] PASS: child PATH exactly matches input file

REM ============================================================
REM Registry verification — runs on ALL paths that reach Step 1.
REM Test-step failures jump here with FAILCODE set. Success falls
REM through here. Registry failure overrides FAILCODE to 6,
REM because a registry change is the most important concern.
REM ============================================================
:verify_registry

REM --- Step 5: Snapshot HKCU\Environment AFTER — fail-closed ---
reg query "HKCU\Environment" >nul 2>&1
if errorlevel 1 (
    echo [CRITICAL] HKCU\Environment disappeared or became inaccessible.
    echo [CRITICAL] Registry integrity cannot be verified after testing.
    set "FAILCODE=6"
    goto :report_result
)

reg export "HKCU\Environment" "%AFTER_REG%" /y >nul 2>&1
if errorlevel 1 (
    echo [CRITICAL] Could not export HKCU\Environment AFTER testing.
    echo [CRITICAL] Registry integrity cannot be verified.
    set "FAILCODE=6"
    goto :report_result
)

if not exist "%AFTER_REG%" (
    echo [CRITICAL] AFTER registry snapshot is missing.
    echo [CRITICAL] Registry integrity cannot be verified.
    set "FAILCODE=6"
    goto :report_result
)

for %%A in ("%AFTER_REG%") do set "AFTER_SIZE=%%~zA"
if "%AFTER_SIZE%"=="" (
    echo [CRITICAL] Could not stat AFTER snapshot file.
    set "FAILCODE=6"
    goto :report_result
)
if %AFTER_SIZE% LSS 16 (
    echo [CRITICAL] AFTER snapshot is implausibly small: %AFTER_SIZE% bytes.
    set "FAILCODE=6"
    goto :report_result
)

set "AFTER=1"
echo [STEP 5] PASS: HKCU\Environment snapshot successful %AFTER_SIZE% bytes

REM --- Step 6: Compare before/after ---
REM
REM fc.exe errorlevels:
REM   0 = files identical
REM   1 = files differ, registry changed
REM   2 = comparison error, cannot determine
REM
REM Check errorlevel 2 FIRST. A comparison error means we cannot
REM tell whether the registry changed. That must never be reported
REM as PASS. It is treated as a critical unverifiable result.
REM ============================================================
fc /b "%BEFORE_REG%" "%AFTER_REG%" >nul 2>&1

if errorlevel 2 (
    echo.
    echo ============================================================
    echo [CRITICAL FAILURE] Registry snapshot comparison failed
    echo ============================================================
    echo.
    echo fc.exe could not compare the before/after snapshots.
    echo Cannot establish whether HKCU\Environment changed.
    echo.
    echo BEFORE: %BEFORE_REG%
    echo AFTER:  %AFTER_REG%
    echo.
    echo This is not a pass. Investigate the snapshot files manually.
    set "FAILCODE=6"
    goto :report_result
)

if errorlevel 1 (
    echo.
    echo ============================================================
    echo [CRITICAL FAILURE] HKCU\Environment CHANGED DURING TEST
    echo ============================================================
    echo.
    echo The exported contents of HKCU\Environment differ before and
    echo after the test.
    echo.
    echo The test cannot establish which process caused the change.
    echo Another application, installer, Windows component, or user
    echo action could have modified the environment during the test.
    echo.
    echo Registry snapshots differ.
    echo Full registry contents have deliberately not been printed,
    echo because HKCU\Environment may contain sensitive values such
    echo as API keys, credentials, or personal paths.
    echo.
    echo To investigate manually, export HKCU\Environment before
    echo and after a CmdX2 invocation and compare them yourself:
    echo.
    echo   reg export "HKCU\Environment" before.reg /y
    echo   cmdx2 --path-file testpath.txt /c some-command
    echo   reg export "HKCU\Environment" after.reg /y
    echo   fc /b before.reg after.reg
    echo.
    echo Investigate before assuming a CmdX2 regression. If CmdX2 is
    echo the only process that should have been running, a change is
    echo a strong indicator of a regression, but not proof.
    set "FAILCODE=6"
    goto :report_result
)

echo [STEP 6] PASS: HKCU\Environment exported contents unchanged

REM ============================================================
REM Report
REM ============================================================
:report_result
if "%FAILCODE%"=="0" goto :report_pass
goto :report_fail

:report_fail
echo.
echo ============================================================
echo TEST FAILED, exit code %FAILCODE%
echo ============================================================
echo   Scratch directory: %SCRATCH%
goto :cleanup

:report_pass
echo.
echo ============================================================
echo ALL CHECKS PASSED
echo ============================================================
echo   Child PATH length:  %LEN% chars
echo   First entry:        present at start
echo   Middle entry:       present
echo   Last entry:         present at end
echo   Exact match:        child PATH matches input file contents
echo   Registry:           exported contents of HKCU\Environment unchanged
echo.

REM ============================================================
REM Cleanup — only deletes directories this script created.
REM ============================================================
:cleanup
set "CLEANUP_OK=1"
if "%SCRATCH_CREATED%"=="1" (
    if exist "%SCRATCH%\" (
        rmdir /s /q "%SCRATCH%" 2>nul
        if exist "%SCRATCH%\" (
            set "CLEANUP_OK=0"
        )
    )
)
if "%CLEANUP_OK%"=="0" (
    echo.
    echo [WARNING] Scratch directory could not be removed:
    echo           %SCRATCH%
    echo           Some files may be in use. Delete manually when possible.
    echo           Test result is unaffected.
)
exit /b %FAILCODE%