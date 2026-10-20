#!/usr/bin/env python3
"""
train_edge_case_ml.py
Trains a decision tree model on isolated Gavin Wolpert edge cases
(borderline game invitations 22-25 HCP and marginal slams 29-32 HCP).

Target metric:
    Result = Tricks Taken - Target Tricks
    (e.g., 4H making 8 tricks -> 8 - 10 = -2; making 10 tricks -> 0; making 11 tricks -> +1)

Exports a pure JSON model that can be evaluated in Dart with zero external runtime dependencies.
"""

import json
import math
import os
import random

class DecisionTreeNode:
    def __init__(self, feature=None, threshold=None, left=None, right=None, value=None, samples=0, prob=None):
        self.feature = feature
        self.threshold = threshold
        self.left = left
        self.right = right
        self.value = value       # Expected Result (regression)
        self.prob = prob         # Probability of Making (classification Result >= 0)
        self.samples = samples

    def to_dict(self):
        if self.feature is None:
            return {
                "value": round(self.value, 4),
                "prob_making": round(self.prob, 4),
                "samples": self.samples
            }
        return {
            "feature": self.feature,
            "threshold": round(self.threshold, 4),
            "samples": self.samples,
            "left": self.left.to_dict(),
            "right": self.right.to_dict()
        }

def build_tree(rows, features, max_depth=4, min_samples_split=5, depth=0):
    n = len(rows)
    if n == 0:
        return DecisionTreeNode(value=0.0, prob=0.5, samples=0)

    # Compute node statistics
    results = [r["result"] for r in rows]
    mean_val = sum(results) / n
    prob_making = sum(1 for r in results if r >= 0) / n

    if depth >= max_depth or n < min_samples_split:
        return DecisionTreeNode(value=mean_val, prob=prob_making, samples=n)

    # Calculate variance / MSE
    curr_mse = sum((r - mean_val) ** 2 for r in results) / n
    if curr_mse == 0:
        return DecisionTreeNode(value=mean_val, prob=prob_making, samples=n)

    best_gain = -1
    best_split = None

    for feat in features:
        # Get unique values for threshold candidates
        vals = sorted(list(set(r[feat] for r in rows)))
        for i in range(len(vals) - 1):
            thresh = (vals[i] + vals[i + 1]) / 2.0
            left = [r for r in rows if r[feat] <= thresh]
            right = [r for r in rows if r[feat] > thresh]
            if len(left) == 0 or len(right) == 0:
                continue

            # Variance reduction
            left_res = [r["result"] for r in left]
            right_res = [r["result"] for r in right]
            mse_left = sum((r - sum(left_res) / len(left)) ** 2 for r in left_res) / len(left)
            mse_right = sum((r - sum(right_res) / len(right)) ** 2 for r in right_res) / len(right)
            new_mse = (len(left) * mse_left + len(right) * mse_right) / n
            gain = curr_mse - new_mse

            if gain > best_gain:
                best_gain = gain
                best_split = (feat, thresh, left, right)

    if best_split is None or best_gain <= 0.001:
        return DecisionTreeNode(value=mean_val, prob=prob_making, samples=n)

    feat, thresh, left_rows, right_rows = best_split
    left_node = build_tree(left_rows, features, max_depth, min_samples_split, depth + 1)
    right_node = build_tree(right_rows, features, max_depth, min_samples_split, depth + 1)

    return DecisionTreeNode(
        feature=feat,
        threshold=thresh,
        left=left_node,
        right=right_node,
        value=mean_val,
        prob=prob_making,
        samples=n
    )

def main():
    dataset_path = "res/gavin_ml_edge_cases.json"
    if not os.path.exists(dataset_path):
        print(f"Error: {dataset_path} not found.")
        return

    with open(dataset_path, "r") as f:
        raw_data = json.load(f)

    rows = []
    for d in raw_data:
        tricks = d.get("tricks_made")
        if tricks is None:
            continue
        contract = d.get("simulated_contract", "Pass")
        if contract == "Pass":
            continue

        level = int(contract[0]) if contract[0].isdigit() else 1
        strain = contract[1:].lower()
        target = level + 6
        result = tricks - target

        strain_code = 0 # NT
        if "s" in strain: strain_code = 1
        elif "h" in strain: strain_code = 2
        elif "d" in strain: strain_code = 3
        elif "c" in strain: strain_code = 4

        comb_hcp = d.get("comb_hcp", 20)
        hcp_n = d.get("hcp_n", 10)
        hcp_s = d.get("hcp_s", 10)
        hcp_diff = abs(hcp_n - hcp_s)
        spade_fit = d.get("spade_fit", 4)
        heart_fit = d.get("heart_fit", 4)
        max_major_fit = max(spade_fit, heart_fit)

        is_game_target = 1 if (
            (level >= 4 and strain_code in [1, 2]) or
            (level >= 3 and strain_code == 0) or
            (level >= 5 and strain_code in [3, 4])
        ) else 0

        rows.append({
            "comb_hcp": comb_hcp,
            "hcp_diff": hcp_diff,
            "spade_fit": spade_fit,
            "heart_fit": heart_fit,
            "max_major_fit": max_major_fit,
            "contract_level": level,
            "strain_code": strain_code,
            "target_tricks": target,
            "tricks_made": tricks,
            "result": result,
            "is_game_target": is_game_target
        })

    print(f"Loaded {len(rows)} valid edge-case records for ML training.")

    features = [
        "comb_hcp",
        "hcp_diff",
        "max_major_fit",
        "contract_level",
        "strain_code",
        "is_game_target"
    ]

    # Split train/validation (80/20)
    random.seed(42)
    random.shuffle(rows)
    split_idx = int(0.8 * len(rows))
    train_rows = rows[:split_idx]
    val_rows = rows[split_idx:]

    print(f"Training set: {len(train_rows)} | Validation set: {len(val_rows)}")

    # Train Decision Tree
    tree_root = build_tree(train_rows, features, max_depth=3, min_samples_split=6)

    # Evaluate on validation set
    def predict(node, row):
        if node.feature is None:
            return node.value, node.prob
        if row[node.feature] <= node.threshold:
            return predict(node.left, row)
        else:
            return predict(node.right, row)

    val_errors = []
    val_correct_classification = 0
    for r in val_rows:
        pred_val, pred_prob = predict(tree_root, r)
        val_errors.append(abs(r["result"] - pred_val))
        pred_make = 1 if pred_prob >= 0.5 else 0
        actual_make = 1 if r["result"] >= 0 else 0
        if pred_make == actual_make:
            val_correct_classification += 1

    mae = sum(val_errors) / len(val_errors) if val_errors else 0.0
    acc = val_correct_classification / len(val_rows) if val_rows else 0.0

    print(f"Validation MAE (Tricks - Target): {mae:.3f} tricks")
    print(f"Validation Making Accuracy:       {acc * 100:.1f}%")

    # Export model to assets/models/
    os.makedirs("assets/models", exist_ok=True)
    out_model = {
        "model_name": "GavinWolpertEdgeCaseDecisionTree",
        "version": "1.0.0",
        "target_metric": "Tricks Taken - Target Tricks",
        "training_samples": len(rows),
        "validation_mae": round(mae, 4),
        "validation_accuracy": round(acc, 4),
        "features": features,
        "tree": tree_root.to_dict()
    }

    out_path = "assets/models/gavin_ml_edge_model.json"
    with open(out_path, "w") as f:
        json.dump(out_model, f, indent=2)

    print(f"Successfully exported ML edge-case model to: {out_path}")

if __name__ == "__main__":
    main()
