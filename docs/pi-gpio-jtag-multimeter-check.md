# Raspberry Pi To ESP32-S3 JTAG Wiring Check With A Multimeter

This procedure checks electrical continuity and basic logic-level behavior for the Raspberry Pi GPIO JTAG wiring before relying on OpenOCD.

It does not prove that JTAG protocol is working. It only proves that the wires, ground reference, and pin mapping are plausible.

## Wiring Under Test

- ESP32-S3 `GPIO39` `MTCK` -> Raspberry Pi `GPIO11` (physical pin 23)
- ESP32-S3 `GPIO40` `MTDO` -> Raspberry Pi `GPIO24` (physical pin 18)
- ESP32-S3 `GPIO41` `MTDI` -> Raspberry Pi `GPIO25` (physical pin 22)
- ESP32-S3 `GPIO42` `MTMS` -> Raspberry Pi `GPIO7` (physical pin 26)
- ESP32-S3 `GND` -> Raspberry Pi `GND`

## Equipment

- Digital multimeter
- Access to the Raspberry Pi shell
- The ESP32-S3 powered off for continuity checks

## Safety

- Do not use continuity mode on powered hardware.
- Use voltage mode only when both boards are powered normally.
- Keep the Pi and ESP32-S3 at 3.3 V logic only.

## Step 1: Check Ground Continuity

1. Power both boards off.
2. Put the multimeter in continuity mode.
3. Probe Raspberry Pi ground and ESP32-S3 ground.
4. Confirm the meter beeps or shows near-zero resistance.

If this fails, stop. JTAG will not work reliably without common ground.

## Step 2: Check Each Wire End-To-End

Power both boards off.

For each signal below, place one probe on the Pi header pin and the other on the matching ESP32-S3 pin or solder point:

- Pi pin 23 to ESP32-S3 `GPIO39`
- Pi pin 18 to ESP32-S3 `GPIO40`
- Pi pin 22 to ESP32-S3 `GPIO41`
- Pi pin 26 to ESP32-S3 `GPIO42`

Expected result:

- The intended pair shows continuity.
- Adjacent unintended pins do not show continuity.

If a line is open or shorted to a neighbor, fix that before any OpenOCD testing.

## Step 3: Check For Shorts To Ground Or 3V3

Keep both boards powered off.

For each JTAG line, measure resistance:

- signal to ground
- signal to 3.3 V

Expected result:

- Not a dead short to ground
- Not a dead short to 3.3 V

A hard short suggests a wiring mistake or another circuit driving the line.

## Step 4: Drive A Pi GPIO And Measure It On The ESP32 Side

This verifies that the wire carries a logic level from the Pi to the ESP32 pin.

Example using Pi `GPIO11`, which is wired to ESP32-S3 `GPIO39`:

```bash
pinctrl set 11 op dl
pinctrl get 11
```

Measure voltage from ESP32-S3 `GPIO39` to ground.

Expected result:

- Near 0 V when driven low

Then drive it high:

```bash
pinctrl set 11 op dh
pinctrl get 11
```

Measure again at ESP32-S3 `GPIO39`.

Expected result:

- Near 3.3 V when driven high

Repeat the same style of check for:

- Pi `GPIO24` -> ESP32-S3 `GPIO40`
- Pi `GPIO25` -> ESP32-S3 `GPIO41`
- Pi `GPIO7` -> ESP32-S3 `GPIO42`

## Step 5: Return The Pi Pins To Inputs

After the voltage checks, release the Pi GPIOs:

```bash
pinctrl set 11 ip
pinctrl set 24 ip
pinctrl set 25 ip
pinctrl set 7 ip
```

## Interpretation

- Good continuity plus correct low/high voltage strongly suggests the physical wiring is correct.
- If OpenOCD still reports all-zero scan chain after this, the next likely causes are target-selection strap or eFuse state, wrong target reset state, or the ESP32-S3 JTAG pins being repurposed or loaded by other hardware.
