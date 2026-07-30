# Flutter Frontend Migration Runbook

This runbook covers Flutter app execution, USB debugging, and unsigned release APK generation for this repository.

## Canonical Frontend

- New frontend: `flutter_app/`
- Legacy React Native frontends currently left in place:
  - `mobile/`
  - `LandroidApp/`

## Prerequisites

From `flutter_app/`:

```bash
flutter --version
flutter pub get
flutter doctor -v
```

If `flutter doctor -v` reports Android command line tools missing:

1. Open Android Studio > SDK Manager.
2. Install **Android SDK Command-line Tools (latest)**.
3. Re-run `flutter doctor -v`.

## USB Debugging Setup (Windows + Android Phone)

1. Enable Developer Options on phone.
2. Enable USB debugging.
3. Connect via USB and accept the RSA authorization prompt.
4. Verify:

```bash
adb devices -l
flutter devices
```

Expected: device appears as `device` (not `unauthorized`).

## Run On USB Device

From `flutter_app/`:

```bash
flutter run -d <device_id> --debug
```

Notes:
- For physical devices, backend URL should use your PC LAN IP (not `10.0.2.2`).
- Override API base URL at runtime:

```bash
flutter run -d <device_id> --debug --dart-define=API_BASE_URL=http://<your-pc-lan-ip>:8000/api/v1
```

Default fallback in code (emulator-safe): `http://10.0.2.2:8000/api/v1`.

## Build Unsigned Release APK

From `flutter_app/`:

```bash
flutter build apk --release
```

Output:
- `flutter_app/build/app/outputs/flutter-apk/app-release.apk`

Unsigned verification command (use full path on Windows if `apksigner` is not in `PATH`):

```bash
C:\Users\<you>\AppData\Local\Android\Sdk\build-tools\<version>\apksigner.bat verify --print-certs flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

If unsigned, output includes:
- `DOES NOT VERIFY`
- `Missing META-INF/MANIFEST.MF`

## Common USB Troubleshooting

- Device not listed:
  - Reconnect cable and select File Transfer mode.
  - Run `adb kill-server` then `adb start-server`.
  - Re-check `adb devices -l`.
- Device shows `unauthorized`:
  - Revoke USB debugging authorizations on phone.
  - Replug and accept fingerprint prompt.
- Flutter cannot deploy:
  - Run `flutter clean && flutter pub get`.
  - Confirm `flutter doctor -v` Android status.

## Signed APK (Deferred)

Signed release is intentionally deferred. When signing credentials are available:

1. Create/provide keystore.
2. Add `key.properties`.
3. Configure `android/app/build.gradle.kts` signing config.
4. Build signed release APK and verify with `apksigner`.
