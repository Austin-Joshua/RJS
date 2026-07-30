# Run on a USB Android device. Sets PUB_CACHE to D:\Landroid\.pub-cache so native-asset
# hooks (objective_c) do not run `cd` into %USERPROFILE% paths that contain spaces.
#
#   cd D:\Landroid\flutter_app
#   .\run_android.ps1
#
# Optional:
#   $env:LANDROID_API_PORT = "8013"  (match run_backend_demo.ps1)
#   $env:LANDROID_API_BASE_URL = "http://127.0.0.1:8013/api/v1"  (full override)
#   $env:LANDROID_USE_LOCALHOST_API = "1"  (127.0.0.1 + adb reverse; good for USB without Wi-Fi)
# Default: first non-loopback IPv4 on this PC so the phone on the same Wi‑Fi can reach the API
# (backend must listen on 0.0.0.0 — see scripts/run_backend_demo.ps1).

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$PubCache = Join-Path (Split-Path $Root -Parent) ".pub-cache"
if (-not (Test-Path $PubCache)) {
    New-Item -ItemType Directory -Path $PubCache | Out-Null
}
$env:PUB_CACHE = (Resolve-Path $PubCache).Path

$ApiPort = 8013
if ($env:LANDROID_API_PORT -match '^\d+$') {
    $ApiPort = [int]$env:LANDROID_API_PORT
}

if ($env:LANDROID_API_BASE_URL -and $env:LANDROID_API_BASE_URL.Trim().Length -gt 0) {
    $ApiUrl = $env:LANDROID_API_BASE_URL.Trim()
} elseif ($env:LANDROID_USE_LOCALHOST_API -eq "1") {
    $ApiUrl = "http://127.0.0.1:$ApiPort/api/v1"
} else {
    $lan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.'
        } |
        Sort-Object InterfaceMetric |
        Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $lan) {
        $lan = "127.0.0.1"
        Write-Warning "No LAN IPv4 found; using 127.0.0.1 (set LANDROID_USE_LOCALHOST_API=1 and use adb reverse, or set LANDROID_API_BASE_URL)."
    }
    $ApiUrl = "http://${lan}:$ApiPort/api/v1"
}

$FlutterExe = "flutter"
foreach ($candidate in @(
        "X:\develop\flutter\bin\flutter.bat",
        (Join-Path $env:USERPROFILE "develop\flutter\bin\flutter.bat")
    )) {
    if ($candidate -and (Test-Path $candidate)) {
        $FlutterExe = $candidate
        break
    }
}

Write-Host "PUB_CACHE=$($env:PUB_CACHE)"
Write-Host "Flutter: $FlutterExe"

Set-Location $Root
& $FlutterExe pub get

$serial = (adb devices | Select-String "^\S+\s+device\s*$" | Select-Object -First 1)
if (-not $serial) {
    Write-Error "No Android device in 'adb devices' (enable USB debugging)."
}
$deviceId = ($serial.Line -split '\s+')[0]
Write-Host "Device: $deviceId"

if ($ApiUrl -match '127\.0\.0\.1|localhost') {
    & adb -s $deviceId reverse "tcp:$ApiPort" "tcp:$ApiPort"
    Write-Host "adb reverse tcp:$ApiPort (localhost API)"
} else {
    Write-Host "Using LAN URL - ensure the API listens on 0.0.0.0:${ApiPort} (adb reverse not required)."
}

Write-Host "API_BASE_URL=$ApiUrl"
$dartDefine = "--dart-define=API_BASE_URL=$ApiUrl"
& $FlutterExe run -d $deviceId $dartDefine
