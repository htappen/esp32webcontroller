#!/usr/bin/env python3
import argparse
import json
import os
import select
import struct
import sys
import time

from controller_test_core import find_event_device, find_event_devices, parse_hex

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


def event_name(event_type: int, code: int) -> str:
    if event_type == EV_KEY:
        return KEY_NAMES.get(code, f"KEY_{code}")
    if event_type == EV_ABS:
        return ABS_NAMES.get(code, f"ABS_{code}")
    if event_type == EV_SYN:
        return "SYN_REPORT" if code == 0 else f"SYN_{code}"
    return f"TYPE_{event_type}_{code}"


def capture(device_paths: list[str], duration: float, output_path: str | None) -> None:
    deadline = time.monotonic() + duration
    stream = open(output_path, "w", encoding="utf-8") if output_path else sys.stdout
    fds = {os.open(device_path, os.O_RDONLY | os.O_NONBLOCK): device_path for device_path in device_paths}
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            readable, _, _ = select.select(list(fds.keys()), [], [], remaining)
            if not readable:
                continue
            for fd in readable:
                payload = os.read(fd, EVENT_STRUCT.size * 64)
                if not payload:
                    continue
                for offset in range(0, len(payload) - EVENT_STRUCT.size + 1, EVENT_STRUCT.size):
                    sec, usec, event_type, code, value = EVENT_STRUCT.unpack(
                        payload[offset : offset + EVENT_STRUCT.size]
                    )
                    item = {
                        "device": fds[fd],
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
        for fd in fds:
            os.close(fd)
        if output_path:
            stream.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device")
    parser.add_argument("--device-name")
    parser.add_argument("--usb-vid")
    parser.add_argument("--usb-pid")
    parser.add_argument("--print-device", action="store_true")
    parser.add_argument("--all-matching", action="store_true")
    parser.add_argument("--duration", type=float, default=1.0)
    parser.add_argument("--output")
    parser.add_argument("--wait-timeout", type=float, default=0.0)
    args = parser.parse_args()

    if args.device and (args.device_name or args.usb_vid or args.usb_pid):
        parser.error("pass only one device selector")
    if args.device_name and (args.usb_vid or args.usb_pid):
        parser.error("pass only one device selector")
    if bool(args.usb_vid) != bool(args.usb_pid):
        parser.error("pass both --usb-vid and --usb-pid together")
    if not args.device and not args.device_name and not args.usb_vid:
        parser.error("pass --device, --device-name, or --usb-vid/--usb-pid")

    usb_vid = parse_hex(args.usb_vid) if args.usb_vid else None
    usb_pid = parse_hex(args.usb_pid) if args.usb_pid else None

    if args.all_matching:
        device_paths = find_event_devices(args.device_name, usb_vid, usb_pid, args.wait_timeout)
        if args.print_device:
            for device_path in device_paths:
                print(device_path)
            return 0
        capture(device_paths, args.duration, args.output)
        return 0

    device_path = args.device or find_event_device(args.device_name, usb_vid, usb_pid, args.wait_timeout)

    if args.print_device:
        print(device_path)
        return 0

    capture([device_path], args.duration, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
