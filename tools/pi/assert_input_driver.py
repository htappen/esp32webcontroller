#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import re
import struct
import sys
from pathlib import Path

EVIOCGVERSION = 0x80044501


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


def find_matching_event_devices(
    device_name: str | None,
    usb_vid: int | None,
    usb_pid: int | None,
) -> list[str]:
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


def resolve_input_driver(event_device: str) -> str:
    event_path = Path(event_device)
    event_name = event_path.name
    if not event_name.startswith("event"):
        raise ValueError(f"expected an event device path, got {event_device!r}")

    sysfs_input_dir = Path("/sys/class/input") / event_name / "device"
    if not sysfs_input_dir.exists():
        raise FileNotFoundError(f"missing sysfs path for {event_device!r}")

    current = Path(os.path.realpath(sysfs_input_dir))
    for _ in range(4):
        for candidate in (current / "driver", current / "device" / "driver"):
            if candidate.exists():
                return os.path.basename(os.path.realpath(candidate))
        current = current.parent

    raise FileNotFoundError(f"could not resolve kernel driver for {event_device!r}")


def read_evdev_version(event_device: str) -> int:
    with open(event_device, "rb", buffering=0) as handle:
        buf = bytearray(struct.calcsize("i"))
        fcntl.ioctl(handle.fileno(), EVIOCGVERSION, buf, True)
        return struct.unpack("i", buf)[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device")
    parser.add_argument("--device-name")
    parser.add_argument("--usb-vid")
    parser.add_argument("--usb-pid")
    parser.add_argument("--expect-driver")
    parser.add_argument("--expect-version-msb", action="store_true")
    parser.add_argument("--label", default="input device")
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
    event_devices = [args.device] if args.device else find_matching_event_devices(args.device_name, usb_vid, usb_pid)
    if not event_devices:
        raise AssertionError(f"{args.label} did not expose any matching input devices")

    records = []
    for event_device in event_devices:
        driver = resolve_input_driver(event_device)
        version = read_evdev_version(event_device)
        records.append(
            {
                "device": event_device,
                "driver": driver,
                "version": version,
                "versionMsbSet": bool(version & 0x8000),
            }
        )

    if args.expect_driver is not None:
        mismatched = [record for record in records if record["driver"] != args.expect_driver]
        if mismatched:
            raise AssertionError(
                f"{args.label} expected driver {args.expect_driver!r}, got {mismatched[0]['driver']!r} for {mismatched[0]['device']}"
            )

    if args.expect_version_msb:
        missing = [record for record in records if not record["versionMsbSet"]]
        if missing:
            raise AssertionError(
                f"{args.label} expected hid version MSB to be set, but it was clear for {missing[0]['device']}"
            )

    print(json.dumps({"label": args.label, "records": records}, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
