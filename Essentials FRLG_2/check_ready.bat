@echo off
REM ============================================================================
REM Pokemon FRLG MMO - Pre-Deployment Checker
REM ============================================================================

setlocal enabledelayedexpansion

echo ================================================================================
echo              Pokemon FRLG Multiplayer - Pre-Deployment Check
echo ================================================================================
echo.

set READY=1

REM Check for Game.exe
if exist "Game.exe" (
    echo [PASS] Game.exe found
) else (
    echo [FAIL] Game.exe NOT found!
    echo        You need to create this first:
    echo        1. Open your project in RPG Maker XP
    echo        2. Go to File ^> Compile Script (F5^)
    echo        3. Close RPG Maker XP
    echo        4. Game.exe will be created
    echo.
    set READY=0
)

REM Check for Scripts.rxdata
if exist "Data\Scripts.rxdata" (
    echo [PASS] Data\Scripts.rxdata found
) else (
    echo [FAIL] Data\Scripts.rxdata NOT found!
    echo        You need to compile scripts:
    echo        1. Open RPG Maker XP Script Editor (F11^)
    echo        2. Press F5 to save/compile
    echo        3. Close the editor
    echo.
    set READY=0
)

REM Check for required folders
for %%D in (Graphics Audio Data) do (
    if exist "%%D\" (
        echo [PASS] %%D\ folder found
    ) else (
        echo [WARN] %%D\ folder NOT found
        echo        This folder should exist for a proper game
        echo.
    )
)

REM Check for multiplayer config
if exist "multiplayer_config.json" (
    echo [PASS] multiplayer_config.json found
) else (
    echo [WARN] multiplayer_config.json NOT found
    echo        Multiplayer features may not work correctly
    echo.
)

REM Check for Ruby
where ruby >nul 2>nul
if %errorlevel% equ 0 (
    echo [PASS] Ruby installation found
) else (
    echo [FAIL] Ruby NOT found!
    echo        Install Ruby from: https://rubyinstaller.org/
    echo.
    set READY=0
)

echo.
echo ================================================================================

if %READY%==1 (
    echo                         ALL CHECKS PASSED!
    echo ================================================================================
    echo.
    echo Your game is ready for deployment.
    echo.
    echo Next step: Run deploy.bat to create your release package
    echo.
) else (
    echo                      SOME CHECKS FAILED
    echo ================================================================================
    echo.
    echo Please fix the issues above before deploying.
    echo.
    echo QUICK FIX:
    echo 1. Open your game in RPG Maker XP
    echo 2. Press F5 (File ^> Compile Script^)
    echo 3. Wait for compilation to finish
    echo 4. Close RPG Maker XP
    echo 5. Run this checker again
    echo.
)

pause
