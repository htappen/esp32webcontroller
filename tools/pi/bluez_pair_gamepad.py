#!/usr/bin/env python3
import argparse
import os
import sys
import time

import dbus
import dbus.exceptions
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BLUEZ_SERVICE = "org.bluez"
AGENT_MANAGER_IFACE = "org.bluez.AgentManager1"
AGENT_IFACE = "org.bluez.Agent1"
ADAPTER_IFACE = "org.bluez.Adapter1"
DEVICE_IFACE = "org.bluez.Device1"
OBJECT_MANAGER_IFACE = "org.freedesktop.DBus.ObjectManager"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
AGENT_PATH = "/com/controller/pi/agent"


class PairingAgent(dbus.service.Object):
    def __init__(self, bus, path, logger):
        super().__init__(bus, path)
        self._logger = logger

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        self._logger("agent released")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        self._logger(f"pin code requested for {device}, returning empty code")
        return ""

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="")
    def DisplayPinCode(self, device, pincode):
        self._logger(f"display pin code for {device}: {pincode}")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        self._logger(f"passkey requested for {device}, returning 0")
        return dbus.UInt32(0)

    @dbus.service.method(AGENT_IFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        self._logger(f"display passkey for {device}: {int(passkey):06d}")

    @dbus.service.method(AGENT_IFACE, in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        self._logger(f"auto-confirming passkey {int(passkey):06d} for {device}")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        self._logger(f"authorizing device {device}")

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        self._logger(f"authorizing service {uuid} for {device}")

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        self._logger("agent request cancelled")


class Pairer:
    def __init__(self, device_name: str, timeout: float, attempts: int):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self.bus = dbus.SystemBus()
        self.loop = GLib.MainLoop()
        self.device_name = device_name
        self.timeout = timeout
        self.attempts = attempts
        self.agent = PairingAgent(self.bus, AGENT_PATH, self.log)
        self.agent_manager = dbus.Interface(
            self.bus.get_object(BLUEZ_SERVICE, "/org/bluez"),
            AGENT_MANAGER_IFACE,
        )
        self.adapter_path = self._find_adapter_path()
        self.adapter_props = dbus.Interface(
            self.bus.get_object(BLUEZ_SERVICE, self.adapter_path),
            PROPERTIES_IFACE,
        )
        self.adapter_methods = dbus.Interface(
            self.bus.get_object(BLUEZ_SERVICE, self.adapter_path),
            ADAPTER_IFACE,
        )
        self._pending_error = None

    def log(self, message: str) -> None:
        print(f"[pi-pair] {message}", flush=True)

    def _find_adapter_path(self) -> str:
        objects = self._managed_objects()
        for path, interfaces in objects.items():
            if ADAPTER_IFACE in interfaces:
                return path
        raise RuntimeError("no Bluetooth adapter found")

    def _managed_objects(self):
        manager = dbus.Interface(
            self.bus.get_object(BLUEZ_SERVICE, "/"),
            OBJECT_MANAGER_IFACE,
        )
        return manager.GetManagedObjects()

    def _device_match(self, properties) -> bool:
        return (
            properties.get("Name") == self.device_name
            or properties.get("Alias") == self.device_name
        )

    def _find_device(self):
        for path, interfaces in self._managed_objects().items():
            props = interfaces.get(DEVICE_IFACE)
            if props and self._device_match(props):
                return path, props
        return None, None

    def _get_device_properties(self, path: str):
        objects = self._managed_objects()
        return objects.get(path, {}).get(DEVICE_IFACE, {})

    def _wait_for(self, predicate, description: str):
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            while GLib.MainContext.default().iteration(False):
                pass
            time.sleep(0.2)
        raise TimeoutError(f"timed out waiting for {description}")

    def _set_property(self, path: str, prop: str, value):
        props = dbus.Interface(
            self.bus.get_object(BLUEZ_SERVICE, path),
            PROPERTIES_IFACE,
        )
        props.Set(DEVICE_IFACE, prop, value)

    def _call_async(self, path: str, method_name: str):
        device = dbus.Interface(
            self.bus.get_object(BLUEZ_SERVICE, path),
            DEVICE_IFACE,
        )
        self._pending_error = None

        def on_success():
            self.loop.quit()

        def on_error(error):
            self._pending_error = error
            self.loop.quit()

        getattr(device, method_name)(
            reply_handler=on_success,
            error_handler=on_error,
            dbus_interface=DEVICE_IFACE,
        )
        GLib.timeout_add(int(self.timeout * 1000), self.loop.quit)
        self.loop.run()
        if self._pending_error is not None:
            raise self._pending_error

    def _register_agent(self):
        self.log("registering NoInputNoOutput BlueZ agent")
        try:
            self.agent_manager.UnregisterAgent(AGENT_PATH)
        except dbus.exceptions.DBusException:
            pass
        self.agent_manager.RegisterAgent(AGENT_PATH, "NoInputNoOutput")
        self.agent_manager.RequestDefaultAgent(AGENT_PATH)

    def _unregister_agent(self):
        try:
            self.agent_manager.UnregisterAgent(AGENT_PATH)
        except dbus.exceptions.DBusException:
            pass

    def _remove_existing_device(self):
        path, props = self._find_device()
        if not path:
            return
        address = props.get("Address", "unknown")
        self.log(f"removing stale device {address}")
        adapter = dbus.Interface(
            self.bus.get_object(BLUEZ_SERVICE, self.adapter_path),
            ADAPTER_IFACE,
        )
        adapter.RemoveDevice(path)

    def _discover_device(self):
        self.log(f"discovering {self.device_name}")
        try:
            self.adapter_props.Set(ADAPTER_IFACE, "Powered", dbus.Boolean(True))
        except dbus.exceptions.DBusException:
            pass
        try:
            self.adapter_methods.SetDiscoveryFilter({"Transport": dbus.String("le")})
        except dbus.exceptions.DBusException:
            pass
        self.adapter_methods.StartDiscovery()
        try:
            path, props = self._wait_for(
                lambda: self._find_device()[0:2] if self._find_device()[0] else None,
                f"device {self.device_name}",
            )
            address = props.get("Address", "unknown")
            self.log(f"found {self.device_name} at {address}")
            return path, props
        finally:
            try:
                self.adapter_methods.StopDiscovery()
            except dbus.exceptions.DBusException:
                pass

    def _pair(self, path: str):
        self.log("starting BlueZ pair()")
        try:
            self._call_async(path, "Pair")
        except dbus.exceptions.DBusException as exc:
            name = exc.get_dbus_name()
            if name in {
                "org.bluez.Error.AlreadyExists",
                "org.bluez.Error.AlreadyConnected",
            }:
                self.log(f"pairing already satisfied: {name}")
            else:
                raise
        self._wait_for(
            lambda: self._get_device_properties(path).get("Paired", False),
            "device to become paired",
        )

    def _connect(self, path: str):
        self.log("starting BlueZ connect()")
        try:
            self._call_async(path, "Connect")
        except dbus.exceptions.DBusException as exc:
            name = exc.get_dbus_name()
            if name == "org.bluez.Error.AlreadyConnected":
                self.log("device already connected")
            else:
                raise
        self._wait_for(
            lambda: self._get_device_properties(path).get("Connected", False),
            "device to become connected",
        )

    def run_once(self) -> str:
        self._register_agent()
        try:
            self._remove_existing_device()
            path, props = self._discover_device()
            self._pair(path)
            self._set_property(path, "Trusted", dbus.Boolean(True))
            self._connect(path)
            final_props = self._get_device_properties(path)
            if not final_props.get("Paired", False):
                raise RuntimeError("device is not paired")
            if not final_props.get("Connected", False):
                raise RuntimeError("device is not connected")
            address = str(final_props.get("Address", ""))
            self.log(f"paired and connected {self.device_name} at {address}")
            print(address, flush=True)
            return address
        finally:
            self._unregister_agent()

    def run(self) -> str:
        last_error = None
        for attempt in range(1, self.attempts + 1):
            try:
                if attempt > 1:
                    self.log(f"retrying pair/connect flow (attempt {attempt}/{self.attempts})")
                return self.run_once()
            except Exception as exc:
                last_error = exc
                self.log(f"attempt {attempt} failed: {exc}")
                time.sleep(1.0)
        raise last_error


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-name", default=os.environ.get("BLE_NAME", "Sunny Maple Pad"))
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--attempts", type=int, default=3)
    args = parser.parse_args()

    pairer = Pairer(args.device_name, args.timeout, args.attempts)
    pairer.run()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[pi-pair] {exc}", file=sys.stderr)
        raise SystemExit(1)
