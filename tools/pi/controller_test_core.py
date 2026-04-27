#!/usr/bin/env python3
import argparse
import os
import re
import time


def parse_hex(text: str) -> int:
    cleaned = text.strip().lower()
    if cleaned.startswith("0x"):
        cleaned = cleaned[2:]
    return int(cleaned, 16)


def iter_input_device_blocks():
    with open("/proc/bus/input/devices", "r", encoding="utf-8") as handle:
        for block in handle.read().strip().split("\n\n"):
            if block.strip():
                yield block


def find_event_devices_once(device_name: str | None, usb_vid: int | None, usb_pid: int | None) -> list[str]:
    devices = []
    for block in iter_input_device_blocks():
        name_match = re.search(r'^N: Name="(.+)"$', block, flags=re.MULTILINE)
        id_match = re.search(r"^I: Bus=.* Vendor=([0-9a-fA-F]{4}) Product=([0-9a-fA-F]{4}) ", block, flags=re.MULTILINE)
        handler_match = re.search(r"^H: Handlers=(.+)$", block, flags=re.MULTILINE)
        if not name_match or not handler_match:
            continue
        if device_name is not None and name_match.group(1) != device_name:
            continue
        if usb_vid is not None or usb_pid is not None:
            if not id_match:
                continue
            if usb_vid is not None and int(id_match.group(1), 16) != usb_vid:
                continue
            if usb_pid is not None and int(id_match.group(2), 16) != usb_pid:
                continue
        for handler in handler_match.group(1).split():
            if handler.startswith("event"):
                devices.append(os.path.join("/dev/input", handler))
                break
    return devices


def find_event_device_once(device_name: str | None, usb_vid: int | None, usb_pid: int | None) -> str:
    devices = find_event_devices_once(device_name, usb_vid, usb_pid)
    if devices:
        return devices[0]
    if usb_vid is not None or usb_pid is not None:
        raise FileNotFoundError(f"input device not found for vidpid={usb_vid!r}:{usb_pid!r}")
    raise FileNotFoundError(f"input device not found for {device_name!r}")


def find_event_device(device_name: str | None, usb_vid: int | None, usb_pid: int | None, wait_timeout: float) -> str:
    deadline = time.monotonic() + wait_timeout
    while True:
        try:
            return find_event_device_once(device_name, usb_vid, usb_pid)
        except FileNotFoundError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.2)


def find_event_devices(device_name: str | None, usb_vid: int | None, usb_pid: int | None, wait_timeout: float) -> list[str]:
    deadline = time.monotonic() + wait_timeout
    while True:
        devices = find_event_devices_once(device_name, usb_vid, usb_pid)
        if devices:
            return devices
        if time.monotonic() >= deadline:
            if usb_vid is not None or usb_pid is not None:
                raise FileNotFoundError(f"input device not found for vidpid={usb_vid!r}:{usb_pid!r}")
            raise FileNotFoundError(f"input device not found for {device_name!r}")
        time.sleep(0.2)


def count_event_devices(device_name: str | None, usb_vid: int | None, usb_pid: int | None) -> int:
    count = 0
    for block in iter_input_device_blocks():
        name_match = re.search(r'^N: Name="(.+)"$', block, flags=re.MULTILINE)
        id_match = re.search(r"^I: Bus=.* Vendor=([0-9a-fA-F]{4}) Product=([0-9a-fA-F]{4}) ", block, flags=re.MULTILINE)
        handler_match = re.search(r"^H: Handlers=(.+)$", block, flags=re.MULTILINE)
        if not name_match or not handler_match:
            continue
        if device_name is not None and name_match.group(1) != device_name:
            continue
        if usb_vid is not None or usb_pid is not None:
            if not id_match:
                continue
            if usb_vid is not None and int(id_match.group(1), 16) != usb_vid:
                continue
            if usb_pid is not None and int(id_match.group(2), 16) != usb_pid:
                continue
        if any(handler.startswith("event") for handler in handler_match.group(1).split()):
            count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    find_device = subparsers.add_parser("find-device")
    find_device.add_argument("--device-name")
    find_device.add_argument("--usb-vid")
    find_device.add_argument("--usb-pid")
    find_device.add_argument("--wait-timeout", type=float, default=0.0)

    count_devices = subparsers.add_parser("count-devices")
    count_devices.add_argument("--device-name")
    count_devices.add_argument("--usb-vid")
    count_devices.add_argument("--usb-pid")

    args = parser.parse_args()

    if args.command == "find-device":
        if bool(args.usb_vid) != bool(args.usb_pid):
            parser.error("pass both --usb-vid and --usb-pid together")
        usb_vid = parse_hex(args.usb_vid) if args.usb_vid else None
        usb_pid = parse_hex(args.usb_pid) if args.usb_pid else None
        print(find_event_device(args.device_name, usb_vid, usb_pid, args.wait_timeout))
        return 0

    if args.command == "count-devices":
        if bool(args.usb_vid) != bool(args.usb_pid):
            parser.error("pass both --usb-vid and --usb-pid together")
        usb_vid = parse_hex(args.usb_vid) if args.usb_vid else None
        usb_pid = parse_hex(args.usb_pid) if args.usb_pid else None
        print(count_event_devices(args.device_name, usb_vid, usb_pid))
        return 0

    parser.error("unknown command")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
