"""Pytest hooks: tests run without Google Earth Engine credentials."""

import os

# Contract tests call /land-health without EE; allow synthetic unless CI sets otherwise.
os.environ.setdefault("LANDROID_ALLOW_SYNTHETIC_LAND_HEALTH", "true")
