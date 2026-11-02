import os
import glob
import yaml
from collections import defaultdict

def load_yaml(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return yaml.safe_load(f)
    except Exception as e:
        return None

def find_duplicate_bids_in_fragment(frag_name, bids_dict, filepath):
    """Detects bids in the same fragment that share identical structures or references."""
    duplicates = []
    if not isinstance(bids_dict, dict):
        return duplicates

    seen = {}
    for bid, data in bids_dict.items():
        if not isinstance(data, dict):
            continue
        # Check ref + vars signature
        ref = data.get('ref')
        rule = data.get('rule')
        desc = data.get('desc')
        bids_child = data.get('bids')
        
        # Simplified structural key
        child_keys = tuple(sorted(bids_child.keys())) if isinstance(bids_child, dict) else None
        
        sig = (ref, child_keys, len(bids_child) if isinstance(bids_child, dict) else 0)
        seen[bid] = {
            'ref': ref,
            'rule': rule,
            'desc': desc,
            'child_keys': child_keys,
            'vars': data.get('vars'),
            'has_children': isinstance(bids_child, dict) and len(bids_child) > 0,
            'child_count': len(bids_child) if isinstance(bids_child, dict) else 0
        }

    # Group by ref
    by_ref = defaultdict(list)
    for bid, info in seen.items():
        if info['ref']:
            by_ref[info['ref']].append((bid, info['vars']))
    for ref, bid_list in by_ref.items():
        if len(bid_list) > 1:
            duplicates.append({
                'type': 'same_ref_in_fragment',
                'fragment': frag_name,
                'file': filepath,
                'ref': ref,
                'bids': bid_list
            })

    # Group by identical child structure
    by_children = defaultdict(list)
    for bid, info in seen.items():
        if info['child_count'] > 1 and not info['ref']:
            by_children[info['child_keys']].append(bid)
    for child_keys, bid_list in by_children.items():
        if len(bid_list) > 1:
            duplicates.append({
                'type': 'identical_children_structure',
                'fragment': frag_name,
                'file': filepath,
                'child_keys': child_keys,
                'bids': bid_list
            })

    return duplicates

def scan_all_yamls():
    yaml_files = glob.glob('assets/**/*.yaml', recursive=True) + glob.glob('assets/**/*.yml', recursive=True)
    all_fragments = defaultdict(list)
    fragment_dups = []
    bid_dups = []
    interference_blocks = defaultdict(list)

    for yf in sorted(yaml_files):
        data = load_yaml(yf)
        if not data or not isinstance(data, dict):
            continue
        
        frags = data.get('fragments', {})
        if isinstance(frags, dict):
            for fname, fval in frags.items():
                all_fragments[fname].append(yf)
                if isinstance(fval, dict):
                    bids = fval.get('bids', {})
                    bdups = find_duplicate_bids_in_fragment(fname, bids, yf)
                    bid_dups.extend(bdups)

                    # Look for inline interference blocks
                    if isinstance(bids, dict):
                        for b, bdata in bids.items():
                            if b.startswith('(') and b.endswith(')'):
                                interference_blocks[b].append((yf, fname))

    print(f"Total YAML files scanned: {len(yaml_files)}")
    print(f"Total unique fragment names: {len(all_fragments)}")

    print("\n=== 1. Fragments defined in multiple files ===")
    for fname, files in all_fragments.items():
        if len(files) > 1:
            print(f"Fragment '{fname}' defined in {len(files)} files: {files}")

    print("\n=== 2. Repeated Ref / Parameterized Parallel Bids in Same Fragment ===")
    for d in bid_dups:
        if d['type'] == 'same_ref_in_fragment':
            print(f"[{os.path.basename(d['file'])}] Fragment '{d['fragment']}': bids {d['bids']} share ref '{d['ref']}'")

    print("\n=== 3. Sibling Bids with Identical Child Structures (Un-factored trees) ===")
    for d in bid_dups:
        if d['type'] == 'identical_children_structure':
            print(f"[{os.path.basename(d['file'])}] Fragment '{d['fragment']}': bids {d['bids']} have identical child keys: {d['child_keys']}")

    print("\n=== 4. Inline Interference Bids across Fragments ===")
    for call, occ in sorted(interference_blocks.items(), key=lambda x: -len(x[1])):
        if len(occ) > 1:
            print(f"Interference call '{call}' repeated in {len(occ)} fragments across files:")
            for yf, fn in occ[:5]:
                print(f"   - {os.path.basename(yf)} -> {fn}")
            if len(occ) > 5:
                print(f"   ... and {len(occ) - 5} more")

if __name__ == '__main__':
    scan_all_yamls()
