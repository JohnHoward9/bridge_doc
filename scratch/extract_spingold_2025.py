import os
import re
import time
import json
import urllib.parse
import urllib.request

output_dir = r"res/spingold_2025"
os.makedirs(output_dir, exist_ok=True)

# 1. Search Spingold 2025
search_url = "https://www.bridgebase.com/vugraph_archives/vugraph_archives.php?v3b=&command=search&searchstring=2025+spingold"
req = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req) as resp:
    html = resp.read().decode('utf-8', errors='ignore')

row_pattern = re.compile(r'<tr[^>]*>(.*?)</tr>', re.DOTALL | re.IGNORECASE)
matches = {}
for row in row_pattern.findall(html):
    id_m = re.search(r'id=(\d+)', row)
    if not id_m:
        continue
    m_id = id_m.group(1)
    if m_id not in matches:
        cells = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL | re.IGNORECASE)
        clean = [' '.join(re.sub(r'<[^>]+>', ' ', c).split()) for c in cells]
        matches[m_id] = clean

print(f"Discovered {len(matches)} matches in 2025 Spingold.")
print("Starting download and extraction...")

all_boards = []
downloaded_count = 0

for m_id, details in matches.items():
    date = details[1] if len(details) > 1 else ""
    event = details[2] if len(details) > 2 else ""
    segment = details[3] if len(details) > 3 else ""
    team1 = details[4] if len(details) > 4 else ""
    team2 = details[5] if len(details) > 5 else ""

    clean_seg = segment.replace("/", "_").replace(" ", "_")
    lin_url = f"https://www.bridgebase.com/tools/vugraph_linfetch.php?id={m_id}"
    req_lin = urllib.request.Request(lin_url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req_lin) as resp_lin:
            lin_content = resp_lin.read().decode('utf-8', errors='ignore')

        # Save individual raw LIN file
        raw_file = os.path.join(output_dir, f"{m_id}_{clean_seg}.lin")
        with open(raw_file, "w", encoding="utf-8") as f:
            f.write(lin_content)

        # Parse boards from LIN
        records = lin_content.split("qx|")
        for r in records[1:]:
            room_code = r[:r.find('|')]
            room = "Open" if room_code.startswith('o') else "Closed"
            b_num = room_code[1:]

            md_m = re.search(r'md\|(\d)([A-Za-z0-9,]+)\|', r)
            deal_str = md_m.group(0) if md_m else ""

            bids = re.findall(r'mb\|([^\|]+)\|', r)
            mc_m = re.search(r'mc\|(\d+)\|', r)
            tricks = int(mc_m.group(1)) if mc_m else None

            all_boards.append({
                "match_id": m_id,
                "event": event,
                "date": date,
                "segment": segment,
                "team1": team1,
                "team2": team2,
                "board": b_num,
                "room": room,
                "deal": deal_str,
                "auction": bids,
                "tricks_made": tricks
            })

        downloaded_count += 1
        if downloaded_count % 10 == 0 or downloaded_count == len(matches):
            print(f"Downloaded and parsed {downloaded_count}/{len(matches)} matches...")
        time.sleep(0.05) # Polite delay
    except Exception as e:
        print(f"Error on match {m_id}: {e}")

# Save master dataset JSON
dataset_path = os.path.join(output_dir, "spingold_2025_dataset.json")
with open(dataset_path, "w", encoding="utf-8") as f:
    json.dump(all_boards, f, indent=2)

print("="*60)
print(f"COMPLETE: {downloaded_count} matches downloaded.")
print(f"Total board plays extracted: {len(all_boards)}")
print(f"Master dataset saved to: {dataset_path}")
