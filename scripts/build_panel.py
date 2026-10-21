"""Build the state-year panel from three sources:
  * CDC WONDER natality: births by state of residence and birthplace, 2007 to 2024
    (data/raw_wonder_birthplace_state_year_2007_2024.csv, data/raw_wonder_births_state_year_2007_2024.csv)
  * NPPES: active NPIs whose primary taxonomy is Clinic/Center, Birthing (data/raw_nppes_birth_centers.csv)
  * The certificate of need table (data/con_birth_centers.csv)

Usage: python3 scripts/build_panel.py data
Writes: data/birth_centers.csv (one row per NPI), data/panel_state_year.csv, data/panel_state_month.csv
"""
import csv, sys, os, collections, datetime
D = sys.argv[1] if len(sys.argv) > 1 else "data"
STATES = {r["state"]: r for r in csv.DictReader(open(os.path.join(D, "con_birth_centers.csv")))}
NAME2ST = {v["state_name"]: k for k, v in STATES.items()}
FIRST_YEAR, LAST_YEAR, LAST_BIRTH_YEAR = 2007, 2026, 2024
PULL_DATE = datetime.date(2026, 10, 20)

# ---- 1. Birth centers: one row per NPI, organizations whose primary taxonomy is the birth center code
raw = list(csv.DictReader(open(os.path.join(D, "raw_nppes_birth_centers.csv"))))
bc = []
for r in raw:
    if r["entity_type"] != "NPI-2" or r["birth_center_primary"] != "1" or r["state"] not in STATES:
        continue
    y, m = int(r["enumeration_date"][:4]), int(r["enumeration_date"][5:7])
    bc.append({"npi": r["npi"], "name": r["name"], "state": r["state"], "city": r["city"], "zip5": r["zip5"],
               "enumeration_date": r["enumeration_date"], "enum_year": y, "enum_month": f"{y}-{m:02d}",
               "n_taxonomies": r["n_taxonomies"], "last_updated": r["last_updated"]})
with open(os.path.join(D, "birth_centers.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(bc[0].keys())); w.writeheader(); w.writerows(bc)
print(f"{len(bc)} birth center organizations kept out of {len(raw)} NPIs with the taxonomy", file=sys.stderr)

# ---- 2. Births and birth center births by state of residence (NCHS via CDC WONDER)
births, fbc, home = {}, {}, {}
for r in csv.DictReader(open(os.path.join(D, "raw_wonder_births_state_year_2007_2024.csv"))):
    st = NAME2ST.get(r["state_name"])
    if st: births[(st, int(r["year"]))] = int(r["births"])
for r in csv.DictReader(open(os.path.join(D, "raw_wonder_birthplace_state_year_2007_2024.csv"))):
    st = NAME2ST.get(r["state_name"])
    if not st: continue
    key = (st, int(r["year"]))
    if r["birthplace"] == "Freestanding Birth Center": fbc[key] = int(r["births"])
    elif r["birthplace"] == "Residence": home[key] = int(r["births"])

# ---- 3. State-year panel
entries = collections.Counter((b["state"], b["enum_year"]) for b in bc)
rows = []
for st, meta in STATES.items():
    repeal = meta["repeal_effective"]
    ry = int(repeal[:4]) if repeal else None
    cum = sum(1 for b in bc if b["state"] == st and b["enum_year"] < FIRST_YEAR)
    for y in range(FIRST_YEAR, LAST_YEAR + 1):
        n = entries.get((st, y), 0); cum += n
        b = births.get((st, min(y, LAST_BIRTH_YEAR)))
        if meta["con_birth_centers_2015"] == "0":
            con = 0
        elif not repeal:
            con = 1
        elif y < ry: con = 1
        elif y > ry: con = 0
        else:
            con = round((datetime.date.fromisoformat(repeal).timetuple().tm_yday - 1) / 365, 3)
        partial = int(y == 2026)
        fb = fbc.get((st, y)); hb = home.get((st, y))
        has_births = y <= LAST_BIRTH_YEAR
        rows.append({
            "state": st, "state_name": meta["state_name"], "year": y,
            "births": b,
            "fbc_births": fb if has_births else "",
            "fbc_suppressed": int(has_births and fb is None),      # WONDER shows nothing for counts under 10
            "fbc_per_1000_births": round(fb / b * 1000, 3) if (has_births and fb is not None) else "",
            "home_births": hb if has_births else "",
            "home_per_1000_births": round(hb / b * 1000, 3) if (has_births and hb is not None) else "",
            "npi_entries": n,
            "npi_entries_annualized": round(n * 365 / PULL_DATE.timetuple().tm_yday, 2) if partial else n,
            "npi_active_stock": cum,
            "npi_entries_per_100k_births": round(n / b * 1e5, 3),
            "npi_stock_per_100k_births": round(cum / b * 1e5, 3),
            "con_share_of_year": con,
            "con_ever": int(meta["con_birth_centers_2015"] == "1"),
            "con_repealed": int(bool(repeal)), "repeal_effective": repeal,
            "event_time": (y - ry) if repeal else "",
            "births_carried_forward": int(y > LAST_BIRTH_YEAR), "partial_year": partial})
with open(os.path.join(D, "panel_state_year.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

# ---- 4. State-month NPI entries (for the repeal-state timelines)
mentries = collections.Counter((b["state"], b["enum_month"]) for b in bc)
mrows = []
for st in STATES:
    for y in range(2015, 2027):
        for m in range(1, 13):
            if (y, m) > (PULL_DATE.year, PULL_DATE.month): break
            k = f"{y}-{m:02d}"
            mrows.append({"state": st, "month": k, "npi_entries": mentries.get((st, k), 0)})
with open(os.path.join(D, "panel_state_month.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["state", "month", "npi_entries"]); w.writeheader(); w.writerows(mrows)
print(f"wrote {len(rows)} state-years and {len(mrows)} state-months", file=sys.stderr)
