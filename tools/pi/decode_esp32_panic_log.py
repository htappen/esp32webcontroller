#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


BACKTRACE_PAIR_RE = re.compile(r"0x[0-9a-fA-F]{8}(?=:)")
HEX_RE = re.compile(r"0x[0-9a-fA-F]{8}")


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def default_elf_path() -> Path:
    return default_repo_root() / "firmware/.pio/build/esp32_s3_devkitc_1_usb_switch/firmware.elf"


def find_addr2line() -> str:
    override = os.environ.get("ADDR2LINE_BIN")
    if override:
      return override

    found = shutil.which("xtensa-esp32s3-elf-addr2line")
    if found:
        return found

    fallback = Path.home() / ".platformio/packages/toolchain-xtensa-esp32s3/bin/xtensa-esp32s3-elf-addr2line"
    return str(fallback)


def extract_addresses(log_text: str) -> list[str]:
    addresses: list[str] = []
    seen: set[str] = set()

    for line in log_text.splitlines():
        if line.startswith("Backtrace:"):
            for addr in BACKTRACE_PAIR_RE.findall(line):
                if addr not in seen:
                    seen.add(addr)
                    addresses.append(addr)
            continue

        if line.startswith("PC") or line.startswith("Saved PC:"):
            match = HEX_RE.search(line)
            if match:
                addr = match.group(0)
                if addr not in seen:
                    seen.add(addr)
                    addresses.append(addr)

    return addresses


def decode_addresses(addr2line: str, elf_file: Path, addresses: list[str]) -> list[str]:
    if not addresses:
        return []

    proc = subprocess.run(
        [addr2line, "-pfiaC", "-e", str(elf_file), *addresses],
        check=True,
        text=True,
        capture_output=True,
    )
    return proc.stdout.splitlines()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log_file")
    parser.add_argument("elf_file", nargs="?", default=str(default_elf_path()))
    args = parser.parse_args()

    log_path = Path(args.log_file)
    elf_path = Path(args.elf_file)

    if not log_path.is_file():
        print(f"[panic-decode] log file not found: {log_path}", file=sys.stderr)
        return 1
    if not elf_path.is_file():
        print(f"[panic-decode] ELF file not found: {elf_path}", file=sys.stderr)
        return 1

    addr2line = find_addr2line()
    if not Path(addr2line).exists():
        print(f"[panic-decode] addr2line not found: {addr2line}", file=sys.stderr)
        return 1

    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    print(f"[panic-decode] log file: {log_path}")
    print(f"[panic-decode] ELF file: {elf_path}")

    if re.search(r"IntegerDivideByZero|Guru Meditation Error|Backtrace:", log_text):
        print("[panic-decode] panic markers found")
    else:
        print("[panic-decode] no panic markers found; decoding any panic-style addresses anyway")

    addresses = extract_addresses(log_text)
    if not addresses:
        print("[panic-decode] no addresses found in log")
        return 0

    print("[panic-decode] decoded addresses (ordered):")
    for line in decode_addresses(addr2line, elf_path, addresses):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
