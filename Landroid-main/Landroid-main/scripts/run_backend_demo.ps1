# Start Landroid API with a demo orthomosaic tile URL for mobile testing.
# DEM: leave LANDROID_DEM_TILE_URL_TEMPLATE unset so a GeoTIFF in ../data/ is used
# (hillshade PNG). Set LANDROID_DEM_TILE_URL_TEMPLATE yourself to force remote tiles instead.

$ErrorActionPreference = "Stop"
# Default 8013 to match flutter_app/run_android.ps1; override with LANDROID_API_PORT.
$Port = if ($env:LANDROID_API_PORT -match '^\d+$') { [int]$env:LANDROID_API_PORT } else { 8013 }

$env:LANDROID_ORTHOMOSAIC_TILE_URL_TEMPLATE = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
$env:LANDROID_ORTHOMOSAIC_TILE_SCHEME = "xyz"
# Intentionally no LANDROID_DEM_TILE_* — use local "Digital Elevation model.tif" etc. under data/

Set-Location (Join-Path $PSScriptRoot "..\backend")
Write-Host "Starting API on 0.0.0.0:$Port (Wi‑Fi devices use http://<PC-LAN-IP>:$Port/api/v1; USB + adb reverse can use 127.0.0.1)..."
Write-Host "If Windows Firewall blocks inbound connections, allow Python for this port."
python -m uvicorn app.main:app --host 0.0.0.0 --port $Port
