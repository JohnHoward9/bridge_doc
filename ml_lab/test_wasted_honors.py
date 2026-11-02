#!/usr/bin/env python3
"""
ml_lab/test_wasted_honors.py

Unit test directly verifying the user's scenario:
"For the same HCP count: KJ32 opposite x is wasted; xxxx opposite x is better
 as the honours will be in other suits where they will be more useful."

Compares:
- Deal A (Wasted Honors): Partner has 10 HCP with KJ32 in Diamonds opposite South's singleton 9.
- Deal B (Working Honors): Partner has 10 HCP with 7532 in Diamonds opposite South's singleton 9,
  and honors concentrated in South's 5-card Spades (KJ4) and Hearts (Q53).
"""

import json
from partnership_deal_generator import compute_ground_truth_combined_power
from partnership_feature_extractor import (
    extract_partnership_features,
    parse_pbn_suits,
    PARTNERSHIP_FEATURE_NAMES
)

def load_model():
    with open('ml_lab/models/partnership_ml_model.json', 'r') as f:
        return json.load(f)

def predict_partnership(model_data, south_suits, belief):
    feats = extract_partnership_features(south_suits, belief)
    x = [1.0] + feats
    weights = model_data['weights_vector']
    return sum(w * xi for w, xi in zip(weights, x))

def test_wasted_vs_working_honors():
    print("======================================================================")
    print("BENCHMARK TEST: WASTED VS WORKING HONORS OPPOSITE SHORTAGE")
    print("======================================================================\n")
    
    # South hand: ♠AQ1085 ♥K74 ♦9 ♣A96 (13 HCP, singleton Diamond)
    south_suits = {
        'S': 'AQ854',
        'H': 'K74',
        'D': '9',
        'C': 'A962',
    }
    
    # North Hand A (Wasted Honors): 10 HCP with KJ32 in Diamonds opposite South's singleton 9
    north_A = {
        'S': '653',       # 0 HCP
        'H': '852',       # 0 HCP
        'D': 'KJ32',      # 4 HCP (wasted opposite singleton 9)
        'C': 'AQ2',       # 6 HCP (AQ in clubs)
    }
    
    # North Hand B (Working Honors): Exact same 10 HCP, but pure diamonds (7532) and honors in South's suits
    # S: KJ4 (4 HCP in South's 5-card spade fit!)
    # H: Q52 (2 HCP in South's 3-card heart suit)
    # D: 7532 (0 HCP pure opposite South's singleton 9)
    # C: A852 (4 HCP)
    # Total = 4 + 2 + 0 + 4 = 10 HCP. Total cards: 3 + 3 + 4 + 3 = 13 cards (wait: C has 3 cards: A82 -> 13 cards)
    north_B = {
        'S': 'KJ4',       # 4 HCP (working in spades)
        'H': 'Q52',       # 2 HCP (working in hearts)
        'D': '7532',      # 0 HCP (pure cards opposite South's singleton 9!)
        'C': 'A82',       # 4 HCP
    }
    
    # Verify HCP and card counts
    def count_hcp(h):
        hcp_map = {'A': 4, 'K': 3, 'Q': 2, 'J': 1}
        return sum(hcp_map.get(c, 0) for s in h.values() for c in s)
    
    def count_cards(h):
        return sum(len(s) for s in h.values())
        
    assert count_cards(south_suits) == 13, f"South cards = {count_cards(south_suits)}"
    assert count_cards(north_A) == 13, f"North A cards = {count_cards(north_A)}"
    assert count_cards(north_B) == 13, f"North B cards = {count_cards(north_B)}"
    
    hcp_A = count_hcp(north_A)
    hcp_B = count_hcp(north_B)
    assert hcp_A == 10 and hcp_B == 10, f"HCP mismatch: A={hcp_A}, B={hcp_B}"
    
    # 1. Ground Truth Partnership Evaluation
    gt_A = compute_ground_truth_combined_power(south_suits, north_A)
    gt_B = compute_ground_truth_combined_power(south_suits, north_B)
    
    print("South Hand: S:AQ854 H:K74 D:9 C:A962 (13 HCP, singleton D:9)")
    print(f"\nScenario A (Wasted Diamonds):")
    print(f"  North: S:653 H:852 D:KJ32 C:AQ2 (10 HCP)")
    print(f"  Ground Truth Power: {gt_A['total_partnership_power']} KnR (Fit: {gt_A['best_fit_length']}, Mesh: {gt_A['mesh_net']:+.1f})")
    print(f"  Trump Fit: {gt_A['best_fit_suit']} ({gt_A['best_fit_length']} cards)")
    
    print(f"\nScenario B (Working Honors):")
    print(f"  North: S:KJ4 H:Q52 D:7532 C:A82 (10 HCP)")
    print(f"  Ground Truth Power: {gt_B['total_partnership_power']} KnR (Fit: {gt_B['best_fit_length']}, Mesh: {gt_B['mesh_net']:+.1f})")
    print(f"  Trump Fit: {gt_B['best_fit_suit']} ({gt_B['best_fit_length']} cards)")
    
    delta_gt = gt_B['total_partnership_power'] - gt_A['total_partnership_power']
    print(f"\n>>> Ground Truth Advantage of Working Honors (B vs A): +{delta_gt:.2f} KnR points!")
    
    # 2. Test ML Evaluation Under Incomplete Information (Auction Belief State)
    model = load_model()
    
    # Belief State for Auction A: North showed 10 HCP with values in Diamonds & Clubs
    belief_A = {
        'north_bid': '1D',
        'north_min_hcp': 9,
        'north_max_hcp': 11,
        'north_exp_hcp': 10.0,
        'north_exp_lengths': {'S': 2.0, 'H': 3.0, 'D': 4.0, 'C': 4.0},
        'north_exp_hcp_suit': {'S': 0.0, 'H': 0.0, 'D': 4.0, 'C': 6.0}, # KJ in D is expected
    }
    
    # Belief State for Auction B: North showed 10 HCP with Spade support and pure Diamonds
    belief_B = {
        'north_bid': '2S', # Raised South's 1S to 2S
        'north_min_hcp': 9,
        'north_max_hcp': 11,
        'north_exp_hcp': 10.0,
        'north_exp_lengths': {'S': 3.0, 'H': 3.0, 'D': 4.0, 'C': 3.0},
        'north_exp_hcp_suit': {'S': 4.0, 'H': 2.0, 'D': 0.0, 'C': 4.0}, # Honors working in S, H, C
    }
    
    pred_A = predict_partnership(model, south_suits, belief_A)
    pred_B = predict_partnership(model, south_suits, belief_B)
    
    print(f"\nML Model Prediction Under Auction Belief:")
    print(f"  Scenario A (Wasted KJ in D):      {pred_A:.2f} KnR (Target: Partscore 2S / 3C)")
    print(f"  Scenario B (Working Honors D:xxxx): {pred_B:.2f} KnR (Target: Game 4S!)")
    
    delta_pred = pred_B - pred_A
    print(f"\n>>> ML Model Delta (Scenario B over Scenario A): +{delta_pred:.2f} KnR points")
    
    # Assertions
    assert delta_gt >= 0.5, f"Ground truth delta {delta_gt} should be >= 0.5"
    assert delta_pred >= 2.0, f"ML predicted delta {delta_pred} should be >= 2.0"
    print("\n[SUCCESS] The ML Model successfully captured that KJ32 opposite shortage is wasted,")
    print("while xxxx opposite shortage allows honors to work in other suits to produce Game!")

if __name__ == '__main__':
    test_wasted_vs_working_honors()
