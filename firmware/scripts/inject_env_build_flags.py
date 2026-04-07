Import("env")

import os


def env_flag_enabled(name: str) -> bool:
    value = os.environ.get(name, "").strip().lower()
    return value in {"1", "true", "yes", "on"}


if env_flag_enabled("CONTROLLER_USB_XINPUT_DEFER_BEGIN"):
    print("[pio] enabling deferred USB.begin() for usb_xinput")
    env.Append(CPPDEFINES=[("CONTROLLER_USB_XINPUT_DEFER_BEGIN", 1)])
