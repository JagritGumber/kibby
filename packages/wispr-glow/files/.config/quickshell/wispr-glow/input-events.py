#!/usr/bin/env python3
"""Observe Wispr control keys without grabbing input devices."""

import glob
import json
import os
import select
import struct
import time

EVENT = struct.Struct("@llHHI")
EV_KEY = 0x01
KEY_NAMES = {
    1: "escape",
    97: "right_ctrl",
}


def add_devices(devices):
    known = {device.name for device in devices.values()}
    for path in sorted(glob.glob("/dev/input/event*")):
        if path in known:
            continue
        try:
            device = open(path, "rb", buffering=0)
            os.set_blocking(device.fileno(), False)
            devices[device.fileno()] = device
        except (OSError, PermissionError):
            pass


def main():
    devices = {}
    last_scan = 0.0
    while True:
        now = time.monotonic()
        if not devices or now - last_scan >= 2:
            add_devices(devices)
            last_scan = now
        if not devices:
            time.sleep(1)
            continue
        readable, _, _ = select.select(list(devices), [], [], 0.5)
        for fd in readable:
            device = devices[fd]
            try:
                payload = device.read(EVENT.size * 32)
            except OSError:
                payload = b""
            if not payload:
                device.close()
                devices.pop(fd, None)
                continue
            for offset in range(0, len(payload) - EVENT.size + 1, EVENT.size):
                _, _, event_type, code, value = EVENT.unpack_from(payload, offset)
                if event_type == EV_KEY and code in KEY_NAMES:
                    state = {0: "up", 1: "down", 2: "repeat"}.get(value, "unknown")
                    print(json.dumps({"key": KEY_NAMES[code], "state": state}), flush=True)


if __name__ == "__main__":
    main()
