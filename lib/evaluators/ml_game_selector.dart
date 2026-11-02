import '../models/card.dart';
import '../models/hand.dart';
import '../models/seat_belief_state.dart';
import 'ml_strain_model.dart';

/// The result of an empirical ML game selection between 3NT and 5 of a minor.
class MLGameDecision {
  final String recommendedGame; // '3NT', '5D', '5C'
  final Suit? recommendedStrain; // null for NT, Suit.diamonds, Suit.clubs
  final int recommendedLevel; // 3 or 5
  final bool hasAllStoppers;
  final List<Suit> unstoppedSuits;
  final double confidence;
  final String reasoning;

  const MLGameDecision({
    required this.recommendedGame,
    required this.recommendedStrain,
    required this.recommendedLevel,
    required this.hasAllStoppers,
    required this.unstoppedSuits,
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
  /// [candidateMinor] must be Suit.diamonds or Suit.clubs.
  static MLGameDecision selectOptimalGame({
    required Hand myHand,
    required SeatBeliefState partnerBelief,
    Suit? candidateMinor,
    bool isOpponentActive = false,
  }) {
    // 1. Determine minor fit and suit
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
      final partnerHas = (partnerBelief.minSuitLength[s] ?? 0) >= 4 ||
          (partnerBelief.minHcp >= 12 && (partnerBelief.minSuitLength[s] ?? 0) >= 3);
      if (!myHas && !partnerHas) {
        unstopped.add(s);
      }
    }

    final hasAllStoppers = unstopped.isEmpty;

    // 3. Evaluate shape and distribution
    final lengths = [myHand.spadesLength, myHand.heartsLength, myHand.diamondsLength, myHand.clubsLength]..sort();
    final hasShortness = lengths[0] <= 1; // singleton or void
    final minorFit = minor != null ? partnerBelief.totalGuaranteedFit(myHand, minor) : 0;

    // 4. Decision logic:
    // If all suits stopped and balanced distribution:
    // 3NT requires only 9 tricks (+400/+600) vs 11 tricks in 5m (+400/+600).
    if (minor == null || (hasAllStoppers && !hasShortness)) {
      return MLGameDecision(
        recommendedGame: '3NT',
        recommendedStrain: null,
        recommendedLevel: 3,
        hasAllStoppers: hasAllStoppers,
        unstoppedSuits: unstopped,
        confidence: 0.90,
        reasoning: 'All suits stopped and balanced distribution; 3NT is optimal (9 tricks vs 11).',
      );
    }

    // If an unstopped suit hole exists and partnership has a 9+ card minor fit with ruffing values:
    if (unstopped.isNotEmpty && minorFit >= 9 && hasShortness) {
      final gameCall = minor == Suit.diamonds ? '5D' : '5C';
      return MLGameDecision(
        recommendedGame: gameCall,
        recommendedStrain: minor,
        recommendedLevel: 5,
        hasAllStoppers: false,
        unstoppedSuits: unstopped,
        confidence: 0.85,
        reasoning: 'Exposed unstopped suit (${unstopped.map((s) => s.symbol).join(', ')}) with $minorFit-card fit and ruffing values; 5-Minor preferred.',
      );
    }

    // Default to 3NT if 3 stoppers confirmed:
    if (unstopped.length <= 1) {
      return MLGameDecision(
        recommendedGame: '3NT',
        recommendedStrain: null,
        recommendedLevel: 3,
        hasAllStoppers: hasAllStoppers,
        unstoppedSuits: unstopped,
        confidence: 0.80,
        reasoning: 'Sufficient stoppers (${4 - unstopped.length}/4 suits) for 3NT game.',
      );
    }

    // Otherwise 5m if 8+ fit exists:
    if (minor != null && minorFit >= 8) {
      final gameCall = minor == Suit.diamonds ? '5D' : '5C';
      return MLGameDecision(
        recommendedGame: gameCall,
        recommendedStrain: minor,
        recommendedLevel: 5,
        hasAllStoppers: false,
        unstoppedSuits: unstopped,
        confidence: 0.75,
        reasoning: 'Unstopped suit risks in NT; choosing $gameCall in $minorFit-card minor fit.',
      );
    }

    return MLGameDecision(
      recommendedGame: '3NT',
      recommendedStrain: null,
      recommendedLevel: 3,
      hasAllStoppers: hasAllStoppers,
      unstoppedSuits: unstopped,
      confidence: 0.70,
      reasoning: 'Fallback to 3NT as primary game contract.',
    );
  }
}
