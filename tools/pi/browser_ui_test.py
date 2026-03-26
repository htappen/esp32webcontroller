#!/usr/bin/env python3
import argparse
import json
import shutil
import time

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


PRELOAD_SCRIPT = r"""
(() => {
  const RealWebSocket = window.WebSocket;
  const emptyGamepads = () => [];
  const defineEmptyGamepads = (name) => {
    if (name in navigator || name === "getGamepads") {
      Object.defineProperty(navigator, name, {
        configurable: true,
        value: emptyGamepads,
      });
    }
  };
  defineEmptyGamepads("getGamepads");
  defineEmptyGamepads("webkitGetGamepads");
  defineEmptyGamepads("mozGetGamepads");
  defineEmptyGamepads("msGetGamepads");
  window.__codexUiTest = {
    payloads: [],
    lastUrl: null,
  };

  class RecordingWebSocket extends RealWebSocket {
    constructor(...args) {
      super(...args);
      window.__codexUiTest.lastUrl = String(args[0] || "");
    }

    send(data) {
      try {
        if (typeof data === "string") {
          window.__codexUiTest.payloads.push(JSON.parse(data));
        } else {
          window.__codexUiTest.payloads.push({ nonTextPayload: true });
        }
      } catch (error) {
        window.__codexUiTest.payloads.push({ parseError: String(error), raw: String(data) });
      }
      return super.send(data);
    }
  }

  Object.defineProperty(RecordingWebSocket, "CONNECTING", { value: RealWebSocket.CONNECTING });
  Object.defineProperty(RecordingWebSocket, "OPEN", { value: RealWebSocket.OPEN });
  Object.defineProperty(RecordingWebSocket, "CLOSING", { value: RealWebSocket.CLOSING });
  Object.defineProperty(RecordingWebSocket, "CLOSED", { value: RealWebSocket.CLOSED });

  window.WebSocket = RecordingWebSocket;
})();
"""

BUTTON_TAP_TARGET_IDS = [
    "button_1_tap_target",
    "button_2_tap_target",
    "button_3_tap_target",
    "button_4_tap_target",
    "shoulder_button_front_left_tap_target",
    "shoulder_button_front_right_tap_target",
    "shoulder_trigger_back_left_tap_target",
    "shoulder_trigger_back_right_tap_target",
    "select_button_tap_target",
    "start_button_tap_target",
    "stick_button_left_tap_target",
    "stick_button_right_tap_target",
    "dpad_up_tap_target",
    "dpad_down_tap_target",
    "dpad_left_tap_target",
    "dpad_right_tap_target",
]


def wait_for_button_payload(page, baseline_count: int, button_value: int, timeout_ms: int) -> dict:
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        payload = page.evaluate(
            """([baseline, buttonValue]) => {
              const payloads = window.__codexUiTest.payloads.slice(baseline);
              return payloads.find((entry) => entry && entry.btn && entry.btn.a === buttonValue) || null;
            }""",
            [baseline_count, button_value],
        )
        if payload:
            return payload
        time.sleep(0.1)
    state_name = "pressed" if button_value else "released"
    raise TimeoutError(f"UI click did not produce an A-button {state_name} websocket payload")


def set_button_state(page, gamepad_index: int, button_index: int, value: int, touched: bool) -> None:
    if gamepad_index != 0:
        raise ValueError(f"unsupported gamepad index for UI test: {gamepad_index}")
    if button_index < 0 or button_index >= len(BUTTON_TAP_TARGET_IDS):
        raise ValueError(f"unsupported button index for UI test: {button_index}")

    event_name = "pointerdown" if value else "pointerup"
    buttons = 1 if value else 0
    tap_target_id = BUTTON_TAP_TARGET_IDS[button_index]
    page.evaluate(
        """([tapTargetId, eventName, buttons]) => {
          const target = document.getElementById(tapTargetId);
          if (!target) {
            throw new Error(`gamepad tap target not found: ${tapTargetId}`);
          }
          target.dispatchEvent(new PointerEvent(eventName, {
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 1,
            pointerType: "mouse",
            isPrimary: true,
            button: 0,
            buttons,
          }));
        }""",
        [tap_target_id, event_name, buttons],
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--page-url", default="http://game.local")
    parser.add_argument("--expected-ws-url", default="ws://game.local:81")
    parser.add_argument("--gamepad-index", type=int, default=0)
    parser.add_argument("--button-index", type=int, default=0)
    parser.add_argument("--payload-file")
    parser.add_argument("--chromium-bin")
    parser.add_argument("--click-hold-seconds", type=float, default=0.2)
    parser.add_argument("--post-click-settle-seconds", type=float, default=0.75)
    args = parser.parse_args()

    chromium_bin = args.chromium_bin or shutil.which("chromium") or shutil.which("chromium-browser")
    if not chromium_bin:
      raise FileNotFoundError("could not find Chromium binary")

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=chromium_bin,
            headless=True,
            args=["--no-sandbox"],
        )
        context = browser.new_context(viewport={"width": 1280, "height": 960})
        page = context.new_page()
        page.add_init_script(PRELOAD_SCRIPT)

        try:
            page.goto(args.page_url, wait_until="load", timeout=15000)
            page.wait_for_selector("#controller-root svg", timeout=10000)

            title = page.title()
            if title != "ESP32 Controller":
                raise RuntimeError(f"unexpected page title: {title!r}")

            try:
                page.wait_for_function(
                    "() => window.__codexUiTest && typeof window.__codexUiTest.lastUrl === 'string' && window.__codexUiTest.lastUrl.length > 0",
                    timeout=10000,
                )
            except PlaywrightTimeoutError as exc:
                raise TimeoutError("page did not attempt websocket connection") from exc

            last_ws_url = page.evaluate("() => window.__codexUiTest.lastUrl")
            if last_ws_url != args.expected_ws_url:
                raise RuntimeError(f"unexpected websocket URL: {last_ws_url!r}")

            try:
                page.wait_for_function("() => window.__codexUiTest.payloads.length > 0", timeout=10000)
            except PlaywrightTimeoutError as exc:
                raise TimeoutError("page did not send any websocket payloads") from exc

            try:
                page.wait_for_function(
                    "() => !!window.__controllerApp?.gamepadController?.gpadEmulator",
                    timeout=10000,
                )
            except PlaywrightTimeoutError as exc:
                raise TimeoutError("page did not expose gamepad emulator test hook") from exc

            baseline_payload_count = page.evaluate("() => window.__codexUiTest.payloads.length")
            set_button_state(page, args.gamepad_index, args.button_index, 1, True)
            pressed_payload = wait_for_button_payload(page, baseline_payload_count, button_value=1, timeout_ms=10000)
            time.sleep(args.click_hold_seconds)
            pressed_payload_count = page.evaluate("() => window.__codexUiTest.payloads.length")
            set_button_state(page, args.gamepad_index, args.button_index, 0, False)
            release_payload = wait_for_button_payload(page, pressed_payload_count, button_value=0, timeout_ms=10000)

            if args.payload_file:
                with open(args.payload_file, "w", encoding="utf-8") as handle:
                    json.dump(pressed_payload, handle, separators=(",", ":"))
                    handle.write("\n")

            # Keep the browser session alive briefly so the ESP32 can push the
            # pressed report through BLE before the page disconnects.
            time.sleep(args.post_click_settle_seconds)

            summary = {
                "pageUrl": args.page_url,
                "title": title,
                "expectedWsUrl": args.expected_ws_url,
                "observedWsUrl": last_ws_url,
                "gamepadIndex": args.gamepad_index,
                "buttonIndex": args.button_index,
                "pressedPayload": pressed_payload,
                "releasePayload": release_payload,
            }
            print(json.dumps(summary, separators=(",", ":")))
            return 0
        finally:
            context.close()
            browser.close()


if __name__ == "__main__":
    raise SystemExit(main())
