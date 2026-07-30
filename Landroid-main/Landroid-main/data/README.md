# Data assets

Place raster and documentation files here for local analysis:

- `*.tif` / `*.tiff` — GeoTIFF inputs (expecting **two** files for the hackathon pipeline).
- `index.pdf` — Index / methodology describing how those rasters should be interpreted (bands, CRS, expected outputs).

This repository snapshot may omit large binaries. After you add files, run:

```bash
cd scripts
pip install -r requirements-raster.txt
python analyze_geotiff.py
```

The script prints CRS, dimensions, bounds, and per-band statistics. To persist rows into Supabase `raster_assets`, use the **service role** key from a trusted backend or SQL editor (not the Flutter anon key).
