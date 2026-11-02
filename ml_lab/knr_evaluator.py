#!/usr/bin/env python3
"""
ml_lab/knr_evaluator.py

Official 26-step Kaplan-Rubens (KnR / Four C's) Bridge Hand Evaluation Algorithm.
Devised by Edgar Kaplan and Jeff Rubens (The Bridge World, 1982).
Reference implementation verified against Richard Pavlicek (rpbridge.net/8j19.htm).
"""

from typing import List, Dict, Tuple, Union

# Standard suit order
SUITS = ['S', 'H', 'D', 'C']
HONOR_RANKS = {'A': 14, 'K': 13, 'Q': 12, 'J': 11, 'T': 10, '9': 9, '8': 8}

def evaluate_suit_knr(cards: str) -> float:
    """
    Evaluates a single suit holding using the 26-step Kaplan-Rubens algorithm.
    `cards` is a string of ranks, e.g. "AKQ974", "K3", "9", "" (void).
    Returns the fractional KnR suit points.
    """
    length = len(cards)
    
    # Step 24: Void
    if length == 0:
        return 3.0

    ranks = set(cards.upper().replace('10', 'T'))
    has_ace = 'A' in ranks
    has_king = 'K' in ranks
    has_queen = 'Q' in ranks
    has_jack = 'J' in ranks
    has_ten = 'T' in ranks
    has_nine = '9' in ranks
    has_eight = '8' in ranks

    higher_honors = sum([has_ace, has_king, has_queen, has_jack])
    higher_than_queen = sum([has_ace, has_king])

    # --- Phase 1: High Card Base (Steps 1 - 11) ---
    val = 0.0

    # Step 1: Ace
    if has_ace:
        val += 4.0
    # Step 2: King
    if has_king:
        val += 3.0
    # Step 3: Queen
    if has_queen:
        val += 2.0
    # Step 4: Jack
    if has_jack:
        val += 1.0
    # Step 5: Ten
    if has_ten:
        val += 0.5

    # Step 6: 2-6 cards with ten accompanied by jack or two (or more) higher honors
    if 2 <= length <= 6 and has_ten:
        if has_jack or higher_than_queen >= 2:
            val += 0.5

    # Step 7: 2-6 cards with nine accompanied by eight, ten, or exactly two higher honors
    # Step 8: 4-6 cards with nine (no eight or ten) and exactly three higher honors
    if 2 <= length <= 6 and has_nine:
        if has_eight or has_ten or higher_honors == 2:
            val += 0.5
        elif 4 <= length <= 6 and not has_eight and not has_ten and higher_honors == 3:
            val += 0.5

    # Step 9: 7+ cards missing queen or jack (or both)
    if length >= 7 and (not has_queen or not has_jack):
        val += 1.0
    # Step 10: 8+ cards missing queen
    if length >= 8 and not has_queen:
        val += 1.0
    # Step 11: 9+ cards missing queen and jack
    if length >= 9 and not has_queen and not has_jack:
        val += 1.0

    # Step 12: Multiply current total by suit length, divide by 10, then continue
    val = (val * length) / 10.0

    # --- Phase 2: Honor Accompaniment & Distribution (Steps 13 - 26) ---
    # Step 13: Ace
    if has_ace:
        val += 3.0

    # Step 14: King guarded (length >= 2)
    if has_king and length >= 2:
        val += 2.0
    # Step 15: King singleton
    elif has_king and length == 1:
        val += 0.5

    # Steps 16 - 19: Queen
    if has_queen:
        if length >= 3:
            if higher_than_queen > 0:
                val += 1.0     # Step 16: Queen (3+ cards) with ace or king
            else:
                val += 0.75    # Step 17: Queen (3+ cards) with no higher honor
        elif length == 2:
            if higher_than_queen > 0:
                val += 0.5     # Step 18: Queen doubleton with ace or king
            else:
                val += 0.25    # Step 19: Queen doubleton with no higher honor

    # Steps 20 - 21: Jack
    if has_jack:
        if higher_honors - 1 == 2:   # Jack with exactly two higher honors
            val += 0.5     # Step 20
        elif higher_honors - 1 == 1: # Jack with exactly one higher honor
            val += 0.25    # Step 21

    # Steps 22 - 23: Ten & Nine
    if has_ten and (higher_honors == 2):
        val += 0.25        # Step 22: Ten with exactly two higher honors
    if has_ten and has_nine and (higher_honors == 1):
        val += 0.25        # Step 23: Ten and nine with exactly one higher honor

    # Steps 24 - 26: Shortness/Length
    if length == 1:
        val += 2.0         # Step 25: Singleton
    elif length == 2:
        val += 1.0         # Step 26: Doubleton

    return round(val, 4)

def evaluate_hand_knr(spades: str, hearts: str, diamonds: str, clubs: str) -> Dict[str, Union[float, Dict[str, float]]]:
    """
    Evaluates a full 13-card hand using the complete 26-step Kaplan-Rubens method.
    Returns:
      {
        'total': float,
        'suits': {'S': float, 'H': float, 'D': float, 'C': float},
        'adjustment': float,
        'is_4333': bool
      }
    """
    s_val = evaluate_suit_knr(spades)
    h_val = evaluate_suit_knr(hearts)
    d_val = evaluate_suit_knr(diamonds)
    c_val = evaluate_suit_knr(clubs)

    lengths = sorted([len(spades), len(hearts), len(diamonds), len(clubs)], reverse=True)
    is_4333 = (lengths == [4, 3, 3, 3])

    # Final adjustment: subtract 1, then if 4-3-3-3 add 0.5
    adj = -1.0
    if is_4333:
        adj += 0.5

    total = s_val + h_val + d_val + c_val + adj
    # KnR is reported in 1/20 (0.05) increments
    total = round(total, 2)

    return {
        'total': total,
        'suits': {'S': round(s_val, 2), 'H': round(h_val, 2), 'D': round(d_val, 2), 'C': round(c_val, 2)},
        'adjustment': adj,
        'is_4333': is_4333,
    }

def evaluate_pbn_hand_knr(pbn_string: str) -> Dict[str, Union[float, Dict[str, float]]]:
    """
    Evaluates hand in PBN dot-separated format: 'K3.AKQ974.9.K862' (S.H.D.C).
    """
    parts = pbn_string.strip().split('.')
    if len(parts) != 4:
        raise ValueError(f"Invalid PBN hand string: '{pbn_string}'. Must have 4 dot-separated suits.")
    return evaluate_hand_knr(parts[0], parts[1], parts[2], parts[3])

if __name__ == '__main__':
    # Test on North's hand from the user's board
    hand_pbn = "K3.AKQ974.9.K862"
    res = evaluate_pbn_hand_knr(hand_pbn)
    print(f"Hand: {hand_pbn}")
    print(f"KnR Suits: {res['suits']}")
    print(f"KnR Adjustment: {res['adjustment']}")
    print(f"KnR Total: {res['total']}")
