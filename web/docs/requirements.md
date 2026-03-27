# Overview
This document outlines the user interaction flow for the controller app. The coding agent should use this to update the behavior.

## User flow

1. When the ESP32 powers on, it checks whether it has saved Wi-Fi configuration.
   1. If saved Wi-Fi configuration exists, it should attempt to connect to that network.
   2. If it connects successfully, it should not continue broadcasting its own Wi-Fi network.
   3. If it cannot connect after some retries, it should instead broadcast its own Wi-Fi network so a user can connect locally and reconfigure it.
   4. If no saved Wi-Fi configuration exists, it should start by broadcasting its own Wi-Fi network.
2. Regardless of if the ESP32 is connected to a shared wifi network or a device is connected to its network, a device can navigate to http://game.local .
3. The first page should only have the gamepad and a button to launch config on it. We'll cover more about the gamepad later.
4. When the user presses the config button, a modal should open on the same page and include an `X` button to close it.
5. The config modal should have a clear separator between `Device Config` and `Controller Config`.
   1. `Device Config` includes Wi-Fi settings.
      1. The user can enter an SSID and password, then press Enter or click the connect button.
      2. The device should try to connect using the new credentials before replacing the currently saved configuration.
      3. New Wi-Fi credentials should only be saved onto the ESP32 after a successful connection.
      4. If the new connection attempt fails, the previously saved working credentials should be kept.
   2. `Controller Config` includes a controller layout dropdown.
      1. Currently, only one layout is supported, taken from the virtual-gamepad lib.
      2. Controller configuration should be persisted in browser cookies on the client device, not in ESP32 firmware storage.

## Security
Wi-Fi passwords should not be exposed through the UI, APIs, or logs.
The implementation should reduce the risk of someone reading saved passwords from a lost ESP32 device, and any final implementation should document the security tradeoffs of the chosen storage approach.

## Design
The design should use a clean, minimalist design using modern typography and iconography. It's overall color scheme should be black background, white text, and lilac highlights. You can use other shades of purple if you need more differentiation.

The main page from game.local should not have any text or extra layout on it. It should have a black background and no padding.

The only thing the main page should have is the config button and the virtual gamepad. The config button should be a circle with a gear inside of it. Embed the image into CSS, preferably using an icon or glyph for it.

The gamepad should be a split gamepad, and shown in the virtual-gamepad adapters. The left half should be align to the bottom left of the screen. The right half should align to the bottom right. The gamepad images should shrink to fit the vertical area of the screen, but never grow past the image's native size. It should also maintain its aspect ratio.


## Construction
In order to make editing easy, it should use separate HTML, js, and css files for layout and code. It should follow good coding principles.

## Testing
The project should include an automated or semi-automated validation path for both Wi-Fi operating modes without storing real STA credentials in git.

1. AP fallback path:
   1. Verify the device starts or falls back to its own AP when no saved credentials exist or STA connection fails.
   2. Verify the device remains reachable through `http://game.local` and status APIs in this mode.
2. STA success path:
   1. Verify the device can accept test STA credentials from a non-UI test path.
   2. Verify the device joins the shared Wi-Fi network successfully.
   3. Verify the device stops broadcasting its AP once STA is connected.
   4. Verify the saved credentials survive reboot and reconnect correctly.
3. Failed credential update path:
   1. Verify a bad candidate STA update does not replace the previously saved working credentials.
   2. Verify the device still reconnects using the previous saved credentials after reboot.
4. Secret handling for tests:
   1. Real STA test credentials must come from ignored local environment configuration, not tracked repository files.
   2. The test path does not need to drive the browser UI, but it should still verify the same firmware behavior that the UI relies on.
