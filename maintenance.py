"""macOS system maintenance orchestrator."""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import os
import re
import shutil
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import TextIO


# ------------------------------------------------------------------- Colors
class Color:
    BOLD_BLUE = "\033[1;34m"
    BOLD_GREEN = "\033[1;32m"
    BOLD_YELLOW = "\033[1;33m"
    BOLD_RED = "\033[1;31m"
    DIM = "\033[2m"
    RESET = "\033[0m"


# ------------------------------------------------------------------- Status
class Status(Enum):
    SUCCESS = "success"
    FAILED = "failed"
    SKIPPED = "skipped"
    DRY_RUN = "dry-run"


@dataclass
class SectionResult:
    id: str
    label: str
    status: Status
    elapsed: float


# ------------------------------------------------------------------- Helpers
def format_duration(secs: float) -> str:
    s = int(secs)
    if s < 60:
        return f"{s}s"
    return f"{s // 60}m{s % 60}s"


def require_cmd(cmd: str, label: str) -> bool:
    if shutil.which(cmd) is None:
        print(f"{Color.BOLD_RED}  \u2717 '{cmd}' not found \u2014 skipping {label}{Color.RESET}")
        return False
    return True


def confirm(label: str, auto: bool) -> bool:
    if auto:
        return True
    try:
        response = input(f"{Color.BOLD_YELLOW}==> Run {label}? (y/N): {Color.RESET}")
    except (EOFError, KeyboardInterrupt):
        print()
        return False
    return response.strip().lower() in ("y", "yes")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, **kwargs)


# ------------------------------------------------------------------- Sections
def do_brew_formulae() -> bool:
    if not require_cmd("brew", "Homebrew Formulae"):
        return False
    run(["brew", "update"], check=True)
    run(["brew", "upgrade"], check=True)
    run(["brew", "cleanup"], check=True)
    return True


def do_brew_casks() -> bool:
    if not require_cmd("brew", "Homebrew Casks"):
        return False

    result = run(["brew", "ls", "--cask"], capture_output=True, text=True)
    installed = result.stdout.split()

    if not installed:
        print("  No casks installed.")
        return True

    info = run(
        ["brew", "info", "--cask", "--json=v2", *installed],
        capture_output=True, text=True, check=True,
    )
    data = json.loads(info.stdout)
    casks = [c["token"] for c in data.get("casks", []) if c.get("auto_updates")]

    if casks:
        print(f"  Updating {len(casks)} auto-updating casks...")
        run(["brew", "upgrade", "--cask", *casks], check=True)
    else:
        print("  No auto-updating casks found.")
    return True


def do_rust() -> bool:
    if not require_cmd("rustup", "Rust"):
        return False
    run(["rustup", "update"], check=True)

    if shutil.which("cargo-install-update"):
        run(["cargo", "install-update", "-a"], check=True)
    else:
        print("  cargo-update not found \u2014 skipping binary updates.")
    return True


def do_volta() -> bool:
    if not require_cmd("volta", "Volta"):
        return False

    result = run(["volta", "list", "all", "--format", "plain"], capture_output=True, text=True)
    tools = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "package":
            name = parts[1].split("@")[0]
            if name:
                tools.append(name)

    if not tools:
        print("  No Volta tools installed.")
        return True

    print(f"  Updating {len(tools)} tools: {', '.join(tools)}")
    run(["volta", "install", *tools], check=True)
    return True


def do_pre_commit() -> bool:
    if not require_cmd("pre-commit", "Pre-commit"):
        return False

    pc_dir = Path.home() / ".config" / "pre-commit"
    pc_config = "global-config.yaml"

    if pc_dir.is_dir() and (pc_dir / pc_config).is_file():
        git_dir = pc_dir / ".git"
        if not git_dir.is_dir():
            run(["git", "init", "-q"], cwd=pc_dir, check=True)
        run(["pre-commit", "autoupdate", "--config", pc_config], cwd=pc_dir, check=True)
        return True
    else:
        print(f"  Global config not found at {pc_dir}/{pc_config}")
        return False


# ------------------------------------------------------------------- Section Registry
SECTIONS: list[tuple[str, str, Callable[[], bool]]] = [
    ("brew-formulae", "Homebrew Formulae", do_brew_formulae),
    ("brew-casks", "Homebrew Casks", do_brew_casks),
    ("rust", "Rust", do_rust),
    ("volta", "Volta", do_volta),
    ("pre-commit", "Pre-commit", do_pre_commit),
]

SECTION_IDS = [s[0] for s in SECTIONS]


# ------------------------------------------------------------------- Dispatcher
def run_section(
    id: str, label: str, fn: Callable[[], bool], *, auto: bool, dry_run: bool, only: list[str],
) -> SectionResult:
    # Section filter
    if only and id not in only:
        return SectionResult(id, label, Status.SKIPPED, 0.0)

    # Confirm
    if not confirm(label, auto):
        return SectionResult(id, label, Status.SKIPPED, 0.0)

    # Dry-run
    if dry_run:
        print(f"\n{Color.DIM}[dry-run] Would run: {label}{Color.RESET}")
        return SectionResult(id, label, Status.DRY_RUN, 0.0)

    # Execute
    print(f"\n{Color.BOLD_GREEN}Updating {label}...{Color.RESET}")
    start = time.monotonic()
    try:
        success = fn()
    except subprocess.CalledProcessError:
        success = False
    except Exception as exc:
        print(f"{Color.BOLD_RED}  Error: {exc}{Color.RESET}")
        success = False
    elapsed = time.monotonic() - start

    status = Status.SUCCESS if success else Status.FAILED
    return SectionResult(id, label, status, elapsed)


# ------------------------------------------------------------------- Summary
def print_summary(results: list[SectionResult]) -> None:
    print(f"\n{Color.BOLD_BLUE}--- Summary ---{Color.RESET}")
    print(f"  {'Section':<22} {'Status':<10} {'Time'}")
    print(f"  {'\u2500' * 19:<22} {'\u2500' * 8:<10} {'\u2500' * 5}")
    for r in results:
        match r.status:
            case Status.SUCCESS:
                color = Color.BOLD_GREEN
            case Status.FAILED:
                color = Color.BOLD_RED
            case _:
                color = Color.DIM
        print(f"  {r.label:<22} {color}{r.status.value:<10}{Color.RESET} {format_duration(r.elapsed)}")

    print(f"\n{Color.BOLD_BLUE}--- Maintenance Complete! ---{Color.RESET}")


# ------------------------------------------------------------------- Logging
class TeeWriter:
    """Wraps stdout to also write ANSI-stripped text to a log file."""

    _ansi_re = re.compile(r"\x1b\[[0-9;]*m")

    def __init__(self, original: TextIO, log_file: TextIO) -> None:
        self._original = original
        self._log_file = log_file

    def write(self, text: str) -> int:
        self._original.write(text)
        stripped = self._ansi_re.sub("", text)
        self._log_file.write(stripped)
        self._log_file.flush()
        return len(text)

    def flush(self) -> None:
        self._original.flush()
        self._log_file.flush()

    def fileno(self) -> int:
        return self._original.fileno()

    def isatty(self) -> bool:
        return self._original.isatty()


def setup_logging(path: str) -> None:
    log_fh = open(path, "a")  # noqa: SIM115
    tee = TeeWriter(sys.stdout, log_fh)
    sys.stdout = tee
    sys.stderr = TeeWriter(sys.stderr, log_fh)
    print(f"{Color.DIM}Logging to {path}{Color.RESET}")


# ------------------------------------------------------------------- CLI
def version() -> str:
    try:
        return importlib.metadata.version("maintenance")
    except importlib.metadata.PackageNotFoundError:
        return "dev"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="maintenance",
        description="Orchestrates system maintenance tasks on macOS.",
    )
    parser.add_argument("--auto", action="store_true", help="Run all sections without prompts")
    parser.add_argument("--dry-run", action="store_true", help="Show what would run without executing")
    parser.add_argument(
        "--section", action="append", dest="sections", metavar="NAME",
        choices=SECTION_IDS,
        help=f"Run only named section(s), repeatable. Names: {', '.join(SECTION_IDS)}",
    )
    parser.add_argument(
        "--log", nargs="?", const=True, default=None, metavar="PATH",
        help="Tee output to log file (default: ~/maintenance-<timestamp>.log)",
    )
    parser.add_argument("--version", action="version", version=f"maintenance v{version()}")

    args = parser.parse_args(argv)

    # Logging
    if args.log is not None:
        if args.log is True:
            log_path = os.path.expanduser(
                f"~/maintenance-{time.strftime('%Y%m%d-%H%M%S')}.log"
            )
        else:
            log_path = args.log
        setup_logging(log_path)

    # Header
    if args.auto:
        print(f"{Color.BOLD_BLUE}--- SYSTEM MAINTENANCE (AUTO-PILOT MODE) ---{Color.RESET}")
    else:
        print(f"{Color.BOLD_BLUE}--- SYSTEM MAINTENANCE ORCHESTRATOR ---{Color.RESET}")
    if args.dry_run:
        print(f"{Color.DIM}(dry-run mode \u2014 no changes will be made){Color.RESET}")

    # Run sections
    results: list[SectionResult] = []
    for sid, label, fn in SECTIONS:
        result = run_section(
            sid, label, fn,
            auto=args.auto, dry_run=args.dry_run, only=args.sections or [],
        )
        results.append(result)

    # Summary
    print_summary(results)

    # Exit code
    if any(r.status == Status.FAILED for r in results):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
