#!/usr/bin/env python3
"""Picks a usable iOS simulator from `xcrun simctl list ... --json` output.

Runtimes and device types are not freely combinable — an iOS 26 runtime refuses
an iPhone 6s — so this prefers a device the machine has already created, since
those are known-good pairings. Falls back to naming a modern device type to
create.

    pick-simulator.py devices <devices.json>   -> "<udid> <name>"  (or nothing)
    pick-simulator.py runtime <devices.json>   -> newest iOS runtime identifier
"""
import json
import re
import sys

# The app's deployment target. Anything older cannot install it, and the error
# simctl gives when you try does not mention the version — so a runtime that is
# too old is filtered out here rather than becoming a puzzling install failure
# twenty lines further down.
MINIMUM = (18, 0)


def newest_first(devices):
    """All available iPhones, worst candidate first."""
    ranked = []
    for runtime, devs in devices.items():
        match = re.search(r"iOS-(\d+)-(\d+)", runtime)
        if not match:
            continue
        version = (int(match.group(1)), int(match.group(2)))
        if version < MINIMUM:
            continue
        for dev in devs:
            if not dev.get("isAvailable"):
                continue
            name = dev.get("name", "")
            if "iPhone" not in name:
                continue
            number = re.search(r"iPhone\s+(\d+)", name)
            ranked.append((
                version,
                int(number.group(1)) if number else 0,
                1 if "Pro" in name else 0,
                dev["udid"],
                name,
            ))
    ranked.sort()
    return ranked


def main():
    if len(sys.argv) < 3:
        return 1
    mode, path = sys.argv[1], sys.argv[2]
    with open(path) as f:
        devices = json.load(f)["devices"]

    if mode == "devices":
        ranked = newest_first(devices)
        if ranked:
            print(ranked[-1][3], ranked[-1][4])
        return 0

    if mode == "runtime":
        runtimes = []
        for r in devices:
            match = re.search(r"iOS-(\d+)-(\d+)", r)
            if match and (int(match.group(1)), int(match.group(2))) >= MINIMUM:
                runtimes.append(((int(match.group(1)), int(match.group(2))), r))
        if runtimes:
            print(sorted(runtimes)[-1][1])
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
