import os
import re
import csv
import json
import time
import urllib.request
from collections import defaultdict

output_csv = "res/bbo_2025_catalog.csv"
output_summary = "res/bbo_2025_event_summary.json"
os.makedirs("res", exist_ok=True)

print("Cataloging all matches for 2025 across all 12 months...")
all_matches = {}

for m in range(1, 13):
    month_str = f"2025-{m:02d}"
    url = f"https://www.bridgebase.com/vugraph_archives/vugraph_archives.php?v3b=&command=search&searchstring={month_str}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req) as resp:
            html = resp.read().decode('utf-8', errors='ignore')
            
        row_pattern = re.compile(r'<tr[^>]*>(.*?)</tr>', re.DOTALL | re.IGNORECASE)
        count = 0
        for row in row_pattern.findall(html):
            id_m = re.search(r'id=(\d+)', row)
            if not id_m:
                continue
            m_id = id_m.group(1)
            if m_id not in all_matches:
                cells = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL | re.IGNORECASE)
                clean = [' '.join(re.sub(r'<[^>]+>', ' ', c).split()) for c in cells]
                
                # cells: [0: Links, 1: Date, 2: Event, 3: Segment, 4: Team1, 5: Team2]
                date = clean[1] if len(clean) > 1 else ""
                event = clean[2] if len(clean) > 2 else ""
                segment = clean[3] if len(clean) > 3 else ""
                team1 = clean[4] if len(clean) > 4 else ""
                team2 = clean[5] if len(clean) > 5 else ""

                all_matches[m_id] = {
                    "id": m_id,
                    "date": date,
                    "event": event,
                    "segment": segment,
                    "team1": team1,
                    "team2": team2
                }
                count += 1
        print(f"[{month_str}]: indexed {count} matches.")
        time.sleep(0.04)
    except Exception as e:
        print(f"[{month_str}] Error: {e}")

print(f"\nTotal matches cataloged: {len(all_matches)}")

# Save to CSV
with open(output_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=["id", "date", "event", "segment", "team1", "team2"])
    writer.writeheader()
    for m in sorted(all_matches.values(), key=lambda x: int(x["id"])):
        writer.writerow(m)

# Aggregate by Event
event_groups = defaultdict(list)
for m in all_matches.values():
    norm_event = m["event"].strip()
    event_groups[norm_event].append(m)

summary_list = []
for ev_name, matches in event_groups.items():
    ids = [int(x["id"]) for x in matches]
    dates = [x["date"] for x in matches if x["date"]]
    summary_list.append({
        "event": ev_name,
        "match_count": len(matches),
        "min_id": min(ids) if ids else 0,
        "max_id": max(ids) if ids else 0,
        "start_date": min(dates) if dates else "",
        "end_date": max(dates) if dates else ""
    })

# Sort by match count descending
summary_list.sort(key=lambda x: x["match_count"], reverse=True)

with open(output_summary, "w", encoding="utf-8") as f:
    json.dump(summary_list, f, indent=2)

print(f"Catalog CSV saved to: {output_csv}")
print(f"Event Summary saved to: {output_summary}")

# Print Top 30 Events
print("\n" + "="*100)
print(f"{'EVENT NAME':<45} | {'MATCHES':<8} | {'ID RANGE':<15} | {'DATES'}")
print("="*100)
for ev in summary_list[:35]:
    id_range = f"{ev['min_id']} - {ev['max_id']}"
    dates = f"{ev['start_date']} to {ev['end_date']}"
    print(f"{ev['event'][:45]:<45} | {ev['match_count']:<8} | {id_range:<15} | {dates}")
