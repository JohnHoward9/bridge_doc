#!/usr/bin/env python3
"""
ml_lab/train_model.py

Trains a multivariate Ridge Regression Machine Learning model on 10,000 deals
to predict Kaplan-Rubens (KnR) hand valuation from suit-specific continuous features.
Uses 100% standard library Python (zero external dependencies).
"""

import json
import os
import math
from typing import List, Dict, Tuple
from deal_generator import generate_knr_dataset
from feature_extractor import extract_features, FEATURE_NAMES

def solve_linear_system(A: List[List[float]], b: List[float]) -> List[float]:
    """Solves A * x = b via Gaussian elimination with partial pivoting."""
    n = len(b)
    M = [A[i][:] + [b[i]] for i in range(n)]
    for i in range(n):
        # Partial pivoting
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
    """Computes R^2, RMSE, and MAE."""
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

def train_knr_model(num_deals: int = 10000, ridge_lambda: float = 1.0) -> Dict:
    """
    Main training routine:
    1. Generates 10,000 hands with KnR labels.
    2. Splits 80% train / 20% test.
    3. Solves Ridge regression.
    4. Evaluates on test set.
    5. Saves weights to ml_lab/models/knr_ml_model.json.
    """
    print(f"Generating {num_deals} deals with ground-truth KnR evaluations...")
    deals = generate_knr_dataset(num_deals, seed=2026)
    
    # Feature matrix X and target y
    # X has 1.0 prepended for bias (intercept)
    all_X = []
    all_y = []
    
    for d in deals:
        feats = extract_features(d['pbn'])
        all_X.append([1.0] + feats)
        all_y.append(d['knr_total'])
        
    num_train = int(len(deals) * 0.8)
    X_train = all_X[:num_train]
    y_train = all_y[:num_train]
    X_test = all_X[num_train:]
    y_test = all_y[num_train:]
    
    d_dim = len(X_train[0])
    print(f"Training on {len(X_train)} samples across {d_dim - 1} continuous features...")
    
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
                    
    # Add Ridge regularization to diagonal (skip bias at index 0)
    for i in range(1, d_dim):
        A[i][i] += ridge_lambda
        
    print("Solving linear system for optimal continuous feature weights...")
    weights_with_bias = solve_linear_system(A, b)
    
    bias = weights_with_bias[0]
    weights = weights_with_bias[1:]
    
    # Predict on test set
    test_preds = []
    for x in X_test:
        pred = sum(w * val for w, val in zip(weights_with_bias, x))
        test_preds.append(pred)
        
    metrics = compute_metrics(y_test, test_preds)
    print("\n--- Test Set Evaluation Metrics ---")
    print(f"  R^2 Score : {metrics['r2'] * 100:.2f}% (Target: >= 96%)")
    print(f"  RMSE      : {metrics['rmse']:.3f} points")
    print(f"  MAE       : {metrics['mae']:.3f} points")
    print(f"  Mean KnR  : {metrics['mean_target']:.2f}")
    print(f"  Mean Pred : {metrics['mean_predicted']:.2f}")
    
    # Save model artifact
    models_dir = os.path.join(os.path.dirname(__file__), 'models')
    os.makedirs(models_dir, exist_ok=True)
    model_path = os.path.join(models_dir, 'knr_ml_model.json')
    
    model_artifact = {
        'version': '1.0.0-knr-suit-specific',
        'model_type': 'RidgeRegression',
        'training_samples': len(X_train),
        'test_samples': len(X_test),
        'metrics': metrics,
        'feature_names': FEATURE_NAMES,
        'weights': [round(w, 5) for w in weights],
        'bias': round(bias, 5),
    }
    
    with open(model_path, 'w', encoding='utf-8') as f:
        json.dump(model_artifact, f, indent=2)
        
    print(f"\nModel artifact successfully saved to: {model_path}")
    return model_artifact

if __name__ == '__main__':
    train_knr_model(10000)
