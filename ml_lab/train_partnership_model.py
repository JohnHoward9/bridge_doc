#!/usr/bin/env python3
"""
ml_lab/train_partnership_model.py

Trains the Partnership ML Valuation Model under Incomplete Information.
Predicts Combined Partnership Power from South's known hand + North's belief state.
Uses 100% standard library Python (zero external dependencies).
"""

import json
import os
import math
from typing import List, Dict
from partnership_deal_generator import generate_partnership_dataset
from partnership_feature_extractor import (
    extract_partnership_features,
    PARTNERSHIP_FEATURE_NAMES
)

def solve_linear_system(A: List[List[float]], b: List[float]) -> List[float]:
    """Solves A * x = b via Gaussian elimination with partial pivoting."""
    n = len(b)
    M = [A[i][:] + [b[i]] for i in range(n)]
    for i in range(n):
        max_row = max(range(i, n), key=lambda r: abs(M[r][i]))
        M[i], M[max_row] = M[max_row], M[i]
        pivot = M[i][i]
        if abs(pivot) < 1e-12:
            continue
        for j in range(i, n + 1):
            M[i][j] /= pivot
        for r in range(n):
            if r != i:
                factor = M[r][i]
                for c in range(i, n + 1):
                    M[r][c] -= factor * M[i][c]
    return [M[i][n] for i in range(n)]

def compute_metrics(y_true: List[float], y_pred: List[float]) -> Dict[str, float]:
    n = len(y_true)
    mean_y = sum(y_true) / n
    ss_tot = sum((y - mean_y) ** 2 for y in y_true)
    ss_res = sum((yt - yp) ** 2 for yt, yp in zip(y_true, y_pred))
    
    r2 = 1.0 - (ss_res / ss_tot) if ss_tot > 0 else 0.0
    rmse = math.sqrt(ss_res / n)
    mae = sum(abs(yt - yp) for yt, yp in zip(y_true, y_pred)) / n
    
    return {
        'r2': round(r2, 4),
        'rmse': round(rmse, 4),
        'mae': round(mae, 4),
        'mean_target': round(mean_y, 4),
        'mean_predicted': round(sum(y_pred) / n, 4),
    }

def train_partnership_model(num_deals: int = 10000, ridge_lambda: float = 1.0):
    print(f"1. Generating {num_deals} deals with ground-truth partnership power and simulated auctions...")
    deals = generate_partnership_dataset(num_deals, seed=2026)
    
    all_X = []
    all_y = []
    naive_y_preds = []
    
    for d in deals:
        feats = extract_partnership_features(d['south_suits'], d['belief'])
        all_X.append([1.0] + feats)
        target = d['ground_truth']['total_partnership_power']
        all_y.append(target)
        
        # Naive baseline: South KnR + North Expected HCP (approx KnR)
        naive_pred = feats[0] + d['belief']['north_exp_hcp']
        naive_y_preds.append(naive_pred)
        
    num_train = int(len(deals) * 0.8)
    X_train = all_X[:num_train]
    y_train = all_y[:num_train]
    X_test = all_X[num_train:]
    y_test = all_y[num_train:]
    naive_test = naive_y_preds[num_train:]
    
    d_dim = len(X_train[0])
    print(f"2. Training Ridge Regression on {len(X_train)} samples across {d_dim - 1} features...")
    
    # Compute A = X^T * X + lambda * I
    A = [[0.0] * d_dim for _ in range(d_dim)]
    b = [0.0] * d_dim
    
    for row_idx in range(len(X_train)):
        x = X_train[row_idx]
        y = y_train[row_idx]
        for i in range(d_dim):
            xi = x[i]
            b[i] += xi * y
            for j in range(i, d_dim):
                val = xi * x[j]
                A[i][j] += val
                if i != j:
                    A[j][i] += val
                    
    for i in range(d_dim):
        A[i][i] += ridge_lambda
        
    print("3. Solving linear system...")
    weights = solve_linear_system(A, b)
    
    # Evaluate ML Model
    y_pred_test = []
    for x in X_test:
        pred = sum(w * xi for w, xi in zip(weights, x))
        y_pred_test.append(pred)
        
    ml_metrics = compute_metrics(y_test, y_pred_test)
    naive_metrics = compute_metrics(y_test, naive_test)
    
    print("\n--- RESULTS ON 2,000 HELD-OUT TEST DEALS ---")
    print(f"Naive Baseline (KnR_South + E[HCP_North]): R^2 = {naive_metrics['r2']*100:.2f}%, RMSE = {naive_metrics['rmse']:.3f}, MAE = {naive_metrics['mae']:.3f}")
    print(f"ML Partnership Model (with Cross-Features):  R^2 = {ml_metrics['r2']*100:.2f}%, RMSE = {ml_metrics['rmse']:.3f}, MAE = {ml_metrics['mae']:.3f}")
    improvement = ((naive_metrics['mae'] - ml_metrics['mae']) / naive_metrics['mae']) * 100.0
    print(f"MAE Error Reduction: {improvement:.1f}%\n")
    
    # Highlight Key Feature Weights
    feature_weights = {'intercept': weights[0]}
    for name, w in zip(PARTNERSHIP_FEATURE_NAMES, weights[1:]):
        feature_weights[name] = round(w, 4)
        
    print("Key Learned Cross-Feature Weights:")
    for key in ['fit_bonus_synergy', 'wasted_partner_hcp_in_shortage', 'working_partner_hcp_in_length', 'my_honors_in_partner_suit']:
        if key in feature_weights:
            print(f"  • {key:32}: {feature_weights[key]:+.4f}")
            
    # Save model
    os.makedirs('ml_lab/models', exist_ok=True)
    model_path = 'ml_lab/models/partnership_ml_model.json'
    with open(model_path, 'w') as f:
        json.dump({
            'model_type': 'ridge_regression',
            'd_dim': d_dim,
            'intercept': round(weights[0], 4),
            'features': feature_weights,
            'weights_vector': [round(w, 5) for w in weights],
            'metrics': ml_metrics,
        }, f, indent=2)
    print(f"\nModel saved to {model_path}")
    return weights

if __name__ == '__main__':
    train_partnership_model(10000)
