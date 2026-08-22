@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =============================================================================
REM Package Cronet artifacts for Windows
REM Usage:
REM   package_cronet.bat --target windows/amd64
REM   package_cronet.bat --target windows/386
REM   package_cronet.bat --target windows/arm64
REM =============================================================================

set "ROOT_DIR=%~dp0"
set "SRC_ROOT=%ROOT_DIR%naiveproxy\src"

set "ARCH="
set "CPU="

REM ---------------------------------------------------------------------------
REM Parse arguments
REM ---------------------------------------------------------------------------
:parse_args

if "%~1"=="" goto validate

if /i "%~1"=="--target" (
    if "%~2"=="" (
        echo [ERROR] --target requires a value.
        exit /b 1
    )

    call :parse_target "%~2"
    if errorlevel 1 exit /b 1

    shift
    shift
    goto parse_args
)

echo [ERROR] Unknown argument: %~1
exit /b 1


REM ---------------------------------------------------------------------------
REM Parse target
REM ---------------------------------------------------------------------------
:parse_target

set "TARGET=%~1"
set "TARGET_OS="
set "TARGET_ARCH="

for /f "tokens=1,2 delims=/" %%A in ("%TARGET%") do (
    set "TARGET_OS=%%A"
    set "TARGET_ARCH=%%B"
)

if /i not "%TARGET_OS%"=="windows" (
    echo [ERROR] Unsupported target: %~1
    echo         Supported target format:
    echo         windows/amd64
    echo         windows/386
    echo         windows/arm64
    exit /b 1
)

if /i "%TARGET_ARCH%"=="amd64" (
    set "ARCH=amd64"
    set "CPU=x64"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="x64" (
    set "ARCH=amd64"
    set "CPU=x64"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="386" (
    set "ARCH=386"
    set "CPU=x86"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="x86" (
    set "ARCH=386"
    set "CPU=x86"
    exit /b 0
)

if /i "%TARGET_ARCH%"=="arm64" (
    set "ARCH=arm64"
    set "CPU=arm64"
    exit /b 0
)

echo [ERROR] Unsupported Windows architecture: %TARGET_ARCH%
exit /b 1


REM ---------------------------------------------------------------------------
REM Validate
REM ---------------------------------------------------------------------------
:validate

if not defined ARCH (
    echo [ERROR] Target is required.
    echo Example:
    echo   package_cronet.bat --target windows/amd64
    exit /b 1
)

if not exist "%SRC_ROOT%" (
    echo [ERROR] Chromium source directory not found:
    echo         %SRC_ROOT%
    exit /b 1
)

set "OUT_DIR=%SRC_ROOT%\out\cronet-win-%CPU%"
set "PACKAGE_DIR=%ROOT_DIR%lib\windows_%ARCH%"
set "INCLUDE_DIR=%ROOT_DIR%include"

echo ======================================================
echo  Packaging Cronet Windows
echo  Architecture : %ARCH%
echo  CPU          : %CPU%
echo  Build dir    : %OUT_DIR%
echo  Package dir  : %PACKAGE_DIR%
echo ======================================================


REM ---------------------------------------------------------------------------
REM Check build output
REM ---------------------------------------------------------------------------
if not exist "%OUT_DIR%" (
    echo [ERROR] Build output directory not found:
    echo         %OUT_DIR%
    echo.
    echo Please run build_cronet.bat first.
    exit /b 1
)

if not exist "%OUT_DIR%\cronet.dll" (
    echo [ERROR] cronet.dll not found:
    echo         %OUT_DIR%\cronet.dll
    echo.
    echo The build may not have completed successfully.
    exit /b 1
)


REM ---------------------------------------------------------------------------
REM Create directories
REM ---------------------------------------------------------------------------
if not exist "%INCLUDE_DIR%" mkdir "%INCLUDE_DIR%"
if errorlevel 1 (
    echo [ERROR] Failed to create:
    echo         %INCLUDE_DIR%
    exit /b 1
)

if not exist "%PACKAGE_DIR%" mkdir "%PACKAGE_DIR%"
if errorlevel 1 (
    echo [ERROR] Failed to create:
    echo         %PACKAGE_DIR%
    exit /b 1
)


REM ---------------------------------------------------------------------------
REM Copy headers
REM ---------------------------------------------------------------------------
echo.
echo [*] Copying headers...

call :copy_required ^
    "%SRC_ROOT%\components\cronet\native\include\cronet_c.h" ^
    "%INCLUDE_DIR%\cronet_c.h"
if errorlevel 1 exit /b 1

call :copy_required ^
    "%SRC_ROOT%\components\cronet\native\include\cronet_export.h" ^
    "%INCLUDE_DIR%\cronet_export.h"
if errorlevel 1 exit /b 1

call :copy_required ^
    "%SRC_ROOT%\components\cronet\native\generated\cronet.idl_c.h" ^
    "%INCLUDE_DIR%\cronet.idl_c.h"
if errorlevel 1 exit /b 1

call :copy_required ^
    "%SRC_ROOT%\components\grpc_support\include\bidirectional_stream_c.h" ^
    "%INCLUDE_DIR%\bidirectional_stream_c.h"
if errorlevel 1 exit /b 1


REM ---------------------------------------------------------------------------
REM Copy main DLL
REM ---------------------------------------------------------------------------
echo.
echo [*] Copying cronet.dll...

call :copy_required ^
    "%OUT_DIR%\cronet.dll" ^
    "%PACKAGE_DIR%\cronet.dll"
if errorlevel 1 exit /b 1


REM ---------------------------------------------------------------------------
REM Copy other artifacts
REM ---------------------------------------------------------------------------
echo.
echo [*] Copying libraries/debug files...

set "FOUND_LIB=0"
set "FOUND_PDB=0"

for /r "%OUT_DIR%" %%F in (*.lib) do (
    echo       %%~nxF
    copy /y "%%~fF" "%PACKAGE_DIR%\%%~nxF" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy:
        echo         %%~fF
        exit /b 1
    )
    set "FOUND_LIB=1"
)

for /r "%OUT_DIR%" %%F in (*.pdb) do (
    echo       %%~nxF
    copy /y "%%~fF" "%PACKAGE_DIR%\%%~nxF" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy:
        echo         %%~fF
        exit /b 1
    )
    set "FOUND_PDB=1"
)


REM ---------------------------------------------------------------------------
REM Result
REM ---------------------------------------------------------------------------
echo.
echo ======================================================
echo  Packaging Completed Successfully!
echo ======================================================
echo.
echo Include:
echo   %INCLUDE_DIR%
echo.
echo Libraries:
echo   %PACKAGE_DIR%
echo.
echo   cronet.dll
if "%FOUND_LIB%"=="1" echo   *.lib
if "%FOUND_PDB%"=="1" echo   *.pdb
echo.

exit /b 0


REM ---------------------------------------------------------------------------
REM Copy required file
REM ---------------------------------------------------------------------------
:copy_required

if not exist "%~1" (
    echo [ERROR] Required file not found:
    echo         %~1
    exit /b 1
)

echo       %~nx1

copy /y "%~1" "%~2" >nul

if errorlevel 1 (
    echo [ERROR] Failed to copy:
    echo         %~1
    exit /b 1
)

exit /b 0