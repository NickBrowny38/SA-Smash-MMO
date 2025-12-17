@echo off
REM ============================================================================
REM Find and list all DLL files in the game directory
REM ============================================================================

echo ================================================================================
echo                    DLL Finder - Pokemon FRLG Multiplayer
echo ================================================================================
echo.
echo Scanning for DLL files in the game directory...
echo.

set DLL_COUNT=0

for %%D in (*.dll) do (
    set /a DLL_COUNT+=1
    echo   [!DLL_COUNT!] %%D
)

echo.
echo ================================================================================
echo Found %DLL_COUNT% DLL files
echo ================================================================================
echo.

if %DLL_COUNT%==0 (
    echo [WARNING] No DLL files found!
    echo.
    echo Your game needs DLL files to run. These are usually:
    echo   - RGSS104E.dll ^(or RGSS102E.dll, RGSS300.dll^)
    echo   - zlib1.dll
    echo   - x64-msvcrt-ruby310.dll ^(or similar Ruby DLL^)
    echo.
    echo Make sure you have:
    echo   1. RPG Maker XP properly installed
    echo   2. Run the game at least once from RPG Maker XP
    echo   3. All DLLs are in the game folder
    echo.
) else (
    echo These DLL files will be copied to your release package.
    echo.
)

echo Press any key to exit...
pause >nul
