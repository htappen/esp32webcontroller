#!/usr/bin/env python3
import argparse
import json
import os
import re
import select
import struct
import sys
import time

EVENT_STRUCT = struct.Struct("@llHHi")
EV_SYN = 0
EV_KEY = 1
EV_ABS = 3

KEY_NAMES = {
    304: "BTN_SOUTH",
    305: "BTN_EAST",
    307: "BTN_NORTH",
    308: "BTN_WEST",
    310: "BTN_TL",
    311: "BTN_TR",
    314: "BTN_SELECT",
    315: "BTN_START",
    317: "BTN_THUMBL",
    318: "BTN_THUMBR",
}

ABS_NAMES = {
    0: "ABS_X",
    1: "ABS_Y",
    2: "ABS_Z",
    3: "ABS_RX",
    4: "ABS_RY",
    5: "ABS_RZ",
    16: "ABS_HAT0X",
    17: "ABS_HAT0Y",
}


def find_event_device_once(device_name: str) -> str:
    with open("/proc/bus/input/devices", "r", encoding="utf-8") as handle:
        blocks = handle.read().strip().split("\n\n")

    for block in blocks:
        name_match = re.search(r'^N: Name="(.+)"$', block, flags=re.MULTILINE)
        handler_match = re.search(r"^H: Handlers=(.+)$", block, flags=re.MULTILINE)
        if not name_match or not handler_match:
            continue
        if name_match.group(1) != device_name:
            continue
        for handler in handler_match.group(1).split():
            if handler.startswith("event"):
                return os.path.join("/dev/input", handler)
    raise FileNotFoundError(f"input device not found for {device_name!r}")


def find_event_device(device_name: str, wait_timeout: float) -> str:
    deadline = time.monotonic() + wait_timeout
    while True:
        try:
            return find_event_device_once(device_name)
        except FileNotFoundError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.2)


def event_name(event_type: int, code: int) -> str:
    if event_type == EV_KEY:
        return KEY_NAMES.get(code, f"KEY_{code}")
    if event_type == EV_ABS:
        return ABS_NAMES.get(code, f"ABS_{code}")
    if event_type == EV_SYN:
        return "SYN_REPORT" if code == 0 else f"SYN_{code}"
    return f"TYPE_{event_type}_{code}"


def capture(device_path: str, duration: float, output_path: str | None) -> None:
    deadline = time.monotonic() + duration
    stream = open(output_path, "w", encoding="utf-8") if output_path else sys.stdout
    fd = os.open(device_path, os.O_RDONLY | os.O_NONBLOCK)
    try:
      while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        readable, _, _ = select.select([fd], [], [], remaining)
        if not readable:
            continue
        payload = os.read(fd, EVENT_STRUCT.size * 64)
        if not payload:
            continue
        for offset in range(0, len(payload) - EVENT_STRUCT.size + 1, EVENT_STRUCT.size):
            sec, usec, event_type, code, value = EVENT_STRUCT.unpack(
                payload[offset : offset + EVENT_STRUCT.size]
            )
            item = {
                "sec": sec,
                "usec": usec,
                "type": event_type,
                "code": code,
                "value": value,
                "name": event_name(event_type, code),
            }
            stream.write(json.dumps(item, separators=(",", ":")) + "\n")
            stream.flush()
    finally:
        os.close(fd)
        if output_path:
            stream.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device")
    parser.add_argument("--device-name")
    parser.add_argument("--print-device", action="store_true")
    parser.add_argument("--duration", type=float, default=1.0)
    parser.add_argument("--output")
    parser.add_argument("--wait-timeout", type=float, default=0.0)
    args = parser.parse_args()

    if not args.device and not args.device_name:
        parser.error("pass --device or --device-name")

    device_path = args.device or find_event_device(args.device_name, args.wait_timeout)

    if args.print_device:
        print(device_path)
        return 0

    capture(device_path, args.duration, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
