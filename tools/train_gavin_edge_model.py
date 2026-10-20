import json
import math
import random
import os

def variance(ys):
    if not ys:
        return 0.0
    mean = sum(ys) / len(ys)
    return sum((y - mean) ** 2 for y in ys) / len(ys)

class Node:
    def __init__(self, samples, value, prob_making, feature=None, threshold=None, left=None, right=None):
        self.samples = samples
        self.value = value
        self.prob_making = prob_making
        self.feature = feature
        self.threshold = threshold
        self.left = left
        self.right = right

    def is_leaf(self):
        return self.left is None and self.right is None

    def to_dict(self):
        if self.is_leaf():
            return {
                "value": round(self.value, 4),
                "prob_making": round(self.prob_making, 4),
                "samples": self.samples,
            }
        return {
            "feature": self.feature,
            "threshold": round(self.threshold, 2),
            "samples": self.samples,
            "left": self.left.to_dict(),
            "right": self.right.to_dict(),
        }

def build_tree(X, y_res, y_make, features, max_depth, min_samples_split, depth=0):
    n_samples = len(y_res)
    mean_val = sum(y_res) / n_samples
    prob_val = sum(y_make) / n_samples

    if depth >= max_depth or n_samples < min_samples_split:
        return Node(samples=n_samples, value=mean_val, prob_making=prob_val)

    best_gain = 0.0
    best_split = None
    current_var = variance(y_res)

    for f_idx, feat in enumerate(features):
        vals = [x[f_idx] for x in X]
        unique_vals = sorted(set(vals))
        if len(unique_vals) <= 1:
            continue

        # Test midpoints as thresholds
        for i in range(len(unique_vals) - 1):
            threshold = (unique_vals[i] + unique_vals[i + 1]) / 2.0
            left_y = [y_res[k] for k in range(n_samples) if X[k][f_idx] <= threshold]
            right_y = [y_res[k] for k in range(n_samples) if X[k][f_idx] > threshold]

            if len(left_y) < 15 or len(right_y) < 15:
                continue

            var_l = variance(left_y)
            var_r = variance(right_y)
            n_l, n_r = len(left_y), len(right_y)
            gain = current_var - (n_l / n_samples * var_l + n_r / n_samples * var_r)

            if gain > best_gain:
                best_gain = gain
                best_split = (feat, f_idx, threshold)

    if best_gain < 1e-4 or best_split is None:
        return Node(samples=n_samples, value=mean_val, prob_making=prob_val)

    feat_name, f_idx, threshold = best_split
    left_X, left_y_res, left_y_make = [], [], []
    right_X, right_y_res, right_y_make = [], [], []

    for k in range(n_samples):
        if X[k][f_idx] <= threshold:
            left_X.append(X[k])
            left_y_res.append(y_res[k])
            left_y_make.append(y_make[k])
        else:
            right_X.append(X[k])
            right_y_res.append(y_res[k])
            right_y_make.append(y_make[k])

    left_node = build_tree(left_X, left_y_res, left_y_make, features, max_depth, min_samples_split, depth + 1)
    right_node = build_tree(right_X, right_y_res, right_y_make, features, max_depth, min_samples_split, depth + 1)

    return Node(
        samples=n_samples,
        value=mean_val,
        prob_making=prob_val,
        feature=feat_name,
        threshold=threshold,
        left=left_node,
        right=right_node,
    )

def predict(node, x, features):
    if node.is_leaf():
        return node.value, node.prob_making
    f_idx = features.index(node.feature)
    if x[f_idx] <= node.threshold:
        return predict(node.left, x, features)
    else:
        return predict(node.right, x, features)

def main():
    dataset_path = "res/gavin_ml_edge_cases_full.json"
    if not os.path.exists(dataset_path):
        print(f"Error: {dataset_path} not found.")
        return

    with open(dataset_path, "r", encoding="utf-8") as f:
        records = json.load(f)

    # Filter records with verified table result
    valid_records = [r for r in records if r.get("result") is not None and r.get("made") is not None]
    print(f"Loaded {len(valid_records)} verified championship edge-case records.")

    features = [
        "comb_hcp",
        "hcp_diff",
        "max_major_fit",
        "comb_controls",
        "comb_ltc",
        "contract_level",
        "strain_code",
        "is_game_target",
        "is_vulnerable",
    ]

    X = []
    y_res = []
    y_make = []

    for r in valid_records:
        x_row = [
            float(r.get("comb_hcp", 20)),
            float(r.get("hcp_diff", 0)),
            float(r.get("max_major_fit", 7)),
            float(r.get("comb_controls", 4)),
            float(r.get("comb_ltc", 14)),
            float(r.get("contract_level", 3)),
            float(r.get("strain_code", 0)),
            float(r.get("is_game_target", 0)),
            float(r.get("is_vulnerable", 0)),
        ]
        X.append(x_row)
        y_res.append(float(r["result"]))
        y_make.append(float(r["made"]))

    # 80/20 train/test split with deterministic seed
    random.seed(42)
    indices = list(range(len(X)))
    random.shuffle(indices)

    split_idx = int(len(X) * 0.8)
    train_indices = indices[:split_idx]
    val_indices = indices[split_idx:]

    X_train = [X[i] for i in train_indices]
    y_res_train = [y_res[i] for i in train_indices]
    y_make_train = [y_make[i] for i in train_indices]

    X_val = [X[i] for i in val_indices]
    y_res_val = [y_res[i] for i in val_indices]
    y_make_val = [y_make[i] for i in val_indices]

    print(f"Training on {len(X_train)} samples, validating on {len(X_val)} samples.")

    # Train CART tree
    tree = build_tree(X_train, y_res_train, y_make_train, features, max_depth=5, min_samples_split=35)

    # Validation evaluation
    mae_sum = 0.0
    correct_class = 0
    for i in range(len(X_val)):
        pred_val, pred_prob = predict(tree, X_val[i], features)
        mae_sum += abs(pred_val - y_res_val[i])
        actual_made = y_make_val[i] >= 0.5
        pred_made = pred_prob >= 0.5
        if actual_made == pred_made:
            correct_class += 1

    val_mae = mae_sum / len(X_val)
    val_acc = correct_class / len(X_val)

    print(f"Validation MAE (tricks): {val_mae:.4f}")
    print(f"Validation Make/Decline Accuracy: {val_acc * 100:.2f}%")

    model_output = {
        "model_name": "GavinWolpertEdgeCaseDecisionTree",
        "version": "2.0.0",
        "target_metric": "Tricks Taken - Target Tricks",
        "training_samples": len(X_train),
        "validation_samples": len(X_val),
        "validation_mae": round(val_mae, 4),
        "validation_accuracy": round(val_acc, 4),
        "features": features,
        "tree": tree.to_dict(),
    }

    out_file = "assets/models/gavin_ml_edge_model.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(model_output, f, indent=2)

    print(f"Successfully exported production model to: {out_file}")

if __name__ == "__main__":
    main()
