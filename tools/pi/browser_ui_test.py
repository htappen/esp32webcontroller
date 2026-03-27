#!/usr/bin/env python3
import argparse
import json
import re
import shutil
import subprocess


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--page-url", default="http://game.local")
    parser.add_argument("--chromium-bin")
    parser.add_argument("--virtual-time-budget-ms", type=int, default=5000)
    parser.add_argument("--min-svg-count", type=int, default=2)
    parser.add_argument("--summary-file")
    args = parser.parse_args()

    chromium_bin = args.chromium_bin or shutil.which("chromium") or shutil.which("chromium-browser")
    if not chromium_bin:
        raise FileNotFoundError("could not find Chromium binary")

    result = subprocess.run(
        [
            chromium_bin,
            "--headless",
            "--disable-gpu",
            "--no-sandbox",
            f"--virtual-time-budget={args.virtual_time_budget_ms}",
            "--dump-dom",
            args.page_url,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    dom = result.stdout

    title_match = re.search(r"<title>(.*?)</title>", dom, flags=re.IGNORECASE | re.DOTALL)
    title = title_match.group(1).strip() if title_match else ""
    if title != "ESP32 Controller":
        raise RuntimeError(f"unexpected page title: {title!r}")

    if 'id="controller-stage"' not in dom:
        raise RuntimeError("controller stage element missing from DOM")

    svg_count = len(re.findall(r"<svg\b", dom, flags=re.IGNORECASE))
    if svg_count < args.min_svg_count:
        raise RuntimeError(
            f"controller page did not hydrate expected SVGs: found {svg_count}, need {args.min_svg_count}"
        )

    summary = {
        "pageUrl": args.page_url,
        "title": title,
        "svgCount": svg_count,
        "controllerStagePresent": True,
    }
    if args.summary_file:
        with open(args.summary_file, "w", encoding="utf-8") as handle:
            json.dump(summary, handle, separators=(",", ":"))
            handle.write("\n")

    print(json.dumps(summary, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
