import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../models/card.dart';
import '../models/hand.dart';
import '../models/seat_belief_state.dart';
import '../models/bidding_system.dart';

/// Single-hand power evaluation across all 5 strains (NT, Spades, Hearts, Diamonds, Clubs).
class MLStrainHandResult {
  final double notrump;
  final double spades;
  final double hearts;
  final double diamonds;
  final double clubs;

  const MLStrainHandResult({
    required this.notrump,
    required this.spades,
    required this.hearts,
    required this.diamonds,
    required this.clubs,
  });

  double powerFor(Suit? strain) {
    if (strain == null) return notrump;
    switch (strain) {
      case Suit.spades: return spades;
      case Suit.hearts: return hearts;
      case Suit.diamonds: return diamonds;
      case Suit.clubs: return clubs;
    }
  }

  /// The suit with the highest single-hand power.
  Suit get bestSuit {
    var best = Suit.spades;
    var maxPower = spades;
    if (hearts > maxPower) { maxPower = hearts; best = Suit.hearts; }
    if (diamonds > maxPower) { maxPower = diamonds; best = Suit.diamonds; }
    if (clubs > maxPower) { maxPower = clubs; best = Suit.clubs; }
    return best;
  }

  /// Highest suit power.
  double get maxSuitPower => powerFor(bestSuit);

  @override
  String toString() =>
      'MLStrainHandResult(NT: ${notrump.toStringAsFixed(1)}, ♠: ${spades.toStringAsFixed(1)}, '
      '♥: ${hearts.toStringAsFixed(1)}, ♦: ${diamonds.toStringAsFixed(1)}, ♣: ${clubs.toStringAsFixed(1)})';
}

/// Partnership evaluation integrating the player's private hand with the auction belief state of partner.
class MLPartnershipEvaluation {
  final Hand myHand;
  final SeatBeliefState partnerBelief;
  final MLStrainHandResult myStrainResult;

  /// Combined partnership power (0-37 scale) per strain.
  final double combinedNotrump;
  final double combinedSpades;
  final double combinedHearts;
  final double combinedDiamonds;
  final double combinedClubs;

  /// Best recommended strain (null = NT).
  final Suit? recommendedStrain;

  /// Best recommended target level (e.g. 4 for 4H, 3 for 3NT, 6 for Slam).
  final int recommendedLevel;

  /// Human-readable recommendation, e.g. "4H (Signoff in 8-card Major Fit)".
  final String recommendedCall;

  /// Probability of making game in the recommended strain (0.0 to 1.0).
  final double probMakeGame;

  /// Probability of making slam (0.0 to 1.0).
  final double probMakeSlam;

  /// Step-by-step reasoning explaining the ML evaluation.
  final List<String> reasoning;

  const MLPartnershipEvaluation({
    required this.myHand,
    required this.partnerBelief,
    required this.myStrainResult,
    required this.combinedNotrump,
    required this.combinedSpades,
    required this.combinedHearts,
    required this.combinedDiamonds,
    required this.combinedClubs,
    required this.recommendedStrain,
    required this.recommendedLevel,
    required this.recommendedCall,
    required this.probMakeGame,
    required this.probMakeSlam,
    required this.reasoning,
  });

  double combinedPowerFor(Suit? strain) {
    if (strain == null) return combinedNotrump;
    switch (strain) {
      case Suit.spades: return combinedSpades;
      case Suit.hearts: return combinedHearts;
      case Suit.diamonds: return combinedDiamonds;
      case Suit.clubs: return combinedClubs;
    }
  }

  int fitFor(Suit suit) => partnerBelief.totalGuaranteedFit(myHand, suit);
  bool hasGoldenFit(Suit suit) => partnerBelief.hasGoldenFit(myHand, suit);
}

/// The 5-Strain Machine Learning Bidding Model.
/// Evaluates single hands across strains and uses accumulated auction belief state
/// to evaluate partnership contracts and next-bid decisions.
class MLStrainBiddingModel {
  static Map<String, dynamic>? _cachedModelData;

  static Map<String, dynamic> _getModelData() {
    if (_cachedModelData != null) return _cachedModelData!;
    try {
      final file = File('assets/models/ml_strain_model.json');
      if (file.existsSync()) {
        _cachedModelData = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return _cachedModelData!;
      }
    } catch (_) {}
    _cachedModelData = _defaultStrainModel;
    return _cachedModelData!;
  }

  /// Returns learned empirical partnership weights for [strain] (null = NT).
  static Map<String, double> getPartnershipWeights(Suit? strain) {
    final data = _getModelData();
    final strains = data['strains'] as Map<String, dynamic>?;
    final key = strain == null ? 'nt' : strain.symbol.toLowerCase();
    final sData = strains?[key] as Map<String, dynamic>?;
    final pWeights = sData?['partnership_weights'] as Map<String, dynamic>?;
    if (pWeights != null) {
      return pWeights.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }
    return const {
      'trump_fit_surplus': 1.85,
      'has_double_fit': 1.50,
      'sec_fit_surplus': 0.25,
      'side_shortness': 1.25,
      'running_suit_surplus': 0.67,
      'is_opp_active': -0.50,
    };
  }

  static final Map<String, dynamic> _defaultStrainModel = {
    "model_name": "BBOChampionshipsJointPartnershipStrainModel",
    "version": "3.0.0-empirical-joint",
    "strains": {
      "nt": {
        "partnership_weights": {
          "bias": 1.5218,
          "running_suit_surplus": 0.6685,
          "comb_controls_diff": 1.0626,
          "is_opp_active": -0.1934,
          "is_flat": -1.4237
        }
      },
      "s": {
        "partnership_weights": {
          "bias": 4.2293,
          "trump_fit_surplus": 1.9468,
          "has_double_fit": 1.7537,
          "sec_fit_surplus": -0.3793,
          "side_shortness": 1.2455,
          "comb_controls_diff": 0.0726,
          "is_opp_active": 0.0641
        }
      },
      "h": {
        "partnership_weights": {
          "bias": 4.0128,
          "trump_fit_surplus": 1.8769,
          "has_double_fit": 0.6396,
          "sec_fit_surplus": 0.0049,
          "side_shortness": 1.4483,
          "comb_controls_diff": 0.2404,
          "is_opp_active": 0.1107
        }
      },
      "d": {
        "partnership_weights": {
          "bias": 6.1083,
          "trump_fit_surplus": 3.0182,
          "has_double_fit": 0.8400,
          "sec_fit_surplus": 1.3195,
          "side_shortness": 0.8121,
          "comb_controls_diff": -2.9407,
          "is_opp_active": -2.8996
        }
      },
      "c": {
        "partnership_weights": {
          "bias": 3.9986,
          "trump_fit_surplus": 1.5841,
          "has_double_fit": 1.7402,
          "sec_fit_surplus": -0.2982,
          "side_shortness": 1.5430,
          "comb_controls_diff": -0.0478,
          "is_opp_active": 0.0535
        }
      }
    }
  };

  /// Evaluates a single 13-card [hand] across all 5 strains using zero-centered empirical weights.
  static MLStrainHandResult evaluateHand(Hand hand) {
    final rawHcp = hand.hcp.toDouble();

    final aces = hand.cards.where((c) => c.rank == Rank.ace).length;
    final kings = hand.cards.where((c) => c.rank == Rank.king).length;
    final queens = hand.cards.where((c) => c.rank == Rank.queen).length;
    final jacks = hand.cards.where((c) => c.rank == Rank.jack).length;
    final tens = hand.cards.where((c) => c.rank == Rank.ten).length;
    final nines = hand.cards.where((c) => c.rank == Rank.nine).length;

    // Centered honors & intermediates differences (relative to average 1-per-hand baseline)
    final acesDiff = (aces - 1.0);
    final kingsDiff = (kings - 1.0);
    final queensDiff = (queens - 1.0);
    final jacksDiff = (jacks - 1.0);
    final tensDiff = (tens - 1.0);
    final ninesDiff = (nines - 1.0);

    // Distribution
    final lengths = [hand.spadesLength, hand.heartsLength, hand.diamondsLength, hand.clubsLength]..sort();
    final is4333 = (lengths[0] == 3 && lengths[1] == 3 && lengths[2] == 3 && lengths[3] == 4);
    final isBalanced = hand.isBalanced;

    // 1. Notrump Evaluation (Zero-centered: E[Delta] = 0.0)
    // Premium for Aces/Kings stoppers, slight discount for soft Queens/Jacks without Aces,
    // flat 4333 deduction, reward for 5-card suit stoppers.
    double ntDelta = (acesDiff * 0.45) + (kingsDiff * 0.15) - (queensDiff * 0.15) - (jacksDiff * 0.25) +
        (tensDiff * 0.15) + (ninesDiff * 0.05);
    if (is4333) ntDelta -= 0.50;
    if (isBalanced && lengths[3] == 5) {
      // 5332 with 5-card suit: bonus if suit has top honors
      final maxSuit = Suit.values.firstWhere((s) => hand.length(s) == 5);
      final honors = hand.cards.where((c) => c.suit == maxSuit && (c.rank.hcp > 0 || c.rank == Rank.ten)).length;
      if (honors >= 3) ntDelta += 0.50;
    }

    // 5-4-2-2 Semi-balanced evaluation:
    // When doubletons contain concentrated honors (Ace, King, Queen), Notrump is protected (+0.40).
    // Empty/hollow doubletons risk defensive run of tricks in NT (-0.50), favoring suit play.
    final is5422 = (lengths[0] == 2 && lengths[1] == 2 && lengths[2] == 4 && lengths[3] == 5);
    if (is5422) {
      final doubletonSuits = Suit.values.where((s) => hand.length(s) == 2).toList();
      double doubletonHcp = 0.0;
      for (final s in doubletonSuits) {
        final cards = hand.cards.where((c) => c.suit == s);
        for (final c in cards) {
          doubletonHcp += c.rank.hcp.toDouble();
        }
      }
      if (doubletonHcp >= 3.0) {
        ntDelta += 0.40;
      } else if (doubletonHcp == 0.0) {
        ntDelta -= 0.50;
      }
    }
    final ntPower = (rawHcp + ntDelta).clamp(0.0, 37.0);

    // 2. Suit Evaluation helper
    double evalSuit(Suit trumpSuit) {
      final trumpLen = hand.length(trumpSuit);
      final trumpCards = hand.cards.where((c) => c.suit == trumpSuit).toList();
      final trumpHonors = trumpCards.where((c) => c.rank.hcp > 0 || c.rank == Rank.ten).length;

      // Trump length surplus / deficit
      double lengthBonus = 0.0;
      if (trumpLen >= 4) {
        lengthBonus = (trumpLen - 4) * 1.0;
        if (trumpLen >= 6) lengthBonus += (trumpLen - 5) * 0.5; // Long running suit
      } else {
        // Holding under 4 trumps is a severe deficit when trying to declare this suit
        lengthBonus = (trumpLen - 4.0) * 1.5;
      }

      // Trump honor quality
      double qualityBonus = 0.0;
      if (trumpLen >= 4) {
        if (trumpHonors >= 4) qualityBonus += 1.0;
        else if (trumpHonors == 3) qualityBonus += 0.6;
        else if (trumpHonors == 0) qualityBonus -= 0.4; // Hollow trumps
      }

      // Outside shortness / ruffing potential
      double sideShortness = 0.0;
      for (final s in Suit.values) {
        if (s == trumpSuit) continue;
        final sLen = hand.length(s);
        if (sLen == 0) sideShortness += 2.0; // Void
        else if (sLen == 1) sideShortness += 1.2; // Singleton
        else if (sLen == 2) sideShortness += 0.3; // Doubleton
      }

      // Controls (Aces and Kings are prime in suit play)
      final suitControls = (acesDiff * 0.40) + (kingsDiff * 0.20) - (queensDiff * 0.10) - (jacksDiff * 0.20) +
          (tensDiff * 0.10);

      final totalSuitPower = rawHcp + lengthBonus + qualityBonus + sideShortness + suitControls;
      return totalSuitPower.clamp(0.0, 37.0);
    }

    return MLStrainHandResult(
      notrump: double.parse(ntPower.toStringAsFixed(1)),
      spades: double.parse(evalSuit(Suit.spades).toStringAsFixed(1)),
      hearts: double.parse(evalSuit(Suit.hearts).toStringAsFixed(1)),
      diamonds: double.parse(evalSuit(Suit.diamonds).toStringAsFixed(1)),
      clubs: double.parse(evalSuit(Suit.clubs).toStringAsFixed(1)),
    );
  }

  /// Evaluates the partnership given [myHand] and the accumulated [partnerBelief] from the auction.
  /// When [forcingLevel] is game or higher, partscore signoffs are prohibited and target level
  /// is constrained to at least game (or slam / grand slam).
  /// Factors in all 4 suits, rewarding secondary / double fits (e.g. Spades + Clubs) and long running minor suits.
  /// Also conditions contract safety on whether opponents have intervened ([isOpponentActive]),
  /// penalizing bad split probabilities and unstopped suit threats.
  static MLPartnershipEvaluation evaluatePartnership(
    Hand myHand,
    SeatBeliefState partnerBelief, {
    ForcingLevel forcingLevel = ForcingLevel.partScore,
    String? candidateRule,
    bool isOpponentActive = false,
  }) {
    // If a candidate rule was provided that specifies suit length, incorporate it into the belief state:
    SeatBeliefState effectiveBelief = partnerBelief;
    if (candidateRule != null && candidateRule.isNotEmpty) {
      final parsed = SeatBeliefState.parseRuleSuitBounds(candidateRule);
      if (parsed.minSuit.isNotEmpty) {
        final mergedMin = Map<Suit, int>.from(effectiveBelief.minSuitLength);
        for (final e in parsed.minSuit.entries) {
          if (e.value > (mergedMin[e.key] ?? 0)) mergedMin[e.key] = e.value;
        }
        effectiveBelief = effectiveBelief.copyWith(minSuitLength: mergedMin);
      }
    }

    final singleHand = evaluateHand(myHand);
    final partnerMeanHcp = (effectiveBelief.minHcp + (effectiveBelief.maxHcp < 37 ? effectiveBelief.maxHcp : effectiveBelief.minHcp + 4)) / 2.0;
    final List<String> reasons = [];

    // 1. Working Honors & Mesh
    final workingHonors = effectiveBelief.workingHonorsHcp(myHand);
    final wastedHonors = effectiveBelief.wastedHonorsHcp(myHand);
    double meshBonus = (workingHonors * 0.15) - (wastedHonors * 0.30);
    if (workingHonors >= 4.0) {
      reasons.add('+${(workingHonors * 0.15).toStringAsFixed(1)} Working honors in partner\'s shown suits ($workingHonors HCP)');
    }
    if (wastedHonors >= 2.0) {
      reasons.add('-${(wastedHonors * 0.30).toStringAsFixed(1)} Wasted secondary honors facing shortness ($wastedHonors HCP)');
    }

    // 2. Evaluate Combined Power per Strain
    // For Notrump:
    double combinedNT = singleHand.notrump + partnerMeanHcp;
    // Check stopper coverage
    int stoppers = 0;
    for (final s in Suit.values) {
      if (SeatBeliefState.hasStopper(myHand, s) || (effectiveBelief.minSuitLength[s] ?? 0) >= 4) {
        stoppers++;
      }
    }
    if (stoppers < 4) {
      combinedNT -= (4 - stoppers) * 0.75;
      reasons.add('Lack of confirmed stoppers in ${4 - stoppers} suits reduces NT potential');
    }
    // Minor or long running suit bonus in NT using learned empirical model weights:
    final ntWeights = getPartnershipWeights(null);
    final runningSuitCoeff = ntWeights['running_suit_surplus'] ?? 0.67;
    final maxFitAcrossSuits = effectiveBelief.primaryFit(myHand);
    final bestFitSuit = effectiveBelief.bestFitSuit(myHand);
    if (maxFitAcrossSuits >= 8 && (bestFitSuit == Suit.clubs || bestFitSuit == Suit.diamonds)) {
      final minorRunBonus = (maxFitAcrossSuits - 7) * runningSuitCoeff;
      combinedNT += minorRunBonus;
      reasons.add('+${minorRunBonus.toStringAsFixed(1)} Running ${bestFitSuit.symbol} trick source ($maxFitAcrossSuits combined cards) in NT');
    }
    if (isOpponentActive) {
      combinedNT -= 1.0;
      reasons.add('-1.0 Active opponent bidding threatens unstopped suits in NT');
    }

    // For Suit contracts using learned empirical weights:
    double evalCombinedSuit(Suit s) {
      final weights = getPartnershipWeights(s);
      final trumpFitSurplusCoeff = weights['trump_fit_surplus'] ?? 1.85;
      final doubleFitCoeff = weights['has_double_fit'] ?? 1.50;
      final secFitSurplusCoeff = weights['sec_fit_surplus'] ?? 0.0;

      final guaranteedFit = effectiveBelief.totalGuaranteedFit(myHand, s);
      double fitBonus = 0.0;
      if (guaranteedFit >= 8) {
        fitBonus = (guaranteedFit - 7) * trumpFitSurplusCoeff;
      } else if (guaranteedFit <= 6) {
        fitBonus = -trumpFitSurplusCoeff; // Mis-fit deduction proportional to fit surplus weight
      }

      // Multi-Suit & Double-Fit Evaluation across all 4 suits:
      double doubleFitBonus = 0.0;
      final secFit = effectiveBelief.secondaryFit(myHand, s);
      final secSuit = effectiveBelief.secondaryFitSuit(myHand, s);
      if (guaranteedFit >= 8 && secFit >= 8) {
        // Confirmed Double Fit! (e.g. 8+ in Spades AND 8+ in Clubs)
        final secSurplus = (secFit - 8.0) * (secFitSurplusCoeff > 0 ? secFitSurplusCoeff : 0.35);
        doubleFitBonus = doubleFitCoeff + secSurplus;
        if (secSuit != null && !reasons.any((r) => r.contains('Double-fit synergy'))) {
          reasons.add('+${doubleFitBonus.toStringAsFixed(1)} Double-fit synergy in ${secSuit.symbol} ($secFit-card secondary fit)');
        }
      } else if (guaranteedFit >= 8 && secFit == 7) {
        doubleFitBonus = doubleFitCoeff * 0.33; // Helpful 7-card secondary mesh
      }

      // Opponent Activity Split Risk Adjustment:
      final oppPenalty = isOpponentActive ? -0.5 : 0.0;

      return singleHand.powerFor(s) + partnerMeanHcp + fitBonus + doubleFitBonus + meshBonus + oppPenalty;
    }

    if (isOpponentActive) {
      reasons.add('-0.5 Active opponent bidding increases bad split probability');
    }

    final combinedS = evalCombinedSuit(Suit.spades);
    final combinedH = evalCombinedSuit(Suit.hearts);
    final combinedD = evalCombinedSuit(Suit.diamonds);
    final combinedC = evalCombinedSuit(Suit.clubs);

    // 3. Select Best Strain & Contract Decision
    Suit? bestStrain;
    double bestPower = combinedNT;
    int targetLevel = 3;
    String recCall = '3NT';

    // A. Check for Slam Potential across any strain (>= 31.5 power)
    final candidateStrains = <Suit?, double>{
      null: combinedNT,
      Suit.spades: combinedS,
      Suit.hearts: combinedH,
      Suit.diamonds: combinedD,
      Suit.clubs: combinedC,
    };

    Suit? maxSlamSuit;
    double maxSlamPower = 0.0;
    candidateStrains.forEach((s, p) {
      if (s == null) {
        if (p >= 32.5 && stoppers == 4 && p > maxSlamPower) {
          maxSlamPower = p;
          maxSlamSuit = null;
        }
      } else if (partnerBelief.hasGoldenFit(myHand, s)) {
        // Minor suit slams require higher power (>= 32.5) than major suit slams (>= 31.5)
        final slamThreshold = (s == Suit.clubs || s == Suit.diamonds) ? 32.5 : 31.5;
        if (p >= slamThreshold && p > maxSlamPower) {
          maxSlamPower = p;
          maxSlamSuit = s;
        }
      }
    });

    if (maxSlamPower > 0.0 || forcingLevel == ForcingLevel.slam || forcingLevel == ForcingLevel.grandSlam) {
      bestStrain = maxSlamSuit;
      bestPower = maxSlamPower > 0.0 ? maxSlamPower : combinedNT;
      if (forcingLevel == ForcingLevel.grandSlam) {
        targetLevel = 7;
        recCall = bestStrain == null ? '7NT' : '7${bestStrain!.symbol}';
        reasons.add('Grand slam force: committed to level 7 in ${bestStrain == null ? 'NT' : bestStrain!.symbol}');
      } else {
        targetLevel = 6;
        recCall = bestStrain == null ? '6NT' : '6${bestStrain!.symbol}';
        reasons.add(forcingLevel == ForcingLevel.slam
            ? 'Slam force: committed to level 6 in ${bestStrain == null ? 'NT' : bestStrain!.symbol}'
            : 'Slam threshold reached in ${bestStrain == null ? 'NT' : bestStrain!.symbol} (combined power ${bestPower.toStringAsFixed(1)} >= 31.5)');
      }
    } else if (partnerBelief.hasGoldenFit(myHand, Suit.hearts) && combinedH >= 23.5) {
      // Prioritize 8-card Major fits over Notrump for game
      bestStrain = Suit.hearts;
      bestPower = combinedH;
      targetLevel = 4;
      recCall = '4H';
      reasons.add('8+ Heart fit confirmed (${myHand.heartsLength} in hand + ${partnerBelief.minSuitLength[Suit.hearts]}+ shown)');
    } else if (partnerBelief.hasGoldenFit(myHand, Suit.spades) && combinedS >= 23.5) {
      bestStrain = Suit.spades;
      bestPower = combinedS;
      targetLevel = 4;
      recCall = '4S';
      reasons.add('8+ Spade fit confirmed (${myHand.spadesLength} in hand + ${partnerBelief.minSuitLength[Suit.spades]}+ shown)');
    } else {
      // No 8-card major fit: consider 3NT vs minor fit
      if (combinedNT >= 24.5 && stoppers >= 3) {
        bestStrain = null; // NT
        bestPower = combinedNT;
        targetLevel = 3;
        recCall = '3NT';
        reasons.add('No major fit found; 3NT chosen with stoppers across unbid suits');
      } else if (partnerBelief.hasGoldenFit(myHand, Suit.diamonds) && combinedD >= 28.0) {
        bestStrain = Suit.diamonds;
        bestPower = combinedD;
        targetLevel = 5;
        recCall = '5D';
      } else if (partnerBelief.hasGoldenFit(myHand, Suit.clubs) && combinedC >= 28.0) {
        bestStrain = Suit.clubs;
        bestPower = combinedC;
        targetLevel = 5;
        recCall = '5C';
      } else if (forcingLevel == ForcingLevel.game) {
        // Under Game Force, partscore signoff is forbidden.
        // Determine the best game contract: 4H, 4S, 3NT, 5D, or 5C.
        if (partnerBelief.hasGoldenFit(myHand, Suit.hearts)) {
          bestStrain = Suit.hearts;
          bestPower = combinedH;
          targetLevel = 4;
          recCall = '4H';
          reasons.add('Game forced: signing off in 4H with 8+ Heart fit');
        } else if (partnerBelief.hasGoldenFit(myHand, Suit.spades)) {
          bestStrain = Suit.spades;
          bestPower = combinedS;
          targetLevel = 4;
          recCall = '4S';
          reasons.add('Game forced: signing off in 4S with 8+ Spade fit');
        } else if (stoppers >= 3) {
          bestStrain = null;
          bestPower = combinedNT;
          targetLevel = 3;
          recCall = '3NT';
          reasons.add('Game forced: choosing 3NT (no major fit)');
        } else if (partnerBelief.hasGoldenFit(myHand, Suit.diamonds)) {
          bestStrain = Suit.diamonds;
          bestPower = combinedD;
          targetLevel = 5;
          recCall = '5D';
          reasons.add('Game forced: choosing 5D in minor fit');
        } else if (partnerBelief.hasGoldenFit(myHand, Suit.clubs)) {
          bestStrain = Suit.clubs;
          bestPower = combinedC;
          targetLevel = 5;
          recCall = '5C';
          reasons.add('Game forced: choosing 5C in minor fit');
        } else {
          bestStrain = null;
          bestPower = combinedNT;
          targetLevel = 3;
          recCall = '3NT';
          reasons.add('Game forced: selecting 3NT as best available game');
        }
      } else {
        // Signoff in partscore
        if (partnerBelief.hasGoldenFit(myHand, Suit.hearts)) {
          bestStrain = Suit.hearts;
          bestPower = combinedH;
          targetLevel = 3;
          recCall = '3H';
        } else if (partnerBelief.hasGoldenFit(myHand, Suit.spades)) {
          bestStrain = Suit.spades;
          bestPower = combinedS;
          targetLevel = 3;
          recCall = '3S';
        } else {
          bestStrain = null;
          bestPower = combinedNT;
          targetLevel = 2;
          recCall = 'Pass / 2NT';
        }
        reasons.add('Combined power below game threshold (25.0)');
      }
    }

    double probSlam = (bestPower >= 33.0) ? 0.85 : (bestPower >= 31.5 ? 0.50 : 0.05);
    double probGame = (bestPower >= 25.5) ? 0.90 : (bestPower >= 24.0 ? 0.60 : (bestPower >= 22.5 ? 0.35 : 0.10));

    return MLPartnershipEvaluation(
      myHand: myHand,
      partnerBelief: partnerBelief,
      myStrainResult: singleHand,
      combinedNotrump: double.parse(combinedNT.toStringAsFixed(1)),
      combinedSpades: double.parse(combinedS.toStringAsFixed(1)),
      combinedHearts: double.parse(combinedH.toStringAsFixed(1)),
      combinedDiamonds: double.parse(combinedD.toStringAsFixed(1)),
      combinedClubs: double.parse(combinedC.toStringAsFixed(1)),
      recommendedStrain: bestStrain,
      recommendedLevel: targetLevel,
      recommendedCall: recCall,
      probMakeGame: double.parse(probGame.toStringAsFixed(2)),
      probMakeSlam: double.parse(probSlam.toStringAsFixed(2)),
      reasoning: reasons,
    );
  }
}
