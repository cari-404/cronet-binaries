#!/usr/bin/env bash
# =============================================================================
# Build Cronet Standalone (Bash script - Linux / macOS)
# Inspired by cronet-go (cmd/build-naive)
# Compiles Cronet without Golang
# =============================================================================

set -e

# Default settings
TARGET_OS=""
TARGET_CPU=""
LIBC=""
ACTION="all"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$ROOT_DIR/naiveproxy/src"

show_help() {
    echo "Usage: $0 [options] [action]"
    echo ""
    echo "Actions:"
    echo "  all                 Build and package (default)"
    echo "  build               Build cronet library"
    echo "  package             Copy libraries and headers to lib/ and include/"
    echo "  download-toolchain  Download clang/sysroot only"
    echo ""
    echo "Options:"
    echo "  -o, --os <os>       Target OS (linux, mac, win, ios, android, openwrt)"
    echo "  -c, --cpu <cpu>     Target CPU (x64, arm64, x86, arm, loong64, mipsel, mips64el, riscv64)"
    echo "  -t, --target <tgt>  Target in os/arch format (e.g., linux/amd64, darwin/arm64)"
    echo "  --libc <libc>       C library for Linux: glibc (default) or musl"
    echo "  -h, --help          Show this help"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--os)
            TARGET_OS="$2"; shift 2 ;;
        -c|--cpu)
            TARGET_CPU="$2"; shift 2 ;;
        -t|--target)
            TARGET_STR="$2"; shift 2
            IFS='/' read -r TARGET_GOOS TARGET_GOARCH TARGET_EXTRA <<< "$TARGET_STR"
            case "$TARGET_GOOS" in
                linux) TARGET_OS="linux" ;;
                darwin|mac) TARGET_OS="mac" ;;
                windows|win) TARGET_OS="win" ;;
                ios) TARGET_OS="ios" ;;
                android) TARGET_OS="android" ;;
                openwrt) TARGET_OS="openwrt" ;;
                *) TARGET_OS="$TARGET_GOOS" ;;
            esac
            case "$TARGET_GOARCH" in
                amd64) TARGET_CPU="x64" ;;
                arm64) TARGET_CPU="arm64" ;;
                386|x86) TARGET_CPU="x86" ;;
                arm) TARGET_CPU="arm" ;;
                loong64) TARGET_CPU="loong64" ;;
                mipsle|mipsel) TARGET_CPU="mipsel" ;;
                mips64le|mips64el) TARGET_CPU="mips64el" ;;
                riscv64) TARGET_CPU="riscv64" ;;
                *) TARGET_CPU="$TARGET_GOARCH" ;;
            esac
            ;;
        -j|--jobs)
            NINJA_JOBS="-j $2"; shift 2 ;;
        --no-sccache)
            NO_SCCACHE=1; shift ;;
        --libc)
            LIBC="$2"; shift 2 ;;
        build|package|download-toolchain|all)
            ACTION="$1"; shift ;;
        -h|--help)
            show_help ;;
        *)
            echo "Unknown argument: $1"
            show_help ;;
    esac
done

# Auto-detect host OS and CPU if not specified
if [ -z "$TARGET_OS" ]; then
    UNAME_S="$(uname -s)"
    case "$UNAME_S" in
        Linux*)   TARGET_OS="linux" ;;
        Darwin*)  TARGET_OS="mac" ;;
        CYGWIN*|MINGW*|MSYS*) TARGET_OS="win" ;;
        *) TARGET_OS="linux" ;;
    esac
fi

if [ -z "$TARGET_CPU" ]; then
    UNAME_M="$(uname -m)"
    case "$UNAME_M" in
        x86_64|amd64)   TARGET_CPU="x64" ;;
        aarch64|arm64)  TARGET_CPU="arm64" ;;
        i386|i686)      TARGET_CPU="x86" ;;
        armv7l|arm)     TARGET_CPU="arm" ;;
        loongarch64)    TARGET_CPU="loong64" ;;
        mips64el)       TARGET_CPU="mips64el" ;;
        mipsel)         TARGET_CPU="mipsel" ;;
        riscv64)        TARGET_CPU="riscv64" ;;
        *)              TARGET_CPU="x64" ;;
    esac
fi

if [ "$LIBC" = "musl" ] && [ "$TARGET_OS" = "linux" ]; then
    TARGET_OS="openwrt"
fi

echo "[build] Configuration:"
echo "[build]   Target OS : $TARGET_OS"
echo "[build]   Target CPU: $TARGET_CPU"
echo "[build]   Action    : $ACTION"
if [ -n "$LIBC" ]; then
    echo "[build]   Libc      : $LIBC"
fi

if [ ! -d "$SRC_ROOT" ]; then
    echo "Error: $SRC_ROOT does not exist. Did you clone submodules?"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

OUT_DIR="out/cronet-$TARGET_OS-$TARGET_CPU"

# Run get-clang.sh / toolchain download
download_toolchain() {
    echo "[build] Preparing toolchain & sysroot..."
    pushd "$SRC_ROOT" > /dev/null

    EXTRA_FLAGS="target_os=\"$TARGET_OS\" target_cpu=\"$TARGET_CPU\""
    
    if [ "$TARGET_OS" = "openwrt" ]; then
        case "$TARGET_CPU" in
            x64)     OPENWRT_FLAGS='target="x86" subtarget="64" arch="x86_64" release="23.05.5" gcc_ver="12.3.0"' ;;
            arm64)   OPENWRT_FLAGS='target="armsr" subtarget="armv8" arch="aarch64" release="23.05.5" gcc_ver="12.3.0"' ;;
            x86)     OPENWRT_FLAGS='target="x86" subtarget="generic" arch="i386_pentium4" release="23.05.5" gcc_ver="12.3.0"' ;;
            arm)     OPENWRT_FLAGS='target="mvebu" subtarget="cortexa9" arch="arm_cortex-a9_vfpv3-d16" release="23.05.5" gcc_ver="12.3.0"' ;;
            loong64) OPENWRT_FLAGS='target="loongarch64" subtarget="generic" arch="loongarch64" release="24.10.5" gcc_ver="13.3.0"' ;;
            mipsel)  OPENWRT_FLAGS='target="ramips" subtarget="rt305x" arch="mipsel_24kc" release="23.05.5" gcc_ver="12.3.0"' ;;
            riscv64) OPENWRT_FLAGS='target="sifiveu" subtarget="generic" arch="riscv64" release="23.05.5" gcc_ver="12.3.0"' ;;
        esac
        EXTRA_FLAGS="$EXTRA_FLAGS" OPENWRT_FLAGS="$OPENWRT_FLAGS" bash ./get-clang.sh
    else
        EXTRA_FLAGS="$EXTRA_FLAGS" bash ./get-clang.sh
    fi
    popd > /dev/null
}

# Build cronet
build_cronet() {
    download_toolchain

    echo "[build] Generating GN build configuration..."
    pushd "$SRC_ROOT" > /dev/null

    GN_ARGS="is_official_build=true is_debug=false is_clang=true use_clang_modules=false use_thin_lto=false \
fatal_linker_warnings=false treat_warnings_as_errors=false is_cronet_build=true \
use_udev=false use_aura=false use_ozone=false use_gio=false use_glib=false use_kerberos=false \
disable_file_support=true enable_reporting=false enable_bracketed_proxy_uris=true enable_quic_proxy_support=true \
use_nss_certs=false enable_dangling_raw_ptr_checks=false \
exclude_unwind_tables=true enable_resource_allowlist_generation=false symbol_level=0 enable_dsyms=false optimize_for_size=true \
target_os=\"$TARGET_OS\" target_cpu=\"$TARGET_CPU\""

    case "$TARGET_OS" in
        mac)
            GN_ARGS="$GN_ARGS use_sysroot=false"
            ;;
        win)
            GN_ARGS="$GN_ARGS use_sysroot=false"
            ;;
        android)
            GN_ARGS="$GN_ARGS use_sysroot=false default_min_sdk_version=23"
            ;;
        ios)
            GN_ARGS="$GN_ARGS use_sysroot=false ios_enable_code_signing=false target_platform=\"iphoneos\" target_environment=\"device\" ios_deployment_target=\"15.0\" enable_built_in_dns=true ios_partition_alloc_enabled=false"
            ;;
        linux)
            case "$TARGET_CPU" in
                x64)      SYSROOT_DIR="out/sysroot-build/bullseye/bullseye_amd64_staging" ;;
                arm64)    SYSROOT_DIR="out/sysroot-build/bullseye/bullseye_arm64_staging" ;;
                x86)      SYSROOT_DIR="out/sysroot-build/bullseye/bullseye_i386_staging" ;;
                arm)      SYSROOT_DIR="out/sysroot-build/bullseye/bullseye_armhf_staging" ;;
                loong64)  SYSROOT_DIR="out/sysroot-build/sid/sid_loong64_staging" ;;
                mipsel)   SYSROOT_DIR="out/sysroot-build/bullseye/bullseye_mipsel_staging" ;;
                mips64el) SYSROOT_DIR="out/sysroot-build/bullseye/bullseye_mips64el_staging" ;;
                riscv64)  SYSROOT_DIR="out/sysroot-build/trixie/trixie_riscv64_staging" ;;
            esac
            GN_ARGS="$GN_ARGS use_sysroot=true target_sysroot=\"//$SYSROOT_DIR\""
            if [ "$TARGET_CPU" = "x64" ]; then
                GN_ARGS="$GN_ARGS use_cfi_icall=false is_cfi=false"
            fi
            ;;
        openwrt)
            case "$TARGET_CPU" in
                x64)     OW_REL="23.05.5"; OW_ARCH="x86_64" ;;
                arm64)   OW_REL="23.05.5"; OW_ARCH="aarch64" ;;
                x86)     OW_REL="23.05.5"; OW_ARCH="i386_pentium4" ;;
                arm)     OW_REL="23.05.5"; OW_ARCH="arm_cortex-a9_vfpv3-d16"; GN_ARGS="$GN_ARGS arm_arch=\"armv7-a\" arm_fpu=\"vfpv3-d16\" arm_float_abi=\"hard\" arm_use_neon=false" ;;
                loong64) OW_REL="24.10.5"; OW_ARCH="loongarch64" ;;
                mipsel)  OW_REL="23.05.5"; OW_ARCH="mipsel_24kc"; GN_ARGS="$GN_ARGS mips_float_abi=\"soft\" mips_arch_variant=\"r2\"" ;;
                riscv64) OW_REL="23.05.5"; OW_ARCH="riscv64" ;;
            esac
            GN_ARGS="$GN_ARGS use_sysroot=true target_sysroot=\"//out/sysroot-build/openwrt/$OW_REL/$OW_ARCH\" build_static=true use_allocator_shim=false use_partition_alloc=false"
            if [ "$TARGET_CPU" = "x64" ]; then
                GN_ARGS="$GN_ARGS use_cfi_icall=false is_cfi=false"
            fi
            ;;
    esac

    # Wrapper (ccache / sccache)
    if command -v ccache &> /dev/null; then
        GN_ARGS="$GN_ARGS cc_wrapper=\"$(command -v ccache)\""
    elif command -v sccache &> /dev/null; then
        GN_ARGS="$GN_ARGS cc_wrapper=\"$(command -v sccache)\""
    fi

    # Run GN
    GN_BIN="./gn/out/gn"
    if [ ! -f "$GN_BIN" ]; then
        GN_BIN="gn"
    fi

    echo "[build] Running: $GN_BIN gen $OUT_DIR"
    $GN_BIN gen "$OUT_DIR" --args="$GN_ARGS"

    # Run Ninja
    if [ "$TARGET_OS" = "win" ]; then
        echo "[build] Running: ninja -C $OUT_DIR $NINJA_JOBS cronet"
        ninja -C "$OUT_DIR" $NINJA_JOBS cronet
    else
        echo "[build] Running: ninja -C $OUT_DIR $NINJA_JOBS cronet_static"
        ninja -C "$OUT_DIR" $NINJA_JOBS cronet_static

        if [ "$TARGET_OS" = "linux" ] && [ "$LIBC" != "musl" ]; then
            echo "[build] Running: ninja -C $OUT_DIR $NINJA_JOBS cronet"
            ninja -C "$OUT_DIR" $NINJA_JOBS cronet
        fi
    fi

    popd > /dev/null
    echo "[build] Build successful!"
}

# Package libraries and headers
package_cronet() {
    echo "[build] Packaging artifacts..."
    
    mkdir -p "$ROOT_DIR/include"
    
    # Headers
    cp -f "$SRC_ROOT/components/cronet/native/include/cronet_c.h" "$ROOT_DIR/include/" 2>/dev/null || true
    cp -f "$SRC_ROOT/components/cronet/native/include/cronet_export.h" "$ROOT_DIR/include/" 2>/dev/null || true
    cp -f "$SRC_ROOT/components/cronet/native/generated/cronet.idl_c.h" "$ROOT_DIR/include/" 2>/dev/null || true
    cp -f "$SRC_ROOT/components/grpc_support/include/bidirectional_stream_c.h" "$ROOT_DIR/include/" 2>/dev/null || true
    echo "[build] Copied headers to $ROOT_DIR/include/"

    # Lib directory name mapping
    ARCH_NAME="$TARGET_CPU"
    case "$TARGET_CPU" in
        x64) ARCH_NAME="amd64" ;;
        x86) ARCH_NAME="386" ;;
        mipsel) ARCH_NAME="mipsle" ;;
        mips64el) ARCH_NAME="mips64le" ;;
    esac

    OS_NAME="$TARGET_OS"
    case "$TARGET_OS" in
        mac) OS_NAME="darwin" ;;
        win) OS_NAME="windows" ;;
    esac

    LIB_TARGET_DIR="$ROOT_DIR/lib/${OS_NAME}_${ARCH_NAME}"
    if [ "$TARGET_OS" = "openwrt" ] || [ "$LIBC" = "musl" ]; then
        LIB_TARGET_DIR="${LIB_TARGET_DIR}_musl"
    fi
    mkdir -p "$LIB_TARGET_DIR"

    if [ "$TARGET_OS" = "win" ]; then
        if [ -f "$SRC_ROOT/$OUT_DIR/cronet.dll" ]; then
            cp -f "$SRC_ROOT/$OUT_DIR/cronet.dll" "$LIB_TARGET_DIR/libcronet.dll"
            cp -f "$SRC_ROOT/$OUT_DIR/cronet.dll" "$ROOT_DIR/libcronet.dll"
            echo "[build] Copied DLL to $LIB_TARGET_DIR/libcronet.dll and $ROOT_DIR/libcronet.dll"
        fi
    else
        if [ -f "$SRC_ROOT/$OUT_DIR/obj/components/cronet/libcronet_static.a" ]; then
            cp -f "$SRC_ROOT/$OUT_DIR/obj/components/cronet/libcronet_static.a" "$LIB_TARGET_DIR/libcronet.a"
            echo "[build] Copied static library to $LIB_TARGET_DIR/libcronet.a"
        fi
        if [ -f "$SRC_ROOT/$OUT_DIR/libcronet.so" ]; then
            cp -f "$SRC_ROOT/$OUT_DIR/libcronet.so" "$LIB_TARGET_DIR/libcronet.so"
            echo "[build] Copied shared library to $LIB_TARGET_DIR/libcronet.so"
        fi
    fi

    echo "[build] Packaging complete!"
}

# Main execution flow
case "$ACTION" in
    download-toolchain)
        download_toolchain
        ;;
    build)
        build_cronet
        ;;
    package)
        package_cronet
        ;;
    all)
        build_cronet
        package_cronet
        ;;
esac
