import os
import re
import sys

# Ensure utf-8 output
sys.stdout.reconfigure(encoding='utf-8')

lib_dir = "lib"

patterns = [
    r'(\b\w*bonus\w*\b)',
    r'(\b\w*penalty\w*\b)',
    r'(\b\w*adjustment\w*\b)',
    r'(\b\w*upgrade\w*\b)',
    r'(\b\w*downgrade\w*\b)',
    r'(\bworkinghonors\b)',
    r'(\bwastedhonors\b)',
]

combined_re = re.compile('|'.join(patterns), re.IGNORECASE)

findings = []

for root, _, files in os.walk(lib_dir):
    for f in files:
        if not f.endswith('.dart'): continue
        path = os.path.join(root, f)
        with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
            for line_no, line in enumerate(fp, start=1):
                clean = line.strip()
                if clean.startswith('//') or clean.startswith('*'): continue
                if combined_re.search(clean):
                    findings.append((path.replace('\\', '/'), line_no, clean))

print(f"Total lines flagged: {len(findings)}\n")

files_map = {}
for path, line_no, line in findings:
    files_map.setdefault(path, []).append((line_no, line))

for path in sorted(files_map.keys()):
    print(f"=== {path} ({len(files_map[path])} occurrences) ===")
    for line_no, line in files_map[path]:
        print(f"  L{line_no}: {line}")
    print()
