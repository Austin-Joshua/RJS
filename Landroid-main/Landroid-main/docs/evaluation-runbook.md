# Evaluation Runbook (5-Minute Judge Flow)

## Pre-Demo Checklist

1. Backend running and healthy (`GET /api/v1/healthz`).
2. Mobile app connected to backend.
3. Consultant session active.
4. Parcel created from `data/Boundary.geojson`.
5. API responses pre-warmed once.

## Live Demo Script

1. **Consultant login**
   - Show role = consultant.
   - Create parcel.
2. **GIS check (M-04)**
   - Open map, show boundary overlay and map navigation.
3. **AI module check (M-02)**
   - Open dashboard and show:
     - Land Health score + confidence.
     - Plant Zones + confidence.
4. **Parcel sensitivity (M-01)**
   - Recreate parcel with changed NDVI and show score change.
5. **RBAC (M-03)**
   - Switch to landowner.
   - Attempt consultant action; show blocked behavior.
6. **Desirable features**
   - Show valuation top factors (D-03).
   - Show clear cache action in settings (D-04).
   - Toggle Tamil labels (D-02).

## Timing Target

- 00:00–01:00 auth + parcel
- 01:00–02:00 GIS
- 02:00–03:30 AI modules
- 03:30–04:30 RBAC
- 04:30–05:00 desirable extras
