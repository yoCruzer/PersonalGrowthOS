#!/usr/bin/env python3
"""Run independent, local logic probes without modifying the product repository.

This does not run Xcode, SwiftUI, SwiftData, or the app's XCTest suite.
Requires Python 3.9+ and a local Swift compiler. No network access is used.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HEAD = "4e407591868d63c96a647494d5aa8a91a6fcc5b3"
SOURCE_PATH = "Shared/ImportantDays/ImportantDayDate.swift"
EXPECTED_BLOB = "456a4cca8a78c51f49fd6f263bafd19f9e712163"


def blob_hash(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, help="Read the fixed source with git show from an existing local repository.")
    parser.add_argument("--output", type=Path, help="Optionally save stdout and environment details to this file.")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise RuntimeError("swiftc was not found; install/select a local Swift toolchain first.")
    if args.repo:
        source = subprocess.run(
            ["git", "-C", str(args.repo.resolve()), "show", f"{HEAD}:{SOURCE_PATH}"],
            check=True, capture_output=True, timeout=15,
        ).stdout
    else:
        source = (here / "ImportantDayDate.swift").read_bytes()
    actual = blob_hash(source)
    if actual != EXPECTED_BLOB:
        raise RuntimeError(f"Source mismatch: expected Git blob {EXPECTED_BLOB}; got {actual}. No probes run.")
    harness = here / "ReviewProbes.swift"
    if not harness.is_file():
        raise FileNotFoundError(harness)
    version = subprocess.run([swiftc, "--version"], check=True, capture_output=True, text=True, timeout=10).stdout.strip()
    notes = [f"Fixed delivery SHA: {HEAD}", f"Verified source Git blob: {actual}", version]
    text = source.decode("utf-8")
    # Swift 6.2.1 Linux has a name-resolution issue in this one expression.
    # Explicitly qualify the already-intended static function in a temporary copy only.
    if sys.platform.startswith("linux"):
        old = "let original = try rule.year.flatMap { try original(rule, in: $0) }"
        new = "let original = try rule.year.flatMap { try Self.original(rule, in: $0) }"
        if text.count(old) != 1:
            raise RuntimeError("Expected compatibility expression not found exactly once; refusing to patch.")
        text = text.replace(old, new, 1)
        notes.append("Linux-only compatibility adaptation: qualify original(rule,in:) with Self on one line in the temporary copy.")
    else:
        notes.append("Compiling the original, unmodified date source on this platform.")
    with tempfile.TemporaryDirectory(prefix="pgos-pr10-review-") as temp:
        root = Path(temp)
        compiled_source = root / "ImportantDayDate.swift"
        compiled_source.write_text(text, encoding="utf-8")
        executable = root / "review_probes"
        build = subprocess.run([swiftc, str(compiled_source), str(harness), "-o", str(executable)],
                               capture_output=True, text=True, timeout=60)
        if build.returncode:
            sys.stderr.write(build.stdout + build.stderr)
            raise RuntimeError(f"Probe compilation failed (exit {build.returncode}); this is not an iOS app build result.")
        run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
        result = "\n".join(notes) + "\n\n" + run.stdout
        if run.stderr:
            result += "\nSTDERR:\n" + run.stderr
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(result, encoding="utf-8")
        print(result, end="")
        return run.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f"Review probe error: {exc}", file=sys.stderr)
        raise SystemExit(1)
