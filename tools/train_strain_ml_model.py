#!/usr/bin/env python3
"""
train_strain_ml_model.py
Trains strain-dependent trick expectation and power models (NT, Spades, Hearts, Diamonds, Clubs)
directly from the 2025 BBO Championship dataset (res/bbo_championships_2025_dataset.json).

Trains TWO models per strain:
1. single_hand: Evaluates an individual hand's playing power across strains.
2. partnership: Evaluates joint partnership contracts directly using combined features:
   - Trump fit length (8-card, 9-card, 10-card fits)
   - Secondary fit & Double-fit synergy (8+ secondary fit)
   - Combined controls and shortness
   - Active opponent competition penalty

Exports empirical weights to assets/models/ml_strain_model.json.
"""

import json
import math
import os
import random

SUITS = ['s', 'h', 'd', 'c']

def parse_deal(deal_str):
    if not deal_str.startswith('md|'):
        return None
    content = deal_str[3:].rstrip('|')
    dealer_char = content[0]
    hands_str = content[1:].split(',')
    
    order = ['S', 'W', 'N', 'E']
    parsed = {}
    for i, seat in enumerate(order):
        hand = {'s': [], 'h': [], 'd': [], 'c': []}
        curr_suit = None
        for ch in hands_str[i]:
            if ch in 'SHDC':
                curr_suit = ch.lower()
            elif curr_suit:
                hand[curr_suit].append(ch)
        parsed[seat] = hand
    return parsed

def extract_hand_features(hand):
    lengths = {s: len(hand[s]) for s in SUITS}
    hcp = 0
    tens = 0
    nines = 0
    aces = 0
    kings = 0
    queens = 0
    jacks = 0
    
    suit_hcp = {s: 0 for s in SUITS}
    for s in SUITS:
        for card in hand[s]:
            if card == 'A':
                hcp += 4
                aces += 1
                suit_hcp[s] += 4
            elif card == 'K':
                hcp += 3
                kings += 1
                suit_hcp[s] += 3
            elif card == 'Q':
                hcp += 2
                queens += 1
                suit_hcp[s] += 2
            elif card == 'J':
                hcp += 1
                jacks += 1
                suit_hcp[s] += 1
            elif card == 'T':
                tens += 1
            elif card == '9':
                nines += 1
                
    sorted_lens = sorted(lengths.values(), reverse=True)
    is_4333 = 1.0 if sorted_lens == [4, 3, 3, 3] else 0.0
    is_balanced = 1.0 if (sorted_lens in [[4, 3, 3, 3], [4, 4, 3, 2], [5, 3, 3, 2]]) else 0.0
    
    return {
        'hcp': float(hcp),
        'aces': float(aces),
        'kings': float(kings),
        'queens': float(queens),
        'jacks': float(jacks),
        'tens': float(tens),
        'nines': float(nines),
        'len_s': float(lengths['s']),
        'len_h': float(lengths['h']),
        'len_d': float(lengths['d']),
        'len_c': float(lengths['c']),
        'hcp_s': float(suit_hcp['s']),
        'hcp_h': float(suit_hcp['h']),
        'hcp_d': float(suit_hcp['d']),
        'hcp_c': float(suit_hcp['c']),
        'is_4333': is_4333,
        'is_balanced': is_balanced,
    }

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
        if abs(diag) < 1e-9:
            diag = 1e-9
            
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

def main():
    dataset_path = "res/bbo_championships_2025_dataset.json"
    if not os.path.exists(dataset_path):
        print(f"Error: {dataset_path} not found.")
        return
        
    print(f"Loading {dataset_path}...")
    with open(dataset_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 1. Datasets for Single Hand Evaluation (predicting hand power delta)
    single_samples = {s: {'X': [], 'y': []} for s in ['nt', 's', 'h', 'd', 'c']}
    single_features = [
        'bias',
        'aces_diff',
        'kings_diff',
        'queens_diff',
        'jacks_diff',
        'tens_diff',
        'nines_diff',
        'trump_len_surplus',
        'side_shortness',
        'is_4333',
        'is_balanced',
    ]

    # 2. Datasets for Partnership Joint Evaluation (predicting partnership power delta over comb_hcp)
    part_suit_features = [
        'bias',
        'trump_fit_surplus',    # max(0, comb_trump - 8)
        'has_double_fit',       # 1.0 if trump >= 8 and sec >= 8
        'sec_fit_surplus',      # max(0, sec_fit - 7)
        'side_shortness',       # voids/singletons in outside suits
        'comb_controls_diff',   # (aces - 2)*1.0 + (kings - 2)*0.5
        'is_opp_active',        # 1.0 if opponents competed
    ]
    part_nt_features = [
        'bias',
        'running_suit_surplus', # max(0, max_fit - 7)
        'comb_controls_diff',
        'is_opp_active',
        'is_flat',
    ]
    part_samples = {s: {'X': [], 'y': []} for s in ['nt', 's', 'h', 'd', 'c']}

    for entry in data:
        tricks = entry.get('tricks_made')
        deal_str = entry.get('deal')
        auction = entry.get('auction', [])
        if tricks is None or not deal_str or not auction:
            continue
            
        clean_auc = [b.lower().replace('!', '').replace('?', '').strip() for b in auction if b.lower().replace('!', '') not in ['p', 'pass']]
        if not clean_auc:
            continue
        final_call = clean_auc[-1]
        
        strain = None
        if 'nt' in final_call or 'n' in final_call:
            strain = 'nt'
        elif 's' in final_call:
            strain = 's'
        elif 'h' in final_call:
            strain = 'h'
        elif 'd' in final_call:
            strain = 'd'
        elif 'c' in final_call:
            strain = 'c'
        if not strain:
            continue
            
        hands = parse_deal(deal_str)
        if not hands:
            continue
            
        dealer_char = deal_str[3]
        dealer_idx = int(dealer_char) - 1
        order = ['S', 'W', 'N', 'E']

        calls_with_seats = []
        for i, b in enumerate(auction):
            seat = order[(dealer_idx + i) % 4]
            clean_b = b.lower().replace('!', '').replace('?', '').strip()
            calls_with_seats.append((seat, clean_b))

        clean_calls = [(s, c) for s, c in calls_with_seats if c not in ['p', 'pass']]
        if not clean_calls:
            continue
        last_seat, last_call = clean_calls[-1]
        declaring_team = ('N', 'S') if last_seat in ['N', 'S'] else ('E', 'W')
        defending_team = ('E', 'W') if declaring_team == ('N', 'S') else ('N', 'S')

        is_opp_active = 1.0 if any(s in defending_team and c not in ['p', 'pass'] for s, c in clean_calls) else 0.0

        h1 = hands[declaring_team[0]]
        h2 = hands[declaring_team[1]]
        hf1 = extract_hand_features(h1)
        hf2 = extract_hand_features(h2)

        # ---------------- PARTNERSHIP JOINT EVALUATION ----------------
        comb_hcp = hf1['hcp'] + hf2['hcp']
        comb_power = (tricks / 13.0) * 40.0
        part_delta = comb_power - comb_hcp
        comb_lens = {s: len(h1[s]) + len(h2[s]) for s in SUITS}
        comb_aces = hf1['aces'] + hf2['aces']
        comb_kings = hf1['kings'] + hf2['kings']
        comb_controls_diff = (comb_aces - 2.0) * 1.0 + (comb_kings - 2.0) * 0.5

        if strain != 'nt':
            trump_fit = comb_lens[strain]
            trump_surplus = max(0.0, float(trump_fit - 8))
            outside_fits = [comb_lens[s] for s in SUITS if s != strain]
            sec_fit = max(outside_fits) if outside_fits else 0
            has_df = 1.0 if (trump_fit >= 8 and sec_fit >= 8) else 0.0
            sec_surplus = max(0.0, float(sec_fit - 7))
            
            # Count shortness in outside suits
            shortness = 0.0
            for s in SUITS:
                if s != strain:
                    if len(h1[s]) == 0: shortness += 2.0
                    elif len(h1[s]) == 1: shortness += 1.0
                    if len(h2[s]) == 0: shortness += 2.0
                    elif len(h2[s]) == 1: shortness += 1.0
                    
            part_row = [
                1.0, # bias
                trump_surplus,
                has_df,
                sec_surplus,
                shortness,
                comb_controls_diff,
                is_opp_active,
            ]
            part_samples[strain]['X'].append(part_row)
            part_samples[strain]['y'].append(part_delta)
        else:
            max_fit = max(comb_lens.values())
            running_suit = max(0.0, float(max_fit - 7))
            is_flat = 1.0 if (hf1['is_balanced'] and hf2['is_balanced']) else 0.0
            part_row = [
                1.0, # bias
                running_suit,
                comb_controls_diff,
                is_opp_active,
                is_flat,
            ]
            part_samples['nt']['X'].append(part_row)
            part_samples['nt']['y'].append(part_delta)

        # ---------------- SINGLE HAND EVALUATION ----------------
        target_hand_power = (tricks / 13.0) * 20.0
        for hf in [hf1, hf2]:
            trump_len = hf.get(f'len_{strain}', 3.25) if strain != 'nt' else 0.0
            trump_len_surplus = max(0.0, trump_len - 4.0) if strain != 'nt' else 0.0
            side_short = 0.0
            if strain != 'nt':
                for s in SUITS:
                    if s != strain:
                        sl = hf.get(f'len_{s}', 3.25)
                        if sl <= 1.0:
                            side_short += (2.0 - sl)

            s_row = [
                1.0,
                hf['aces'] - 1.0,
                hf['kings'] - 1.0,
                hf['queens'] - 1.0,
                hf['jacks'] - 1.0,
                hf['tens'] - 1.0,
                hf['nines'] - 1.0,
                trump_len_surplus,
                side_short,
                hf['is_4333'],
                hf['is_balanced'],
            ]
            single_samples[strain]['X'].append(s_row)
            single_samples[strain]['y'].append(target_hand_power - hf['hcp'])

    model_output = {
        'model_name': 'BBOChampionshipsJointPartnershipStrainModel',
        'version': '3.0.0-empirical-joint',
        'single_hand_features': single_features,
        'partnership_suit_features': part_suit_features,
        'partnership_nt_features': part_nt_features,
        'strains': {}
    }

    print("\n========================================================")
    print("   TRAINING JOINT PARTNERSHIP STRAIN MODELS PER STRAIN   ")
    print("========================================================")
    for strain in ['nt', 's', 'h', 'd', 'c']:
        X_p = part_samples[strain]['X']
        y_p = part_samples[strain]['y']
        feat_p = part_nt_features if strain == 'nt' else part_suit_features
        weights_p = solve_linear_regression(X_p, y_p)

        residuals_p = [sum(X_p[i][j] * weights_p[j] for j in range(len(weights_p))) - y_p[i] for i in range(len(y_p))]
        mean_res_p = sum(residuals_p) / len(residuals_p)
        mae_p = sum(abs(r) for r in residuals_p) / len(residuals_p)
        w_dict_p = {feat_p[j]: round(weights_p[j], 4) for j in range(len(feat_p))}

        # Single hand weights
        X_s = single_samples[strain]['X']
        y_s = single_samples[strain]['y']
        weights_s = solve_linear_regression(X_s, y_s)
        w_dict_s = {single_features[j]: round(weights_s[j], 4) for j in range(len(single_features))}

        print(f"\n--- STRAIN: {strain.upper()} ({len(y_p)} deals) ---")
        print(f"Partnership MAE: {mae_p:.4f} power points, Mean Residual: {mean_res_p:+.4f}")
        for feat, w in w_dict_p.items():
            print(f"  [PARTNERSHIP] {feat:22}: {w:+.4f}")

        model_output['strains'][strain] = {
            'deals': len(y_p),
            'partnership_weights': w_dict_p,
            'single_hand_weights': w_dict_s,
            'mae': round(mae_p, 4),
        }

    os.makedirs('assets/models', exist_ok=True)
    out_path = 'assets/models/ml_strain_model.json'
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(model_output, f, indent=2)
    print(f"\nSuccessfully exported trained 5-strain models to {out_path}")

if __name__ == '__main__':
    main()
