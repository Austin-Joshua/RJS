import json
from pathlib import Path


def load_boundary(boundary_path: str) -> dict:
    path = Path(boundary_path)
    if not path.exists():
        raise FileNotFoundError(f"Boundary file not found: {boundary_path}")
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def line_string_bbox_centroid(boundary_geojson: dict) -> tuple[list[float], list[float]]:
    feature = boundary_geojson["features"][0]
    coordinates = feature["geometry"]["coordinates"]
    xs = [point[0] for point in coordinates]
    ys = [point[1] for point in coordinates]
    bbox = [min(xs), min(ys), max(xs), max(ys)]
    centroid = [(bbox[0] + bbox[2]) / 2.0, (bbox[1] + bbox[3]) / 2.0]
    return bbox, centroid
