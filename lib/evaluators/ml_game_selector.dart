import '../models/card.dart';
import '../models/hand.dart';
import '../models/seat_belief_state.dart';

/// The result of an empirical ML game selection between 3NT and 5 of a minor.
class MLGameDecision {
  final String recommendedGame; // '3NT', '5D', '5C'
  final Suit? recommendedStrain; // null for NT, Suit.diamonds, Suit.clubs
  final int recommendedLevel; // 3 or 5
  final bool hasAllStoppers;
  final List<Suit> unstoppedSuits;
  final bool isOpponentSuitExposed;
  final double confidence;
  final String reasoning;

  const MLGameDecision({
    required this.recommendedGame,
    required this.recommendedStrain,
    required this.recommendedLevel,
    required this.hasAllStoppers,
    required this.unstoppedSuits,
    this.isOpponentSuitExposed = false,
    required this.confidence,
    required this.reasoning,
  });

  @override
  String toString() => '$recommendedGame ($reasoning)';
}

/// Evaluator that determines whether to declare 3NT or 5-Minor (5D / 5C)
/// when the partnership holds game values and a confirmed minor suit fit.
class MLGameSelector {
  /// Evaluates optimal game choice between 3NT and 5 of [candidateMinor].
  /// Incorporates table perspective (partner, LHO, and RHO beliefs).
  static MLGameDecision selectOptimalGame({
    required Hand myHand,
    required SeatBeliefState partnerBelief,
    SeatBeliefState? lhoBelief,
    SeatBeliefState? rhoBelief,
    Suit? candidateMinor,
    bool isOpponentActive = false,
  }) {
    // 1. Determine candidate minor fit and suit
    final minor = candidateMinor ??
        (partnerBelief.hasGoldenFit(myHand, Suit.diamonds)
            ? Suit.diamonds
            : partnerBelief.hasGoldenFit(myHand, Suit.clubs)
                ? Suit.clubs
                : null);

    // 2. Check stopper integrity across all 4 suits
    final unstopped = <Suit>[];
    for (final s in Suit.values) {
      final myHas = SeatBeliefState.hasStopper(myHand, s);
      final partnerHas = partnerBelief.controlledSuits.contains(s) ||
          (partnerBelief.minSuitLength[s] ?? 0) >= 4 ||
          (partnerBelief.isBalanced && (partnerBelief.minSuitLength[s] ?? 0) >= 2) ||
          (partnerBelief.minHcp >= 12 && (partnerBelief.minSuitLength[s] ?? 0) >= 3);
      if (!myHas && !partnerHas) {
        unstopped.add(s);
      }
    }

    final hasAllStoppers = unstopped.isEmpty;

    // 3. Check if opponents have bid any unstopped suit
    final oppBidSuits = <Suit>{};
    void checkOpp(SeatBeliefState? opp) {
      if (opp == null) return;
      for (final s in Suit.values) {
        if ((opp.minSuitLength[s] ?? 0) >= 4) {
          oppBidSuits.add(s);
        }
      }
    }
    checkOpp(lhoBelief);
    checkOpp(rhoBelief);
    final isOpponentSuitExposed = unstopped.any((s) => oppBidSuits.contains(s));

    // 4. Evaluate shape, distribution, and trick-taking capacity
    final lengths = [myHand.spadesLength, myHand.heartsLength, myHand.diamondsLength, myHand.clubsLength]..sort();
    final hasShortness = lengths[0] <= 1; // singleton or void
    final minorFit = minor != null ? partnerBelief.totalGuaranteedFit(myHand, minor) : 0;

    final myLtc = myHand.losingTrickCount;
    final partnerMeanHcp = (partnerBelief.minHcp + (partnerBelief.maxHcp < 37 ? partnerBelief.maxHcp : partnerBelief.minHcp + 4)) / 2.0;
    double partnerInferredLtc = partnerMeanHcp >= 16 ? 5.0 : (partnerMeanHcp >= 12 ? 6.5 : (partnerMeanHcp >= 9 ? 7.5 : 9.0));
    final combLtc = myLtc + partnerInferredLtc;
    final combHcp = myHand.hcp + partnerMeanHcp;

    // 5. Decision hierarchy:
    // A. All suits stopped and balanced distribution:
    // 3NT requires only 9 tricks (+400/+600) vs 11 tricks in 5m (+400/+600).
    if (minor == null || (hasAllStoppers && !hasShortness)) {
      return MLGameDecision(
        recommendedGame: '3NT',
        recommendedStrain: null,
        recommendedLevel: 3,
        hasAllStoppers: hasAllStoppers,
        unstoppedSuits: unstopped,
        isOpponentSuitExposed: false,
        confidence: 0.95,
        reasoning: 'All suits stopped across partnership; 3NT is optimal (9 tricks vs 11).',
      );
    }

    // B. Critical vulnerability: Opponents bid an unstopped suit and we have a minor fit
    if (isOpponentSuitExposed && minorFit >= 8) {
      final gameCall = minor == Suit.diamonds ? '5D' : '5C';
      return MLGameDecision(
        recommendedGame: gameCall,
        recommendedStrain: minor,
        recommendedLevel: 5,
        hasAllStoppers: false,
        unstoppedSuits: unstopped,
        isOpponentSuitExposed: true,
        confidence: 0.90,
        reasoning: 'Opponent bid unstopped suit (${unstopped.where(oppBidSuits.contains).map((s) => s.symbol).join(', ')}); 3NT is unviable, $gameCall preferred.',
      );
    }

    // C. Deep minor fit (9+ cards) with shortness and sufficient trick-taking power (LTC <= 13 or HCP >= 27)
    if (unstopped.isNotEmpty && minorFit >= 9 && hasShortness && (combLtc <= 13.5 || combHcp >= 27)) {
      final gameCall = minor == Suit.diamonds ? '5D' : '5C';
      return MLGameDecision(
        recommendedGame: gameCall,
        recommendedStrain: minor,
        recommendedLevel: 5,
        hasAllStoppers: false,
        unstoppedSuits: unstopped,
        isOpponentSuitExposed: isOpponentSuitExposed,
        confidence: 0.85,
        reasoning: 'Exposed suit hole (${unstopped.map((s) => s.symbol).join(', ')}) with $minorFit-card fit and ruffing power; $gameCall preferred.',
      );
    }

    // D. Mild hole (at most 1 unstopped suit, unbid by opponents), but lack 11-trick strength for 5m:
    // 3NT is mathematically higher IMP expectation than an impossible 5m.
    if (unstopped.length <= 1 && !isOpponentSuitExposed) {
      return MLGameDecision(
        recommendedGame: '3NT',
        recommendedStrain: null,
        recommendedLevel: 3,
        hasAllStoppers: hasAllStoppers,
        unstoppedSuits: unstopped,
        isOpponentSuitExposed: false,
        confidence: 0.80,
        reasoning: 'Sufficient stoppers (${4 - unstopped.length}/4 suits) with unbid hole; 3NT has superior 9-trick equity over 5-Minor.',
      );
    }

    // E. Multiple unstopped suits (2+ holes) facing 8+ minor fit:
    if (minorFit >= 8) {
      final gameCall = minor == Suit.diamonds ? '5D' : '5C';
      return MLGameDecision(
        recommendedGame: gameCall,
        recommendedStrain: minor,
        recommendedLevel: 5,
        hasAllStoppers: false,
        unstoppedSuits: unstopped,
        isOpponentSuitExposed: isOpponentSuitExposed,
        confidence: 0.75,
        reasoning: 'Multiple unstopped suits (${unstopped.map((s) => s.symbol).join(', ')}); choosing $gameCall in $minorFit-card fit.',
      );
    }

    // F. Fallback default
    return MLGameDecision(
      recommendedGame: '3NT',
      recommendedStrain: null,
      recommendedLevel: 3,
      hasAllStoppers: hasAllStoppers,
      unstoppedSuits: unstopped,
      isOpponentSuitExposed: isOpponentSuitExposed,
      confidence: 0.70,
      reasoning: 'Fallback to 3NT as primary game contract.',
    );
  }
}
