#!/usr/bin/env python3
"""
ml_lab/partnership_deal_generator.py

Generates full 4-hand bridge deals (South, North, East, West) with:
1. Exact KnR evaluations for both South and North.
2. Ground-truth Combined Partnership Power (including trump fit synergy,
   double-fit bonuses, and working vs wasted honor mesh).
3. Realistic auction belief state masking for North (partner) representing
   incomplete information during bidding.
"""

import random
from typing import Dict, List, Tuple
from knr_evaluator import evaluate_hand_knr

RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A']
SUITS = ['S', 'H', 'D', 'C']
RANK_HCP = {'A': 4, 'K': 3, 'Q': 2, 'J': 1, 'T': 0, '9': 0, '8': 0, '7': 0, '6': 0, '5': 0, '4': 0, '3': 0, '2': 0}

def full_deck() -> List[Tuple[str, str]]:
    return [(r, s) for s in SUITS for r in RANKS]

def deal_four_hands(rng: random.Random) -> Dict[str, Dict[str, str]]:
    """Deals 52 cards into S, N, E, W hand dicts."""
    deck = full_deck()
    rng.shuffle(deck)
    
    hands = {'S': {s: [] for s in SUITS},
             'N': {s: [] for s in SUITS},
             'E': {s: [] for s in SUITS},
             'W': {s: [] for s in SUITS}}
    
    seats = ['S', 'W', 'N', 'E']
    for i, (r, s) in enumerate(deck):
        hands[seats[i % 4]][s].append(r)
        
    rank_order = {r: idx for idx, r in enumerate(RANKS)}
    res = {}
    for seat in seats:
        res[seat] = {}
        for s in SUITS:
            hands[seat][s].sort(key=lambda r: rank_order[r], reverse=True)
            res[seat][s] = ''.join(hands[seat][s])
    return res

def format_pbn(hand_dict: Dict[str, str]) -> str:
    return f"{hand_dict['S']}.{hand_dict['H']}.{hand_dict['D']}.{hand_dict['C']}"

def compute_hcp(cards: str) -> int:
    return sum(RANK_HCP.get(c, 0) for c in cards)

def compute_ground_truth_combined_power(south: Dict[str, str], north: Dict[str, str]) -> Dict:
    """
    Computes ground-truth partnership playing strength combining:
    1. KnR of South + KnR of North.
    2. Trump fit bonus: +1.5 for each card beyond 8 in the best fit suit.
    3. Double fit bonus: +1.5 if a second 8+ card fit exists.
    4. Working vs wasted honor mesh:
       - Working honors (+0.5 per honor in partner's 4+ card suit).
       - Wasted honors (-1.0 for Q/J, -0.5 for K opposite partner's singleton/void).
    """
    knr_s = evaluate_hand_knr(south['S'], south['H'], south['D'], south['C'])['total']
    knr_n = evaluate_hand_knr(north['S'], north['H'], north['D'], north['C'])['total']
    
    combined_lengths = {s: len(south[s]) + len(north[s]) for s in SUITS}
    sorted_fits = sorted(combined_lengths.values(), reverse=True)
    best_fit = sorted_fits[0]
    second_fit = sorted_fits[1]
    
    # 1. Trump fit bonus
    fit_bonus = max(0.0, (best_fit - 8) * 1.5)
    double_fit_bonus = 1.5 if second_fit >= 8 else 0.0
    
    # 2. Honor Mesh: Working honors in long suits
    working_mesh = 0.0
    for s in SUITS:
        # South honors working in North's 4+ suit
        if len(north[s]) >= 4:
            for c in south[s]:
                if c in ['A', 'K', 'Q']:
                    working_mesh += 0.5
        # North honors working in South's 4+ suit
        if len(south[s]) >= 4:
            for c in north[s]:
                if c in ['A', 'K', 'Q']:
                    working_mesh += 0.5
                    
    # 3. Honor Mesh: Wasted honors opposite shortage (singleton/void)
    wasted_mesh = 0.0
    for s in SUITS:
        # North honors opposite South shortage
        if len(south[s]) <= 1:
            for c in north[s]:
                if c == 'K':
                    wasted_mesh += 0.5
                elif c in ['Q', 'J']:
                    wasted_mesh += 1.0
        # South honors opposite North shortage
        if len(north[s]) <= 1:
            for c in south[s]:
                if c == 'K':
                    wasted_mesh += 0.5
                elif c in ['Q', 'J']:
                    wasted_mesh += 1.0
                    
    mesh_adjustment = working_mesh - wasted_mesh
    total_power = knr_s + knr_n + fit_bonus + double_fit_bonus + mesh_adjustment
    
    return {
        'knr_south': knr_s,
        'knr_north': knr_n,
        'best_fit_suit': max(combined_lengths, key=combined_lengths.get),
        'best_fit_length': best_fit,
        'fit_bonus': fit_bonus,
        'double_fit_bonus': double_fit_bonus,
        'working_mesh': working_mesh,
        'wasted_mesh': wasted_mesh,
        'mesh_net': mesh_adjustment,
        'total_partnership_power': round(total_power, 2),
    }

def simulate_bidding_belief_state(north: Dict[str, str], rng: random.Random) -> Dict:
    """
    Simulates what South knows about North from typical bidding scenarios:
    Returns belief constraints (HCP min/max, expected suit lengths, expected HCP per suit).
    """
    hcp_n = sum(compute_hcp(north[s]) for s in SUITS)
    lengths_n = {s: len(north[s]) for s in SUITS}
    
    # Check what opening bid North would make
    is_balanced = (
        all(lengths_n[s] >= 2 for s in SUITS) and
        sum(1 for s in SUITS if lengths_n[s] == 2) <= 1 and
        max(lengths_n.values()) <= 5
    )
    
    if 15 <= hcp_n <= 17 and is_balanced:
        # North opened 1NT (15-17 balanced)
        bid = '1NT'
        hcp_min, hcp_max = 15, 17
        exp_lengths = {s: 3.25 for s in SUITS}
        # Expected HCP distributed evenly
        exp_hcp_suit = {s: 16.0 / 4.0 for s in SUITS}
    elif lengths_n['S'] >= 5 and 12 <= hcp_n <= 21:
        # North opened 1S (12-21, 5+ spades)
        bid = '1S'
        hcp_min, hcp_max = 12, 21
        exp_lengths = {'S': 5.3, 'H': 2.7, 'D': 2.5, 'C': 2.5}
        # Honors concentrated in Spades
        exp_hcp_suit = {'S': 7.0, 'H': 3.0, 'D': 3.0, 'C': 3.0}
    elif lengths_n['H'] >= 5 and 12 <= hcp_n <= 21:
        # North opened 1H (12-21, 5+ hearts)
        bid = '1H'
        hcp_min, hcp_max = 12, 21
        exp_lengths = {'H': 5.3, 'S': 2.7, 'D': 2.5, 'C': 2.5}
        exp_hcp_suit = {'H': 7.0, 'S': 3.0, 'D': 3.0, 'C': 3.0}
    elif hcp_n < 12:
        # North passed (0-11 HCP)
        bid = 'PASS'
        hcp_min, hcp_max = 0, 11
        exp_lengths = {s: 3.25 for s in SUITS}
        exp_hcp_suit = {s: 1.5 for s in SUITS}
    else:
        # North opened 1 minor (12-21)
        bid = '1m'
        hcp_min, hcp_max = 12, 21
        exp_lengths = {s: 3.25 for s in SUITS}
        exp_hcp_suit = {s: 3.5 for s in SUITS}
        
    return {
        'north_bid': bid,
        'north_min_hcp': hcp_min,
        'north_max_hcp': hcp_max,
        'north_exp_hcp': (hcp_min + hcp_max) / 2.0,
        'north_exp_lengths': exp_lengths,
        'north_exp_hcp_suit': exp_hcp_suit,
    }

def generate_partnership_dataset(num_samples: int = 10000, seed: int = 42) -> List[Dict]:
    """Generates `num_samples` deals with ground-truth partnership power and belief states."""
    rng = random.Random(seed)
    dataset = []
    
    for i in range(num_samples):
        deal = deal_four_hands(rng)
        south = deal['S']
        north = deal['N']
        
        gt = compute_ground_truth_combined_power(south, north)
        belief = simulate_bidding_belief_state(north, rng)
        
        dataset.append({
            'id': i,
            'south_pbn': format_pbn(south),
            'north_pbn': format_pbn(north),
            'south_suits': south,
            'north_suits': north,
            'ground_truth': gt,
            'belief': belief,
        })
        
    return dataset

if __name__ == '__main__':
    data = generate_partnership_dataset(3)
    for d in data:
        print(f"Deal {d['id']}: S={d['south_pbn']} | N={d['north_pbn']}")
        print(f"  Ground Truth Power: {d['ground_truth']['total_partnership_power']} KnR (Fit: {d['ground_truth']['best_fit_length']}, Mesh: {d['ground_truth']['mesh_net']})")
        print(f"  North Belief: {d['belief']['north_bid']}, Exp HCP={d['belief']['north_exp_hcp']}")
