#!/usr/bin/env python3
"""
ml_lab/feature_extractor.py

Suit-Specific & Rule-Inferred Feature Extractor for Bridge Hand Evaluation.
Organizes dimensions by named suits (length_spades, length_hearts, etc.)
and computes dynamic expected partner suit lengths and combined fits.
"""

from typing import Dict, List, Optional, Tuple

SUITS = ['S', 'H', 'D', 'C']
RANK_HCP = {'A': 4, 'K': 3, 'Q': 2, 'J': 1, 'T': 0, '9': 0, '8': 0, '7': 0, '6': 0, '5': 0, '4': 0, '3': 0, '2': 0}

# Combinatorial suit length prior distribution P(L = k) for a random 13-card holding
SUIT_LENGTH_PRIORS = {
    0: 0.01279,
    1: 0.07007,
    2: 0.20581,
    3: 0.28633,
    4: 0.23861,
    5: 0.12469,
    6: 0.04501,
    7: 0.01183,
    8: 0.00207,
    9: 0.00025,
    10: 0.00002,
}

FEATURE_NAMES = [
    'raw_hcp',
    'length_spades',
    'length_hearts',
    'length_diamonds',
    'length_clubs',
    'hcp_spades',
    'hcp_hearts',
    'hcp_diamonds',
    'hcp_clubs',
    'aces',
    'kings',
    'queens',
    'jacks',
    'tens',
    'nines',
    'controls',
    'length_sorted_1',              # Longest suit length (e.g. 6)
    'length_sorted_2',              # Second suit length (e.g. 4)
    'length_sorted_3',              # Third suit length (e.g. 2)
    'length_sorted_4',              # Shortest suit length (e.g. 1)
    'long_suit_length_bonus',       # max(0, L1 - 4)
    'second_suit_bonus',            # max(0, L2 - 3)
    'shortness_value',              # max(0, 3 - L4)
    'honor_length_interaction',     # (HCP_L1 * L1) / 10.0
    'partner_exp_spades',           # E[L_s] from rules
    'partner_exp_hearts',
    'partner_exp_diamonds',
    'partner_exp_clubs',
    'combined_spades',              # L_my + E[L_partner]
    'combined_hearts',
    'combined_diamonds',
    'combined_clubs',
    'golden_fit_bonus',             # max(0, max(combined) - 8.0)
]

def expected_suit_length(min_len: int = 0, max_len: int = 13) -> float:
    """
    Computes expected suit length E[L | min_len <= L <= max_len] using combinatorial priors.
    """
    weighted_sum = 0.0
    prob_sum = 0.0
    for k in range(min_len, min(max_len, 10) + 1):
        p = SUIT_LENGTH_PRIORS.get(k, 0.00001)
        weighted_sum += k * p
        prob_sum += p
    
    if prob_sum > 0:
        return round(weighted_sum / prob_sum, 2)
    return float(min_len)

def parse_pbn_suits(pbn_string: str) -> Dict[str, str]:
    """
    Parses 'K3.AKQ974.9.K862' into {'S': 'K3', 'H': 'AKQ974', 'D': '9', 'C': 'K862'}.
    """
    parts = pbn_string.strip().split('.')
    return {
        'S': parts[0].upper().replace('10', 'T'),
        'H': parts[1].upper().replace('10', 'T'),
        'D': parts[2].upper().replace('10', 'T'),
        'C': parts[3].upper().replace('10', 'T'),
    }

def extract_features(
    pbn_hand: str,
    partner_rules: Optional[Dict[str, Tuple[int, int]]] = None
) -> List[float]:
    """
    Extracts continuous, suit-specific feature vector for a hand.
    `partner_rules` maps suit ('S','H','D','C') to (min_len, max_len) constraints shown in auction.
    Default prior is unconstrained random hand (E[L] = 3.25 per suit).
    """
    suits = parse_pbn_suits(pbn_hand)
    
    lengths = {s: len(suits[s]) for s in SUITS}
    hcp_per_suit = {
        s: sum(RANK_HCP.get(c, 0) for c in suits[s]) for s in SUITS
    }
    raw_hcp = sum(hcp_per_suit.values())
    
    # Honors counts
    all_cards = ''.join(suits.values())
    aces = all_cards.count('A')
    kings = all_cards.count('K')
    queens = all_cards.count('Q')
    jacks = all_cards.count('J')
    tens = all_cards.count('T')
    nines = all_cards.count('9')
    controls = (2 * aces) + kings
    
    # Sorted lengths for distribution power
    sorted_lens = sorted(lengths.values(), reverse=True)
    l1, l2, l3, l4 = sorted_lens[0], sorted_lens[1], sorted_lens[2], sorted_lens[3]
    long_bonus = max(0.0, l1 - 4.0)
    second_bonus = max(0.0, l2 - 3.0)
    shortness = max(0.0, 3.0 - l4)
    
    # Honor concentration in longest suit
    longest_suit = max(SUITS, key=lambda s: lengths[s])
    hcp_l1 = hcp_per_suit[longest_suit]
    honor_length_interaction = (hcp_l1 * l1) / 10.0

    # Partner expected suit lengths
    partner_rules = partner_rules or {}
    partner_exp = {}
    for s in SUITS:
        if s in partner_rules:
            min_l, max_l = partner_rules[s]
            partner_exp[s] = expected_suit_length(min_l, max_l)
        else:
            partner_exp[s] = 3.25  # a priori prior expectation

    # Combined partnership lengths
    combined = {s: lengths[s] + partner_exp[s] for s in SUITS}
    golden_fit_bonus = max(0.0, max(combined.values()) - 8.0)

    return [
        float(raw_hcp),
        float(lengths['S']),
        float(lengths['H']),
        float(lengths['D']),
        float(lengths['C']),
        float(hcp_per_suit['S']),
        float(hcp_per_suit['H']),
        float(hcp_per_suit['D']),
        float(hcp_per_suit['C']),
        float(aces),
        float(kings),
        float(queens),
        float(jacks),
        float(tens),
        float(nines),
        float(controls),
        float(l1),
        float(l2),
        float(l3),
        float(l4),
        float(long_bonus),
        float(second_bonus),
        float(shortness),
        float(honor_length_interaction),
        float(partner_exp['S']),
        float(partner_exp['H']),
        float(partner_exp['D']),
        float(partner_exp['C']),
        float(combined['S']),
        float(combined['H']),
        float(combined['D']),
        float(combined['C']),
        float(golden_fit_bonus),
    ]

if __name__ == '__main__':
    hand = "K3.AKQ974.9.K862"
    vec = extract_features(hand)
    print("Features for", hand)
    for name, val in zip(FEATURE_NAMES, vec):
        print(f"  {name:25}: {val}")
