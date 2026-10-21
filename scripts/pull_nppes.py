"""Pull every NPI that lists the birth center taxonomy (261QB0400X, "Clinic/Center,
Birthing") from the NPPES NPI Registry API, state by state, and write a tidy CSV.

The registry API only returns active NPIs, so this is the stock of birth centers that
exist today, dated by when each one obtained its NPI. Centers that closed and
deactivated their NPI are not in it (see README, Limits).

Usage: python3 scripts/pull_nppes.py data/raw_nppes_birth_centers.csv
"""
import csv, json, sys, time, urllib.request, urllib.parse

OUT = sys.argv[1] if len(sys.argv) > 1 else "data/raw_nppes_birth_centers.csv"
STATES = ["AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY","PR","VI","GU","AS","MP"]
TAX = "261QB0400X"
BASE = "https://npiregistry.cms.hhs.gov/api/?version=2.1&taxonomy_description=Birthing&limit=200"

def fetch(url, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "birth-centers-con research (krc-123)"})
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            time.sleep(3 * (i + 1))
            if i == tries - 1:
                raise

rows = []
for st in STATES:
    skip, n_state = 0, 0
    while True:
        d = fetch(f"{BASE}&state={st}&skip={skip}")
        results = d.get("results", [])
        for r in results:
            taxes = r.get("taxonomies", [])
            codes = [t["code"] for t in taxes]
            if TAX not in codes:
                continue
            prim = next((t for t in taxes if t.get("primary")), None)
            loc = next((a for a in r.get("addresses", []) if a.get("address_purpose") == "LOCATION"), r["addresses"][0] if r.get("addresses") else {})
            b = r["basic"]
            rows.append({
                "npi": r["number"], "entity_type": r["enumeration_type"],
                "name": b.get("organization_name") or f'{b.get("first_name","")} {b.get("last_name","")}'.strip(),
                "enumeration_date": b.get("enumeration_date"), "last_updated": b.get("last_updated"),
                "status": b.get("status"), "primary_taxonomy": prim["code"] if prim else "",
                "primary_desc": prim["desc"] if prim else "", "n_taxonomies": len(taxes),
                "birth_center_primary": int(bool(prim and prim["code"] == TAX)),
                "state": loc.get("state"), "city": loc.get("city"), "zip5": (loc.get("postal_code") or "")[:5],
                "taxonomy_codes": "|".join(codes),
            })
            n_state += 1
        if len(results) < 200 or skip >= 1000:
            break
        skip += 200
        time.sleep(0.5)
    print(f"{st}: {n_state}", file=sys.stderr)
    time.sleep(0.5)

with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
print(f"wrote {len(rows)} rows to {OUT}", file=sys.stderr)
