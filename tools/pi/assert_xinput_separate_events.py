#!/usr/bin/env python3
import argparse
import json
import sys

EV_KEY = 1
EV_ABS = 3


def load_events(path: str) -> list[dict]:
    events = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                events.append(json.loads(line))
    return events


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--button-code", type=int, default=304)
    parser.add_argument("--button-value", type=int, default=1)
    parser.add_argument("--axis-code", type=int, default=0)
    parser.add_argument("--axis-min", type=int, default=20000)
    parser.add_argument("--axis-max", type=int, default=32767)
    args = parser.parse_args()

    events = load_events(args.file)
    by_device: dict[str, dict[str, bool]] = {}
    for event in events:
        device = event.get("device")
        if not device:
            continue
        state = by_device.setdefault(device, {"button": False, "axis": False})
        if (
            event.get("type") == EV_KEY
            and event.get("code") == args.button_code
            and event.get("value") == args.button_value
        ):
            state["button"] = True
        if (
            event.get("type") == EV_ABS
            and event.get("code") == args.axis_code
            and args.axis_min <= event.get("value", 0) <= args.axis_max
        ):
            state["axis"] = True

    button_devices = {device for device, state in by_device.items() if state["button"]}
    axis_devices = {device for device, state in by_device.items() if state["axis"]}

    if not button_devices:
      raise AssertionError("no device reported the expected button event")
    if not axis_devices:
      raise AssertionError("no device reported the expected axis event")
    if button_devices & axis_devices:
      shared = sorted(button_devices & axis_devices)
      raise AssertionError(f"expected button and axis events on separate devices, but shared devices were {shared}")

    print(
        json.dumps(
            {
                "buttonDevices": sorted(button_devices),
                "axisDevices": sorted(axis_devices),
                "eventCount": len(events),
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
