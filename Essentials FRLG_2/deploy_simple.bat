@echo off
REM ============================================================================
REM Pokemon FRLG MMO - Simple Deployment (Fixed & Verbose)
REM ============================================================================

setlocal enabledelayedexpansion

echo ================================================================================
echo         Pokemon FRLG Multiplayer - Simple Game Deployment
echo                     (No Ruby Installation Required!)
echo ================================================================================
echo.

REM Configuration
set GAME_TITLE=Pokemon FRLG Multiplayer
set VERSION=1.0.0
set BUILD_DIR=Build
set RELEASE_DIR=Release

REM Get timestamp
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set TIMESTAMP=%datetime:~0,8%_%datetime:~8,6%

REM Step 1: Pre-flight checks
echo [1/7] Running pre-flight checks...
echo.

set CHECKS_PASSED=1

if exist "Game.exe" (
    echo   [OK] Game.exe found
) else (
    echo   [FAIL] Game.exe not found!
    echo         Please compile your game in RPG Maker XP first (File ^> Compile Script, F5^)
    set CHECKS_PASSED=0
)

if exist "Data\Scripts.rxdata" (
    echo   [OK] Data\Scripts.rxdata found
) else (
    echo   [FAIL] Data\Scripts.rxdata not found!
    echo          Scripts are required! Open RPG Maker XP and press F11, then F5 to save.
    set CHECKS_PASSED=0
)

if exist "Graphics\" (
    echo   [OK] Graphics folder found
) else (
    echo   [WARN] Graphics folder not found
)

if exist "Audio\" (
    echo   [OK] Audio folder found
) else (
    echo   [WARN] Audio folder not found
)

if exist "Data\" (
    echo   [OK] Data folder found
) else (
    echo   [FAIL] Data folder not found!
    set CHECKS_PASSED=0
)

echo.

if %CHECKS_PASSED%==0 (
    echo [ERROR] Pre-flight checks failed!
    echo.
    echo Please fix the issues above and try again.
    echo.
    pause
    exit /b 1
)

REM Step 2: Clean old builds
echo [2/7] Cleaning old builds...
echo.

if exist "%BUILD_DIR%" (
    rmdir /s /q "%BUILD_DIR%" 2>nul
    timeout /t 1 /nobreak >nul
    echo   Cleaned Build directory
)

if exist "%RELEASE_DIR%" (
    rmdir /s /q "%RELEASE_DIR%" 2>nul
    timeout /t 1 /nobreak >nul
    echo   Cleaned Release directory
)

mkdir "%BUILD_DIR%" 2>nul
mkdir "%RELEASE_DIR%" 2>nul

echo.

REM Step 3: Copy game files
echo [3/7] Copying game files...
echo.

REM Copy executable
if exist "Game.exe" (
    copy /Y "Game.exe" "%BUILD_DIR%\%GAME_TITLE%.exe"
    echo   [OK] Copied game executable
)

REM Copy ALL DLL files
echo.
echo   Copying DLL files:
set DLL_COUNT=0
for %%D in (*.dll) do (
    copy /Y "%%D" "%BUILD_DIR%\"
    echo     - %%D
    set /a DLL_COUNT+=1
)
echo   [OK] Copied %DLL_COUNT% DLL files

echo.
echo   Copying game folders (this may take 1-3 minutes for large games^):

REM Copy Graphics
echo     - Graphics folder...
if exist "Graphics\" (
    xcopy /E /I /Y /Q "Graphics" "%BUILD_DIR%\Graphics"
    if exist "%BUILD_DIR%\Graphics\" (
        echo       [OK] Graphics folder copied
    ) else (
        echo       [FAIL] Graphics folder copy failed!
    )
) else (
    echo       [SKIP] Graphics folder not found
)

REM Copy Audio
echo     - Audio folder...
if exist "Audio\" (
    xcopy /E /I /Y /Q "Audio" "%BUILD_DIR%\Audio"
    if exist "%BUILD_DIR%\Audio\" (
        echo       [OK] Audio folder copied
    ) else (
        echo       [FAIL] Audio folder copy failed!
    )
) else (
    echo       [SKIP] Audio folder not found
)

REM Copy Data
echo     - Data folder...
if exist "Data\" (
    xcopy /E /I /Y /Q "Data" "%BUILD_DIR%\Data"
    if exist "%BUILD_DIR%\Data\" (
        echo       [OK] Data folder copied
    ) else (
        echo       [FAIL] Data folder copy failed!
        echo              This is critical - game won't work!
    )
) else (
    echo       [FAIL] Data folder not found!
)

REM Copy Fonts
echo     - Fonts folder...
if exist "Fonts\" (
    xcopy /E /I /Y /Q "Fonts" "%BUILD_DIR%\Fonts"
    if exist "%BUILD_DIR%\Fonts\" (
        echo       [OK] Fonts folder copied
    ) else (
        echo       [WARN] Fonts folder copy failed
    )
) else (
    echo       [SKIP] Fonts folder not found (optional^)
)

echo.

REM Copy config files
if exist "multiplayer_config.json" (
    copy /Y "multiplayer_config.json" "%BUILD_DIR%\"
    echo   [OK] Copied multiplayer config
)

echo.

REM Step 4: Create Game.ini
echo [4/7] Creating Game.ini...
echo.

REM Create Game.ini with proper format
(
echo [Game]
echo Library=RGSS104E.dll
echo Scripts=Data\Scripts.rxdata
echo Title=%GAME_TITLE%
echo RTP=
echo.
echo [Window]
echo FullScreen=0
echo ShowTitle=1
echo.
echo [Audio]
echo BGM=100
echo BGS=100
echo ME=100
echo SE=100
echo.
echo [Graphics]
echo FrameRate=40
echo VSync=1
echo SmoothMode=1
) > "%BUILD_DIR%\Game.ini"

if exist "%BUILD_DIR%\Game.ini" (
    echo   [OK] Game.ini created
    echo.
    echo   Verifying Game.ini contents:
    type "%BUILD_DIR%\Game.ini" | findstr /C:"Scripts="
) else (
    echo   [FAIL] Failed to create Game.ini!
)

echo.

REM Step 5: Verify critical files
echo [5/7] Verifying deployment...
echo.

set VERIFY_OK=1

if exist "%BUILD_DIR%\%GAME_TITLE%.exe" (
    echo   [OK] Game executable present
) else (
    echo   [FAIL] Game executable missing!
    set VERIFY_OK=0
)

if exist "%BUILD_DIR%\Game.ini" (
    echo   [OK] Game.ini present
) else (
    echo   [FAIL] Game.ini missing!
    set VERIFY_OK=0
)

if exist "%BUILD_DIR%\Data\Scripts.rxdata" (
    echo   [OK] Scripts.rxdata present
) else (
    echo   [FAIL] Scripts.rxdata missing!
    set VERIFY_OK=0
)

if exist "%BUILD_DIR%\RGSS104E.dll" (
    echo   [OK] RGSS104E.dll present
) else (
    echo   [FAIL] RGSS104E.dll missing!
    set VERIFY_OK=0
)

if exist "%BUILD_DIR%\Graphics\" (
    for /f %%i in ('dir /b /a-d "%BUILD_DIR%\Graphics" 2^>nul ^| find /c /v ""') do set GFX_COUNT=%%i
    echo   [OK] Graphics folder present (!GFX_COUNT! files^)
) else (
    echo   [WARN] Graphics folder missing
)

if exist "%BUILD_DIR%\Audio\" (
    for /f %%i in ('dir /b /a-d "%BUILD_DIR%\Audio" 2^>nul ^| find /c /v ""') do set AUD_COUNT=%%i
    echo   [OK] Audio folder present (!AUD_COUNT! files^)
) else (
    echo   [WARN] Audio folder missing
)

echo.

if %VERIFY_OK%==0 (
    echo [ERROR] Critical files are missing! Deployment may have failed.
    echo.
    echo Please check the error messages above.
    echo.
    pause
    exit /b 1
)

REM Step 6: Create player README
echo [6/7] Creating player instructions...
echo.

(
echo ===============================================================================
echo                      %GAME_TITLE%
echo                         Version %VERSION%
echo ===============================================================================
echo.
echo INSTALLATION:
echo 1. Extract all files to a folder on your computer
echo 2. Run "%GAME_TITLE%.exe" to start the game
echo.
echo MULTIPLAYER SETUP:
echo 1. The game will automatically connect to the server
echo 2. Create an account or log in with existing credentials
echo 3. Your progress is saved on the server
echo.
echo SYSTEM REQUIREMENTS:
echo - Windows 7 or higher
echo - 1GB RAM minimum
echo - 500MB free disk space
echo - Internet connection for multiplayer
echo.
echo CONTROLS:
echo - Arrow Keys: Move
echo - Z / Enter: Confirm / Interact
echo - X / Esc: Cancel / Menu
echo - C: Open Menu
echo - A: Toggle Following Pokemon ^(if available^)
echo - F5: Toggle Fullscreen
echo.
echo TROUBLESHOOTING:
echo - If game doesn't start, install Microsoft Visual C++ Redistributable:
echo   https://aka.ms/vs/17/release/vc_redist.x86.exe
echo - For connection issues, check multiplayer_config.json
echo - Make sure firewall allows the game to connect
echo.
echo ===============================================================================
echo                         Enjoy your adventure!
echo ===============================================================================
) > "%BUILD_DIR%\README.txt"

echo   [OK] README.txt created

echo.

REM Step 7: Create release package
echo [7/7] Creating release package...
echo.

set RELEASE_NAME=%GAME_TITLE:.= %_v%VERSION%_%TIMESTAMP%
set RELEASE_NAME=%RELEASE_NAME: =_%
set RELEASE_PATH=%RELEASE_DIR%\%RELEASE_NAME%

REM Copy build to release
echo   Copying to release folder...
xcopy /E /I /Y /Q "%BUILD_DIR%" "%RELEASE_PATH%"

if exist "%RELEASE_PATH%" (
    echo   [OK] Release folder created: %RELEASE_NAME%
) else (
    echo   [FAIL] Failed to create release folder!
    pause
    exit /b 1
)

REM Try to create ZIP using PowerShell
echo   Creating ZIP archive (this may take a minute^)...
powershell -Command "try { Compress-Archive -Path '%RELEASE_PATH%\*' -DestinationPath '%RELEASE_PATH%.zip' -CompressionLevel Optimal -ErrorAction Stop; Write-Host '   [OK] ZIP created successfully' } catch { Write-Host '   [FAIL] ZIP creation failed:' $_.Exception.Message }"

if exist "%RELEASE_PATH%.zip" (
    for %%A in ("%RELEASE_PATH%.zip") do set ZIP_SIZE=%%~zA
    set /a ZIP_SIZE_MB=!ZIP_SIZE! / 1048576
    echo   [OK] ZIP archive: %RELEASE_NAME%.zip ^(!ZIP_SIZE_MB!MB^)
) else (
    echo   [WARN] ZIP creation failed. Distribute the folder instead.
)

echo.

REM Calculate total size
if exist "%RELEASE_PATH%" (
    for /f "tokens=3" %%a in ('dir /s "%RELEASE_PATH%" 2^>nul ^| find "File(s)"') do set TOTAL_SIZE=%%a
    if defined TOTAL_SIZE (
        set TOTAL_SIZE=!TOTAL_SIZE:,=!
        set /a TOTAL_SIZE_MB=!TOTAL_SIZE! / 1048576
    )
)

echo.
echo ================================================================================
echo                       Deployment Completed Successfully!
echo ================================================================================
echo.
echo Release Information:
echo   Version:     %VERSION%
echo   Location:    %RELEASE_PATH%
if defined TOTAL_SIZE_MB (
    echo   Size:        ~!TOTAL_SIZE_MB!MB
)
echo.
echo Files Included:
echo   - %GAME_TITLE%.exe
echo   - Game.ini
echo   - Data\Scripts.rxdata
echo   - Graphics folder
echo   - Audio folder
echo   - All required DLLs
echo   - README.txt
echo.
echo Next Steps:
echo   1. TEST the game from: %RELEASE_PATH%\%GAME_TITLE%.exe
echo   2. Verify multiplayer connection works
echo   3. Distribute the ZIP file to players
echo   4. Update your download page/Discord
echo.
echo ================================================================================

REM Open release folder
echo.
set /p OPEN="Open release folder now? (Y/N): "
if /i "%OPEN%"=="Y" start "" explorer "%RELEASE_DIR%"

echo.
echo Press any key to exit...
pause >nul
