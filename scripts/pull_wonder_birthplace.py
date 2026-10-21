"""Pull births by state of residence, year, and birthplace (hospital, freestanding birth
center, home, and so on) from CDC WONDER's Natality 2016-2024 expanded dataset (D149).

WONDER's XML API refuses sub-national natality queries, so this script does what a
person does in the browser: it accepts the data use agreement, loads the query form,
keeps every default, sets the three group-by boxes, and submits. The result table is
parsed from the returned HTML.

Usage: python3 scripts/pull_wonder_birthplace.py <out.csv> [D149|D66] [totals]
  D149 = Natality 2016-2024 expanded (default); D66 = Natality 2007 onward (2007 to 2024 as of October 2026).
  "totals" drops the birthplace grouping and returns all births by state and year.
"""
import csv, re, sys, time, urllib.request, urllib.parse, http.cookiejar
from html.parser import HTMLParser

OUT = sys.argv[1] if len(sys.argv) > 1 else "data/raw_wonder_birthplace_state_year.csv"
DS = sys.argv[2] if len(sys.argv) > 2 else "D149"   # D149 = Natality 2016-2024 expanded; D66 = Natality 2007 onward
URL = f"https://wonder.cdc.gov/controller/datarequest/{DS}"
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
opener.addheaders = [("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"),
                     ("Accept", "text/html,application/xhtml+xml"), ("Origin", "https://wonder.cdc.gov"), ("Referer", f"https://wonder.cdc.gov/controller/datarequest/{DS}")]

def post(data, url=URL, timeout=600):
    body = urllib.parse.urlencode(data, doseq=True).encode()
    try:
        with opener.open(urllib.request.Request(url, data=body), timeout=timeout) as r:
            return r.read().decode("utf-8", "ignore")
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", "ignore")
        open("wonder_error.html", "w").write(err)
        txt = re.sub(r"<[^>]+>", " ", err); txt = re.sub(r"\s+", " ", txt)
        print("HTTP", e.code, txt[:1500], file=sys.stderr); raise

# 1. Agree to the data use restrictions and get the form with its defaults
form_html = post([("stage", "about"), ("saved_id", ""), ("action-I Agree", "I Agree")])

class FormParser(HTMLParser):
    def __init__(self):
        super().__init__(); self.fields = []; self.sel = None; self.cur = None; self.selected = []; self.first = None
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "input" and a.get("name"):
            t = a.get("type", "text")
            if t in ("hidden", "text") or (t in ("radio", "checkbox") and "checked" in a):
                self.fields.append((a["name"], a.get("value", "")))
        elif tag == "select":
            self.sel = a.get("name"); self.selected = []; self.first = None
        elif tag == "option" and self.sel is not None:
            v = a.get("value", "")
            if self.first is None: self.first = v
            if "selected" in a: self.selected.append(v)
    def handle_endtag(self, tag):
        if tag == "select" and self.sel is not None:
            vals = self.selected or ([self.first] if self.first is not None else [])
            for v in vals: self.fields.append((self.sel, v))
            self.sel = None

fp = FormParser(); fp.feed(form_html)
# WONDER keeps the session in the form's action URL (;jsessionid=...), not in a cookie
m = re.search(r'id="wonderform"[^>]*action="([^"]+)"|action="([^"]+)"[^>]*id="wonderform"', form_html)
action = next(g for g in m.groups() if g) if m else f"/controller/datarequest/{DS}"
SESSION_URL = "https://wonder.cdc.gov" + action if action.startswith("/") else action
print("session url:", SESSION_URL, file=sys.stderr)
fields = [(n, v) for n, v in fp.fields if n not in ("query", "affiliate")]
seen = set(); dedup = []
for n, v in fields:
    if (n, v) in seen: continue
    seen.add((n, v)); dedup.append((n, v))
fields = dedup

def setf(name, values):
    global fields
    fields = [(n, v) for n, v in fields if n != name] + [(name, v) for v in values]

# 2. Group by state of residence, year, and birthplace (6-level recode); all years; all locations
TOTALS = len(sys.argv) > 3 and sys.argv[3] == "totals"   # state x year only, for denominators
setf("B_1", [f"{DS}.V21-level1"]); setf("B_2", [f"{DS}.V20"]); setf("B_3", ["*None*" if TOTALS else f"{DS}.V30"])
setf("B_4", ["*None*"]); setf("B_5", ["*None*"])
setf(f"V_{DS}.V20", ["*All*"]); setf(f"V_{DS}.V30", ["*All*"])
setf("O_place", [f"{DS}.V30"])  # the radio button for the birthplace variable must match the group-by choice
setf("O_show_totals", ["false"]); setf("O_timeout", ["1200"])
fields.append(("action-Send", "Send"))

# 3. Submit and parse the results table
html = post(fields, url=SESSION_URL, timeout=1200)
open(OUT.replace(".csv", ".html"), "w").write(html)

# The results table nests a header table inside its header; the data rows are
# <tr><th>state</th><th>year</th>[<th>birthplace</th>]<td>births</td></tr> rows in the tbody,
# and WONDER collapses repeated leading cells with rowspan, so those are carried forward.
NCOL = 2 if TOTALS else 3
out = []; carry = []   # carry: [value, rows_remaining] for leading columns collapsed by rowspan
for tr in re.findall(r"<tr>(.*?)</tr>", html, re.S):
    cells = re.findall(r"<(th|td)([^>]*)>(.*?)</\1>", tr, re.S)
    ths = [(re.sub(r"<[^>]+>", "", c[2]).strip(), int((re.search(r'rowspan="(\d+)"', c[1]) or [None, "1"])[1])) for c in cells if c[0] == "th"]
    tds = [re.sub(r"<[^>]+>", "", c[2]).strip() for c in cells if c[0] == "td"]
    if not tds or not ths or not re.match(r"^[\d,]+$|^Suppressed$", tds[0]):
        continue
    carry = [c for c in carry if c[1] > 0]
    labels = [c[0] for c in carry] + [t[0] for t in ths]
    if len(labels) != NCOL or labels[0].lower().startswith("total"):
        continue
    for c in carry: c[1] -= 1
    for t in ths:
        if t[1] > 1: carry.append([t[0], t[1] - 1])
    m = re.match(r"^(.*?)\s*\((\d+)\)$", labels[0])
    if not m: continue
    state, code = m.groups()
    out.append([state, code] + labels[1:] + [tds[0].replace(",", "")])
hdr = ["state_name", "state_fips", "year"] + ([] if TOTALS else ["birthplace"]) + ["births"]
if not out:
    print("could not find the results rows; saved the HTML for inspection", file=sys.stderr); sys.exit(1)
with open(OUT, "w", newline="") as f:
    w = csv.writer(f); w.writerow(hdr); w.writerows(out)
print(f"wrote {len(out)} rows to {OUT}", file=sys.stderr)
