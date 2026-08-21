@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM Build Cronet Standalone for Windows (Batch Script)
REM Inspired by cronet-go (cmd/build-naive/cmd_build.go)
REM Compiles Cronet DLL without Golang
REM =============================================================================

set "ARCH=amd64"
set "USE_SCCACHE=1"
set "NINJA_JOBS="

:parse_args
if "%~1"=="" goto done_args

if /i "%~1"=="-j" (
    set "NINJA_JOBS=-j %~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--jobs" (
    set "NINJA_JOBS=-j %~2"
    shift
    shift
    goto parse_args
)
set "ARG_PREFIX=%~1"
if /i "%ARG_PREFIX:~0,2%"=="-j" (
    set "NINJA_JOBS=-j %ARG_PREFIX:~2%"
    shift
    goto parse_args
)
if /i "%~1"=="--no-sccache" (
    set "USE_SCCACHE=0"
    shift
    goto parse_args
)
if /i "%~1"=="amd64" (
    set "ARCH=amd64"
    shift
    goto parse_args
)
if /i "%~1"=="x64" (
    set "ARCH=amd64"
    shift
    goto parse_args
)
if /i "%~1"=="386" (
    set "ARCH=386"
    shift
    goto parse_args
)
if /i "%~1"=="x86" (
    set "ARCH=386"
    shift
    goto parse_args
)
if /i "%~1"=="arm64" (
    set "ARCH=arm64"
    shift
    goto parse_args
)

echo Unknown option or architecture: %~1
shift
goto parse_args

:done_args

set CPU=x64
if "%ARCH%"=="386" set CPU=x86
if "%ARCH%"=="arm64" set CPU=arm64
if "%ARCH%"=="amd64" set CPU=x64

echo ======================================================
echo  Compiling Cronet Windows (%ARCH% / %CPU%) without Go
if not "%NINJA_JOBS%"=="" echo  Parallel Jobs: %NINJA_JOBS%
echo ======================================================

set ROOT_DIR=%~dp0
set SRC_ROOT=%ROOT_DIR%naiveproxy\src
set OUT_DIR=out\cronet-win-%CPU%

if not exist "%SRC_ROOT%" (
    echo Error: %SRC_ROOT% not found.
    echo Please make sure submodules are initialized:
    echo git submodule update --init --recursive
    exit /b 1
)

REM Check ninja
where ninja >nul 2>nul
if errorlevel 1 (
    echo [!] ninja not found in PATH. Attempting to install via choco or ensure it exists...
    where choco >nul 2>nul
    if not errorlevel 1 (
        choco install ninja -y
    ) else (
        echo [ERROR] Please install ninja and add to PATH.
        exit /b 1
    )
)

REM Check sccache (optional)
if "%USE_SCCACHE%"=="1" (
    where sccache >nul 2>nul
    if not errorlevel 1 (
        echo [*] Ensuring sccache server is running...
        sccache --start-server >nul 2>nul
        sccache -z >nul 2>nul
        set "WRAPPER_FLAG=cc_wrapper=\"sccache\""
    ) else (
        set "WRAPPER_FLAG="
    )
) else (
    echo [*] sccache disabled.
    set "WRAPPER_FLAG="
)

REM Set GN Path
set "GN_EXE=%SRC_ROOT%\gn\out\gn.exe"
if not exist "%GN_EXE%" (
    where gn >nul 2>nul
    if not errorlevel 1 (
        set "GN_EXE=gn"
    ) else (
        echo [ERROR] gn.exe not found in %SRC_ROOT%\gn\out or PATH.
        exit /b 1
    )
)

REM Setup GN Arguments
set "GN_ARGS=is_official_build=true is_debug=false is_clang=true use_clang_modules=false use_thin_lto=false fatal_linker_warnings=false treat_warnings_as_errors=false is_cronet_build=true use_udev=false use_aura=false use_ozone=false use_gio=false use_glib=false use_kerberos=false disable_file_support=true enable_reporting=false enable_bracketed_proxy_uris=true enable_quic_proxy_support=true use_nss_certs=false enable_dangling_raw_ptr_checks=false exclude_unwind_tables=true enable_resource_allowlist_generation=false symbol_level=0 enable_dsyms=false optimize_for_size=true target_os=\"win\" target_cpu=\"%CPU%\" use_sysroot=false %WRAPPER_FLAG%"
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
echo [*] Generating build directory: %OUT_DIR%
pushd "%SRC_ROOT%"
"%GN_EXE%" gen "%OUT_DIR%" --args="%GN_ARGS%"
if errorlevel 1 (
    echo [ERROR] gn gen failed!
    popd
    exit /b 1
)

echo [*] Building cronet.dll via ninja...
ninja -C "%OUT_DIR%" %NINJA_JOBS% cronet
if errorlevel 1 (
    echo [ERROR] ninja build failed!
    popd
    exit /b 1
)
popd

echo [*] Packaging artifacts...
if not exist "%ROOT_DIR%include" mkdir "%ROOT_DIR%include"
if not exist "%ROOT_DIR%lib\windows_%ARCH%" mkdir "%ROOT_DIR%lib\windows_%ARCH%"

REM Copy headers
copy /y "%SRC_ROOT%\components\cronet\native\include\cronet_c.h" "%ROOT_DIR%include\" >nul 2>nul
copy /y "%SRC_ROOT%\components\cronet\native\include\cronet_export.h" "%ROOT_DIR%include\" >nul 2>nul
copy /y "%SRC_ROOT%\components\cronet\native\generated\cronet.idl_c.h" "%ROOT_DIR%include\" >nul 2>nul
copy /y "%SRC_ROOT%\components\grpc_support\include\bidirectional_stream_c.h" "%ROOT_DIR%include\" >nul 2>nul

REM Copy DLL
if exist "%SRC_ROOT%\%OUT_DIR%\cronet.dll" (
    copy /y "%SRC_ROOT%\%OUT_DIR%\cronet.dll" "%ROOT_DIR%lib\windows_%ARCH%\libcronet.dll"
    copy /y "%SRC_ROOT%\%OUT_DIR%\cronet.dll" "%ROOT_DIR%libcronet.dll"
    echo [*] Copied cronet.dll to:
    echo     - %ROOT_DIR%lib\windows_%ARCH%\libcronet.dll
    echo     - %ROOT_DIR%libcronet.dll
)

where sccache >nul 2>nul
if not errorlevel 1 (
    echo [*] sccache stats:
    sccache -s
)

echo ======================================================
echo  Build and Packaging Completed Successfully!
echo ======================================================
exit /b 0
