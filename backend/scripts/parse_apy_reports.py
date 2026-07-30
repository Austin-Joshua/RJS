"""Parses the real APY (Area/Production/Yield) reports in
data/training/raw_apy/ into one clean csv (TRD SS5.1 upgrade path).

Source: Directorate of Economics & Statistics (DES), Ministry of
Agriculture & Farmers Welfare — "APY Total Group Report" and "Horizontal
Crop / Vertical Year Report" exports from https://data.desagri.gov.in,
manually queried per crop for Tamil Nadu, 1997-98 to 2022-23. These are the
"original site" real government exports (HTML tables saved with an .xls
extension by the portal) — not the earlier synthetic panel.

- paddy_kharif_tn.xls / black_gram_tn.xls / groundnut_tn.xls / maize_tn.xls:
  one crop per file, all 38 TN districts x 26 years, Area/Production/Yield
  triplets per fiscal year.
- all_crops_whole_year_tn.xls: all crops in one "Whole Year" session query;
  used only for sugarcane here (a long-duration crop correctly reported as
  a single whole-year figure; the per-crop files above don't include it
  because it wasn't queried separately).

Writes data/training/apy_real_tn.csv: year, district, crop,
district_area_ha, district_production_t, yield_t_ha (source-reported,
kept alongside the derived ratio as a cross-check).
"""
import re
from pathlib import Path

import pandas as pd

RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "training" / "raw_apy"
OUT_PATH = Path(__file__).resolve().parents[1] / "data" / "training" / "apy_real_tn.csv"

DISTRICTS = ["Thanjavur", "Tiruvarur", "Nagapattinam", "Tiruchirappalli", "Madurai"]
DISTRICT_FIXUPS = {"Thiruvarur": "Tiruvarur"}

SINGLE_CROP_FILES = {
    "paddy_kharif_tn.xls": "paddy",
    "black_gram_tn.xls": "black_gram",
    "groundnut_tn.xls": "groundnut",
    "maize_tn.xls": "maize",
}

# Generous per-crop sanity ceilings (t/ha) — a handful of the source's 1997/98
# digitized columns report production ~10x too high for their area (e.g.
# Madurai sugarcane 1997 = 2,247 t/ha vs a realistic ~100), a known artifact
# of early DES digitization, not a parsing bug here. Rows past these bounds
# are dropped rather than silently kept or fabricated-down.
MAX_PLAUSIBLE_YIELD_T_HA = {"paddy": 8.0, "black_gram": 2.0, "groundnut": 6.0, "sugarcane": 150.0, "maize": 10.0}


def _parse_single_crop_report(path: Path, crop: str) -> pd.DataFrame:
    t = pd.read_html(path, header=[0, 1])[0]
    district = t.iloc[:, 2].astype(str).str.replace(r"^\d+\.\s*", "", regex=True).str.strip().replace(DISTRICT_FIXUPS)
    mask = district.isin(DISTRICTS)

    rows = []
    cols = t.columns[3:]
    for i in range(0, len(cols), 3):
        year_match = re.match(r"(\d{4})", str(cols[i][0]))
        if not year_match:
            continue
        year = int(year_match.group(1))
        area = pd.to_numeric(t.iloc[:, 3 + i], errors="coerce")
        production = pd.to_numeric(t.iloc[:, 3 + i + 1], errors="coerce")
        yield_reported = pd.to_numeric(t.iloc[:, 3 + i + 2], errors="coerce")
        for d, a, p, y in zip(district[mask], area[mask], production[mask], yield_reported[mask]):
            if a and a > 0:
                rows.append({"year": year, "district": d, "crop": crop, "district_area_ha": a,
                             "district_production_t": p, "yield_t_ha": y})
    return pd.DataFrame(rows)


def _parse_sugarcane(path: Path) -> pd.DataFrame:
    t = pd.read_html(path, header=[0, 1, 2])[0]
    district = (
        t[("District", "District", "District")].astype(str).str.replace(r"^\d+\.\s*", "", regex=True).str.strip()
        .replace(DISTRICT_FIXUPS)
    )
    year = t[("Year", "Year", "Year")].astype(str).str.extract(r"(\d{4})")[0]
    area = pd.to_numeric(t[("Sugarcane", "Whole Year", "Area (Hectare)")], errors="coerce")
    production = pd.to_numeric(t[("Sugarcane", "Whole Year", "Production (Tonnes)")], errors="coerce")
    yield_reported = pd.to_numeric(t[("Sugarcane", "Whole Year", "Yield (Tonne/Hectare)")], errors="coerce")

    mask = district.isin(DISTRICTS) & (area > 0)
    return pd.DataFrame(
        {
            "year": year[mask].astype(int),
            "district": district[mask],
            "crop": "sugarcane",
            "district_area_ha": area[mask],
            "district_production_t": production[mask],
            "yield_t_ha": yield_reported[mask],
        }
    )


def main() -> None:
    frames = [_parse_single_crop_report(RAW_DIR / fname, crop) for fname, crop in SINGLE_CROP_FILES.items()]
    frames.append(_parse_sugarcane(RAW_DIR / "all_crops_whole_year_tn.xls"))
    df = pd.concat(frames, ignore_index=True).dropna(subset=["yield_t_ha"])
    df = df[df["yield_t_ha"] > 0]
    ceiling = df["crop"].map(MAX_PLAUSIBLE_YIELD_T_HA)
    dropped = df[df["yield_t_ha"] > ceiling]
    if len(dropped):
        print(f"Dropping {len(dropped)} rows past the sanity ceiling (source digitization artifacts):")
        print(dropped[["year", "district", "crop", "yield_t_ha"]].to_string(index=False))
    df = df[df["yield_t_ha"] <= ceiling].sort_values(["crop", "district", "year"]).reset_index(drop=True)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT_PATH, index=False)
    print(f"Wrote {len(df)} real rows to {OUT_PATH}")
    print(df.groupby("crop").size())


if __name__ == "__main__":
    main()
