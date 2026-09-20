#!/usr/bin/env python3
"""Package a local AtomZero release for the current platform.

Mirrors the GitHub Actions `release` job:
  1. runs the functional test suite with the 100% coverage gate
     (tools/run_tests.py --cov-fail-under 100),
  2. regenerates export_presets.cfg inside a throwaway copy (so the
     committed file is never touched),
  3. exports the game for the current platform with the installed
     Godot editor,
  4. packages the artifact(s) into dist/ with the CI naming scheme.

The export runs in a temp copy of the project, so the working tree stays
clean after a run.

Examples:
  python3 tools/release.py                       # run tests + package current platform
  python3 tools/release.py --dry-run             # print the plan without building
  python3 tools/release.py --version 2026.9.0    # explicit version (default from project.godot)
  python3 tools/release.py --platform Windows    # cross-export another platform
  python3 tools/release.py --skip-tests          # skip the suite + coverage gate
  python3 tools/release.py --out build/release   # custom output directory
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tools.run_tests import IGNORE_PATTERNS, godot_binary  # noqa: E402

# platform label -> (export preset name, artifact stem, exported filename suffix)
PLATFORM_PRESETS = {
    "macos": ("macOS", "macos", ".app"),
    "linux": ("Linux", "linux", ".x86_64"),
    "windows": ("Windows Desktop", "windows", ".exe"),
}
_SYS_TO_LABEL = {"darwin": "macos", "linux": "linux", "win32": "windows"}


def version_from_project(root: Path) -> str:
    for line in (root / "project.godot").read_text(encoding="utf-8").splitlines():
        m = re.match(r'^config/version="([^"]+)"', line.strip())
        if m:
            return m.group(1)
    sys.exit("release: could not read config/version from project.godot")


def _zip_bundle(bundle: Path, out_zip: Path) -> None:
    if shutil.which("ditto"):
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", str(bundle), str(out_zip)],
                       check=True)
    else:
        shutil.make_archive(str(out_zip.with_suffix("")), "zip", bundle.parent, bundle.name)


def package(godot: str, staging: Path, preset: str, out_dir: Path,
            version: str, stem: str, suffix: str) -> list[str]:
    dist = out_dir / "dist"
    dist.mkdir(parents=True, exist_ok=True)
    export_path = dist / f"AtomZero{suffix}"
    subprocess.run([godot, "--headless", "--path", str(staging), "--import", "--quit"],
                   check=True, capture_output=True)
    subprocess.run([godot, "--headless", "--path", str(staging),
                    "--export-release", preset, str(export_path)],
                   check=True)
    if not (export_path.exists() or (suffix == ".app" and export_path.is_dir())):
        sys.exit(f"release: export produced no artifact at {export_path}")

    artifacts = []
    if suffix == ".app":
        out_zip = out_dir / f"AtomZero-{version}-{stem}.zip"
        _zip_bundle(export_path, out_zip)
        artifacts.append(str(out_zip))
    elif stem == "linux":
        out_zip = out_dir / f"AtomZero-{version}-linux.zip"
        shutil.make_archive(str(out_zip.with_suffix("")), "zip", dist, export_path.name)
        artifacts.append(str(out_zip))
        if shutil.which("dpkg-deb"):
            subprocess.run(["bash", str(ROOT / "tools" / "ci" / "package_linux.sh"),
                            "deb", version, str(export_path), str(ROOT)], check=True)
            deb = ROOT / "dist" / f"AtomZero-{version}-linux.deb"
            if deb.exists():
                artifacts.append(str(deb))
    elif stem == "windows":
        out_zip = out_dir / f"AtomZero-{version}-windows.zip"
        files = sorted(dist.glob("AtomZero*"))
        if not files:
            sys.exit("release: no exports found for Windows packaging")
        shutil.make_archive(str(out_zip.with_suffix("")), "zip", dist,
                            [p.name for p in files])
        artifacts.append(str(out_zip))
    else:
        sys.exit(f"release: unsupported platform {stem!r}")
    return artifacts


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", default="",
                    help="game version (default: project.godot config/version)")
    ap.add_argument("--platform", default="",
                    help="export platform label: macOS | Linux | Windows (default: current OS)")
    ap.add_argument("--out", default=str(ROOT),
                    help="output directory (default: project root; artifacts go to <out>/dist)")
    ap.add_argument("--workers", type=int, default=8, help="test workers (default 8)")
    ap.add_argument("--cov-threshold", type=float, default=100.0,
                    help="coverage gate (default 100)")
    ap.add_argument("--skip-tests", action="store_true",
                    help="skip the test suite + coverage gate")
    ap.add_argument("--dry-run", action="store_true",
                    help="print the release plan and exit without building")
    args = ap.parse_args()

    version = args.version or version_from_project(ROOT)
    label = (args.platform or _SYS_TO_LABEL.get(sys.platform, "")).lower()
    if label not in PLATFORM_PRESETS:
        sys.exit(f"release: unsupported platform {label or sys.platform!r}; "
                 f"expected one of {', '.join(PLATFORM_PRESETS)}")
    preset, stem, suffix = PLATFORM_PRESETS[label]

    out_dir = Path(args.out).resolve()
    if args.dry_run:
        print(f"[release] dry-run: version={version} platform={preset!r} "
              f"tests={'RUN' if not args.skip_tests else 'SKIPPED'} "
              f"output={out_dir / 'dist'} / AtomZero-{version}-{stem}.(zip|deb)")
        return 0

    if not args.skip_tests:
        print(f"[release] running test suite + coverage gate (workers={args.workers}) ...")
        rc = subprocess.run([sys.executable, str(ROOT / "tools" / "run_tests.py"),
                             "-n", str(args.workers),
                             "--cov-fail-under", str(args.cov_threshold)],
                            cwd=str(ROOT)).returncode
        if rc != 0:
            sys.exit("release: test suite or coverage gate failed; aborting release")

    godot = godot_binary()
    print(f"[release] godot={godot} version={version} platform={preset!r}")

    staging = Path(tempfile.mkdtemp(prefix="atomzero_release_"))
    try:
        shutil.copytree(ROOT, staging, ignore=shutil.ignore_patterns(*IGNORE_PATTERNS))
        subprocess.run([sys.executable, str(ROOT / "tools" / "ci" / "generate_export_presets.py"),
                        "--version", version, "--output", str(staging / "export_presets.cfg")],
                       check=True)
        artifacts = package(godot, staging, preset, out_dir, version, stem, suffix)
        for a in artifacts:
            print(f"[release] packaged: {a}")
        print("[release] PASS")
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())