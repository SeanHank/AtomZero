# Coverage instrumentation for the AtomZero test pipeline.
#
# Function-level coverage: parses every core/*.gd script, inserts a probe after
# each function signature, and reports the full function inventory that the test
# suite must cover (the gate). Instrumentation runs inside a throwaway copy of
# the project so the real source tree is never modified.
#
# Probes must not rely on `CoverageHub` being resolvable as a compile-time
# global identifier: instrumented core scripts can be compiled during autoload
# instantiation (before every autoload singleton name is registered). Instead
# the probe looks the CoverageHub autoload node up in the live scene tree at
# run time (CoverageHub is registered before Bootstrap in the patched
# project.godot). The lookup must also be null-safe: the engine instantiates
# `ResourceFormatLoader` subclasses at startup, before any autoload node
# exists in the tree, so `Engine.get_main_loop()`/CoverageHub may not be
# available yet there. Probes never crash and never report a hit when the hub
# is unreachable.
#
# Usage:
#   python3 tools/instrument.py report   # print the coverage gate inventory

import os
import re
import sys
from pathlib import Path

PROBE_TPL = '_cn.call("hit", "res://core/{rel}", "{name}")'

# A function signature begins at a line's first non-tab char with `func`:
#   func name(
#   static func name(
#   func name(\n  ... args may span multiple lines
FUNC_RE = re.compile(r"^\t*(?:(?:static|async)\s+)?func\s+([A-Za-z_]\w*)\s*\(")


TRIPLE = chr(34) * 3


def _line_in_triple(lines: list[str]) -> list[bool]:
    """Track whether each line is inside a triple-quoted string span."""
    inside = False
    out: list[bool] = []
    for line in lines:
        out.append(inside)
        if line.count(TRIPLE) % 2 == 1:
            inside = not inside
    return out


def parse_functions(text: str) -> list[tuple[str, int]]:
    """Return [(func_name, start_line_1based)] in source order."""
    lines = text.split("\n")
    triple = _line_in_triple(lines)
    found: list[tuple[str, int]] = []
    for i, raw in enumerate(lines):
        if triple[i]:
            continue
        m = FUNC_RE.match(raw)
        if m is not None:
            found.append((m.group(1), i + 1))
    return found


def _sig_end_index(lines: list[str], start: int) -> int:
    """Index of the last signature line (parentheses balanced)."""
    depth = 0
    j = start
    while j < len(lines):
        depth += lines[j].count("(") - lines[j].count(")")
        if depth <= 0:
            return j
        j += 1
    return start


def instrument_source(text: str, rel_path: str) -> str:
    lines = text.split("\n")
    triple = _line_in_triple(lines)
    out: list[str] = []
    i = 0
    n = len(lines)
    while i < n:
        raw = lines[i]
        out.append(raw)
        if triple[i]:
            i += 1
            continue
        m = FUNC_RE.match(raw)
        if m is None:
            i += 1
            continue
        end = _sig_end_index(lines, i)
        for j in range(i + 1, end + 1):
            out.append(lines[j])
        probe_indent = re.match(r"^\t*", raw).group(0) + "\t"
        body = PROBE_TPL.format(rel=rel_path, name=m.group(1))
        out.append(probe_indent + "var _ct := Engine.get_main_loop() as SceneTree")
        out.append(probe_indent + "if _ct != null:")
        out.append(probe_indent + "\t" + "var _cn := _ct.root.get_node_or_null(\"CoverageHub\")")
        out.append(probe_indent + "\t" + "if _cn != null:")
        out.append(probe_indent + "\t\t" + body)
        i = end + 1
    return "\n".join(out)


def instrument_project(core_root: Path, instrument: bool = True) -> dict[str, list[tuple[str, int]]]:
    """Walk core/, optionally instrumenting each script in place. Returns the gate."""
    gate: dict[str, list[tuple[str, int]]] = {}
    for root, _dirs, files in os.walk(core_root):
        for fname in sorted(files):
            if not fname.endswith(".gd"):
                continue
            path = Path(root) / fname
            text = path.read_text(encoding="utf-8")
            funcs = parse_functions(text)
            if not funcs:
                continue
            idx = path.resolve().as_posix().find("core/")
            rel = path.resolve().as_posix()[idx + 5:]
            gate["res://core/" + rel] = funcs
            if instrument:
                new_text = instrument_source(text, rel)
                if new_text != text:
                    path.write_text(new_text, encoding="utf-8")
    return gate


def report_gate(gate: dict[str, list[tuple[str, int]]]) -> str:
    total = sum(len(v) for v in gate.values())
    lines = [f"{len(gate)} files, {total} functions"]
    for rel, funcs in sorted(gate.items()):
        names = ", ".join(n for n, _ in funcs)
        lines.append(f"  {rel} -- {names}")
    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] != "report":
        print(__doc__)
        return 1
    core = Path(__file__).resolve().parent.parent / "core"
    gate = instrument_project(core, instrument=False)
    print(report_gate(gate))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())