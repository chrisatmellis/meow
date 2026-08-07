#!/usr/bin/env python3
"""Freshens `lastSeen` in a save file.

Used before a screenshot launch so the offline catch-up finds nothing to report
and the "while you were away" sheet does not cover the room.
"""
import datetime
import json
import sys

path = sys.argv[1]
with open(path) as f:
    save = json.load(f)
save["lastSeen"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(path, "w") as f:
    json.dump(save, f)
