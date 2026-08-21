import argparse
import tarfile
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--archive", required=True)
parser.add_argument("--libdir", required=True)
args = parser.parse_args()

allowed = {
    ".h",
    ".a",
    ".so",
    ".dylib",
    ".dll",
    ".lib",
    ".pdb",
}

files = []

for base in (Path("include"), Path("lib") / args.libdir):
    if not base.exists():
        continue

    for path in base.rglob("*"):
        if path.is_file() and path.suffix.lower() in allowed:
            files.append(path)

if not files:
    raise RuntimeError("No release files found")

if args.archive.endswith(".zip"):
    with zipfile.ZipFile(
        args.archive,
        "w",
        compression=zipfile.ZIP_DEFLATED,
    ) as z:
        for path in files:
            z.write(path, arcname=path.as_posix())
else:
    with tarfile.open(args.archive, "w:xz") as t:
        for path in files:
            t.add(path, arcname=path.as_posix())

print(f"Created {args.archive} ({len(files)} files)")