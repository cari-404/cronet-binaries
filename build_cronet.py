#!/usr/bin/env python3
"""
Cronet Standalone Build Script
Inspired by and referencing cronet-go (cmd/build-naive).
Compiles Cronet without requiring Go / Golang.
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

# Target definitions matching cmd/build-naive/cmd.go
TARGET_TABLE = [
    {"os": "linux", "cpu": "x64", "goos": "linux", "arch": "amd64"},
    {"os": "linux", "cpu": "arm64", "goos": "linux", "arch": "arm64"},
    {"os": "linux", "cpu": "x86", "goos": "linux", "arch": "386"},
    {"os": "linux", "cpu": "arm", "goos": "linux", "arch": "arm"},
    {"os": "linux", "cpu": "loong64", "goos": "linux", "arch": "loong64"},
    {"os": "linux", "cpu": "mipsel", "goos": "linux", "arch": "mipsle"},
    {"os": "linux", "cpu": "mips64el", "goos": "linux", "arch": "mips64le"},
    {"os": "linux", "cpu": "riscv64", "goos": "linux", "arch": "riscv64"},
    {"os": "mac", "cpu": "x64", "goos": "darwin", "arch": "amd64"},
    {"os": "mac", "cpu": "arm64", "goos": "darwin", "arch": "arm64"},
    {"os": "win", "cpu": "x64", "goos": "windows", "arch": "amd64"},
    {"os": "win", "cpu": "x86", "goos": "windows", "arch": "386"},
    {"os": "win", "cpu": "arm64", "goos": "windows", "arch": "arm64"},
    {"os": "ios", "cpu": "arm64", "goos": "ios", "arch": "arm64", "platform": "iphoneos", "environment": "device"},
    {"os": "ios", "cpu": "arm64", "goos": "ios", "arch": "arm64", "platform": "iphoneos", "environment": "simulator"},
    {"os": "ios", "cpu": "x64", "goos": "ios", "arch": "amd64", "platform": "iphoneos", "environment": "simulator"},
    {"os": "ios", "cpu": "arm64", "goos": "ios", "arch": "arm64", "platform": "tvos", "environment": "device"},
    {"os": "ios", "cpu": "arm64", "goos": "ios", "arch": "arm64", "platform": "tvos", "environment": "simulator"},
    {"os": "ios", "cpu": "x64", "goos": "ios", "arch": "amd64", "platform": "tvos", "environment": "simulator"},
    {"os": "android", "cpu": "arm64", "goos": "android", "arch": "arm64"},
    {"os": "android", "cpu": "x64", "goos": "android", "arch": "amd64"},
    {"os": "android", "cpu": "arm", "goos": "android", "arch": "arm"},
    {"os": "android", "cpu": "x86", "goos": "android", "arch": "386"},
]

OPENWRT_CONFIGS = {
    "x64": {"target": "x86", "subtarget": "64", "arch": "x86_64", "release": "23.05.5", "gcc_ver": "12.3.0", "extra_gn": []},
    "arm64": {"target": "armsr", "subtarget": "armv8", "arch": "aarch64", "release": "23.05.5", "gcc_ver": "12.3.0", "extra_gn": []},
    "x86": {"target": "x86", "subtarget": "generic", "arch": "i386_pentium4", "release": "23.05.5", "gcc_ver": "12.3.0", "extra_gn": []},
    "arm": {
        "target": "mvebu", "subtarget": "cortexa9", "arch": "arm_cortex-a9_vfpv3-d16", "release": "23.05.5", "gcc_ver": "12.3.0",
        "extra_gn": ['arm_arch="armv7-a"', 'arm_fpu="vfpv3-d16"', 'arm_float_abi="hard"', 'arm_use_neon=false']
    },
    "loong64": {"target": "loongarch64", "subtarget": "generic", "arch": "loongarch64", "release": "24.10.5", "gcc_ver": "13.3.0", "extra_gn": []},
    "mipsel": {
        "target": "ramips", "subtarget": "rt305x", "arch": "mipsel_24kc", "release": "23.05.5", "gcc_ver": "12.3.0",
        "extra_gn": ['mips_float_abi="soft"', 'mips_arch_variant="r2"']
    },
    "riscv64": {"target": "sifiveu", "subtarget": "generic", "arch": "riscv64", "release": "23.05.5", "gcc_ver": "12.3.0", "extra_gn": []},
}

SYSROOT_INFO = {
    "x64": ("amd64", "bullseye"),
    "arm64": ("arm64", "bullseye"),
    "x86": ("i386", "bullseye"),
    "arm": ("armhf", "bullseye"),
    "loong64": ("loong64", "sid"),
    "mipsel": ("mipsel", "bullseye"),
    "mips64el": ("mips64el", "bullseye"),
    "riscv64": ("riscv64", "trixie"),
}


def log(msg):
    print(f"[build] {msg}", flush=True)


def get_project_root():
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / "naiveproxy").exists() or (current / "go.mod").exists():
            return current
        current = current.parent
    return Path.cwd()


def get_host_target():
    sys_os = platform.system().lower()
    machine = platform.machine().lower()

    os_map = {"windows": "win", "linux": "linux", "darwin": "mac"}
    goos_map = {"windows": "windows", "linux": "linux", "darwin": "darwin"}
    cpu_map = {
        "x86_64": "x64", "amd64": "x64",
        "aarch64": "arm64", "arm64": "arm64",
        "i386": "x86", "i686": "x86", "x86": "x86",
        "armv7l": "arm", "arm": "arm"
    }

    target_os = os_map.get(sys_os, sys_os)
    target_goos = goos_map.get(sys_os, sys_os)
    target_cpu = cpu_map.get(machine, machine)

    for t in TARGET_TABLE:
        if t["os"] == target_os and t["cpu"] == target_cpu:
            return dict(t)

    # fallback
    return {"os": target_os, "cpu": target_cpu, "goos": target_goos, "arch": target_cpu}


def parse_targets(target_str, libc_str=""):
    if libc_str and libc_str not in ("glibc", "musl"):
        sys.exit(f"Invalid libc: {libc_str} (expected glibc or musl)")

    if not target_str:
        t = get_host_target()
        if libc_str == "musl" and t["goos"] == "linux":
            t["os"] = "openwrt"
            t["libc"] = "musl"
        return [t]

    if target_str == "all":
        results = []
        for t in TARGET_TABLE:
            entry = dict(t)
            if libc_str == "musl" and entry.get("goos") == "linux":
                entry["os"] = "openwrt"
                entry["libc"] = "musl"
            results.append(entry)
        return results

    results = []
    for part in target_str.split(","):
        part = part.strip()
        parts = part.split("/")
        goos = parts[0]
        goarch = parts[1] if len(parts) > 1 else ""

        if goos in ("ios", "tvos"):
            platform_val = "tvos" if goos == "tvos" else "iphoneos"
            env_val = "device"
            if len(parts) == 3 and parts[2] == "simulator":
                env_val = "simulator"
            elif goarch == "amd64":
                env_val = "simulator"

            matched = False
            for t in TARGET_TABLE:
                if (t.get("goos") == "ios" and t.get("arch") == goarch and
                        t.get("platform") == platform_val and t.get("environment") == env_val):
                    results.append(dict(t))
                    matched = True
                    break
            if not matched:
                sys.exit(f"Unsupported Apple target: {part}")
            continue

        matched = False
        for t in TARGET_TABLE:
            if t.get("goos") == goos and t.get("arch") == goarch and "platform" not in t:
                entry = dict(t)
                if libc_str == "musl" and entry.get("goos") == "linux":
                    entry["os"] = "openwrt"
                    entry["libc"] = "musl"
                results.append(entry)
                matched = True
                break
        if not matched:
            sys.exit(f"Unsupported target: {part}")

    return results


def get_sysroot_path(src_root, target):
    cpu = target["cpu"]
    if target.get("libc") == "musl":
        cfg = OPENWRT_CONFIGS.get(cpu, {})
        return src_root / "out" / "sysroot-build" / "openwrt" / cfg["release"] / cfg["arch"]
    if cpu in SYSROOT_INFO:
        arch, release = SYSROOT_INFO[cpu]
        return src_root / "out" / "sysroot-build" / release / f"{release}_{arch}_staging"
    return None


def get_output_dir(target):
    if target.get("platform"):
        out = f"out/cronet-{target['platform']}-{target['cpu']}"
        if target.get("environment") == "simulator":
            out += "-simulator"
        return out
    return f"out/cronet-{target['os']}-{target['cpu']}"


def format_target_log(target):
    if target.get("platform"):
        pname = "tvOS" if target["platform"] == "tvos" else "iOS"
        sim = " Simulator" if target.get("environment") == "simulator" else ""
        return f"{pname}{sim} {target['arch']}"
    if target.get("libc") == "musl":
        return f"{target.get('goos', target['os'])}/{target.get('arch', target['cpu'])} (musl)"
    return f"{target.get('goos', target['os'])}/{target.get('arch', target['cpu'])}"


def run_get_clang(src_root, target):
    host_os = platform.system().lower()
    host_arch = platform.machine().lower()
    host_cpu = "x64" if host_arch in ("x86_64", "amd64") else ("arm64" if host_arch in ("aarch64", "arm64") else "x86")

    # On Linux host cross-compiling, build host sysroot first
    needs_host_sysroot = (host_os == "linux" and target["os"] in ("linux", "android", "openwrt"))
    if needs_host_sysroot:
        host_flags = f'target_os="linux" target_cpu="{host_cpu}"'
        log(f"Running get-clang.sh for host sysroot with EXTRA_FLAGS={host_flags}")
        env = os.environ.copy()
        env["EXTRA_FLAGS"] = host_flags
        res = subprocess.run(["bash", "./get-clang.sh"], cwd=str(src_root), env=env)
        if res.returncode != 0:
            sys.exit(f"get-clang.sh (host) failed with code {res.returncode}")

        host_sysroot_src = get_sysroot_path(src_root, {"cpu": host_cpu})
        host_sysroot_dst = src_root / "build" / "linux" / "debian_bullseye_amd64-sysroot"
        if host_sysroot_src and not host_sysroot_dst.exists():
            log(f"Creating symlink for host sysroot: {host_sysroot_dst} -> {host_sysroot_src}")
            host_sysroot_dst.parent.mkdir(parents=True, exist_ok=True)
            try:
                host_sysroot_dst.symlink_to(host_sysroot_src)
            except Exception as e:
                log(f"Notice: symlink error: {e}")

    extra_flags = f'target_os="{target["os"]}" target_cpu="{target["cpu"]}"'
    env = os.environ.copy()
    env["EXTRA_FLAGS"] = extra_flags

    if target.get("os") == "openwrt" or target.get("libc") == "musl":
        cfg = OPENWRT_CONFIGS.get(target["cpu"])
        if cfg:
            openwrt_flags = (
                f'target="{cfg["target"]}" subtarget="{cfg["subtarget"]}" '
                f'arch="{cfg["arch"]}" release="{cfg["release"]}" gcc_ver="{cfg["gcc_ver"]}"'
            )
            env["OPENWRT_FLAGS"] = openwrt_flags
            log(f"Running get-clang.sh with EXTRA_FLAGS={extra_flags} OPENWRT_FLAGS={openwrt_flags}")
    else:
        log(f"Running get-clang.sh with EXTRA_FLAGS={extra_flags}")

    # Use bash if available, or sh
    shell_cmd = "bash" if shutil.which("bash") else "sh"
    if os.name == "nt":
        bash_path = shutil.which("bash")
        if not bash_path:
            git_bash = Path(r"C:\Program Files\Git\bin\bash.exe")
            if git_bash.exists():
                shell_cmd = str(git_bash)

    res = subprocess.run([shell_cmd, "./get-clang.sh"], cwd=str(src_root), env=env)
    if res.returncode != 0:
        sys.exit(f"get-clang.sh failed with code {res.returncode}")


def build_target(src_root, target, jobs=None, no_sccache=False):
    run_get_clang(src_root, target)

    out_dir = get_output_dir(target)

    args = [
        "is_official_build=true",
        "is_debug=false",
        "is_clang=true",
        "use_clang_modules=false",
        "use_thin_lto=false",
        "fatal_linker_warnings=false",
        "treat_warnings_as_errors=false",
        "is_cronet_build=true",
        "use_udev=false",
        "use_aura=false",
        "use_ozone=false",
        "use_gio=false",
        "use_glib=false",
        "use_kerberos=false",
        "disable_file_support=true",
        "enable_reporting=false",
        "enable_bracketed_proxy_uris=true",
        "enable_quic_proxy_support=true",
        "use_nss_certs=false",
        "enable_backup_ref_ptr_support=false",
        "enable_dangling_raw_ptr_checks=false",
        "exclude_unwind_tables=true",
        "enable_resource_allowlist_generation=false",
        "symbol_level=0",
        "enable_dsyms=false",
        "optimize_for_size=true",
        f'target_os="{target["os"]}"',
        f'target_cpu="{target["cpu"]}"',
    ]

    os_name = target["os"]
    if os_name == "mac":
        args.append("use_sysroot=false")
    elif os_name == "linux":
        sysroot_path = get_sysroot_path(src_root, target)
        if sysroot_path:
            rel_sysroot = sysroot_path.relative_to(src_root).as_posix()
            args.extend(["use_sysroot=true", f'target_sysroot="//{rel_sysroot}"'])
        if target["cpu"] == "x64":
            args.extend(["use_cfi_icall=false", "is_cfi=false"])
    elif os_name == "openwrt":
        cfg = OPENWRT_CONFIGS.get(target["cpu"], {})
        sysroot_dir = f"out/sysroot-build/openwrt/{cfg['release']}/{cfg['arch']}"
        args.extend([
            "use_sysroot=true",
            f'target_sysroot="//{sysroot_dir}"',
            "build_static=true",
            "use_allocator_shim=false",
            "use_partition_alloc=false",
        ])
        args.extend(cfg.get("extra_gn", []))
        if target["cpu"] == "x64":
            args.extend(["use_cfi_icall=false", "is_cfi=false"])
    elif os_name == "win":
        args.append("use_sysroot=false")
    elif os_name == "android":
        args.extend([
            "use_sysroot=false",
            "default_min_sdk_version=23",
        ])
    elif os_name == "ios":
        platform_val = target.get("platform", "iphoneos")
        env_val = target.get("environment", "device")
        args.extend([
            "use_sysroot=false",
            "ios_enable_code_signing=false",
            f'target_platform="{platform_val}"',
            f'target_environment="{env_val}"',
            'ios_deployment_target="15.0"',
            "enable_built_in_dns=true",
            "ios_partition_alloc_enabled=false",
        ])

    # Compiler wrapper (sccache / ccache)
    if not no_sccache:
        if platform.system().lower() == "windows":
            sccache = shutil.which("sccache")
            if sccache:
                # Ensure server is running
                subprocess.run(["sccache", "--start-server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                args.append(f'cc_wrapper="{sccache}"')
        else:
            ccache = shutil.which("ccache")
            if ccache:
                args.append(f'cc_wrapper="{ccache}"')

    gn_args_str = " ".join(args)

    # Find GN binary
    gn_bin = src_root / "gn" / "out" / ("gn.exe" if platform.system().lower() == "windows" else "gn")
    if not gn_bin.exists():
        sys.exit(f"GN binary not found at {gn_bin}")

    log(f"Running: {gn_bin.name} gen {out_dir}")
    env = os.environ.copy()
    if platform.system().lower() == "windows":
        env["DEPOT_TOOLS_WIN_TOOLCHAIN"] = "0"

    res = subprocess.run([str(gn_bin), "gen", out_dir, f"--args={gn_args_str}"], cwd=str(src_root), env=env)
    if res.returncode != 0:
        sys.exit(f"gn gen failed with code {res.returncode}")

    # Run ninja
    ninja_bin = shutil.which("ninja") or "ninja"
    ninja_cmd = [ninja_bin, "-C", out_dir]
    if jobs:
        ninja_cmd.extend(["-j", str(jobs)])

    if target["goos"] == "windows":
        log(f"Running: {' '.join(ninja_cmd)} cronet")
        res = subprocess.run(ninja_cmd + ["cronet"], cwd=str(src_root), env=env)
        if res.returncode != 0:
            sys.exit(f"ninja cronet failed with code {res.returncode}")
    else:
        log(f"Running: {' '.join(ninja_cmd)} cronet_static")
        res = subprocess.run(ninja_cmd + ["cronet_static"], cwd=str(src_root), env=env)
        if res.returncode != 0:
            sys.exit(f"ninja cronet_static failed with code {res.returncode}")

        if target["goos"] == "linux" and target.get("libc") != "musl":
            log(f"Running: {' '.join(ninja_cmd)} cronet")
            subprocess.run(ninja_cmd + ["cronet"], cwd=str(src_root), env=env)


def get_library_dir_name(target):
    if target.get("platform"):
        dir_name = f"{target['platform']}_{target['arch']}"
        if target.get("environment") == "simulator":
            dir_name += "_simulator"
        return dir_name
    if target.get("libc") == "musl":
        return f"linux_{target['arch']}_musl"
    return f"{target['goos']}_{target['arch']}"


def package_targets(project_root, src_root, targets):
    log(f"Packaging libraries for {len(targets)} target(s)")

    lib_dir = project_root / "lib"
    inc_dir = project_root / "include"

    inc_dir.mkdir(parents=True, exist_ok=True)

    headers = [
        (src_root / "components/cronet/native/include/cronet_c.h", "cronet_c.h"),
        (src_root / "components/cronet/native/include/cronet_export.h", "cronet_export.h"),
        (src_root / "components/cronet/native/generated/cronet.idl_c.h", "cronet.idl_c.h"),
        (src_root / "components/grpc_support/include/bidirectional_stream_c.h", "bidirectional_stream_c.h"),
    ]

    for src_h, dst_name in headers:
        if src_h.exists():
            shutil.copy2(src_h, inc_dir / dst_name)
            log(f"Copied header: {dst_name}")
        else:
            log(f"Warning: header not found: {src_h}")

    for t in targets:
        target_dir = lib_dir / get_library_dir_name(t)
        target_dir.mkdir(parents=True, exist_ok=True)

        out_dir = src_root / get_output_dir(t)

        if t["goos"] == "windows":
            src_dll = out_dir / "cronet.dll"
            dst_dll = target_dir / "libcronet.dll"
            if src_dll.exists():
                shutil.copy2(src_dll, dst_dll)
                shutil.copy2(src_dll, project_root / "libcronet.dll")
                log(f"Copied DLL for {t['goos']}/{t['arch']} -> {dst_dll}")
            else:
                log(f"Warning: DLL not found at {src_dll}")
        else:
            src_static = out_dir / "obj" / "components" / "cronet" / "libcronet_static.a"
            dst_static = target_dir / "libcronet.a"
            if src_static.exists():
                shutil.copy2(src_static, dst_static)
                log(f"Copied static library for {format_target_log(t)} -> {dst_static}")
            else:
                log(f"Warning: static library not found at {src_static}")

            if t["goos"] == "linux" and t.get("libc") != "musl":
                src_so = out_dir / "libcronet.so"
                dst_so = target_dir / "libcronet.so"
                if src_so.exists():
                    shutil.copy2(src_so, dst_so)
                    log(f"Copied shared library for {format_target_log(t)} -> {dst_so}")


def main():
    parser = argparse.ArgumentParser(description="Build Cronet standalone without Go")
    parser.add_argument("action", choices=["build", "package", "download-toolchain", "all"], default="all", nargs="?",
                        help="Action to perform (default: all)")
    parser.add_argument("-t", "--target", default="",
                        help="Comma-separated target list (e.g. windows/amd64, linux/amd64). Empty means host platform.")
    parser.add_argument("-j", "--jobs", type=int, default=None,
                        help="Number of concurrent compilation jobs for ninja (e.g. -j 8)")
    parser.add_argument("--no-sccache", action="store_true", default=False,
                        help="Disable sccache / compiler cache wrapper")
    parser.add_argument("--libc", default="", choices=["", "glibc", "musl"],
                        help="C library for Linux: glibc (default) or musl")

    args = parser.parse_args()

    project_root = get_project_root()
    src_root = project_root / "naiveproxy" / "src"

    if not src_root.exists():
        sys.exit(f"Error: naiveproxy/src directory not found at {src_root}")

    targets = parse_targets(args.target, args.libc)

    log(f"Selected action: {args.action}")
    log(f"Target count: {len(targets)}")
    if args.jobs:
        log(f"Ninja parallel jobs: {args.jobs}")

    if args.action in ("download-toolchain",):
        for t in targets:
            log(f"Downloading toolchain for {format_target_log(t)}...")
            run_get_clang(src_root, t)
        log("Toolchain download complete!")
        return

    if args.action in ("build", "all"):
        for t in targets:
            log(f"Building {format_target_log(t)}...")
            build_target(src_root, t, jobs=args.jobs, no_sccache=args.no_sccache)
        log("Build complete!")

    if args.action in ("package", "all"):
        package_targets(project_root, src_root, targets)
        log("Packaging complete!")


if __name__ == "__main__":
    main()
