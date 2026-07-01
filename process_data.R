# process_data.R
# Reads the Harbor Water Quality CSV and writes a compact data.json
# for the HTML dashboard.
#
# Usage:
#   Rscript process_data.R
#
# Or run interactively in RStudio.
#
# Requirements:
#   install.packages(c("readr", "dplyr", "jsonlite", "lubridate"))

library(readr)
library(dplyr)
library(jsonlite)
library(lubridate)

# ── Config ────────────────────────────────────────────────────────────────────

CSV_FILE  <- "Harbor_Water_Quality_20260701.csv"
OUT_FILE  <- "data.json"

# Active sites from the 2026 DEP Harbor Survey map
ACTIVE_SITES <- c(
  # Staten Island Transects
  "K1","K2","K3","K4","K5","K5A","K6",
  # Hudson Transects
  "N1","N3B","N4","N5","N6","G2","N7","N8","N9","N16",
  # East River
  "E2","E4","E6","E7","E8","E10","E11","E12","E13","E14","E15",
  # Jamaica Bay
  "J1","J2","J3","J5","J7","J8","J9A","J10","J11","J12","JA1","N9A",
  # Jamaica Bay Interior
  "J14","J16","J18",
  # Harlem River
  "H3",
  # Tributaries
  "AC1","AC2","BB2","BB4","BR1","BR3","BR5",
  "CIC2","CIC3","F1","F5","FB1","FLC1","FLC2","GB1",
  "GC3","GC4","GC5","GC6",
  "HC1","HC2","HC3","HR1","HR2","HR03","LN1",
  "NC0","NC0B","NC1","NC2","NC3",
  "PB2","PB3","SP1","SP2","TB1","TB2",
  "WC1","WC2","WC3"
)

# Columns to exclude (non-parameter columns)
SKIP_COLS <- c(
  "Sampling Location", "Duplicate Sample", "Sample Date", "Sample Time",
  "Weather Condition (Dry or Wet)", "Sea State", "Type",
  "Current Speed (knot)", "Current Direction (Current Direction)",
  "Wind Speed (mph)", "Wind Direction (Wind Direction)",
  "Fecal Coliform Top Sample Less Than or Greater Than Result",
  "Fecal Coliform Bottom Sample Less Than or Greater Than Result",
  "Enterococcus Top Sample Less Than or Greater Than Result",
  "Enterococcus Bottom Sample Less Than or Greater Than Result",
  "Sampling Comment", "Long", "Lat"
)

# Hardcoded site coordinates and metadata (from 2026 DEP map)
SITE_META <- list(
  K1   = list(lat=40.6433, lon=-74.0739, type="open_water", name="St. George"),
  K2   = list(lat=40.6409, lon=-74.1453, type="open_water", name="Shooter Island"),
  K3   = list(lat=40.6361, lon=-74.1631, type="open_water", name="A & K Railroad Bridge"),
  K4   = list(lat=40.5719, lon=-74.1833, type="open_water", name="Fresh Kills"),
  K5   = list(lat=40.5161, lon=-74.2461, type="open_water", name="Tottenville"),
  K5A  = list(lat=40.4991, lon=-74.2721, type="open_water", name="Raritan River"),
  K6   = list(lat=40.5021, lon=-74.1883, type="open_water", name="Old Orchard Light"),
  N1   = list(lat=40.8775, lon=-73.9127, type="open_water", name="Mt. St. Vincent"),
  N3B  = list(lat=40.8116, lon=-73.9501, type="open_water", name="W. 125th Street"),
  N4   = list(lat=40.7602, lon=-73.9976, type="open_water", name="W. 42nd Street"),
  N5   = list(lat=40.7012, lon=-74.0177, type="open_water", name="Pier A - The Battery"),
  N6   = list(lat=40.6272, lon=-74.0402, type="open_water", name='Bell Buoy "31"'),
  G2   = list(lat=40.6721, lon=-74.0158, type="open_water", name="Gowanus Canal"),
  N7   = list(lat=40.6584, lon=-74.0649, type="open_water", name='Robbins Reef Buoy "28"'),
  N8   = list(lat=40.6120, lon=-74.0531, type="open_water", name="The Narrows"),
  N9   = list(lat=40.5726, lon=-74.0019, type="open_water", name="Steeplechase Pier"),
  N16  = list(lat=40.5562, lon=-73.9416, type="open_water", name="Rockaway Point"),
  E2   = list(lat=40.7399, lon=-73.9716, type="open_water", name="E. 23rd Street"),
  E4   = list(lat=40.7797, lon=-73.9318, type="open_water", name="Hell Gate"),
  E6   = list(lat=40.7773, lon=-73.8830, type="open_water", name="Flushing Bay"),
  E7   = list(lat=40.8038, lon=-73.8399, type="open_water", name="Whitestone Bridge"),
  E8   = list(lat=40.8055, lon=-73.7955, type="open_water", name="Throgs Neck Bridge"),
  E10  = list(lat=40.8513, lon=-73.7627, type="open_water", name="Hart Island"),
  E11  = list(lat=40.8303, lon=-73.7404, type="open_water", name="Little Neck Bay"),
  E12  = list(lat=40.8621, lon=-73.8028, type="open_water", name="Eastchester Bay Buoy N6"),
  E13  = list(lat=40.8281, lon=-73.8309, type="open_water", name="Westchester Creek Buoy N2"),
  E14  = list(lat=40.8142, lon=-73.8593, type="open_water", name="Mouth of Bronx River Buoy N2"),
  E15  = list(lat=40.7651, lon=-73.8673, type="open_water", name="Flushing Bay South Buoy N2"),
  J1   = list(lat=40.5682, lon=-73.9470, type="open_water", name="Rockaway Inlet"),
  J2   = list(lat=40.6041, lon=-73.9254, type="open_water", name="Mill Basin"),
  J3   = list(lat=40.6339, lon=-73.8952, type="open_water", name="Canarsie Pier"),
  J5   = list(lat=40.6176, lon=-73.8763, type="open_water", name="Railroad Trestle"),
  J7   = list(lat=40.6371, lon=-73.8769, type="open_water", name="Bergen Basin"),
  J8   = list(lat=40.6448, lon=-73.8619, type="open_water", name="Spring Creek"),
  J9A  = list(lat=40.6334, lon=-73.8795, type="open_water", name='Fresh Creek Buoy "C21"'),
  J10  = list(lat=40.6253, lon=-73.9039, type="open_water", name="Paerdegat Basin"),
  J11  = list(lat=40.5843, lon=-73.9442, type="open_water", name="Sheepshead Bay"),
  J12  = list(lat=40.6096, lon=-73.8373, type="open_water", name="Grassy Bay"),
  JA1  = list(lat=40.6473, lon=-73.8232, type="open_water", name="Jamaica WWTP Outfall"),
  N9A  = list(lat=40.5738, lon=-73.9873, type="open_water", name="Coney Island Outfall"),
  J14  = list(lat=40.6153, lon=-73.8564, type="open_water", name="West of Broad Channel"),
  J16  = list(lat=40.6061, lon=-73.8329, type="open_water", name="Horse Channel"),
  J18  = list(lat=40.5912, lon=-73.8258, type="open_water", name="Pumpkin Patch"),
  H3   = list(lat=40.8264, lon=-73.9264, type="open_water", name="E. 155th Street"),
  AC1  = list(lat=40.7713, lon=-73.7445, type="tributary",  name="Alley Creek & Northern Blvd"),
  AC2  = list(lat=40.7641, lon=-73.7524, type="tributary",  name="Alley Creek Outfall"),
  BB2  = list(lat=40.6451, lon=-73.8572, type="tributary",  name="Head of Bergen Basin"),
  BB4  = list(lat=40.6361, lon=-73.8691, type="tributary",  name="Mouth of Bergen Basin"),
  BR1  = list(lat=40.8882, lon=-73.8702, type="tributary",  name="233rd St & Bronx River"),
  BR3  = list(lat=40.8322, lon=-73.8723, type="tributary",  name="Westchester Ave & Bronx River"),
  BR5  = list(lat=40.8082, lon=-73.8762, type="tributary",  name="Mouth of Bronx River"),
  CIC2 = list(lat=40.5876, lon=-73.9955, type="tributary",  name="Cropsy Ave & Coney Island Creek"),
  CIC3 = list(lat=40.5918, lon=-73.9991, type="tributary",  name="Coney Island Creek"),
  F1   = list(lat=40.6621, lon=-73.8793, type="tributary",  name="Fresh Creek Outfall"),
  F5   = list(lat=40.6441, lon=-73.8862, type="tributary",  name="Mouth of Fresh Creek"),
  FB1  = list(lat=40.7784, lon=-73.8510, type="tributary",  name="Flushing Bay North"),
  FLC1 = list(lat=40.7591, lon=-73.8327, type="tributary",  name="Flushing Creek"),
  FLC2 = list(lat=40.7637, lon=-73.8421, type="tributary",  name="Mouth of Flushing Creek"),
  GB1  = list(lat=40.5916, lon=-74.0070, type="tributary",  name="Gravesend Bay"),
  GC3  = list(lat=40.6779, lon=-73.9997, type="tributary",  name="Union Street Bridge"),
  GC4  = list(lat=40.6756, lon=-73.9994, type="tributary",  name="Carroll Street Bridge"),
  GC5  = list(lat=40.6742, lon=-73.9990, type="tributary",  name="3rd Street Bridge"),
  GC6  = list(lat=40.6718, lon=-73.9982, type="tributary",  name="9th Street Bridge"),
  HC1  = list(lat=40.6494, lon=-73.8648, type="tributary",  name="Hendrix Creek Head"),
  HC2  = list(lat=40.6420, lon=-73.8616, type="tributary",  name="Hendrix at 26th Ward Outfall"),
  HC3  = list(lat=40.6385, lon=-73.8628, type="tributary",  name="Hendrix Creek under Belt Pkwy"),
  HR1  = list(lat=40.8524, lon=-73.8310, type="tributary",  name="Bartow Av Br & Hutchinson River Pkwy"),
  HR2  = list(lat=40.8603, lon=-73.8446, type="tributary",  name="Boston Rd Br & Conner Ave"),
  HR03 = list(lat=40.8663, lon=-73.8512, type="tributary",  name="Conner Street Pump Station"),
  LN1  = list(lat=40.7901, lon=-73.7240, type="tributary",  name="Little Neck Bay South"),
  NC0  = list(lat=40.7048, lon=-73.9145, type="tributary",  name="English Kills"),
  NC0B = list(lat=40.7181, lon=-73.9072, type="tributary",  name="Grand Ave & Newtown Creek"),
  NC1  = list(lat=40.7188, lon=-73.8983, type="tributary",  name="Maspeth Creek"),
  NC2  = list(lat=40.7172, lon=-73.8956, type="tributary",  name="Amoco Tank Farm"),
  NC3  = list(lat=40.7152, lon=-73.8937, type="tributary",  name="Whale Creek"),
  PB2  = list(lat=40.6312, lon=-73.9062, type="tributary",  name="Middle of Paerdegat Basin"),
  PB3  = list(lat=40.6228, lon=-73.9098, type="tributary",  name="Mouth of Paerdegat Basin"),
  SP1  = list(lat=40.6531, lon=-73.8419, type="tributary",  name="Spring Creek under Belt Pkwy"),
  SP2  = list(lat=40.6471, lon=-73.8541, type="tributary",  name="Spring Creek"),
  TB1  = list(lat=40.5940, lon=-73.7742, type="tributary",  name="Thurston Basin"),
  TB2  = list(lat=40.5908, lon=-73.7703, type="tributary",  name="Thurston Basin Mouth"),
  WC1  = list(lat=40.8162, lon=-73.8304, type="tributary",  name="WC Bruckner & Cross Bronx Exps"),
  WC2  = list(lat=40.8141, lon=-73.8222, type="tributary",  name="South Bound Hutchinson Pkwy"),
  WC3  = list(lat=40.8109, lon=-73.8083, type="tributary",  name='Buoy "10"')
)

# ── Read CSV ──────────────────────────────────────────────────────────────────

cat("Reading", CSV_FILE, "...\n")
raw <- suppressWarnings(read_csv(CSV_FILE, show_col_types = FALSE))
cat("  Rows:", nrow(raw), "  Columns:", ncol(raw), "\n")

# Trim whitespace from site names to ensure exact matching
raw[[site_col]] <- trimws(raw[[site_col]])

# ── Filter to active sites ────────────────────────────────────────────────────

site_col <- "Sampling Location"
date_col <- "Sample Date"

df <- raw %>%
  filter(.data[[site_col]] %in% ACTIVE_SITES) %>%
  filter(!is.na(.data[[date_col]]))

cat("  Rows after site filter:", nrow(df), "\n")

# ── Identify parameter columns ────────────────────────────────────────────────

all_cols   <- names(df)
param_cols <- setdiff(all_cols, SKIP_COLS)

# Keep only columns that are actually numeric
param_cols <- param_cols[sapply(param_cols, function(col) {
  vals <- suppressWarnings(as.numeric(df[[col]]))
  sum(!is.na(vals)) > 0
})]

cat("  Parameter columns:", length(param_cols), "\n")

# ── Parse dates → days since 1970-01-01 (compact integers, ~5 digits vs 13) ──

df <- df %>%
  mutate(
    ts_days = as.numeric(
      as.Date(.data[[date_col]], tryFormats = c("%m/%d/%Y", "%Y-%m-%d", "%d/%m/%Y"))
    )
  ) %>%
  filter(!is.na(ts_days))

# ── Build parameter metadata ──────────────────────────────────────────────────

label_for <- function(col) {
  lo <- tolower(col)
  
  # Exact matches first
  exact <- list(
    "Top Sample Temperature (ºC)"                          = list(label="Temperature (Surface)",          unit="°C"),
    "Bottom Sample Temperature (ºC)"                       = list(label="Temperature (Bottom)",           unit="°C"),
    "Top Salinity  (psu)"                                  = list(label="Salinity (Surface)",             unit="ppt"),
    "Bottom Salinity  (psu)"                               = list(label="Salinity (Bottom)",              unit="ppt"),
    "Winkler Method Top Dissolved Oxygen (mg/L)"           = list(label="Dissolved Oxygen (Surface)",     unit="mg/L"),
    "Winkler Method Bottom Dissolved Oxygen (mg/L)"        = list(label="Dissolved Oxygen (Bottom)",      unit="mg/L"),
    "Top Fecal Coliform Bacteria (Cells/100mL)"            = list(label="Fecal Coliform (Surface)",       unit="MPN/100mL"),
    "Bottom Fecal Coliform Bacteria (Cells/100mL)"         = list(label="Fecal Coliform (Bottom)",        unit="MPN/100mL"),
    "Top Enterococci Bacteria (Cells/100mL)"               = list(label="Enterococcus (Surface)",         unit="MPN/100mL"),
    "Bottom Enterococci Bacteria (Cells/100mL)"            = list(label="Enterococcus (Bottom)",          unit="MPN/100mL"),
    "Top Total Coliform Cells/100 mL"                      = list(label="Total Coliform (Surface)",       unit="MPN/100mL"),
    "Secchi Depth (ft)"                                    = list(label="Secchi Depth",                   unit="ft"),
    "Top PH"                                               = list(label="pH (Surface)",                   unit=""),
    "Bottom PH"                                            = list(label="pH (Bottom)",                    unit=""),
    "Top Active Chlorophyll 'A' (µg/L)"                    = list(label="Chlorophyll a (Surface)",        unit="µg/L"),
    "Bottom Active Chlorophyll 'A' (µg/L)"                 = list(label="Chlorophyll a (Bottom)",         unit="µg/L"),
    "Top Turbidity (Nephelometric Turbidity Units)"        = list(label="Turbidity (Surface)",            unit="NTU"),
    "Bottom Turbidity YSI (Nephelometric Turbidity Units)" = list(label="Turbidity (Bottom)",             unit="NTU"),
    "Top Nitrate/Nitrite (mg/L)"                           = list(label="Nitrate+Nitrite (Surface)",      unit="mg/L"),
    "Bottom Nitrate/Nitrite (mg/L)"                        = list(label="Nitrate+Nitrite (Bottom)",       unit="mg/L"),
    "Top Ammonium (mg/L)"                                  = list(label="Ammonium (Surface)",             unit="mg/L"),
    "Bottom Ammonium (mg/L)"                               = list(label="Ammonium (Bottom)",              unit="mg/L"),
    "Top Dissolved Organic Carbon (mg/L)"                  = list(label="Dissolved Organic Carbon",       unit="mg/L"),
    "Top Total Suspended Solid (mg/L)"                     = list(label="Suspended Solids (Surface)",     unit="mg/L"),
    "Bottom Total Suspended Solid (mg/L)"                  = list(label="Suspended Solids (Bottom)",      unit="mg/L"),
    "Site Actual Depth (ft)"                               = list(label="Site Depth",                     unit="ft")
  )
  
  if (!is.null(exact[[col]])) return(exact[[col]])
  
  # Fallback: extract unit from trailing parenthetical, use col name as label
  unit <- ""
  label <- col
  m <- regmatches(col, regexpr("\\(([^)]+)\\)\\s*$", col))
  if (length(m) > 0 && nchar(m) > 0) {
    unit  <- gsub("[ÂÃ]", "", gsub(".*\\((.*)\\).*", "\\1", m))
    label <- trimws(sub("\\s*\\([^)]+\\)\\s*$", "", col))
  }
  label <- gsub("[ÂÃ]", "", label)
  list(label=label, unit=unit)
}

parameters <- setNames(
  lapply(param_cols, label_for),
  param_cols
)

# ── Build data: per-site files + summary averages for map coloring ────────────

cat("Building data structure...\n")
dir.create("data", showWarnings = FALSE)

summaries <- list()   # site → param → average value (for map coloring)

for (site in ACTIVE_SITES) {
  site_df <- df %>% filter(.data[[site_col]] == site)
  if (nrow(site_df) == 0) next

  site_data  <- list()
  site_avgs  <- list()

  for (col in param_cols) {
    vals <- suppressWarnings(as.numeric(site_df[[col]]))
    mask <- !is.na(vals)
    if (sum(mask) < 3) next

    ts  <- site_df$ts_days[mask]
    v   <- round(vals[mask], 2)
    ord <- order(ts)

    pts <- mapply(function(t, x) list(t, x), ts[ord], v[ord], SIMPLIFY = FALSE)
    site_data[[col]] <- pts
    site_avgs[[col]] <- round(mean(v), 3)
  }

  if (length(site_data) == 0) next

  # Write per-site file: data/SITEID.json
  site_file <- file.path("data", paste0(site, ".json"))
  write(toJSON(site_data, auto_unbox = TRUE, digits = 4), site_file)

  summaries[[site]] <- site_avgs
}

cat("  Sites with data:", length(summaries), "\n")

# ── Write main index file (small — no time series) ────────────────────────────

index <- list(
  metadata   = list(
    generated    = format(Sys.Date(), "%Y-%m-%d"),
    source       = CSV_FILE,
    record_count = nrow(df)
  ),
  sites      = SITE_META,
  parameters = parameters,
  summaries  = summaries    # per-site averages for map coloring
)

cat("Writing", OUT_FILE, "...\n")
write(toJSON(index, auto_unbox = TRUE, digits = 4), OUT_FILE)

index_kb  <- file.size(OUT_FILE) / 1024
site_files <- list.files("data", "*.json", full.names = TRUE)
site_kb    <- sum(file.size(site_files)) / 1024

cat(sprintf("Done!\n"))
cat(sprintf("  %s:         %.0f KB  (index)\n", OUT_FILE, index_kb))
cat(sprintf("  data/*.json: %.0f KB  (%.0f KB avg per site)\n",
            site_kb, site_kb / max(length(site_files), 1)))
cat(sprintf("  Sites: %d    Parameters: %d\n", length(summaries), length(parameters)))
