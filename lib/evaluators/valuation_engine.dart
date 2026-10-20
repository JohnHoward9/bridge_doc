import '../models/card.dart';
import '../models/hand.dart';

/// Pluggable engine for evaluating bridge hands.
abstract class HandValuationEngine {
  /// Name of this valuation methodology.
  String get name;

  /// Evaluate the primary point count (e.g. HCP or ML strength).
  double evaluatePoints(Hand hand, {Suit? trumpSuit, Suit? partnerSuit, Suit? oppSuit});

  /// Feature extraction vector for ML training/inference (e.g. 52-card one-hot or suit distribution).
  List<double> extractFeatureVector(Hand hand);
}

/// Standard Milton Work High Card Point count (A=4, K=3, Q=2, J=1).
class MiltonWorkValuation extends HandValuationEngine {
  @override
  String get name => 'Milton Work HCP (A=4, K=3, Q=2, J=1)';

  @override
  double evaluatePoints(Hand hand, {Suit? trumpSuit, Suit? partnerSuit, Suit? oppSuit}) {
    return hand.hcp.toDouble();
  }

  @override
  List<double> extractFeatureVector(Hand hand) {
    return [
      hand.hcp.toDouble(),
      hand.spadesLength.toDouble(),
      hand.heartsLength.toDouble(),
      hand.diamondsLength.toDouble(),
      hand.clubsLength.toDouble(),
      hand.suitHcp(Suit.spades).toDouble(),
      hand.suitHcp(Suit.hearts).toDouble(),
      hand.suitHcp(Suit.diamonds).toDouble(),
      hand.suitHcp(Suit.clubs).toDouble(),
      hand.isBalanced ? 1.0 : 0.0,
    ];
  }
}

/// Structured diagnosis of an ML hand upgrade or downgrade.
class MLHandBreakdown {
  final double rawHcp;
  final double intermediateAdjustment;
  final double suitQualityAdjustment;
  final double controlAdjustment;
  final double shapeAdjustment;
  final double partnerMeshAdjustment;
  final double opponentWasteAdjustment;
  final double effectiveHcp;
  final List<String> reasons;

  const MLHandBreakdown({
    required this.rawHcp,
    required this.intermediateAdjustment,
    required this.suitQualityAdjustment,
    required this.controlAdjustment,
    required this.shapeAdjustment,
    required this.partnerMeshAdjustment,
    required this.opponentWasteAdjustment,
    required this.effectiveHcp,
    required this.reasons,
  });

  bool get isUpgraded => effectiveHcp >= rawHcp + 1.0;
  bool get isDowngraded => effectiveHcp <= rawHcp - 1.0;
  double get netDelta => effectiveHcp - rawHcp;

  String get summaryText {
    final prefix = isUpgraded ? '🚀 Upgraded' : (isDowngraded ? '⚠️ Downgraded' : '⚖️ Neutral');
    final sign = netDelta >= 0 ? '+' : '';
    return '$prefix (${rawHcp.toStringAsFixed(0)} → ${effectiveHcp.toStringAsFixed(1)} HCP, $sign${netDelta.toStringAsFixed(1)})';
  }
}

/// Machine Learning hand valuation engine incorporating intermediate honor density (10s and 9s),
/// prime control ratios, 5-card suit quality, fit shortness, and partner/opponent mesh.
class MLHandValuation extends HandValuationEngine {
  final String modelVersion;

  MLHandValuation({this.modelVersion = 'v2.0-bbo-calibrated'});

  @override
  String get name => 'ML Hand Valuation ($modelVersion)';

  @override
  double evaluatePoints(Hand hand, {Suit? trumpSuit, Suit? partnerSuit, Suit? oppSuit}) {
    return evaluateBreakdown(
      hand,
      trumpSuit: trumpSuit,
      partnerSuit: partnerSuit,
      oppSuit: oppSuit,
    ).effectiveHcp;
  }

  MLHandBreakdown evaluateBreakdown(
    Hand hand, {
    Suit? trumpSuit,
    Suit? partnerSuit,
    Suit? oppSuit,
  }) {
    final rawHcp = hand.hcp.toDouble();
    final List<String> reasons = [];

    // 1. Intermediates Adjustment (10s and 9s)
    double intermediateAdj = 0.0;
    int supportedTens = 0;
    int supportedNines = 0;

    for (final suit in Suit.values) {
      final suitCards = hand.cards.where((c) => c.suit == suit).toList();
      final hasTen = suitCards.any((c) => c.rank == Rank.ten);
      final hasNine = suitCards.any((c) => c.rank == Rank.nine);
      final hasEight = suitCards.any((c) => c.rank == Rank.eight);
      final hasHonor = suitCards.any((c) => c.rank.hcp > 0);

      if (hasTen) {
        if (hasHonor) {
          intermediateAdj += 0.35;
          supportedTens++;
        } else if (hasNine || hasEight) {
          intermediateAdj += 0.25;
          supportedTens++;
        } else {
          intermediateAdj += 0.10;
        }
      }

      if (hasNine) {
        if (hasHonor || hasTen) {
          intermediateAdj += 0.20;
          supportedNines++;
        }
      }
    }
    if (intermediateAdj > 1.25) intermediateAdj = 1.25;
    if (intermediateAdj >= 0.3) {
      reasons.add('+${intermediateAdj.toStringAsFixed(1)} Intermediates ($supportedTens tens, $supportedNines nines)');
    }

    // 2. Suit Quality & Running 5-card Suits
    double suitQualityAdj = 0.0;
    for (final suit in Suit.values) {
      final suitCards = hand.cards.where((c) => c.suit == suit).toList();
      if (suitCards.length >= 5) {
        final honorsCount = suitCards.where((c) => c.rank.hcp > 0 || c.rank == Rank.ten).length;
        if (honorsCount >= 4) {
          suitQualityAdj += 1.20; // e.g. AQJT
          reasons.add('+1.2 Solid 5-card ${suit.symbol} suit ($honorsCount honors)');
        } else if (honorsCount == 3) {
          suitQualityAdj += 0.80; // e.g. KQJ or AKJ
          reasons.add('+0.8 Strong 5-card ${suit.symbol} suit (3 honors)');
        } else if (honorsCount == 2 && suitCards.any((c) => c.rank == Rank.ace || c.rank == Rank.king)) {
          suitQualityAdj += 0.50;
          reasons.add('+0.5 Quality 5-card ${suit.symbol} suit');
        }
      }
    }
    if (suitQualityAdj > 1.5) suitQualityAdj = 1.5;

    // 3. Prime Controls (Aces & Kings vs soft Queens & Jacks)
    final aces = hand.cards.where((c) => c.rank == Rank.ace).length;
    final kings = hand.cards.where((c) => c.rank == Rank.king).length;
    final queens = hand.cards.where((c) => c.rank == Rank.queen).length;
    final jacks = hand.cards.where((c) => c.rank == Rank.jack).length;

    double controlAdj = (aces * 0.40) + (kings * 0.10) - (queens * 0.15) - (jacks * 0.25);
    if (controlAdj > 1.0) controlAdj = 1.0;
    if (controlAdj < -1.0) controlAdj = -1.0;
    if (controlAdj >= 0.3) {
      reasons.add('+${controlAdj.toStringAsFixed(1)} Prime controls ($aces Aces, $kings Kings)');
    } else if (controlAdj <= -0.3) {
      reasons.add('${controlAdj.toStringAsFixed(1)} Soft values ($queens Queens, $jacks Jacks)');
    }

    // 4. Shape & Distribution
    double shapeAdj = 0.0;
    if (trumpSuit == null) {
      // Notrump context: penalize completely flat 4333, reward 5332
      final lengths = [hand.spadesLength, hand.heartsLength, hand.diamondsLength, hand.clubsLength]..sort();
      if (lengths[0] == 3 && lengths[1] == 3 && lengths[2] == 3 && lengths[3] == 4) {
        shapeAdj = -0.50;
        reasons.add('-0.5 Flat 4333 distribution');
      } else if (lengths[0] == 2 && lengths[1] == 3 && lengths[2] == 3 && lengths[3] == 5) {
        shapeAdj = 0.25;
      }
    } else {
      // Suit play context: reward shortness
      for (final s in Suit.values) {
        if (s == trumpSuit) continue;
        final len = hand.length(s);
        if (len == 0) {
          shapeAdj += 3.5;
          reasons.add('+3.5 Void in ${s.symbol}');
        } else if (len == 1) {
          shapeAdj += 2.0;
          reasons.add('+2.0 Singleton in ${s.symbol}');
        } else if (len == 2) {
          shapeAdj += 0.5;
        }
      }
      if (shapeAdj > 4.0) shapeAdj = 4.0;
    }

    // 5. Partner Suit Mesh
    double meshAdj = 0.0;
    if (partnerSuit != null) {
      final pCards = hand.cards.where((c) => c.suit == partnerSuit).toList();
      if (pCards.any((c) => c.rank == Rank.ace || c.rank == Rank.king)) {
        meshAdj += 0.75;
        reasons.add('+0.8 Working top honor in partner\'s ${partnerSuit.symbol}');
      } else if (pCards.any((c) => c.rank == Rank.queen)) {
        meshAdj += 0.50;
        reasons.add('+0.5 Working Queen in partner\'s ${partnerSuit.symbol}');
      }
    }
    if (meshAdj > 1.25) meshAdj = 1.25;

    // 6. Opponent Suit Waste
    double wasteAdj = 0.0;
    if (oppSuit != null) {
      final oCards = hand.cards.where((c) => c.suit == oppSuit).toList();
      final hasSoftHonor = oCards.any((c) => c.rank == Rank.queen || c.rank == Rank.jack);
      final hasPrime = oCards.any((c) => c.rank == Rank.ace || c.rank == Rank.king);
      if (hasSoftHonor && !hasPrime && oCards.length <= 3) {
        wasteAdj = -0.75;
        reasons.add('-0.8 Wasted secondary honors in opponent\'s ${oppSuit.symbol}');
      }
    }

    final totalDelta = intermediateAdj + suitQualityAdj + controlAdj + shapeAdj + meshAdj + wasteAdj;
    final effectiveHcp = rawHcp + totalDelta;

    return MLHandBreakdown(
      rawHcp: rawHcp,
      intermediateAdjustment: intermediateAdj,
      suitQualityAdjustment: suitQualityAdj,
      controlAdjustment: controlAdj,
      shapeAdjustment: shapeAdj,
      partnerMeshAdjustment: meshAdj,
      opponentWasteAdjustment: wasteAdj,
      effectiveHcp: effectiveHcp,
      reasons: reasons,
    );
  }

  @override
  List<double> extractFeatureVector(Hand hand) {
    return [
      hand.hcp.toDouble(),
      hand.spadesLength.toDouble(),
      hand.heartsLength.toDouble(),
      hand.diamondsLength.toDouble(),
      hand.clubsLength.toDouble(),
      hand.controls.toDouble(),
      hand.losingTrickCount.toDouble(),
      hand.isBalanced ? 1.0 : 0.0,
    ];
  }
}

typedef MachineLearningValuation = MLHandValuation;
