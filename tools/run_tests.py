#!/usr/bin/env python3
"""pytest-style test orchestrator for AtomZero (pytest-xdist-like parallelism).

PREPARE  -> copy the repo into a temp dir, patch project.godot into a
            headless test harness (TestRunner main scene + CoverageHub
            autoload + MOD_DEV_MODE=true), instrument every core/*.gd with
            coverage probes, run `godot --import` once.
WORKERS  -> copy the prepared project into N isolated worker projects and
            launch N Godot headless processes (one per worker) concurrently,
            each running a disjoint batch of tests.
MERGE    -> collect each worker's JSON (results + per-function coverage
            hits), merge, and enforce BOTH the failure gate (0 failures) and
            the coverage gate (--cov-fail-under, default 100%).

Examples:
  python3 tools/run_tests.py                        # default: auto workers
  python3 tools/run_tests.py -n 8 --only semver -v  # filter + verbose
  python3 tools/run_tests.py --cov-fail-under 100   # 100% function coverage
  GODOT_BIN=godot4 python3 tools/run_tests.py       # pick the Godot binary
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# Sub-trees/dirs that must not leak into the throwaway test project.
IGNORE_PATTERNS = [".git", ".godot", ".runtime", ".test_tmp", "dist", "release",
                   "logs", "__pycache__", ".pytest_cache", ".venv", "venv"]

DEFAULT_GODOT_CANDIDATES = [
    os.environ.get("GODOT_BIN", ""),
    "/Applications/Godot.app/Contents/MacOS/Godot",
    "godot",
    "godot4",
    r"C:\Program Files\Godot\Godot_v4.6.3-stable_win64.exe",
]


def godot_binary() -> str:
    for cand in DEFAULT_GODOT_CANDIDATES:
        if not cand:
            continue
        if shutil.which(cand) or Path(cand).exists():
            return cand
    sys.exit("Godot not found; set GODOT_BIN (e.g. GODOT_BIN=/path/to/godot)")


def _patch_project(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'^run/main_scene="[^"]*".*$',
                  'run/main_scene="res://tests/runner/TestRunner.tscn"',
                  text, count=1, flags=re.M)
    if 'Bootstrap="*res://core/bootstrap/Bootstrap.gd"' in text:
        # Register CoverageHub BEFORE Bootstrap so that instrumented core
        # scripts compiled during Bootstrap._ready (e.g. ModResourceFormatLoader)
        # can resolve the CoverageHub global identifier.
        text = text.replace(
            'Bootstrap="*res://core/bootstrap/Bootstrap.gd"',
            'CoverageHub="*res://tests/runner/CoverageHub.gd"\n'
            'Bootstrap="*res://core/bootstrap/Bootstrap.gd"', 1)
    path.write_text(text, encoding="utf-8")


def _patch_bootstrap(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = text.replace("const MOD_DEV_MODE: bool = false",
                        "const MOD_DEV_MODE: bool = true")
    path.write_text(text, encoding="utf-8")


def prepare_project(src: Path, build: Path, instrument: bool = True) -> dict:
    """Copy + patch + instrument, then `--import` to build the class cache."""
    shutil.copytree(src, build, ignore=shutil.ignore_patterns(*IGNORE_PATTERNS))
    gate = {}
    if instrument:
        from tools.instrument import instrument_project
        gate = instrument_project(build / "core", instrument=True)
    _patch_project(build / "project.godot")
    _patch_bootstrap(build / "core" / "bootstrap" / "Bootstrap.gd")
    return gate


def _discover_tests(project: Path) -> int:
    cases = (project / "tests" / "cases")
    return sum(1 for _ in cases.glob("*.gd"))


def run_workers(godot: str, build: Path, out_dir: Path, workers: int,
                only: str, verbose: bool) -> list[tuple[int, str, Path]]:
    """Launch `workers` Godot processes in parallel on isolated copies."""
    procs: list[subprocess.Popen] = []
    meta: list[tuple[int, str, Path]] = []
    for i in range(workers):
        wdir = out_dir / f"worker_{i}"
        shutil.copytree(build, wdir)
        out_json = out_dir / f"worker_{i}.json"
        cmd = [godot, "--headless", "--path", str(wdir), "--",
               "--batch-idx", str(i), "--batch-count", str(workers),
               "--output", str(out_json)]
        if only:
            cmd += ["--only", only]
        if verbose:
            cmd.append("--verbose")
        log = open(out_dir / f"worker_{i}.log", "w")
        procs.append(subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT))
        meta.append((i, str(wdir), log))
    # Wait for all workers (classic xdist-style fan-out).
    for p in procs:
        p.wait()
    for _, _, log in meta:
        log.close()
    return [(i, str(wdir), out_dir / f"worker_{i}.json") for i, wdir, _ in meta]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-n", "--workers", type=int, default=0,
                    help="number of parallel Godot workers (default: cpu count)")
    ap.add_argument("--cov-fail-under", type=float, default=100.0,
                    help="coverage gate percentage (default 100)")
    ap.add_argument("--only", default="", help="run only test cases matching substr")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--cov", action="store_true", help="emit merged coverage summary")
    ap.add_argument("--no-copy", action="store_true",
                    help="run workers on the prepared dir (no per-worker copies; unsafe for parallel fixture writes)")
    ap.add_argument("--keep", default="", help="keep build dir at this path; useful for debugging")
    args = ap.parse_args()

    godot = godot_binary()
    workers = args.workers or max(1, os.cpu_count() or 2)
    workers = min(workers, 64)

    t0 = time.time()
    work = Path(tempfile.mkdtemp(prefix="atomzero_tests_"))
    out_dir = work / "out"
    out_dir.mkdir()

    print(f"[run_tests] godot={godot} workers={workers} cwd={ROOT}")
    print("[run_tests] preparing instrumented project copy ...")
    build = work / "build"
    gate = prepare_project(ROOT, build, instrument=True)
    total_funcs = sum(len(v) for v in gate.values())
    total_cases = _discover_tests(build)
    print(f"[run_tests] coverage gate: {len(gate)} files / {total_funcs} functions; "
          f"{total_cases} test case files")

    print("[run_tests] prewarming import cache (godot --import) ...")
    subprocess.run([godot, "--headless", "--path", str(build), "--import", "--quit"],
                   check=True, capture_output=True)

    if total_cases == 0:
        print("[run_tests] ERROR: no test cases found under tests/cases/")
        return 1

    print(f"[run_tests] launching {workers} worker processes ...")
    meta = run_workers(godot, build, out_dir, workers, args.only, args.verbose)

    # ---- merge worker results ----
    merged_results: list[dict] = []
    summary = {"passed": 0, "failed": 0, "skipped": 0, "total": 0, "duration_ms": 0}
    coverage: dict = {}
    worker_failures = 0
    for i, wdir, out_json in meta:
        if not out_json.exists():
            print(f"[run_tests] ERROR: worker {i} produced no JSON output (crash/parse error). "
                  f"Log: {out_dir / ('worker_%d.log' % i)}")
            worker_failures += 1
            continue
        doc = json.loads(out_json.read_text())
        s = doc.get("summary", {})
        for k in summary:
            summary[k] += int(s.get(k, 0))
        merged_results.extend(doc.get("results", []))
        for path, hits in doc.get("coverage", {}).items():
            cov = coverage.setdefault(path, set())
            cov.update(hits.keys())
    elapsed = int((time.time() - t0) * 1000)

    print("[run_tests] ============================================================")
    print(f"[run_tests] passed={summary['passed']} failed={summary['failed']} "
          f"skipped={summary['skipped']} workers_ok={len(meta) - worker_failures}/{len(meta)} "
          f"({elapsed} ms)")

    for r in merged_results:
        if r["status"] == "failed":
            print(f"[run_tests]   FAIL {r['case']}::{r['test']} :: {r['message']}")

    # ---- coverage gate ----
    covered = verified_cov = 0
    uncovered: dict[str, list[str]] = {}
    if args.cov or True:
        for path, funcs in sorted(gate.items()):
            have = coverage.get(path, set())
            names = {name for name, _ in funcs}
            covered += len(names & have)
            missing = sorted(names - have)
            if missing:
                uncovered[path] = missing
        cov_pct = (covered / total_funcs * 100.0) if total_funcs else 100.0
        print(f"[run_tests] coverage: {covered}/{total_funcs} functions "
              f"({cov_pct:.2f}%) threshold={args.cov_fail_under}%")
        for path, missing in uncovered.items():
            print(f"[run_tests]   UNCOVERED {path}: {', '.join(missing)}")

    failures = summary["failed"]
    cov_ok = cov_pct >= args.cov_fail_under
    ok = failures == 0 and worker_failures == 0 and cov_ok

    print("[run_tests] ============================================================")
    print(f"[run_tests] {'PASS' if ok else 'FAIL'}")
    if not ok:
        print(f"[run_tests] failures={failures} worker_crashes={worker_failures} "
              f"coverage={cov_pct:.2f}% (need {args.cov_fail_under}%)")

    if args.keep:
        shutil.rmtree(args.keep, ignore_errors=True)
        shutil.copytree(build, args.keep)
        print(f"[run_tests] kept prepared project at {args.keep}")
    shutil.rmtree(work, ignore_errors=True)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())