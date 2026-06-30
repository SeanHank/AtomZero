#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AtomZero Mod Packaging Tool (Python version)
Design document §4.3.3 Release mode Mod packaging specification / Mod development guide §11.4.1

Package loose Mod files from development mode into a release .zip archive:
  1. Scan the Mod directory to identify binary resource files
  2. Generate manifest.json (containing size + sha256 for each binary file, used for runtime verification)
  3. Package as <mod_id>-<version>.zip (excluding runtime state directories, keeping .godot/ pre-import cache)

Usage:
  python tools/pack_mod.py <mod_dir> [output_dir]

Examples:
  python tools/pack_mod.py mods/atom_hello
  python tools/pack_mod.py mods/atom_hello ./output
  python tools/pack_mod.py res://mods/atom_hello

Dependencies: Python 3.8+ standard library only, no Godot installation required.
"""

import argparse
import hashlib
import json
import os
import sys
import zipfile
from datetime import datetime
from pathlib import Path

# Binary resource extensions (these files need to be pre-imported and recorded in the manifest)
BINARY_EXTS = (
    ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga",
    ".wav", ".ogg", ".mp3", ".flac",
    ".ttf", ".otf",
    ".glb", ".gltf",
    ".bin", ".res", ".ctex",
)

# Excluded directories/files (for manifest scanning: not included in the binary manifest)
# Note: .godot/ is not listed here — pre-imported resources like .res / .ctex inside it must be recorded in the manifest
EXCLUDE_DIRS = {"config", "data", ".cache"}
EXCLUDE_FILES = {"manifest.json", "mod.json"}

# Directories excluded from zip packaging (design document §4.3.3: release .zip must not contain runtime state)
# Note: .godot/ is not listed here — the pre-imported resource cache must be distributed with the .zip
ZIP_EXCLUDE_DIRS = {"data", "config", ".cache"}
ZIP_EXCLUDE_FILES = {".DS_Store", "Thumbs.db"}

# SHA256 streaming read chunk size (64KB, constant memory)
CHUNK_SIZE = 65536


def find_project_root() -> Path:
    """Search upward for the directory containing project.godot as the project root.

    Search upward from the script's directory, used to resolve res:// paths.
    Falls back to the current working directory when not found.
    """
    p = Path(__file__).resolve().parent
    while True:
        if (p / "project.godot").exists():
            return p
        if p == p.parent:
            break
        p = p.parent
    return Path.cwd()


def resolve_mod_dir(mod_dir: str) -> Path:
    """Normalize the mod_dir path, supporting res:// prefix and relative/absolute paths."""
    if mod_dir.startswith("res://"):
        rel = mod_dir[len("res://"):]
        return (find_project_root() / rel).resolve()
    return Path(mod_dir).resolve()


def is_binary_file(name: str) -> bool:
    """Determine whether the file is a binary resource file (matched by extension, case-insensitive)."""
    lower = name.lower()
    return lower.endswith(BINARY_EXTS)


def compute_sha256(file_path: Path) -> str:
    """Compute the file SHA256 in streaming fashion (64KB chunks, constant memory)."""
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        while True:
            chunk = f.read(CHUNK_SIZE)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def scan_binary_files(root_dir: Path) -> dict:
    """Recursively scan binary files, computing size + sha256.

    Skips content under EXCLUDE_DIRS and EXCLUDE_FILES.
    Returns a {relative_path: {"size": int, "sha256": str}} dictionary.
    """
    binary_files = {}
    for dirpath, dirnames, filenames in os.walk(root_dir):
        # Filter directories in place to prevent os.walk from descending into excluded directories
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fname in filenames:
            if fname in EXCLUDE_FILES:
                continue
            if not is_binary_file(fname):
                continue
            abs_path = Path(dirpath) / fname
            rel_path = abs_path.relative_to(root_dir)
            # Use forward slashes uniformly inside the zip (cross-platform)
            rel_str = str(rel_path).replace(os.sep, "/")
            binary_files[rel_str] = {
                "size": abs_path.stat().st_size,
                "sha256": compute_sha256(abs_path),
            }
    return binary_files


def generate_manifest(mod_dir: Path, mod_id: str, mod_version: str) -> dict:
    """Generate manifest.json content (design document §9.2.3)."""
    return {
        "mod_id": mod_id,
        "mod_version": mod_version,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "binary_files": scan_binary_files(mod_dir),
    }


def create_zip(mod_dir: Path, zip_path: Path) -> int:
    """Package mod_dir contents into a zip.

    Excludes data/, config/, .cache/, .DS_Store, keeps .godot/ and all other files.
    Paths inside the zip are relative to mod_dir (without the mod_id parent directory).
    Returns the number of files written.
    """
    file_count = 0
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for dirpath, dirnames, filenames in os.walk(mod_dir):
            dirnames[:] = [d for d in dirnames if d not in ZIP_EXCLUDE_DIRS]
            for fname in filenames:
                if fname in ZIP_EXCLUDE_FILES:
                    continue
                abs_path = Path(dirpath) / fname
                rel_path = abs_path.relative_to(mod_dir)
                rel_str = str(rel_path).replace(os.sep, "/")
                zf.write(abs_path, rel_str)
                file_count += 1
    return file_count


def pack(mod_dir_arg: str, output_dir_arg: str = "") -> str:
    """Package a Mod.

    mod_dir_arg: Mod directory path (supports res:// prefix, relative path, absolute path)
    output_dir_arg: Output directory (defaults to the parent directory of mod_dir)
    Returns the zip file path, or an empty string on failure.
    """
    mod_dir = resolve_mod_dir(mod_dir_arg)
    if not mod_dir.is_dir():
        print(f"[pack_mod] Mod directory does not exist: {mod_dir}", file=sys.stderr)
        return ""

    if output_dir_arg:
        output_dir = Path(output_dir_arg).resolve()
    else:
        output_dir = mod_dir.parent

    # Read mod.json
    mod_json_path = mod_dir / "mod.json"
    if not mod_json_path.is_file():
        print(f"[pack_mod] mod.json does not exist: {mod_json_path}", file=sys.stderr)
        return ""
    try:
        with open(mod_json_path, "r", encoding="utf-8") as f:
            mod_meta = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"[pack_mod] mod.json parse failed: {mod_json_path} ({e})", file=sys.stderr)
        return ""

    mod_id = mod_meta.get("mod_id", "")
    mod_version = mod_meta.get("version", "")
    if not mod_id or not mod_version:
        print("[pack_mod] mod_id or version is empty", file=sys.stderr)
        return ""

    print(f"[pack_mod] Start packaging: {mod_id} v{mod_version}")

    # 1. Generate manifest.json
    manifest = generate_manifest(mod_dir, mod_id, mod_version)
    manifest_path = mod_dir / "manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent="\t", ensure_ascii=False)
    print(
        f"[pack_mod] Generated manifest.json "
        f"({len(manifest['binary_files'])} binary files)"
    )

    # 2. Package as .zip
    zip_name = f"{mod_id}-{mod_version}.zip"
    zip_path = output_dir / zip_name
    output_dir.mkdir(parents=True, exist_ok=True)

    file_count = create_zip(mod_dir, zip_path)
    print(
        f"[pack_mod] Packaging complete: {zip_path} ({file_count} files)"
    )
    return str(zip_path)


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="pack_mod",
        description="AtomZero Mod Packaging Tool: generate manifest.json and package as .zip",
    )
    parser.add_argument(
        "mod_dir",
        help="Mod directory path (supports res:// prefix, relative path, absolute path)",
    )
    parser.add_argument(
        "output_dir",
        nargs="?",
        default="",
        help="Output directory (defaults to the parent directory of mod_dir)",
    )
    args = parser.parse_args()

    zip_path = pack(args.mod_dir, args.output_dir)
    if not zip_path:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
