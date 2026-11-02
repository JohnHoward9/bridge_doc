import 'dart:math';
import 'card.dart';
import 'hand.dart';
import 'seat_belief_state.dart';
import 'bidding_state_context.dart';
import '../evaluators/ml_bid_evaluator.dart';

/// Structured 5-channel orthogonal feature vector representing the bidding table
/// from the active bidder's first-person perspective:
/// 1 Hand is fully known (private), 3 Hands are consolidated rule beliefs (public).
class MLTablePerspectiveVector {
  // Channel 1: Self Hand Parameters (Exact & Fully Known)
  final double myHcp;
  final double myControls;
  final double mySpades;
  final double myHearts;
  final double myDiamonds;
  final double myClubs;
  final double myExcessLength;
  final double myShortnessDepth;
  final double myIsSolidSuit;
  final double myLtc;
  final double myTens;
  final double myNines;
  final double myRunningTricks;
  final double myHcpConcentrationRatio;

  // Channel 2: Partner Belief Channel (Rule Consolidation)
  final double partnerMinHcp;
  final double partnerMaxHcp;
  final double partnerMeanHcp;
  final double partnerExpSpades;
  final double partnerExpHearts;
  final double partnerExpDiamonds;
  final double partnerExpClubs;
  final double partnerIsBalanced;
  final double partnerIsForcing;

  // Channel 3: Opponents Channels (LHO & RHO Positional Context)
  final double lhoActive;
  final double myHonorsTrappedByLho;
  final double rhoActive;
  final double myTenacesOverRho;
  final double oppTotalMinHcp;

  // Channel 4: Partnership Synergy & Fit Matrix
  final double fitSpades;
  final double fitHearts;
  final double fitDiamonds;
  final double fitClubs;
  final double candidateFit;
  final double candidateFitSurplus;
  final double hasDoubleFit;
  final double combExpectedLtc;
  final double stopperCount;

  // Channel 5: Context & Auction State
  final double contractLevel;
  final double strainCode; // 0=NT, 1=S, 2=H, 3=D, 4=C
  final double isVulnerable;

  const MLTablePerspectiveVector({
    required this.myHcp,
    required this.myControls,
    required this.mySpades,
    required this.myHearts,
    required this.myDiamonds,
    required this.myClubs,
    required this.myExcessLength,
    required this.myShortnessDepth,
    required this.myIsSolidSuit,
    required this.myLtc,
    required this.myTens,
    required this.myNines,
    required this.myRunningTricks,
    required this.myHcpConcentrationRatio,
    required this.partnerMinHcp,
    required this.partnerMaxHcp,
    required this.partnerMeanHcp,
    required this.partnerExpSpades,
    required this.partnerExpHearts,
    required this.partnerExpDiamonds,
    required this.partnerExpClubs,
    required this.partnerIsBalanced,
    required this.partnerIsForcing,
    required this.lhoActive,
    required this.myHonorsTrappedByLho,
    required this.rhoActive,
    required this.myTenacesOverRho,
    required this.oppTotalMinHcp,
    required this.fitSpades,
    required this.fitHearts,
    required this.fitDiamonds,
    required this.fitClubs,
    required this.candidateFit,
    required this.candidateFitSurplus,
    required this.hasDoubleFit,
    required this.combExpectedLtc,
    required this.stopperCount,
    required this.contractLevel,
    required this.strainCode,
    required this.isVulnerable,
  });

  /// Flattened continuous feature vector for neural networks or regression estimators.
  List<double> toFlatVector() => [
        myHcp,
        myControls,
        mySpades,
        myHearts,
        myDiamonds,
        myClubs,
        myExcessLength,
        myShortnessDepth,
        myIsSolidSuit,
        myLtc,
        myTens,
        myNines,
        myRunningTricks,
        myHcpConcentrationRatio,
        partnerMinHcp,
        partnerMaxHcp,
        partnerMeanHcp,
        partnerExpSpades,
        partnerExpHearts,
        partnerExpDiamonds,
        partnerExpClubs,
        partnerIsBalanced,
        partnerIsForcing,
        lhoActive,
        myHonorsTrappedByLho,
        rhoActive,
        myTenacesOverRho,
        oppTotalMinHcp,
        fitSpades,
        fitHearts,
        fitDiamonds,
        fitClubs,
        candidateFit,
        candidateFitSurplus,
        hasDoubleFit,
        combExpectedLtc,
        stopperCount,
        contractLevel,
        strainCode,
        isVulnerable,
      ];

  /// Pure continuous Playing Strength (SPS) calculation.
  ///
  /// Correctly evaluates long suits and solid suit heads without artificial shape caps.
  double get playingStrength {
    double pts = myHcp;

    // Control and texture premiums
    pts += (myControls - 4.0) * 0.4;
    pts += myTens * 0.25;
    pts += myNines * 0.05;

    // Pure continuous length scaling: no hardcoded shapes
    pts += myExcessLength * 1.25;
    if (mySpades >= 7 || myHearts >= 7 || myDiamonds >= 7 || myClubs >= 7) {
      pts += 1.5; // Deep 7+ card suit establishment bonus
    }

    // Solid suit bonus: AKQ in 6+ suit produces guaranteed running tricks
    if (myIsSolidSuit > 0.5) {
      pts += 2.0;
    }

    // Shortness ruffing power
    pts += myShortnessDepth * 1.5;

    // Honor concentration synergy
    pts += (myHcpConcentrationRatio - 0.5) * 2.0;

    return double.parse(pts.clamp(0.0, 37.0).toStringAsFixed(1));
  }

  /// Calculates Expected Tricks for the partnership in the candidate strain.
  double get expectedTricks {
    // 1. Base trick potential from combined LTC: E[Tricks] = 24 - Combined LTC
    // With trump fit >= 8, shortness in the shorter hand produces ruffing tricks
    final dummyRuffTricks = (candidateFit >= 8.0 && myShortnessDepth > 0) ? (myShortnessDepth * 0.75) : 0.0;
    double ltcTricks = 24.0 - combExpectedLtc + dummyRuffTricks;

    // 2. High card & length trick potential:
    double hcpTricks = (myHcp + partnerMeanHcp) / 3.0;

    // Add surplus trump trick-taking power:
    if (candidateFit >= 8.0) {
      hcpTricks += (candidateFit - 8.0) * 0.85;
    }

    if (myIsSolidSuit > 0.5) {
      hcpTricks += 1.5;
    }

    if (hasDoubleFit > 0.5) {
      hcpTricks += 1.0;
    }

    // Weighted ensemble of LTC and HCP-fit models
    double exp = (ltcTricks * 0.55 + hcpTricks * 0.45);
    return double.parse(exp.clamp(1.0, 13.0).toStringAsFixed(2));
  }

  /// Probability of making the target contract (level + 6 tricks).
  double get probabilityOfMaking {
    final target = contractLevel + 6.0;
    final margin = expectedTricks - target;
    // Logistic sigmoid with temperature calibrated to championship IMP variance
    final prob = 1.0 / (1.0 + exp(-1.75 * margin));
    return double.parse(prob.clamp(0.01, 0.99).toStringAsFixed(3));
  }
}

/// Extracts multi-channel table perspective vectors from the active bidder's vantage point.
class MLPerspectiveFeatureExtractor {
  static MLTablePerspectiveVector extract({
    required Hand myHand,
    required SeatBeliefState partnerBelief,
    required SeatBeliefState lhoBelief,
    required SeatBeliefState rhoBelief,
    Suit? candidateStrain,
    int candidateLevel = 4,
    Vulnerability vulnerability = Vulnerability.none,
  }) {
    // 1. Self Hand Parameters
    final myHcp = myHand.hcp.toDouble();
    final myControls = myHand.controls.toDouble();
    final mySpades = myHand.spadesLength.toDouble();
    final myHearts = myHand.heartsLength.toDouble();
    final myDiamonds = myHand.diamondsLength.toDouble();
    final myClubs = myHand.clubsLength.toDouble();

    final lengths = [mySpades, myHearts, myDiamonds, myClubs]..sort((a, b) => b.compareTo(a));
    final l1 = lengths[0];
    final l4 = lengths[3];

    final myExcessLength = max(0.0, l1 - 4.0);
    final myShortnessDepth = max(0.0, 2.0 - l4);

    // Solid suit check: 6+ cards headed by AKQ
    double myIsSolidSuit = 0.0;
    double myRunningTricks = 0.0;
    for (final s in Suit.values) {
      if (myHand.isSolidSuit(s, minLength: 6)) {
        myIsSolidSuit = 1.0;
        myRunningTricks = myHand.length(s).toDouble();
        break;
      }
    }

    final myLtc = myHand.losingTrickCount.toDouble();
    final myTens = myHand.cards.where((c) => c.rank == Rank.ten).length.toDouble();
    final myNines = myHand.cards.where((c) => c.rank == Rank.nine).length.toDouble();

    // Honor concentration: HCP in 2 longest suits / total HCP
    final longestSuits = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs]
      ..sort((a, b) => myHand.length(b).compareTo(myHand.length(a)));
    final longHcp = (myHand.suitHcp(longestSuits[0]) + myHand.suitHcp(longestSuits[1])).toDouble();
    final myHcpConcentrationRatio = myHcp > 0 ? (longHcp / myHcp) : 0.0;

    // 2. Partner Belief
    final partnerMinHcp = partnerBelief.minHcp.toDouble();
    final partnerMaxHcp = min(37.0, partnerBelief.maxHcp.toDouble());
    final partnerMeanHcp = (partnerMinHcp + (partnerMaxHcp < 37 ? partnerMaxHcp : partnerMinHcp + 4.0)) / 2.0;

    final partnerExpectedLengths = partnerBelief.expectedSuitLengths();
    final partnerExpSpades = partnerExpectedLengths[Suit.spades] ?? 3.25;
    final partnerExpHearts = partnerExpectedLengths[Suit.hearts] ?? 3.25;
    final partnerExpDiamonds = partnerExpectedLengths[Suit.diamonds] ?? 3.25;
    final partnerExpClubs = partnerExpectedLengths[Suit.clubs] ?? 3.25;

    final partnerIsBalanced = partnerBelief.isBalanced ? 1.0 : 0.0;
    final partnerIsForcing = partnerBelief.isGameForcing ? 1.0 : 0.0;

    // Inferred Partner LTC based on partner strength and suit length
    double partnerInferredLtc = 8.0;
    if (partnerMeanHcp >= 16) {
      partnerInferredLtc = 5.0;
    } else if (partnerMeanHcp >= 12) {
      partnerInferredLtc = 6.5;
    } else if (partnerMeanHcp >= 9) {
      partnerInferredLtc = 7.5;
    } else if (partnerMeanHcp <= 5) {
      partnerInferredLtc = 9.5;
    }
    final partnerMaxSuit = max(max(partnerExpSpades, partnerExpHearts), max(partnerExpDiamonds, partnerExpClubs));
    if (partnerMaxSuit >= 7.0) {
      partnerInferredLtc -= 1.5;
    } else if (partnerMaxSuit >= 6.0) {
      partnerInferredLtc -= 0.75;
    }

    // 3. Opponents Channels (LHO & RHO)
    final lhoActive = lhoBelief.bidHistory.any((b) => b.toLowerCase() != 'pass') ? 1.0 : 0.0;
    final rhoActive = rhoBelief.bidHistory.any((b) => b.toLowerCase() != 'pass') ? 1.0 : 0.0;

    // Positional Traps / Tenaces
    double myHonorsTrappedByLho = 0.0;
    double myTenacesOverRho = 0.0;

    for (final s in Suit.values) {
      final sCards = myHand.cardsInSuit(s);
      final hasA = sCards.any((c) => c.rank == Rank.ace);
      final hasK = sCards.any((c) => c.rank == Rank.king);
      final hasQ = sCards.any((c) => c.rank == Rank.queen);

      // Trapped under LHO call
      if (lhoBelief.minSuitLength[s] != null && lhoBelief.minSuitLength[s]! >= 4) {
        if (hasK && !hasA) myHonorsTrappedByLho += 1.0;
        if (hasQ && !hasK && !hasA) myHonorsTrappedByLho += 0.5;
      }

      // Protected tenace over RHO call
      if (rhoBelief.minSuitLength[s] != null && rhoBelief.minSuitLength[s]! >= 4) {
        if (hasA && hasQ) myTenacesOverRho += 1.0;
        if (hasK && sCards.length >= 2) myTenacesOverRho += 0.5;
      }
    }

    final oppTotalMinHcp = (lhoBelief.minHcp + rhoBelief.minHcp).toDouble();

    // 4. Partnership Synergy & Fit Matrix
    final fitSpades = mySpades + partnerExpSpades;
    final fitHearts = myHearts + partnerExpHearts;
    final fitDiamonds = myDiamonds + partnerExpDiamonds;
    final fitClubs = myClubs + partnerExpClubs;

    double candidateFit = fitSpades;
    double strainCode = 1.0;
    if (candidateStrain == Suit.hearts) {
      candidateFit = fitHearts;
      strainCode = 2.0;
    } else if (candidateStrain == Suit.diamonds) {
      candidateFit = fitDiamonds;
      strainCode = 3.0;
    } else if (candidateStrain == Suit.clubs) {
      candidateFit = fitClubs;
      strainCode = 4.0;
    } else if (candidateStrain == null) {
      candidateFit = 0.0;
      strainCode = 0.0; // Notrump
    }

    final candidateFitSurplus = candidateStrain != null ? max(0.0, candidateFit - 8.0) : 0.0;

    final allFits = [fitSpades, fitHearts, fitDiamonds, fitClubs]..sort((a, b) => b.compareTo(a));
    final hasDoubleFit = (allFits[0] >= 8.0 && allFits[1] >= 8.0) ? 1.0 : 0.0;

    final combExpectedLtc = myLtc + partnerInferredLtc;

    // Stopper count: suits where myHand has A, KQ, QJx or partner has shown stopper
    int stops = 0;
    for (final s in Suit.values) {
      final sCards = myHand.cardsInSuit(s);
      final hasA = sCards.any((c) => c.rank == Rank.ace);
      final hasK = sCards.any((c) => c.rank == Rank.king);
      final hasQ = sCards.any((c) => c.rank == Rank.queen);
      final hasJ = sCards.any((c) => c.rank == Rank.jack);
      if (hasA || (hasK && sCards.length >= 2) || (hasQ && hasJ && sCards.length >= 3)) {
        stops++;
      } else if (partnerBelief.controlledSuits.contains(s)) {
        stops++;
      }
    }

    final isVul = vulnerability.isWeVul ? 1.0 : 0.0;

    return MLTablePerspectiveVector(
      myHcp: myHcp,
      myControls: myControls,
      mySpades: mySpades,
      myHearts: myHearts,
      myDiamonds: myDiamonds,
      myClubs: myClubs,
      myExcessLength: myExcessLength,
      myShortnessDepth: myShortnessDepth,
      myIsSolidSuit: myIsSolidSuit,
      myLtc: myLtc,
      myTens: myTens,
      myNines: myNines,
      myRunningTricks: myRunningTricks,
      myHcpConcentrationRatio: myHcpConcentrationRatio,
      partnerMinHcp: partnerMinHcp,
      partnerMaxHcp: partnerMaxHcp,
      partnerMeanHcp: partnerMeanHcp,
      partnerExpSpades: partnerExpSpades,
      partnerExpHearts: partnerExpHearts,
      partnerExpDiamonds: partnerExpDiamonds,
      partnerExpClubs: partnerExpClubs,
      partnerIsBalanced: partnerIsBalanced,
      partnerIsForcing: partnerIsForcing,
      lhoActive: lhoActive,
      myHonorsTrappedByLho: myHonorsTrappedByLho,
      rhoActive: rhoActive,
      myTenacesOverRho: myTenacesOverRho,
      oppTotalMinHcp: oppTotalMinHcp,
      fitSpades: fitSpades,
      fitHearts: fitHearts,
      fitDiamonds: fitDiamonds,
      fitClubs: fitClubs,
      candidateFit: candidateFit,
      candidateFitSurplus: candidateFitSurplus,
      hasDoubleFit: hasDoubleFit,
      combExpectedLtc: combExpectedLtc,
      stopperCount: stops.toDouble(),
      contractLevel: candidateLevel.toDouble(),
      strainCode: strainCode,
      isVulnerable: isVul,
    );
  }
}
