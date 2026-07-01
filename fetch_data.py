#!/usr/bin/env python3
"""
fetch_data.py — Download NYC DEP Harbor Water Quality data from NYC Open Data
and write a compact data.json for the static dashboard.

Usage:
    pip install requests
    python fetch_data.py

Output:
    data.json  (~2–5 MB, ready for GitHub Pages)
"""

import requests
import json
import sys
from datetime import datetime
from collections import defaultdict

# ── Config ───────────────────────────────────────────────────────────────────
API_URL   = "https://data.cityofnewyork.us/resource/5uug-f49n.json"
APP_TOKEN = ""          # optional: add your Socrata app token for higher rate limits
PAGE_SIZE = 50_000      # max rows per request
OUT_FILE  = "data.json"

# Pretty labels for known column patterns
LABELS = {
    "winkler_do":        ("Dissolved Oxygen",        "mg/L"),
    "dissolved_oxygen":  ("Dissolved Oxygen",        "mg/L"),
    "fecal_coliform":    ("Fecal Coliform",          "MPN/100mL"),
    "total_coliform":    ("Total Coliform",          "MPN/100mL"),
    "enterococcus":      ("Enterococcus",            "MPN/100mL"),
    "ent_":              ("Enterococcus",            "MPN/100mL"),
    "temperature":       ("Temperature",             "°C"),
    "temp_":             ("Temperature",             "°C"),
    "salinity":          ("Salinity",                "ppt"),
    "sal_":              ("Salinity",                "ppt"),
    "turbidity":         ("Turbidity",               "NTU"),
    "turb_":             ("Turbidity",               "NTU"),
    "chlorophyll":       ("Chlorophyll a",           "µg/L"),
    "chl_":              ("Chlorophyll a",           "µg/L"),
    "secchi":            ("Secchi Depth",            "ft"),
    "ph":                ("pH",                     ""),
    "ammonia":           ("Ammonia",                 "mg/L"),
    "nitrate":           ("Nitrate",                 "mg/L"),
    "nitrogen":          ("Total Nitrogen",          "mg/L"),
    "phosphate":         ("Phosphate",               "mg/L"),
}

SKIP_COLS = {"site_name", "sample_date", "the_geom", ":id",
             ":created_at", ":updated_at", ":updated_meta", ":version"}


# ── Helpers ──────────────────────────────────────────────────────────────────
def label_for(col: str) -> tuple[str, str]:
    """Return (nice label, unit) for a column name."""
    lower = col.lower()
    for key, (lbl, unit) in LABELS.items():
        if key in lower:
            suffix = ""
            if any(s in lower for s in ("top", "surf", "surface")):
                suffix = " (Surface)"
            elif any(s in lower for s in ("bot", "bottom", "bott")):
                suffix = " (Bottom)"
            return lbl + suffix, unit
    # Fallback
    return col.replace("_", " ").title(), ""


def extract_coords(geom) -> tuple[float, float] | None:
    """Extract (lat, lon) from a Socrata GeoJSON point."""
    if not geom:
        return None
    if isinstance(geom, dict) and "coordinates" in geom:
        coords = geom["coordinates"]
        return float(coords[1]), float(coords[0])
    if isinstance(geom, str):
        try:
            obj = json.loads(geom)
            if "coordinates" in obj:
                return float(obj["coordinates"][1]), float(obj["coordinates"][0])
        except Exception:
            pass
    return None


def get(params: dict) -> list[dict]:
    """Make a single Socrata API request."""
    headers = {}
    if APP_TOKEN:
        headers["X-App-Token"] = APP_TOKEN
    r = requests.get(API_URL, params=params, headers=headers, timeout=120)
    r.raise_for_status()
    return r.json()


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    # 1. Discover schema -------------------------------------------------------
    print("Discovering schema …")
    sample = get({"$limit": 1})
    if not sample:
        sys.exit("ERROR: No data returned from API.")

    first_row = sample[0]
    print(f"  Columns: {list(first_row.keys())}")

    # Identify numeric parameter columns
    param_cols = []
    for col, val in first_row.items():
        if col in SKIP_COLS:
            continue
        if val is None or val == "":
            continue
        try:
            float(val)
            param_cols.append(col)
        except (ValueError, TypeError):
            pass

    if not param_cols:
        sys.exit("ERROR: Could not identify any numeric parameter columns.")

    print(f"  Parameter columns ({len(param_cols)}): {param_cols}")

    # 2. Fetch all records (paginated) ----------------------------------------
    print("\nFetching all records …")
    all_rows: list[dict] = []
    offset = 0

    while True:
        batch = get({
            "$order":  "sample_date ASC",
            "$limit":  PAGE_SIZE,
            "$offset": offset,
        })
        if not batch:
            break
        all_rows.extend(batch)
        offset += len(batch)
        print(f"  {offset:,} records …", end="\r", flush=True)
        if len(batch) < PAGE_SIZE:
            break

    print(f"\n  Total: {len(all_rows):,} records")

    # 3. Build compact structure ----------------------------------------------
    print("\nProcessing …")

    sites:  dict[str, dict] = {}          # name → {lat, lon}
    data:   dict[str, dict] = {}          # name → {col → [[ts_ms, val], …]}

    for row in all_rows:
        site = row.get("site_name", "").strip()
        if not site:
            continue

        # Coordinates
        if site not in sites:
            coords = extract_coords(row.get("the_geom"))
            if coords:
                sites[site] = {"lat": round(coords[0], 6),
                               "lon": round(coords[1], 6)}

        # Parse date → milliseconds (JS-compatible)
        raw_date = row.get("sample_date", "")
        if not raw_date:
            continue
        try:
            dt  = datetime.fromisoformat(raw_date.split("T")[0])
            ts  = int(dt.timestamp() * 1000)
        except ValueError:
            continue

        # Values
        if site not in data:
            data[site] = defaultdict(list)

        for col in param_cols:
            raw_val = row.get(col)
            if raw_val is None or raw_val == "":
                continue
            try:
                val = float(raw_val)
                data[site][col].append([ts, round(val, 4)])
            except (ValueError, TypeError):
                pass

    # Convert defaultdicts to plain dicts
    data = {s: dict(cols) for s, cols in data.items()}

    # Build parameter metadata
    parameters = {}
    for col in param_cols:
        label, unit = label_for(col)
        parameters[col] = {"label": label, "unit": unit}

    output = {
        "metadata": {
            "generated":    datetime.now().strftime("%Y-%m-%d"),
            "source":       "NYC DEP Harbor Survey — NYC Open Data (5uug-f49n)",
            "record_count": len(all_rows),
        },
        "sites":      sites,
        "parameters": parameters,
        "data":       data,
    }

    # 4. Write JSON -----------------------------------------------------------
    print(f"\nWriting {OUT_FILE} …")
    with open(OUT_FILE, "w") as fh:
        json.dump(output, fh, separators=(",", ":"))

    size_mb = len(json.dumps(output, separators=(",", ":"))) / 1_048_576
    print(f"Done! {OUT_FILE}")
    print(f"  Sites:      {len(sites)}")
    print(f"  Parameters: {list(parameters.keys())}")
    print(f"  Size:       {size_mb:.1f} MB (uncompressed)")


if __name__ == "__main__":
    main()
