#!/usr/bin/env python3
"""
ml_lab/deal_generator.py

Generates random bridge deals and computes ground truth Kaplan-Rubens (KnR)
evaluations across all 39 distribution shapes and HCP ranges.
"""

import random
from typing import List, Dict, Tuple
from knr_evaluator import evaluate_hand_knr

RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A']
SUITS = ['S', 'H', 'D', 'C']

def full_deck() -> List[Tuple[str, str]]:
    """Returns standard 52-card deck as (rank, suit) tuples."""
    return [(r, s) for s in SUITS for r in RANKS]

def deal_single_hand(rng: random.Random) -> Dict[str, str]:
    """Deals a random 13-card hand, returning {'S': '...', 'H': '...', 'D': '...', 'C': '...'}."""
    deck = full_deck()
    cards = rng.sample(deck, 13)
    
    # Group by suit and sort high-to-low
    suit_cards = {s: [] for s in SUITS}
    for r, s in cards:
        suit_cards[s].append(r)
        
    rank_order = {r: i for i, r in enumerate(RANKS)}
    for s in SUITS:
        suit_cards[s].sort(key=lambda r: rank_order[r], reverse=True)
        
    return {s: ''.join(suit_cards[s]) for s in SUITS}

def format_pbn(suit_dict: Dict[str, str]) -> str:
    """Formats suit dict into PBN string: 'S.H.D.C'."""
    return f"{suit_dict['S']}.{suit_dict['H']}.{suit_dict['D']}.{suit_dict['C']}"

def generate_knr_dataset(num_samples: int = 10000, seed: int = 42) -> List[Dict]:
    """
    Generates `num_samples` random hands with ground-truth Kaplan-Rubens evaluation.
    """
    rng = random.Random(seed)
    dataset = []
    
    for i in range(num_samples):
        suits = deal_single_hand(rng)
        pbn = format_pbn(suits)
        knr = evaluate_hand_knr(suits['S'], suits['H'], suits['D'], suits['C'])
        
        dataset.append({
            'id': i,
            'pbn': pbn,
            'suits': suits,
            'knr_total': knr['total'],
            'knr_suits': knr['suits'],
            'knr_adj': knr['adjustment'],
        })
        
    return dataset

if __name__ == '__main__':
    data = generate_knr_dataset(5)
    for d in data:
        print(f"Deal {d['id']}: {d['pbn']} -> KnR = {d['knr_total']}")
