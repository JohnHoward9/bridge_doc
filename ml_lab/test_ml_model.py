#!/usr/bin/env python3
"""
ml_lab/test_ml_model.py

Evaluates the trained continuous KnR Machine Learning model against
crucial bridge benchmarks and ground-truth KnR scores.
"""

import os
import json
import unittest
from feature_extractor import extract_features, FEATURE_NAMES
from knr_evaluator import evaluate_pbn_hand_knr

class TestTrainedMLModel(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        model_path = os.path.join(os.path.dirname(__file__), 'models', 'knr_ml_model.json')
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model not found at {model_path}. Run train_model.py first.")
        with open(model_path, 'r', encoding='utf-8') as f:
            cls.model = json.load(f)
        cls.bias = cls.model['bias']
        cls.weights = cls.model['weights']

    def predict(self, pbn_hand: str, partner_rules: dict = None) -> float:
        feats = extract_features(pbn_hand, partner_rules)
        pred = self.bias + sum(w * f for w, f in zip(self.weights, feats))
        return round(pred, 2)

    def test_north_powerhouse_hand(self):
        """
        North holding ♠K3 ♥AKQ974 ♦9 ♣K862 (15 raw HCP, 2-6-1-4 distribution).
        Ground truth KnR is 19.5.
        The ML model must predict ~19.5, and NEVER downgrade below 15!
        """
        hand = "K3.AKQ974.9.K862"
        pred = self.predict(hand)
        knr = evaluate_pbn_hand_knr(hand)['total']
        
        print(f"\n[North Powerhouse Hand]")
        print(f"  Raw HCP       : 15.0")
        print(f"  KnR True Score: {knr}")
        print(f"  ML Predicted  : {pred}")
        
        self.assertAlmostEqual(pred, knr, delta=0.6,
            msg=f"ML prediction {pred} should match KnR {knr} within 0.6 points")
        self.assertGreater(pred, 18.5,
            msg=f"North hand has massive playing strength and must evaluate > 18.5, not downgraded to 14.7!")

    def test_shape_differentiation_continuous(self):
        """
        Tests that 6-4-2-1 evaluates higher than 6-3-3-1 through continuous
        suit lengths without any hardcoded shape_ flags.
        """
        h6421 = "AKJ942.Q854.72.6"
        h6331 = "AKJ942.Q85.742.6"
        
        pred_6421 = self.predict(h6421)
        pred_6331 = self.predict(h6331)
        
        knr_6421 = evaluate_pbn_hand_knr(h6421)['total']
        knr_6331 = evaluate_pbn_hand_knr(h6331)['total']
        
        print(f"\n[Continuous Shape Differentiation]")
        print(f"  6-4-2-1 -> KnR: {knr_6421}, ML: {pred_6421}")
        print(f"  6-3-3-1 -> KnR: {knr_6331}, ML: {pred_6331}")
        print(f"  Delta   -> KnR: {knr_6421 - knr_6331:.2f}, ML: {pred_6421 - pred_6331:.2f}")
        
        self.assertGreater(pred_6421, pred_6331,
            msg="6-4-2-1 must evaluate higher than 6-3-3-1 from continuous lengths")

    def test_flat_4333_discount_continuous(self):
        """
        Tests that 4-3-3-3 evaluates lower than 4-4-3-2 with identical honors.
        """
        h4333 = "AQ84.K75.Q83.J42"
        h4432 = "AQ84.K752.Q83.J4"
        
        pred_4333 = self.predict(h4333)
        pred_4432 = self.predict(h4432)
        
        print(f"\n[Flat 4-3-3-3 Discount]")
        print(f"  4-3-3-3 -> ML: {pred_4333}")
        print(f"  4-4-3-2 -> ML: {pred_4432}")
        
        self.assertLess(pred_4333, pred_4432,
            msg="4-3-3-3 must evaluate lower than 4-4-3-2")

    def test_partner_fit_progression(self):
        """
        Tests that as partner shows length in Hearts via bidding rules,
        the continuous combined length and fit bonus dynamically increases hand valuation.
        """
        hand = "K3.AKQ974.9.K862"
        # 1. Unconstrained prior (E[L_H] = 3.25)
        pred_prior = self.predict(hand)
        # 2. Partner shows 5+ hearts (rule shows 5-8 length -> E[L_H] = 5.38)
        pred_fit = self.predict(hand, partner_rules={'H': (5, 8)})
        
        print(f"\n[Partner Rule Fit Progression]")
        print(f"  North Value (Prior E[L_H]=3.25): {pred_prior}")
        print(f"  North Value (Fit   E[L_H]=5.38): {pred_fit}")
        print(f"  Fit Expansion Delta: +{pred_fit - pred_prior:.2f} points")
        
        self.assertGreater(pred_fit, pred_prior,
            msg="Confirmed fit with partner must increase hand valuation")

if __name__ == '__main__':
    unittest.main()
