import json

with open('res/bbo_championships_2025_dataset.json', 'r') as f:
    data = json.load(f)

SUITS = ['s', 'h', 'd', 'c']

def parse_deal(deal_str):
    if not deal_str.startswith('md|'): return None
    content = deal_str[3:].rstrip('|')
    dealer_char = content[0]
    hands_str = content[1:].split(',')
    order = ['S', 'W', 'N', 'E']
    parsed = {}
    for i, seat in enumerate(order):
        hand = {'s': [], 'h': [], 'd': [], 'c': []}
        curr = None
        for ch in hands_str[i]:
            if ch in 'SHDC': curr = ch.lower()
            elif curr: hand[curr].append(ch)
        parsed[seat] = hand
    return parsed

fit_stats = {
    'single_fit': {'tricks': [], 'hcp': []},
    'double_fit': {'tricks': [], 'hcp': []},
}

# Linear regression to predict tricks from HCP and Double Fit indicator
X = []
y = []

for entry in data:
    tricks = entry.get('tricks_made')
    deal_str = entry.get('deal')
    auction = entry.get('auction', [])
    if tricks is None or not deal_str or not auction: continue
    
    clean_auc = [b.lower().replace('!', '').replace('?', '').strip() for b in auction if b.lower().replace('!', '') not in ['p', 'pass']]
    if not clean_auc: continue
    final_call = clean_auc[-1]
    
    strain = None
    for s in ['s', 'h', 'd', 'c']:
        if s in final_call:
            strain = s
            break
    if not strain: continue
    
    hands = parse_deal(deal_str)
    if not hands: continue
    dealer_idx = int(deal_str[3]) - 1
    order = ['S', 'W', 'N', 'E']
    calls_with_seats = []
    for i, b in enumerate(auction):
        seat = order[(dealer_idx + i) % 4]
        calls_with_seats.append((seat, b.lower().replace('!', '').replace('?', '').strip()))
    clean_calls = [(s, c) for s, c in calls_with_seats if c not in ['p', 'pass']]
    if not clean_calls: continue
    declaring_team = ('N', 'S') if clean_calls[-1][0] in ['N', 'S'] else ('E', 'W')
    h1 = hands[declaring_team[0]]
    h2 = hands[declaring_team[1]]
    
    # Combined lengths
    comb_lens = {s: len(h1[s]) + len(h2[s]) for s in SUITS}
    trump_fit = comb_lens[strain]
    if trump_fit < 8: continue
    
    outside_fits = [comb_lens[s] for s in SUITS if s != strain]
    max_outside = max(outside_fits)
    
    # Combined HCP
    hcp_map = {'A': 4, 'K': 3, 'Q': 2, 'J': 1}
    comb_hcp = sum(hcp_map.get(c, 0) for s in SUITS for c in h1[s] + h2[s])
    
    is_double_fit = 1.0 if max_outside >= 8 else 0.0
    sec_fit_surplus = max(0.0, max_outside - 7.0)
    trump_fit_surplus = max(0.0, trump_fit - 8.0)
    
    if is_double_fit:
        fit_stats['double_fit']['tricks'].append(tricks)
        fit_stats['double_fit']['hcp'].append(comb_hcp)
    else:
        fit_stats['single_fit']['tricks'].append(tricks)
        fit_stats['single_fit']['hcp'].append(comb_hcp)
        
    X.append([1.0, comb_hcp - 24.0, trump_fit_surplus, is_double_fit])
    y.append(float(tricks))

n_single = len(fit_stats['single_fit']['tricks'])
n_double = len(fit_stats['double_fit']['tricks'])
print(f"Single Fit count: {n_single}")
print(f"Double Fit count: {n_double}")

avg_t_single = sum(fit_stats['single_fit']['tricks']) / n_single
avg_h_single = sum(fit_stats['single_fit']['hcp']) / n_single
avg_t_double = sum(fit_stats['double_fit']['tricks']) / n_double
avg_h_double = sum(fit_stats['double_fit']['hcp']) / n_double

print(f"Single Fit: Avg HCP = {avg_h_single:.2f}, Avg Tricks = {avg_t_single:.2f}")
print(f"Double Fit: Avg HCP = {avg_h_double:.2f}, Avg Tricks = {avg_t_double:.2f}")

# Pure python least squares
def solve_linear_regression(X, y):
    n_samples = len(y)
    n_features = len(X[0])
    XTX = [[0.0] * n_features for _ in range(n_features)]
    XTy = [0.0] * n_features
    for row_idx in range(n_samples):
        row = X[row_idx]
        y_val = y[row_idx]
        for i in range(n_features):
            XTy[i] += row[i] * y_val
            for j in range(i, n_features):
                XTX[i][j] += row[i] * row[j]
    for i in range(n_features):
        for j in range(i):
            XTX[i][j] = XTX[j][i]
    for i in range(n_features):
        XTX[i][i] += 1e-4
    A = [row[:] for row in XTX]
    b = XTy[:]
    for i in range(n_features):
        max_row = i
        max_val = abs(A[i][i])
        for k in range(i + 1, n_features):
            if abs(A[k][i]) > max_val:
                max_val = abs(A[k][i])
                max_row = k
        if max_row != i:
            A[i], A[max_row] = A[max_row], A[i]
            b[i], b[max_row] = b[max_row], b[i]
        diag = A[i][i]
        if abs(diag) < 1e-9: diag = 1e-9
        for k in range(i + 1, n_features):
            factor = A[k][i] / diag
            for j in range(i, n_features):
                A[k][j] -= factor * A[i][j]
            b[k] -= factor * b[i]
    weights = [0.0] * n_features
    for i in range(n_features - 1, -1, -1):
        s = sum(A[i][j] * weights[j] for j in range(i + 1, n_features))
        weights[i] = (b[i] - s) / A[i][i]
    return weights

beta = solve_linear_regression(X, y)
print("\nEmpirical regression on actual tricks made:")
print(f"  Base tricks at 24 HCP & 8-trump fit (beta0): {beta[0]:.3f}")
print(f"  Tricks per HCP (beta1):                       {beta[1]:.3f}")
print(f"  Tricks per Extra Trump above 8 (beta2):       {beta[2]:.3f}")
print(f"  Tricks for having an 8+ Double Fit (beta3):   {beta[3]:.3f}")

# Convert to Milton Work HCP equivalence:
hcp_per_trick = 1.0 / beta[1]
print(f"\n1 Trick is empirically equivalent to {hcp_per_trick:.2f} HCP points.")
print(f"Therefore, an 8+ Double Fit is empirically worth:")
print(f"  {beta[3] * hcp_per_trick:.2f} Power/HCP points directly from the BBO Championship data!")
