import 'dart:math';

/// Mathematical probability and combinatorics engine for Contract Bridge.
/// Provides exact a priori and hypergeometric conditional expectations
/// with zero hardcoded heuristic offsets.
class BridgeProbabilities {
  /// Memoized Pascal's triangle for combinations nCr.
  static final List<List<double>> _nCr = _initCombinations(53);

  static List<List<double>> _initCombinations(int n) {
    final table = List.generate(n, (i) => List<double>.filled(n, 0.0));
    for (int i = 0; i < n; i++) {
      table[i][0] = 1.0;
      for (int j = 1; j <= i; j++) {
        table[i][j] = table[i - 1][j - 1] + table[i - 1][j];
      }
    }
    return table;
  }

  /// Exact combinations n choose r.
  static double nCr(int n, int r) {
    if (r < 0 || r > n || n < 0 || n >= _nCr.length) return 0.0;
    return _nCr[n][r];
  }

  /// Hypergeometric probability that an unseen 13-card hand holds [partnerLen] cards in a suit,
  /// given that our hand holds [myLen] cards in that suit (leaving 13 - myLen outstanding among 39 unseen cards).
  static double hypergeometricSuitLengthProb(int partnerLen, int myLen) {
    if (partnerLen < 0 || partnerLen > 13) return 0.0;
    final int outstandingInSuit = (13 - myLen).clamp(0, 13);
    final int otherOutstanding = 39 - outstandingInSuit;

    final waysToPickSuit = nCr(outstandingInSuit, partnerLen);
    final waysToPickOther = nCr(otherOutstanding, 13 - partnerLen);
    final totalWays = nCr(39, 13);

    if (totalWays == 0.0) return 0.0;
    return (waysToPickSuit * waysToPickOther) / totalWays;
  }

  /// Unconditioned a priori probability of a 13-card hand having [len] cards in a specific suit.
  static double aPrioriSuitLengthProb(int len) {
    if (len < 0 || len > 13) return 0.0;
    final ways = nCr(13, len) * nCr(39, 13 - len);
    final total = nCr(52, 13);
    return ways / total;
  }

  /// Calculates the exact conditional expected suit length E[L | minLen <= L <= maxLen]
  /// given our hand's known cards [myLen] in that suit.
  ///
  /// Example: If partner shows {6, 7} in hearts, this computes:
  /// (6 * P(6) + 7 * P(7)) / (P(6) + P(7))
  static double conditionalExpectedSuitLength({
    required int minLen,
    required int maxLen,
    int myLen = 0,
  }) {
    final low = minLen.clamp(0, 13);
    final high = maxLen.clamp(low, 13);
    if (low == high) return low.toDouble();

    double weightedSum = 0.0;
    double totalProb = 0.0;

    for (int l = low; l <= high; l++) {
      final p = myLen > 0
          ? hypergeometricSuitLengthProb(l, myLen)
          : aPrioriSuitLengthProb(l);
      weightedSum += l * p;
      totalProb += p;
    }

    if (totalProb <= 0.0) return (low + high) / 2.0;
    return weightedSum / totalProb;
  }

  /// Exact a priori High Card Point (HCP) probability distribution table for 13 cards from 52.
  /// Mean = 10.00 HCP, Variance = 17.06, Std = 4.13.
  static const List<double> aPrioriHcpProbabilities = [
    0.003639, //  0
    0.007884, //  1
    0.013561, //  2
    0.024620, //  3
    0.038453, //  4
    0.051860, //  5
    0.065543, //  6
    0.080277, //  7
    0.088924, //  8
    0.093559, //  9
    0.094052, // 10
    0.089452, // 11
    0.080273, // 12
    0.069155, // 13
    0.056933, // 14
    0.044238, // 15
    0.033107, // 16
    0.023617, // 17
    0.016053, // 18
    0.010362, // 19
    0.006435, // 20
    0.003779, // 21
    0.002102, // 22
    0.001119, // 23
    0.000557, // 24
    0.000260, // 25
    0.000113, // 26
    0.000046, // 27
    0.000017, // 28
    0.000006, // 29
    0.000002, // 30
    0.000001, // 31
    0.000000, // 32
    0.000000, // 33
    0.000000, // 34
    0.000000, // 35
    0.000000, // 36
    0.000000, // 37
  ];

  /// Calculates the exact conditional expected HCP E[HCP | minHcp <= HCP <= maxHcp].
  ///
  /// Example: for 15-17 1NT:
  /// (15*P(15) + 16*P(16) + 17*P(17)) / (P(15) + P(16) + P(17)) = 15.89 HCP.
  static double conditionalExpectedHcp({required int minHcp, required int maxHcp}) {
    final low = minHcp.clamp(0, 37);
    final high = maxHcp.clamp(low, 37);
    if (low == high) return low.toDouble();

    double weightedSum = 0.0;
    double totalProb = 0.0;

    for (int h = low; h <= high; h++) {
      final p = aPrioriHcpProbabilities[h];
      weightedSum += h * p;
      totalProb += p;
    }

    if (totalProb <= 0.0) return (low + high) / 2.0;
    return weightedSum / totalProb;
  }
}
