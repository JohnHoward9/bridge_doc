#!/usr/bin/env python3
"""
ml_lab/test_knr_evaluator.py

Unit tests for Kaplan-Rubens (KnR) 26-step hand evaluator.
Verifies against standard bridge evaluation test cases.
"""

import unittest
from knr_evaluator import evaluate_pbn_hand_knr, evaluate_hand_knr

class TestKnREvaluator(unittest.TestCase):

    def test_north_monster_hand(self):
        # North hand: ♠K3 ♥AKQ974 ♦9 ♣K862
        res = evaluate_pbn_hand_knr("K3.AKQ974.9.K862")
        self.assertEqual(res['suits']['S'], 3.6)
        self.assertEqual(res['suits']['H'], 11.7)
        self.assertEqual(res['suits']['D'], 2.0)
        self.assertEqual(res['suits']['C'], 3.2)
        self.assertEqual(res['adjustment'], -1.0)
        self.assertEqual(res['total'], 19.5)

    def test_yarborough_4333(self):
        # Yarborough: 4333 with no card higher than 8
        res = evaluate_pbn_hand_knr("8762.763.854.762")
        self.assertTrue(res['is_4333'])
        # 0 points in all suits, adjustment: -1.0 + 0.5 = -0.5
        self.assertEqual(res['total'], -0.5)

    def test_shape_differentiation_6421_vs_6331(self):
        # 6-4-2-1 vs 6-3-3-1 with identical honors
        h6421 = evaluate_pbn_hand_knr("AKJ942.Q854.72.6")
        h6331 = evaluate_pbn_hand_knr("AKJ942.Q85.742.6")
        # 6-4-2-1 must evaluate higher than 6-3-3-1
        self.assertGreater(h6421['total'], h6331['total'])
        print(f"6-4-2-1 KnR: {h6421['total']} vs 6-3-3-1 KnR: {h6331['total']} (Diff: {h6421['total'] - h6331['total']:.2f})")

    def test_flat_4333_discount(self):
        # 4-3-3-3 flat hand vs 4-4-3-2 with identical honors
        h4333 = evaluate_pbn_hand_knr("AQ84.K75.Q83.J42")
        h4432 = evaluate_pbn_hand_knr("AQ84.K752.Q83.J4")
        self.assertLess(h4333['total'], h4432['total'])
        print(f"4-3-3-3 KnR: {h4333['total']} vs 4-4-3-2 KnR: {h4432['total']}")

if __name__ == '__main__':
    unittest.main()
