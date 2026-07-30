# Validation Matrix (Judge-Verifiable)

## Mandatory Criteria

| ID | Criterion | How to Validate | Evidence Artifact |
|---|---|---|---|
| M-01 | At least one AI module uses real Birdscale data | Create parcel with `data/Boundary.geojson`, run AI endpoints, then change NDVI input and rerun. | `evidence/m01_parcel_variation.png`, endpoint logs |
| M-02 | At least 2 AI modules with confidence | Call `land-health` and `plant-zones`; verify `confidence` exists in response and UI. | Dashboard screenshot + JSON response dump |
| M-03 | Role-distinct access control | Log in as landowner and attempt consultant parcel create + foreign parcel read. Must return 403/blocked UI. | `evidence/m03_forbidden_api.txt`, screen recording |
| M-04 | GIS map renders correctly | Open map screen, verify boundary overlay aligns and layers toggle. | `evidence/m04_map_alignment.png` |
| M-05 | Confidentiality agreement submitted | Ensure signed form from PDF page is submitted to coordinator. | Submission confirmation email |
| M-06 | No credentials in source | Run secret scan and inspect repo for keys/tokens in tracked files. | `evidence/m06_secret_scan.txt` |

## Desirable Criteria

| ID | Criterion | Status | Evidence |
|---|---|---|---|
| D-03 | Land valuation factor breakdown | Implemented | `valuation` API response + dashboard card |
| D-04 | Clear cache success | Implemented | Settings screen demo + post-clear verification |
| D-02 | Tamil support | Implemented baseline | Locale toggle screenshot |
| D-01 | Three AI modules | Optional stretch | Add canopy module if time remains |
