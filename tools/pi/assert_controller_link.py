#!/usr/bin/env python3
import argparse
import json
import sys


def load_json(path: str) -> object:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def get_int(value: object, default: int = 0) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    return default


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--expect-transport")
    parser.add_argument("--expect-variant")
    parser.add_argument("--label", default="controller")
    args = parser.parse_args()

    before = load_json(args.before)
    after = load_json(args.after)
    after_controller = after.get("controller", {})
    after_host = after.get("host", {})

    if args.expect_transport is not None and after_host.get("transport") != args.expect_transport:
      raise AssertionError(
          f"unexpected host transport: {after_host.get('transport')!r} != {args.expect_transport!r}"
      )
    if args.expect_variant is not None and after_host.get("variant") != args.expect_variant:
      raise AssertionError(
          f"unexpected host variant: {after_host.get('variant')!r} != {args.expect_variant!r}"
      )

    before_controller = before.get("controller", {})
    before_applied = get_int(before_controller.get("debug", {}).get("wsPacketsApplied"))
    after_applied = get_int(after_controller.get("debug", {}).get("wsPacketsApplied"))
    if after_applied <= before_applied:
      raise AssertionError("websocket applied counter did not advance")

    before_received = get_int(before_controller.get("debug", {}).get("wsPacketsReceived"))
    after_received = get_int(after_controller.get("debug", {}).get("wsPacketsReceived"))
    if after_received < before_received:
      raise AssertionError("websocket received counter regressed")

    before_host_debug = before.get("host", {}).get("debug", {})
    after_host_debug = after.get("host", {}).get("debug", {})
    if "usbSendAttempts" in before_host_debug or "usbSendAttempts" in after_host_debug:
      before_attempts = get_int(before_host_debug.get("usbSendAttempts"))
      after_attempts = get_int(after_host_debug.get("usbSendAttempts"))
      if after_attempts <= before_attempts:
        raise AssertionError("host usb send attempts did not advance")

    print(
        json.dumps(
            {
                "host": after_host,
                "controller": {
                    "wsPacketsApplied": after_applied,
                    "wsPacketsReceived": after_received,
                },
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
