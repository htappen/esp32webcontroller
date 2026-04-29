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
    parser.add_argument("--expect-assigned-slots", type=int)
    parser.add_argument("--expect-active-slots", type=int)
    parser.add_argument("--expect-reserved-slots", type=int)
    parser.add_argument("--allow-disconnected", action="store_true")
    parser.add_argument("--print-active-slot", action="store_true")
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
    if not args.allow_disconnected and not controller.get("wsConnected"):
        raise AssertionError(f"{args.label} is not websocket-connected")

    assigned_slots = get_int(controller.get("assignedSlots"))
    active_slots = get_int(controller.get("activeSlots"))
    clients = controller.get("clients") or []
    reserved_slots = len([client for client in clients if client.get("reserved")])
    active_clients = [
        client
        for client in clients
        if client.get("assigned") and client.get("connected") and client.get("active")
    ]

    if args.expect_assigned_slots is not None and assigned_slots != args.expect_assigned_slots:
        raise AssertionError(
            f"{args.label} expected {args.expect_assigned_slots} assigned slots, got {assigned_slots}"
        )
    if args.expect_active_slots is not None and active_slots != args.expect_active_slots:
        raise AssertionError(f"{args.label} expected {args.expect_active_slots} active slots, got {active_slots}")
    if args.expect_reserved_slots is not None and reserved_slots != args.expect_reserved_slots:
        raise AssertionError(
            f"{args.label} expected {args.expect_reserved_slots} reserved slots, got {reserved_slots}"
        )

    if args.expect_assigned_slots is None and assigned_slots < 1:
        raise AssertionError(f"{args.label} did not report any assigned slots")
    if args.expect_active_slots is None and not args.allow_disconnected and active_slots < 1:
        raise AssertionError(f"{args.label} did not report any active slots")
    if not args.allow_disconnected and not active_clients:
        raise AssertionError(f"{args.label} did not expose an active assigned client")

    if args.print_active_slot:
        if len(active_clients) != 1:
            raise AssertionError(f"{args.label} expected exactly one active client, found {len(active_clients)}")
        slot_value = get_int(active_clients[0].get("slot"))
        if slot_value < 1:
            raise AssertionError(f"{args.label} did not expose a valid active slot number")
        print(slot_value)
        return 0

    print(
        json.dumps(
            {
                "host": host,
                "controller": {
                    "wsConnected": controller.get("wsConnected"),
                    "assignedSlots": assigned_slots,
                    "activeSlots": active_slots,
                    "reservedSlots": reserved_slots,
                    "activeClientCount": len(active_clients),
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
