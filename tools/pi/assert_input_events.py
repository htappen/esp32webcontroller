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


def expect_key(events: list[dict], code: int, value: int) -> None:
    for event in events:
        if event["type"] == EV_KEY and event["code"] == code and event["value"] == value:
            return
    raise AssertionError(f"missing key event code={code} value={value}")


def expect_abs_range(events: list[dict], code: int, minimum: int, maximum: int) -> None:
    for event in events:
        if event["type"] == EV_ABS and event["code"] == code and minimum <= event["value"] <= maximum:
            return
    raise AssertionError(
        f"missing abs event code={code} in range [{minimum}, {maximum}]"
    )


def forbid_keydown(events: list[dict]) -> None:
    offenders = [
        event
        for event in events
        if event["type"] == EV_KEY and event["value"] not in (0,)
    ]
    if offenders:
        raise AssertionError(f"unexpected keydown events: {offenders[:5]}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--expect-key", action="append", default=[])
    parser.add_argument("--expect-abs-range", action="append", default=[])
    parser.add_argument("--forbid-keydown", action="store_true")
    args = parser.parse_args()

    events = load_events(args.file)

    for raw in args.expect_key:
        code_text, value_text = raw.split("=", 1)
        expect_key(events, int(code_text), int(value_text))

    for raw in args.expect_abs_range:
        code_text, minimum_text, maximum_text = raw.split(":", 2)
        expect_abs_range(events, int(code_text), int(minimum_text), int(maximum_text))

    if args.forbid_keydown:
        forbid_keydown(events)

    print(f"assertions passed against {len(events)} events")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
