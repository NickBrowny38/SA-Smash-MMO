@echo off
REM ============================================================================
REM Pokemon FRLG MMO - Deployment Script (Windows)
REM ============================================================================

setlocal enabledelayedexpansion

echo ================================================================================
echo              Pokemon FRLG Multiplayer - Game Deployment
echo ================================================================================
echo.

REM Check if Ruby is installed
where ruby >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Ruby is not installed or not in PATH!
    echo.
    echo Please install Ruby from: https://rubyinstaller.org/
    echo Then run this script again.
    echo.
    pause
    exit /b 1
)

echo [✓] Ruby found
echo.

REM Check if RPG Maker XP is available
if not exist "Game.exe" (
    echo [WARNING] Game.exe not found!
    echo.
    echo Make sure you:
    echo 1. Have RPG Maker XP installed
    echo 2. Have compiled your game at least once
    echo 3. Game.exe exists in the game folder
    echo.
)

REM Compile scripts first (if RPG Maker is running, close it)
echo [Step 1/3] Preparing for deployment...
echo.
echo IMPORTANT: Please ensure:
echo - All plugins are saved
echo - Scripts are compiled (Data\Scripts.rxdata exists)
echo - Game has been tested in RPG Maker XP
echo.
pause

REM Run the Ruby deployment script
echo.
echo [Step 2/3] Running deployment script...
echo.
ruby deploy_game.rb

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Deployment failed!
    echo Check the error messages above for details.
    echo.
    pause
    exit /b 1
)

echo.
echo [Step 3/3] Deployment completed!
echo.

REM Open the release folder
if exist "Release" (
    echo Opening Release folder...
    start "" explorer "Release"
)

echo.
echo ================================================================================
echo                         Deployment Successful!
echo ================================================================================
echo.
echo Your game is ready for distribution!
echo.
echo Next steps:
echo 1. Test the game from the Release folder
echo 2. Distribute the ZIP file or folder to players
echo 3. Update your server if needed
echo.
echo Press any key to exit...
pause >nul
