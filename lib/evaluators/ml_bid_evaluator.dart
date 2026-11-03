import 'dart:convert';
import 'dart:io';
import '../models/hand.dart';
import '../models/card.dart';
import '../models/seat_belief_state.dart';
import 'valuation_engine.dart';

/// Prediction result from the Gavin Wolpert ML Edge-Case Model.
class MLEdgeCasePrediction {
  /// Expected Result = Tricks Taken - Target Tricks (e.g. +0.37 or -0.69).
  final double expectedResult;

  /// Probability of making the contract (Result >= 0).
  final double probMaking;

  /// Number of championship training samples supporting this node.
  final int samples;

  const MLEdgeCasePrediction({
    required this.expectedResult,
    required this.probMaking,
    required this.samples,
  });

  /// True if expected tricks >= target or probability of making >= 50%.
  bool get shouldAcceptInvite => probMaking >= 0.50 || expectedResult >= 0.0;

  @override
  String toString() =>
      'MLEdgeCasePrediction(expectedResult: ${expectedResult.toStringAsFixed(2)}, '
      'probMaking: ${(probMaking * 100).toStringAsFixed(1)}%, samples: $samples)';
}

typedef MLBidEvaluator = MLEdgeCaseEvaluator;

/// Evaluates borderline edge cases (e.g. 22-25 HCP game invitations, 29-32 HCP marginal slams)
/// using the Machine Learning decision tree trained on 2025 BBO Championship deals.
class MLEdgeCaseEvaluator {
  final Map<String, dynamic> modelData;

  MLEdgeCaseEvaluator({Map<String, dynamic>? model})
      : modelData = model ?? _defaultModel;

  factory MLEdgeCaseEvaluator.fromJsonString(String jsonStr) {
    return MLEdgeCaseEvaluator(model: jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  /// Evaluates an edge-case contract using partnership features.
  MLEdgeCasePrediction evaluateEdgeCase({
    required double combHcp,
    required double hcpDiff,
    required double maxMajorFit,
    required int contractLevel,
    required int strainCode, // 0=NT, 1=S, 2=H, 3=D, 4=C
    required bool isGameTarget,
    double secondaryFit = 7.0,
    double hasDoubleFit = 0.0,
    double isOpponentActive = 0.0,
    double combControls = 4.0,
    double combLtc = 14.0,
    bool isVulnerable = false,
  }) {
    final features = <String, double>{
      'comb_hcp': combHcp,
      'hcp_diff': hcpDiff,
      'max_major_fit': maxMajorFit,
      'secondary_fit': secondaryFit,
      'has_double_fit': hasDoubleFit,
      'is_opp_active': isOpponentActive,
      'comb_controls': combControls,
      'comb_ltc': combLtc,
      'contract_level': contractLevel.toDouble(),
      'strain_code': strainCode.toDouble(),
      'is_game_target': isGameTarget ? 1.0 : 0.0,
      'is_vulnerable': isVulnerable ? 1.0 : 0.0,
    };

    final tree = modelData['tree'] as Map<String, dynamic>;
    return _traverse(tree, features);
  }

  /// Convenience evaluation directly from North and South hands.
  MLEdgeCasePrediction evaluateHands({
    required Hand north,
    required Hand south,
    required int contractLevel,
    required String strain, // 'nt', 's', 'h', 'd', 'c'
    bool isVulnerable = false,
    bool isOpponentActive = false,
  }) {
    final s = strain.toLowerCase();
    int code = 0;
    if (s.contains('s')) {
      code = 1;
    } else if (s.contains('h')) {
      code = 2;
    } else if (s.contains('d')) {
      code = 3;
    } else if (s.contains('c')) {
      code = 4;
    }

    final combHcp = (north.hcp + south.hcp).toDouble();
    final hcpDiff = (north.hcp - south.hcp).abs().toDouble();
    final fits = [
      (north.length(Suit.spades) + south.length(Suit.spades)).toDouble(),
      (north.length(Suit.hearts) + south.length(Suit.hearts)).toDouble(),
      (north.length(Suit.diamonds) + south.length(Suit.diamonds)).toDouble(),
      (north.length(Suit.clubs) + south.length(Suit.clubs)).toDouble(),
    ];
    final double maxFit;
    final double secFit;
    if (code >= 1 && code <= 4) {
      maxFit = fits[code - 1];
      final outside = [for (int i = 0; i < 4; i++) if (i != code - 1) fits[i]];
      secFit = outside.reduce((a, b) => a > b ? a : b);
    } else {
      final sortedFits = List<double>.from(fits)..sort((a, b) => b.compareTo(a));
      maxFit = sortedFits[0];
      secFit = sortedFits[1];
    }
    final hasDoubleFit = (maxFit >= 8.0 && secFit >= 8.0) ? 1.0 : 0.0;

    final isGame = (contractLevel >= 4 && (code == 1 || code == 2)) ||
        (contractLevel >= 3 && code == 0) ||
        (contractLevel >= 5 && (code == 3 || code == 4));

    final combControls = (north.controls + south.controls).toDouble();
    final combLtc = (north.losingTrickCount + south.losingTrickCount).toDouble();

    return evaluateEdgeCase(
      combHcp: combHcp,
      hcpDiff: hcpDiff,
      maxMajorFit: maxFit,
      secondaryFit: secFit,
      hasDoubleFit: hasDoubleFit,
      isOpponentActive: isOpponentActive ? 1.0 : 0.0,
      contractLevel: contractLevel,
      strainCode: code,
      isGameTarget: isGame,
      combControls: combControls,
      combLtc: combLtc,
      isVulnerable: isVulnerable,
    );
  }

  /// Evaluates an edge case using [myHand] and the accumulated [partnerBelief]
  /// derived from partner's bids and rules in the auction.
  /// Passes the full 4-suit fit vector and double-fit features directly into the trained ML decision tree.
  /// Incorporates [isOpponentActive] to reflect bad-split probabilities and lead pressures.
  MLEdgeCasePrediction evaluateWithBelief({
    required Hand myHand,
    required SeatBeliefState partnerBelief,
    required int contractLevel,
    required String strain,
    bool isVulnerable = false,
    bool isOpponentActive = false,
    String? candidateRule,
  }) {
    final s = strain.toLowerCase();
    int code = 0;
    Suit? trumpSuit;
    if (s.contains('s')) {
      code = 1;
      trumpSuit = Suit.spades;
    } else if (s.contains('h')) {
      code = 2;
      trumpSuit = Suit.hearts;
    } else if (s.contains('d')) {
      code = 3;
      trumpSuit = Suit.diamonds;
    } else if (s.contains('c')) {
      code = 4;
      trumpSuit = Suit.clubs;
    }

    final partnerMeanHcp = (partnerBelief.minHcp + (partnerBelief.maxHcp < 37 ? partnerBelief.maxHcp : partnerBelief.minHcp + 4)) / 2.0;
    final combHcp = myHand.hcp + partnerMeanHcp;
    final hcpDiff = (myHand.hcp - partnerMeanHcp).abs();

    final primaryFit = partnerBelief.primaryFit(myHand, trumpSuit);
    final secondaryFit = partnerBelief.secondaryFit(myHand, trumpSuit);
    final hasDoubleFit = (primaryFit >= 8 && secondaryFit >= 8) ? 1.0 : 0.0;

    final isGame = (contractLevel >= 4 && (code == 1 || code == 2)) ||
        (contractLevel >= 3 && code == 0) ||
        (contractLevel >= 5 && (code == 3 || code == 4));

    return evaluateEdgeCase(
      combHcp: combHcp,
      hcpDiff: hcpDiff,
      maxMajorFit: primaryFit.toDouble(),
      secondaryFit: secondaryFit.toDouble(),
      hasDoubleFit: hasDoubleFit,
      isOpponentActive: isOpponentActive ? 1.0 : 0.0,
      contractLevel: contractLevel,
      strainCode: code,
      isGameTarget: isGame,
      isVulnerable: isVulnerable,
    );
  }

  MLEdgeCasePrediction _traverse(
      Map<String, dynamic> node, Map<String, double> features) {
    if (!node.containsKey('feature') || node['feature'] == null) {
      return MLEdgeCasePrediction(
        expectedResult: (node['value'] as num).toDouble(),
        probMaking: (node['prob_making'] as num).toDouble(),
        samples: (node['samples'] as num).toInt(),
      );
    }

    final featureName = node['feature'] as String;
    final threshold = (node['threshold'] as num).toDouble();
    final val = features[featureName] ?? 0.0;

    if (val <= threshold) {
      return _traverse(node['left'] as Map<String, dynamic>, features);
    } else {
      return _traverse(node['right'] as Map<String, dynamic>, features);
    }
  }

  static Map<String, dynamic> _loadDefaultModel() {
    try {
      final file = File('assets/models/gavin_ml_edge_model.json');
      if (file.existsSync()) {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return _embeddedModel;
  }

  static final Map<String, dynamic> _defaultModel = _loadDefaultModel();

  static final Map<String, dynamic> _embeddedModel = {
    "model_name": "GavinWolpertEdgeCaseDecisionTree",
    "version": "1.0.0",
    "target_metric": "Tricks Taken - Target Tricks",
    "tree": {
      "feature": "contract_level",
      "threshold": 2.5,
      "samples": 116,
      "left": {
        "feature": "hcp_diff",
        "threshold": 1.5,
        "samples": 44,
        "left": {
          "value": -0.25,
          "prob_making": 0.75,
          "samples": 4
        },
        "right": {
          "feature": "strain_code",
          "threshold": 1.5,
          "samples": 40,
          "left": {
            "value": 1.0625,
            "prob_making": 0.9062,
            "samples": 32
          },
          "right": {
            "value": 2.5,
            "prob_making": 1.0,
            "samples": 8
          }
        }
      },
      "right": {
        "feature": "comb_hcp",
        "threshold": 27.0,
        "samples": 72,
        "left": {
          "feature": "max_major_fit",
          "threshold": 7.5,
          "samples": 62,
          "left": {
            "value": -0.6857,
            "prob_making": 0.3429,
            "samples": 35
          },
          "right": {
            "value": 0.3704,
            "prob_making": 0.8148,
            "samples": 27
          }
        },
        "right": {
          "feature": "contract_level",
          "threshold": 3.5,
          "samples": 10,
          "left": {
            "value": 3.3333,
            "prob_making": 1.0,
            "samples": 3
          },
          "right": {
            "value": 0.2857,
            "prob_making": 0.8571,
            "samples": 7
          }
        }
      }
    }
  };
}

/// Vulnerability of the partnership vs opponents.
enum Vulnerability {
  none('None Vul', isWeVul: false, isTheyVul: false),
  both('Both Vul', isWeVul: true, isTheyVul: true),
  favorable('Favorable (White vs Red)', isWeVul: false, isTheyVul: true),
  unfavorable('Unfavorable (Red vs White)', isWeVul: true, isTheyVul: false);

  final String label;
  final bool isWeVul;
  final bool isTheyVul;
  const Vulnerability(this.label, {required this.isWeVul, required this.isTheyVul});
}

/// Bidding seat position (1st, 2nd, 3rd, 4th).
enum SeatPosition {
  first('1st Seat'),
  second('2nd Seat'),
  third('3rd Seat'),
  fourth('4th Seat');

  final String label;
  const SeatPosition(this.label);
}

/// Recommendation for game vs partscore.
class GameDecision {
  final bool shouldBidGame;
  final double probMaking;
  final double expectedTricks;
  final double combinedMpi;
  final String targetContract;
  final String reason;

  const GameDecision({
    required this.shouldBidGame,
    required this.probMaking,
    required this.expectedTricks,
    required this.combinedMpi,
    required this.targetContract,
    required this.reason,
  });

  @override
  String toString() =>
      'GameDecision(bidGame: $shouldBidGame, contract: $targetContract, '
      'prob: ${(probMaking * 100).toStringAsFixed(1)}%, expTricks: ${expectedTricks.toStringAsFixed(2)}, '
      'mpi: ${combinedMpi.toStringAsFixed(1)})';
}

/// Slam recommendation levels.
enum SlamRecommendation {
  pass('Sign off in Game', 0),
  invite('Slam Invitation / Quantitative Try', 1),
  smallSlam('Bid Small Slam (Level 6)', 2),
  grandSlam('Bid Grand Slam (Level 7)', 3);

  final String label;
  final int level;
  const SlamRecommendation(this.label, this.level);
}

/// Recommendation for slam exploration or sign-off.
class SlamDecision {
  final SlamRecommendation recommendation;
  final double probMaking;
  final double expectedTricks;
  final double combinedMpi;
  final int controlsCount;
  final String reason;

  const SlamDecision({
    required this.recommendation,
    required this.probMaking,
    required this.expectedTricks,
    required this.combinedMpi,
    required this.controlsCount,
    required this.reason,
  });

  bool get isSlamTarget =>
      recommendation == SlamRecommendation.smallSlam ||
      recommendation == SlamRecommendation.grandSlam;

  @override
  String toString() =>
      'SlamDecision(${recommendation.label}, prob: ${(probMaking * 100).toStringAsFixed(1)}%, '
      'expTricks: ${expectedTricks.toStringAsFixed(2)}, mpi: ${combinedMpi.toStringAsFixed(1)})';
}

/// Decision comparing candidate strains (e.g. 3NT vs 4M, 3NT vs 5m).
class StrainDecision {
  final String bestStrain;
  final Map<String, double> strainRatings; // Expected surplus tricks above target
  final Map<String, double> winProbabilities;
  final String reason;

  const StrainDecision({
    required this.bestStrain,
    required this.strainRatings,
    required this.winProbabilities,
    required this.reason,
  });

  @override
  String toString() =>
      'StrainDecision(best: $bestStrain, ratings: $strainRatings, reason: $reason)';
}

/// Decision on whether to open a preemptive bid.
class PreemptDecision {
  final bool shouldPreempt;
  final double effectiveMpi;
  final int allowedUndertricks;
  final double expectedTricks;
  final String recommendedCall;
  final String reason;

  const PreemptDecision({
    required this.shouldPreempt,
    required this.effectiveMpi,
    required this.allowedUndertricks,
    required this.expectedTricks,
    required this.recommendedCall,
    required this.reason,
  });

  @override
  String toString() =>
      'PreemptDecision(preempt: $shouldPreempt, call: $recommendedCall, '
      'mpi: ${effectiveMpi.toStringAsFixed(1)}, allowedDown: $allowedUndertricks, reason: $reason)';
}

/// Category of defensive competitive action.
enum DefensiveAction {
  pass('Pass'),
  overcall('Simple Overcall'),
  takeoutDouble('Takeout Double'),
  powerDouble('Power Double (17+ any shape)'),
  unusual2nt('Unusual 2NT (Two-suiter)'),
  michaels('Michaels Cuebid (Major + Other)');

  final String label;
  const DefensiveAction(this.label);
}

/// Decision on defensive action over opponent's bid.
class DefensiveDecision {
  final DefensiveAction action;
  final String recommendedCall;
  final double effectiveMpi;
  final String reason;

  const DefensiveDecision({
    required this.action,
    required this.recommendedCall,
    required this.effectiveMpi,
    required this.reason,
  });

  @override
  String toString() =>
      'DefensiveDecision(${action.label}, call: $recommendedCall, '
      'mpi: ${effectiveMpi.toStringAsFixed(1)}, reason: $reason)';
}

/// Unified Machine Learning Power Engine (replacing static KNR heuristics)
/// mapping hand and partnership strength to a canonical 0-37 scale (MPI: Machine Learning Power Index).
class MLPowerEngine {
  static final MLEdgeCaseEvaluator _mlEvaluator = MLEdgeCaseEvaluator();

  /// Evaluates single-hand power on a calibrated 0-37 scale, factoring in intermediates,
  /// prime controls, suit quality, shape, seat position, and vulnerability.
  static double evaluateSingleHandMpi(
    Hand hand, {
    SeatPosition seat = SeatPosition.first,
    Vulnerability vuln = Vulnerability.none,
  }) {
    final breakdown = MLHandValuation().evaluateBreakdown(hand);
    double mpi = breakdown.effectiveHcp;

    // Tactical adjustments for seat & vulnerability:
    if (seat == SeatPosition.third) {
      if (vuln == Vulnerability.favorable) {
        mpi += 1.0; // Aggressive tactical power in 3rd seat non-vul vs vul
      } else if (vuln == Vulnerability.unfavorable) {
        mpi -= 0.5; // Caution when vulnerable against non-vulnerable
      }
    } else if (seat == SeatPosition.second && vuln == Vulnerability.unfavorable) {
      mpi -= 0.5; // 2nd seat red-vs-white is most dangerous seat
    }

    return double.parse(mpi.clamp(0.0, 37.0).toStringAsFixed(1));
  }

  /// Evaluates partnership combined power on a 0-37+ scale for [strain].
  static double evaluateCombinedMpi(
    Hand north,
    Hand south, {
    String strain = 'nt',
    Vulnerability vuln = Vulnerability.none,
  }) {
    final mpiN = evaluateSingleHandMpi(north, vuln: vuln);
    final mpiS = evaluateSingleHandMpi(south, vuln: vuln);
    double combined = mpiN + mpiS;

    final s = strain.toLowerCase();
    Suit? trumpSuit;
    if (s.contains('s')) trumpSuit = Suit.spades;
    else if (s.contains('h')) trumpSuit = Suit.hearts;
    else if (s.contains('d')) trumpSuit = Suit.diamonds;
    else if (s.contains('c')) trumpSuit = Suit.clubs;

    if (trumpSuit != null) {
      final fit = north.length(trumpSuit) + south.length(trumpSuit);
      if (fit >= 10) {
        combined += 3.5;
      } else if (fit == 9) {
        combined += 2.0;
      } else if (fit == 8) {
        combined += 1.0;
      } else if (fit < 7) {
        combined -= 1.5;
      }

      // Shortness ruffing synergy when trump fit exists
      if (fit >= 8) {
        for (final suit in Suit.values) {
          if (suit == trumpSuit) continue;
          final nLen = north.length(suit);
          final sLen = south.length(suit);
          if (nLen == 0 || sLen == 0) combined += 2.0;
          else if (nLen == 1 || sLen == 1) combined += 1.0;
        }
      }
    } else {
      // Notrump: reward stopped suits and penalize unstopped suits
      int stoppedSuits = 0;
      for (final suit in Suit.values) {
        final nCards = north.cardsInSuit(suit);
        final sCards = south.cardsInSuit(suit);
        final hasAce = nCards.any((c) => c.rank == Rank.ace) || sCards.any((c) => c.rank == Rank.ace);
        final hasKing = (nCards.any((c) => c.rank == Rank.king) && (nCards.length >= 2 || sCards.isNotEmpty)) ||
            (sCards.any((c) => c.rank == Rank.king) && (sCards.length >= 2 || nCards.isNotEmpty));
        final hasQueen = (nCards.any((c) => c.rank == Rank.queen) && nCards.length + sCards.length >= 3) ||
            (sCards.any((c) => c.rank == Rank.queen) && nCards.length + sCards.length >= 3);
        if (hasAce || hasKing || hasQueen) stoppedSuits++;
      }
      if (stoppedSuits == 4) combined += 1.0;
      else if (stoppedSuits <= 2) combined -= 2.0;
    }

    return double.parse(combined.clamp(0.0, 45.0).toStringAsFixed(1));
  }

  /// Domain 1: Partscore vs. Game Decisions.
  static GameDecision evaluateGameVsPartscore({
    required Hand north,
    required Hand south,
    required String strain,
    Vulnerability vuln = Vulnerability.none,
  }) {
    final s = strain.toLowerCase();
    int contractLevel = 3; // 3NT
    String targetContract = '3NT';
    int targetTricks = 9;

    if (s.contains('s') || s.contains('h')) {
      contractLevel = 4;
      targetContract = s.contains('s') ? '4♠' : '4♥';
      targetTricks = 10;
    } else if (s.contains('d') || s.contains('c')) {
      contractLevel = 5;
      targetContract = s.contains('d') ? '5♦' : '5♣';
      targetTricks = 11;
    }

    final isVul = vuln.isWeVul;
    final pred = _mlEvaluator.evaluateHands(
      north: north,
      south: south,
      contractLevel: contractLevel,
      strain: strain,
      isVulnerable: isVul,
    );

    final combMpi = evaluateCombinedMpi(north, south, strain: strain, vuln: vuln);
    final expectedTricks = targetTricks + pred.expectedResult;

    // Vulnerable games at IMPs have massive +500/600 reward vs -100 down 1 -> 38-40% breakeven
    final threshold = isVul ? 0.40 : 0.50;
    final minMpi = (contractLevel == 5) ? 27.5 : 24.0;
    final shouldBidGame = (pred.probMaking >= threshold || pred.expectedResult >= -0.15) && combMpi >= minMpi;

    final reason = shouldBidGame
        ? 'ML recommends bidding $targetContract ($combMpi Combined MPI, ${(pred.probMaking * 100).toStringAsFixed(0)}% make chance, ${expectedTricks.toStringAsFixed(1)} expected tricks).'
        : 'ML recommends stopping in partscore ($combMpi Combined MPI, ${(pred.probMaking * 100).toStringAsFixed(0)}% make chance is below ${isVul ? 'vul' : 'safe'} threshold).';

    return GameDecision(
      shouldBidGame: shouldBidGame,
      probMaking: pred.probMaking,
      expectedTricks: expectedTricks,
      combinedMpi: combMpi,
      targetContract: targetContract,
      reason: reason,
    );
  }

  /// Domain 2: Slam Decisions (Small Slam & Grand Slam).
  static SlamDecision evaluateSlam({
    required Hand north,
    required Hand south,
    required String strain,
    Vulnerability vuln = Vulnerability.none,
  }) {
    final combMpi = evaluateCombinedMpi(north, south, strain: strain, vuln: vuln);
    final totalControls = north.controls + south.controls; // A=2, K=1

    final s = strain.toLowerCase();
    Suit? trumpSuit;
    if (s.contains('s')) trumpSuit = Suit.spades;
    else if (s.contains('h')) trumpSuit = Suit.hearts;
    else if (s.contains('d')) trumpSuit = Suit.diamonds;
    else if (s.contains('c')) trumpSuit = Suit.clubs;

    // Keycards count (4 Aces + Trump King if suit)
    int keycards = north.aceCount + south.aceCount;
    bool hasTrumpQueen = false;
    if (trumpSuit != null) {
      if (north.cardsInSuit(trumpSuit).any((c) => c.rank == Rank.king) ||
          south.cardsInSuit(trumpSuit).any((c) => c.rank == Rank.king)) {
        keycards++;
      }
      hasTrumpQueen = north.hasQueen(trumpSuit) || south.hasQueen(trumpSuit);
    }

    // Grand slam threshold: 35.5+ MPI, all 5 keycards + trump Queen
    if (combMpi >= 35.5 && keycards == 5 && (hasTrumpQueen || (trumpSuit != null && north.length(trumpSuit) + south.length(trumpSuit) >= 10))) {
      return SlamDecision(
        recommendation: SlamRecommendation.grandSlam,
        probMaking: 0.82,
        expectedTricks: 13.0,
        combinedMpi: combMpi,
        controlsCount: totalControls,
        reason: 'Grand Slam Recommended: $combMpi Combined MPI, all 5 Key Cards held with solid trump control.',
      );
    }

    // Small slam threshold: 31.5+ MPI (suit) or 33.0+ (NT), at least 4 keycards, controls in unbid suits
    final minSlamMpi = (trumpSuit == null) ? 33.0 : 31.5;
    if (combMpi >= minSlamMpi && keycards >= 4 && totalControls >= 8) {
      return SlamDecision(
        recommendation: SlamRecommendation.smallSlam,
        probMaking: 0.72,
        expectedTricks: 12.1,
        combinedMpi: combMpi,
        controlsCount: totalControls,
        reason: 'Small Slam Recommended: $combMpi Combined MPI ($keycards/5 Key Cards, $totalControls controls).',
      );
    }

    // Quantitative / Slam Invitation: 29.5 - 31.4 MPI
    if (combMpi >= 29.5 && keycards >= 3) {
      return SlamDecision(
        recommendation: SlamRecommendation.invite,
        probMaking: 0.50,
        expectedTricks: 11.4,
        combinedMpi: combMpi,
        controlsCount: totalControls,
        reason: 'Slam Try / Quantitative Invite: $combMpi Combined MPI is borderline (evaluate maximum honors).',
      );
    }

    return SlamDecision(
      recommendation: SlamRecommendation.pass,
      probMaking: 0.25,
      expectedTricks: 10.5,
      combinedMpi: combMpi,
      controlsCount: totalControls,
      reason: 'Sign off in Game: $combMpi Combined MPI is insufficient for Level 6/7 slam.',
    );
  }

  /// Domain 3 & 4: Strain Tradeoffs (3NT vs 4M, 3NT vs 5m).
  static StrainDecision evaluateOptimalStrain({
    required Hand north,
    required Hand south,
    List<String> candidateStrains = const ['nt', 's', 'h', 'd', 'c'],
  }) {
    final Map<String, double> ratings = {};
    final Map<String, double> winProbs = {};

    for (final strain in candidateStrains) {
      final s = strain.toLowerCase();
      final combMpi = evaluateCombinedMpi(north, south, strain: s);

      if (s == 'nt') {
        // 3NT: Target 9 tricks
        final rating = combMpi - 24.5;
        ratings[strain] = double.parse(rating.toStringAsFixed(2));
        winProbs[strain] = double.parse((0.50 + rating * 0.12).clamp(0.10, 0.98).toStringAsFixed(2));
      } else if (s == 's' || s == 'h') {
        // Major: Target 10 tricks
        final suit = s == 's' ? Suit.spades : Suit.hearts;
        final fit = north.length(suit) + south.length(suit);
        double rating = combMpi - 24.5;
        if (fit >= 8) {
          // Check for ruffing value: singletons/voids
          final hasShortness = north.cards.any((c) => north.length(c.suit) <= 1) ||
              south.cards.any((c) => south.length(c.suit) <= 1);
          if (hasShortness) {
            rating += 0.8; // 4M superior with ruffing values
          } else {
            // Flat 4333 hands in 4M suffer compared to 3NT
            rating -= 0.6;
          }
        } else {
          rating -= 3.0; // No 8-card fit
        }
        ratings[strain] = double.parse(rating.toStringAsFixed(2));
        winProbs[strain] = double.parse((0.50 + rating * 0.10).clamp(0.10, 0.98).toStringAsFixed(2));
      } else {
        // Minor (D/C): Target 11 tricks!
        final suit = s == 'd' ? Suit.diamonds : Suit.clubs;
        final fit = north.length(suit) + south.length(suit);
        double rating = combMpi - 28.0; // 11 tricks requires much more power
        if (fit < 8) rating -= 4.0;
        ratings[strain] = double.parse(rating.toStringAsFixed(2));
        winProbs[strain] = double.parse((0.40 + rating * 0.08).clamp(0.05, 0.95).toStringAsFixed(2));
      }
    }

    String bestStrain = candidateStrains.first;
    double bestRating = -999.0;
    ratings.forEach((str, val) {
      if (val > bestRating) {
        bestRating = val;
        bestStrain = str;
      }
    });

    String reason;
    if (bestStrain == 'nt') {
      reason = '3NT is the optimal strain: faster 9-trick target with balanced honors across side suits.';
    } else if (bestStrain == 's' || bestStrain == 'h') {
      reason = '4${bestStrain.toUpperCase()} is optimal: 8+ major fit with ruffing potential provides higher trick expectancy.';
    } else {
      reason = '5${bestStrain.toUpperCase()} preferred due to extreme minor distribution and unstopped side suits.';
    }

    return StrainDecision(
      bestStrain: bestStrain,
      strainRatings: ratings,
      winProbabilities: winProbs,
      reason: reason,
    );
  }

  /// Domain 5: Preempt Decisions by Seat & Vulnerability (Rule of 2, 3, and 4).
  static PreemptDecision evaluatePreempt(
    Hand hand, {
    required Suit suit,
    required int level, // 2, 3, or 4
    SeatPosition seat = SeatPosition.first,
    Vulnerability vuln = Vulnerability.none,
  }) {
    final mpi = evaluateSingleHandMpi(hand, seat: seat, vuln: vuln);
    final targetTricks = level + 6;
    final suitLength = hand.length(suit);
    final ltc = hand.losingTrickCount;
    // With 7+ card suits, length cards provide additional winners beyond raw 3-card LTC
    final lengthBonus = suitLength >= 7 ? (suitLength - 6) : 0;
    final double expTricks = (13.0 - ltc + lengthBonus).clamp(1.0, 13.0);

    // Rule of 15 in 4th Seat: NEVER PREEMPT!
    if (seat == SeatPosition.fourth) {
      final ruleOf15 = hand.hcp + hand.spadesLength;
      final shouldOpen = ruleOf15 >= 15 && hand.hcp >= 10;
      return PreemptDecision(
        shouldPreempt: false,
        effectiveMpi: mpi,
        allowedUndertricks: 0,
        expectedTricks: expTricks,
        recommendedCall: shouldOpen ? '1${suit.symbol}' : 'Pass',
        reason: '4th Seat Principle: Never preempt when opponents have passed. Rule of 15 ($ruleOf15) ${shouldOpen ? "qualifies for 1${suit.symbol} opening" : "recommends passing out"}.',
      );
    }

    // Rule of 2, 3, and 4 based on vulnerability:
    int allowedDown;
    if (vuln == Vulnerability.favorable) {
      allowedDown = 4; // White vs Red: allowed down 4 tricks
    } else if (vuln == Vulnerability.unfavorable) {
      allowedDown = 2; // Red vs White: allowed down 2 tricks
    } else {
      allowedDown = 3; // Equal: allowed down 3 tricks
    }

    // 3rd seat tactical aggression: +1 allowed down
    if (seat == SeatPosition.third) {
      allowedDown += 1;
    }

    // Suit length requirement:
    // Level 2 = 6-card suit; Level 3 = 7-card suit; Level 4 = 8-card suit
    final minLength = level + 4;
    final hasLength = suitLength >= minLength;

    // 2nd seat discipline: requires sound suit quality (2 of top 3 or 3 of top 5)
    bool soundSuit = true;
    if (seat == SeatPosition.second) {
      final honors = hand.cardsInSuit(suit).where((c) => c.rank.value >= Rank.ten.value).length;
      soundSuit = honors >= 2;
    }

    // Max HCP ceiling: preempts should not hold opening values (<= 10 HCP)
    final isWeak = hand.hcp <= 10;
    final deficit = targetTricks - expTricks;
    final shouldPreempt = hasLength && isWeak && soundSuit && (deficit <= allowedDown);

    final call = '$level${suit.symbol}';
    final reason = shouldPreempt
        ? 'ML recommends opening $call ($suitLength-card suit, ${expTricks.toStringAsFixed(1)} exp tricks, allowed down $allowedDown under Rule of 2/3/4 in ${seat.label}).'
        : 'Preempt $call not recommended: ${!hasLength ? "insufficient length ($suitLength < $minLength)" : (!isWeak ? "too strong for preempt (${hand.hcp} HCP)" : (!soundSuit ? "2nd seat requires sound suit quality" : "deficit ($deficit) exceeds allowed down $allowedDown"))}.';

    return PreemptDecision(
      shouldPreempt: shouldPreempt,
      effectiveMpi: mpi,
      allowedUndertricks: allowedDown,
      expectedTricks: expTricks,
      recommendedCall: shouldPreempt ? call : 'Pass',
      reason: reason,
    );
  }

  /// Domain 6: Defensive Actions (Overcalls, Takeout Doubles, Power Doubles, Unusual 2NT, Michaels).
  static DefensiveDecision evaluateDefense(
    Hand hand, {
    required String oppCall,
    Vulnerability vuln = Vulnerability.none,
  }) {
    final mpi = evaluateSingleHandMpi(hand, vuln: vuln);
    final oppLower = oppCall.trim().toLowerCase();

    // Determine opponent suit if suit opening
    Suit? oppSuit;
    if (oppLower.contains('s')) oppSuit = Suit.spades;
    else if (oppLower.contains('h')) oppSuit = Suit.hearts;
    else if (oppLower.contains('d')) oppSuit = Suit.diamonds;
    else if (oppLower.contains('c')) oppSuit = Suit.clubs;

    // 1. Power Double: 17+ MPI (any shape; doubles first, then bids own suit)
    if (mpi >= 17.0) {
      return DefensiveDecision(
        action: DefensiveAction.powerDouble,
        recommendedCall: 'Dbl',
        effectiveMpi: mpi,
        reason: 'Power Double: Hand has $mpi MPI (17+ any shape), too strong for simple overcall. Double then bid.',
      );
    }

    // 2. Unusual 2NT & Michaels Cuebid (Two-suiters: 5-5+)
    final suitsOver5 = Suit.values.where((s) => hand.length(s) >= 5).toList();
    if (suitsOver5.length >= 2 && oppSuit != null) {
      final minTwoSuitMpi = vuln == Vulnerability.unfavorable ? 10.5 : 7.0;
      if (mpi >= minTwoSuitMpi) {
        // Over 1M: 5-5 in minors is Unusual 2NT
        if ((oppSuit == Suit.hearts || oppSuit == Suit.spades) &&
            hand.clubsLength >= 5 && hand.diamondsLength >= 5) {
          return DefensiveDecision(
            action: DefensiveAction.unusual2nt,
            recommendedCall: '2NT',
            effectiveMpi: mpi,
            reason: 'Unusual 2NT: 5-5 in minors (${hand.clubsLength}♣/${hand.diamondsLength}♦, $mpi MPI) over opponent major.',
          );
        }

        // Over 1M: 5-5 with the other major is Michaels
        final otherMajor = oppSuit == Suit.hearts ? Suit.spades : Suit.hearts;
        if (hand.length(otherMajor) >= 5 && (hand.clubsLength >= 5 || hand.diamondsLength >= 5)) {
          final cuebid = oppSuit == Suit.hearts ? '2♥' : '2♠';
          return DefensiveDecision(
            action: DefensiveAction.michaels,
            recommendedCall: cuebid,
            effectiveMpi: mpi,
            reason: 'Michaels Cuebid ($cuebid): 5-5 in other major and an unspecified minor ($mpi MPI).',
          );
        }

        // Over 1m: 5-5 in majors is Michaels
        if ((oppSuit == Suit.clubs || oppSuit == Suit.diamonds) &&
            hand.spadesLength >= 5 && hand.heartsLength >= 5) {
          final cuebid = oppSuit == Suit.clubs ? '2♣' : '2♦';
          return DefensiveDecision(
            action: DefensiveAction.michaels,
            recommendedCall: cuebid,
            effectiveMpi: mpi,
            reason: 'Michaels Cuebid ($cuebid): 5-5 in both majors (${hand.spadesLength}♠/${hand.heartsLength}♥, $mpi MPI).',
          );
        }
      }
    }

    // 3. Takeout Double: 11.0 - 16.5 MPI, shortness in opp suit (<= 2) and 3+ in all unbid suits
    if (oppSuit != null && mpi >= 11.0 && mpi <= 16.5) {
      final oppLength = hand.length(oppSuit);
      final unbidSuits = Suit.values.where((s) => s != oppSuit);
      final supportAllUnbid = unbidSuits.every((s) => hand.length(s) >= 3);
      if (oppLength <= 2 && supportAllUnbid) {
        return DefensiveDecision(
          action: DefensiveAction.takeoutDouble,
          recommendedCall: 'Dbl',
          effectiveMpi: mpi,
          reason: 'Takeout Double: Shortness in opponent suit ($oppLength in ${oppSuit.symbol}) with 3+ card support for all unbid suits ($mpi MPI).',
        );
      }
    }

    // 4. Simple Overcall: 8.0 - 16.5 MPI, 5+ cards in good suit
    Suit? bestOvercallSuit;
    int maxLen = 4;
    for (final s in Suit.values) {
      if (s == oppSuit) continue;
      final len = hand.length(s);
      if (len > maxLen) {
        maxLen = len;
        bestOvercallSuit = s;
      }
    }

    if (bestOvercallSuit != null && maxLen >= 5 && mpi >= 8.0 && mpi <= 16.5) {
      final call = '1${bestOvercallSuit.symbol}';
      return DefensiveDecision(
        action: DefensiveAction.overcall,
        recommendedCall: call,
        effectiveMpi: mpi,
        reason: 'Simple Overcall: $maxLen-card ${bestOvercallSuit.symbol} suit with $mpi MPI.',
      );
    }

    return DefensiveDecision(
      action: DefensiveAction.pass,
      recommendedCall: 'Pass',
      effectiveMpi: mpi,
      reason: 'Pass: Hand with $mpi MPI lacks the required shape or strength for a competitive entry.',
    );
  }
}

