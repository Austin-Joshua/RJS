# Evidence Capture Guide

This folder contains proof artifacts for mandatory/desirable evaluation.

## Present Artifacts

- `backend_test_report.txt`: unit and API-level test results.

## Capture Remaining Demo Artifacts

1. `m01_parcel_variation_before_after.png`
   - Two dashboard screenshots with different NDVI parcel inputs.
2. `m03_forbidden_flow.mp4`
   - Landowner blocked from consultant-only action.
3. `m04_map_alignment.png`
   - Boundary alignment and layer visibility.
4. `d04_cache_clear.mp4`
   - Settings -> Clear cache -> confirmation.
5. `d02_tamil_ui.png`
   - Tamil locale labels visible.

## Commanded Validation

Run this once backend is live:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\mandatory_validation.ps1
```
