#!/usr/bin/env python3
"""
ml_lab/partnership_feature_extractor.py

Feature extraction for Partnership Valuation under Uncertainty.
Includes:
- South Known Hand Features (KnR, HCP, lengths, shortness).
- North Belief State Features (Expected HCP, expected lengths, expected suit HCP).
- Joint Interaction Cross-Features:
  1. Trump fit synergy: L_south + E[L_north]
  2. Wasted partner honors opposite South shortage (e.g. KJ32 opposite singleton).
  3. Working partner honors in South long suits (e.g. honors in South's 5-card suit).
  4. South honors opposite North shortage.
  5. Secondary honors (Q, J) opposite shortage.
"""

from typing import Dict, List
from knr_evaluator import evaluate_hand_knr

SUITS = ['S', 'H', 'D', 'C']
RANK_HCP = {'A': 4, 'K': 3, 'Q': 2, 'J': 1, 'T': 0, '9': 0, '8': 0, '7': 0, '6': 0, '5': 0, '4': 0, '3': 0, '2': 0}

PARTNERSHIP_FEATURE_NAMES = [
    'south_knr',
    'south_raw_hcp',
    'south_len_spades',
    'south_len_hearts',
    'south_len_diamonds',
    'south_len_clubs',
    'south_hcp_spades',
    'south_hcp_hearts',
    'south_hcp_diamonds',
    'south_hcp_clubs',
    'south_short_spades',               # 1 if len <= 1
    'south_short_hearts',
    'south_short_diamonds',
    'south_short_clubs',
    
    # Partner Belief State
    'north_exp_hcp',
    'north_min_hcp',
    'north_max_hcp',
    'north_exp_len_spades',
    'north_exp_len_hearts',
    'north_exp_len_diamonds',
    'north_exp_len_clubs',
    'north_exp_hcp_spades',
    'north_exp_hcp_hearts',
    'north_exp_hcp_diamonds',
    'north_exp_hcp_clubs',
    
    # Joint Cross-Features
    'fit_spades',                       # south_len + north_exp_len
    'fit_hearts',
    'fit_diamonds',
    'fit_clubs',
    'max_trump_fit',                    # max(fit_s)
    'fit_bonus_synergy',                # max(0, max_trump_fit - 8.0) * 1.5
    'wasted_partner_hcp_in_shortage',   # sum_s (north_exp_hcp_s * I(south_len_s <= 1))
    'working_partner_hcp_in_length',    # sum_s (north_exp_hcp_s * I(south_len_s >= 4))
    'my_honors_in_partner_suit',        # sum_s (south_hcp_s * I(north_exp_len_s >= 5))
    'my_honors_opposite_shortage',      # sum_s (south_hcp_s * I(north_exp_len_s <= 1))
    'my_secondary_honors_in_shortage',  # sum_s ((Q + J) * I(north_exp_len_s <= 1))
]

def parse_pbn_suits(pbn_string: str) -> Dict[str, str]:
    parts = pbn_string.strip().split('.')
    return {
        'S': parts[0].upper().replace('10', 'T'),
        'H': parts[1].upper().replace('10', 'T'),
        'D': parts[2].upper().replace('10', 'T'),
        'C': parts[3].upper().replace('10', 'T'),
    }

def extract_partnership_features(south_suits: Dict[str, str], belief: Dict) -> List[float]:
    """
    Extracts continuous joint feature vector for South hand + North belief state.
    """
    # 1. South hand
    knr_s = evaluate_hand_knr(south_suits['S'], south_suits['H'], south_suits['D'], south_suits['C'])['total']
    lens_s = {s: len(south_suits[s]) for s in SUITS}
    hcp_s = {s: sum(RANK_HCP.get(c, 0) for c in south_suits[s]) for s in SUITS}
    raw_hcp_s = sum(hcp_s.values())
    short_s = {s: 1.0 if lens_s[s] <= 1 else 0.0 for s in SUITS}
    
    # Secondary honors (Queens, Jacks) in South
    qj_s = {s: sum(1 for c in south_suits[s] if c in ['Q', 'J']) for s in SUITS}
    
    # 2. North belief
    n_exp_hcp = belief['north_exp_hcp']
    n_min_hcp = belief['north_min_hcp']
    n_max_hcp = belief['north_max_hcp']
    n_exp_lens = belief['north_exp_lengths']
    n_exp_hcp_suit = belief['north_exp_hcp_suit']
    
    # 3. Joint cross-features
    fits = {s: lens_s[s] + n_exp_lens[s] for s in SUITS}
    max_fit = max(fits.values())
    fit_bonus = max(0.0, max_fit - 8.0) * 1.5
    
    # Wasted partner HCP falling into South's singleton/void
    wasted_partner_hcp = sum(n_exp_hcp_suit[s] for s in SUITS if lens_s[s] <= 1)
    
    # Working partner HCP falling into South's 4+ card suits
    working_partner_hcp = sum(n_exp_hcp_suit[s] for s in SUITS if lens_s[s] >= 4)
    
    # South honors supporting partner's 5+ card suit
    my_honors_in_partner = sum(hcp_s[s] for s in SUITS if n_exp_lens[s] >= 5.0)
    
    # South honors opposite partner's shortage (<= 1.5 cards)
    my_honors_opposite_shortage = sum(hcp_s[s] for s in SUITS if n_exp_lens[s] <= 1.5)
    
    # South secondary honors (Q, J) opposite partner's shortage
    my_secondary_opposite_shortage = sum(qj_s[s] for s in SUITS if n_exp_lens[s] <= 1.5)
    
    vec = [
        knr_s,
        raw_hcp_s,
        float(lens_s['S']),
        float(lens_s['H']),
        float(lens_s['D']),
        float(lens_s['C']),
        float(hcp_s['S']),
        float(hcp_s['H']),
        float(hcp_s['D']),
        float(hcp_s['C']),
        short_s['S'],
        short_s['H'],
        short_s['D'],
        short_s['C'],
        
        # North belief
        float(n_exp_hcp),
        float(n_min_hcp),
        float(n_max_hcp),
        float(n_exp_lens['S']),
        float(n_exp_lens['H']),
        float(n_exp_lens['D']),
        float(n_exp_lens['C']),
        float(n_exp_hcp_suit['S']),
        float(n_exp_hcp_suit['H']),
        float(n_exp_hcp_suit['D']),
        float(n_exp_hcp_suit['C']),
        
        # Joint Cross-Features
        float(fits['S']),
        float(fits['H']),
        float(fits['D']),
        float(fits['C']),
        float(max_fit),
        float(fit_bonus),
        float(wasted_partner_hcp),
        float(working_partner_hcp),
        float(my_honors_in_partner),
        float(my_honors_opposite_shortage),
        float(my_secondary_opposite_shortage),
    ]
    return vec
