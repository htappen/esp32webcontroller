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
    parser.add_argument("--status", required=True)
    parser.add_argument("--expect-transport")
    parser.add_argument("--expect-variant")
    parser.add_argument("--label", default="controller")
    args = parser.parse_args()

    status = load_json(args.status)
    controller = status.get("controller", {})
    host = status.get("host", {})

    if args.expect_transport is not None and host.get("transport") != args.expect_transport:
        raise AssertionError(
            f"unexpected host transport: {host.get('transport')!r} != {args.expect_transport!r}"
        )
    if args.expect_variant is not None and host.get("variant") != args.expect_variant:
        raise AssertionError(
            f"unexpected host variant: {host.get('variant')!r} != {args.expect_variant!r}"
        )
    if not controller.get("wsConnected"):
        raise AssertionError(f"{args.label} is not websocket-connected")

    assigned_slots = get_int(controller.get("assignedSlots"))
    active_slots = get_int(controller.get("activeSlots"))
    if assigned_slots < 1:
        raise AssertionError(f"{args.label} did not report any assigned slots")
    if active_slots < 1:
        raise AssertionError(f"{args.label} did not report any active slots")

    clients = controller.get("clients") or []
    connected_clients = [
        client
        for client in clients
        if client.get("assigned") and client.get("connected") and client.get("active")
    ]
    if not connected_clients:
        raise AssertionError(f"{args.label} did not expose an active assigned client")

    print(
        json.dumps(
            {
                "host": host,
                "controller": {
                    "wsConnected": controller.get("wsConnected"),
                    "assignedSlots": assigned_slots,
                    "activeSlots": active_slots,
                    "activeClientCount": len(connected_clients),
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
