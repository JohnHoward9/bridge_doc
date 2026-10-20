import os
import re
import csv
import json
import time
import urllib.request

catalog_path = "res/bbo_2025_catalog.csv"
lin_dir = "res/bbo_2025_lin"
output_dataset = "res/bbo_championships_2025_dataset.json"

os.makedirs(lin_dir, exist_ok=True)
os.makedirs("res", exist_ok=True)

# Define keywords for Tier 1 & Tier 2 Premier World/National Championships
TARGET_KEYWORDS = [
    "spingold",
    "vanderbilt",
    "wbtc-herning",     # World Bridge Team Championships (Bermuda Bowl, Venice Cup)
    "eoc-poznan",       # European Open Championships
    "wytc-salsomaggiore",# World Youth Team Championships
    "buffett cup",      # Buffett Cup
    "wbt masters",      # World Bridge Tour Masters
    "usbf",             # US Team Trials
    "lederer",          # Lederer Memorial
    "apbf"              # Asia Pacific Championships
]

print("Reading 2025 catalog...")
target_matches = []
with open(catalog_path, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        event_lower = row["event"].lower()
        if any(kw in event_lower for kw in TARGET_KEYWORDS):
            target_matches.append(row)

print(f"Selected {len(target_matches)} championship matches for extraction.")
print("Starting polite, rate-limited download & parsing (150ms delay)...")

all_boards = []
downloaded_count = 0
skipped_count = 0

for i, m in enumerate(target_matches, start=1):
    m_id = m["id"]
    event = m["event"]
    date = m["date"]
    segment = m["segment"]
    team1 = m["team1"]
    team2 = m["team2"]

    lin_path = os.path.join(lin_dir, f"{m_id}.lin")
    lin_content = ""

    # Check if cached locally
    if os.path.exists(lin_path) and os.path.getsize(lin_path) > 100:
        with open(lin_path, "r", encoding="utf-8", errors="ignore") as f:
            lin_content = f.read()
        skipped_count += 1
    else:
        # Check if already present in spingold directory
        spingold_file = os.path.join("res/spingold_2025", f"{m_id}_{segment.replace('/', '_').replace(' ', '_')}.lin")
        if os.path.exists(spingold_file) and os.path.getsize(spingold_file) > 100:
            with open(spingold_file, "r", encoding="utf-8", errors="ignore") as f:
                lin_content = f.read()
            skipped_count += 1
        else:
            # Fetch from BBO with retry & rate limiting
            lin_url = f"https://www.bridgebase.com/tools/vugraph_linfetch.php?id={m_id}"
            req = urllib.request.Request(lin_url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
            
            for attempt in range(3):
                try:
                    with urllib.request.urlopen(req, timeout=15) as resp:
                        lin_content = resp.read().decode('utf-8', errors='ignore')
                    with open(lin_path, "w", encoding="utf-8") as f:
                        f.write(lin_content)
                    downloaded_count += 1
                    time.sleep(0.15) # Polite 150ms delay
                    break
                except Exception as e:
                    print(f"[{m_id}] Attempt {attempt+1} failed: {e}. Backing off...")
                    time.sleep(2.0 * (attempt + 1))

    if not lin_content:
        continue

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

    if i % 50 == 0 or i == len(target_matches):
        print(f"Progress: {i}/{len(target_matches)} matches processed ({downloaded_count} newly downloaded, {skipped_count} cached). Total boards so far: {len(all_boards)}")

# Save master dataset JSON
with open(output_dataset, "w", encoding="utf-8") as f:
    json.dump(all_boards, f, indent=2)

print("="*80)
print("EXTRACTION COMPLETE!")
print(f"Total Matches Processed: {len(target_matches)}")
print(f"Newly Downloaded: {downloaded_count} | Cached: {skipped_count}")
print(f"Total Single-Room Board Plays: {len(all_boards)}")
print(f"Master Dataset Saved To: {output_dataset}")
