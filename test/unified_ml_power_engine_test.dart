import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';

void main() {
  group('Unified ML Power Engine (0-37 Scale) Tests', () {
    test('Single-Hand MPI (0-37) accurately evaluates power and adjustments', () {
      // 1. Weak flat hand: 2 HCP
      final weakHand = Hand.fromString('7432:654:832:542');
      final weakMpi = MLPowerEngine.evaluateSingleHandMpi(weakHand);
      expect(weakMpi, lessThanOrEqualTo(1.0));
      expect(weakMpi, greaterThanOrEqualTo(0.0));

      // 2. Average 12 HCP balanced hand: Q543:K43:Q32:A42
      final avgHand = Hand.fromString('Q543:K43:Q32:A42');
      final avgMpi = MLPowerEngine.evaluateSingleHandMpi(avgHand);
      expect(avgMpi, inInclusiveRange(10.5, 12.5));

      // 3. Upgraded hand: 14 HCP with AQJT 5-card suit and supported 10/9
      // S:AQJT2 (7) H:KQ3 (5) D:Q92 (2) C:42 (0) -> 14 HCP upgraded to 15.5+
      final upgradeHand = Hand.fromString('AQJT2:KQ3:Q92:42');
      final upMpi = MLPowerEngine.evaluateSingleHandMpi(upgradeHand);
      expect(upMpi, greaterThanOrEqualTo(15.0));

      // 4. Powerhouse hand: 28 HCP (AKQ:AKQ:AKQ:J432)
      final monsterHand = Hand.fromString('AKQ:AKQ:AKQ:J432');
      final monsterMpi = MLPowerEngine.evaluateSingleHandMpi(monsterHand);
      expect(monsterMpi, greaterThanOrEqualTo(28.0));
      expect(monsterMpi, lessThanOrEqualTo(37.0));
    });

    test('Domain 1: Partscore vs Game Decisions (Imp Vulnerable vs Non-Vul)', () {
      // North: 15 HCP balanced (1NT)
      // South: 10 HCP with 5 Hearts and singleton Club (LTC = 7, 8-card fit)
      final north = Hand.fromString('KQ3:A42:KJ52:Q43');
      final south = Hand.fromString('982:KQ852:A432:5');

      // In Hearts (4H): Combined MPI ~ 26.5
      final vulDecision = MLPowerEngine.evaluateGameVsPartscore(
        north: north,
        south: south,
        strain: 'h',
        vuln: Vulnerability.unfavorable,
      );

      expect(vulDecision.shouldBidGame, isTrue);
      expect(vulDecision.targetContract, '4♥');
      expect(vulDecision.combinedMpi, greaterThanOrEqualTo(24.5));

      // Weak South hand (5 HCP): should stop in partscore
      final southWeak = Hand.fromString('982:Q8542:432:52');
      final partDecision = MLPowerEngine.evaluateGameVsPartscore(
        north: north,
        south: southWeak,
        strain: 'h',
        vuln: Vulnerability.none,
      );

      expect(partDecision.shouldBidGame, isFalse);
      expect(partDecision.reason, contains('stopping in partscore'));
    });

    test('Domain 2: Slam Decisions (Small Slam & Grand Slam)', () {
      // 1. Small Slam test: Combined 32+ MPI with 4 Aces, Trump King, but missing Trump Queen
      final northSlam = Hand.fromString('AKJ4:KJ3:AJ4:K32'); // 21 HCP
      final southSlam = Hand.fromString('T982:A42:KQ5:A42'); // 12 HCP, 4 Spades

      final smallSlamDec = MLPowerEngine.evaluateSlam(
        north: northSlam,
        south: southSlam,
        strain: 's',
      );

      expect(smallSlamDec.recommendation, SlamRecommendation.smallSlam);
      expect(smallSlamDec.isSlamTarget, isTrue);
      expect(smallSlamDec.controlsCount, greaterThanOrEqualTo(8));

      // 2. Grand Slam test: Combined 36+ MPI with all 5 Keycards and Trump Queen
      final northGrand = Hand.fromString('AKQ4:AK2:AKJ:AQ2'); // 28 HCP
      final southGrand = Hand.fromString('J983:Q54:Q42:K43'); // 9 HCP + 4 spades

      final grandDec = MLPowerEngine.evaluateSlam(
        north: northGrand,
        south: southGrand,
        strain: 's',
      );

      expect(grandDec.recommendation, SlamRecommendation.grandSlam);
      expect(grandDec.expectedTricks, greaterThanOrEqualTo(12.85));

      // 3. Sub-slam game signoff test
      final northGame = Hand.fromString('KQ4:KJ2:AJ4:Q432'); // 16 HCP
      final southGame = Hand.fromString('A982:Q54:842:K43'); // 10 HCP

      final gameDec = MLPowerEngine.evaluateSlam(
        north: northGame,
        south: southGame,
        strain: 's',
      );

      expect(gameDec.recommendation, SlamRecommendation.pass);
      expect(gameDec.isSlamTarget, isFalse);
    });

    test('Domain 3: 3NT vs 4M (Flat 4333 hands prefer 3NT, shortness hands prefer 4M)', () {
      // Hand A: Completely flat 4333 North and 4333 South with stopped side suits
      final northFlat = Hand.fromString('AJ42:KJ3:Q42:K42');
      final southFlat = Hand.fromString('KQ32:A42:J32:Q32');

      final flatDecision = MLPowerEngine.evaluateOptimalStrain(
        north: northFlat,
        south: southFlat,
        candidateStrains: ['nt', 's'],
      );

      // Flat hands take 9 tricks faster in NT
      expect(flatDecision.bestStrain, 'nt');
      expect(flatDecision.reason, contains('3NT is the optimal strain'));

      // Hand B: Major fit with singleton shortness in South
      final southShort = Hand.fromString('KQ32:A8542:4:Q832'); // Singleton Diamond
      final shortDecision = MLPowerEngine.evaluateOptimalStrain(
        north: northFlat,
        south: southShort,
        candidateStrains: ['nt', 's'],
      );

      // Shortness makes 4S superior for ruffing
      expect(shortDecision.bestStrain, 's');
      expect(shortDecision.reason, contains('4S is optimal'));
    });

    test('Domain 4: 3NT vs 5m (9 tricks in 3NT is superior to 11 tricks in 5m)', () {
      // North: 15 HCP with good clubs and stoppers in majors
      final north = Hand.fromString('AQ2:K32:42:KQJ32');
      // South: 10 HCP with 4 clubs and stoppers
      final south = Hand.fromString('K43:Q42:A52:T854');

      final strainDec = MLPowerEngine.evaluateOptimalStrain(
        north: north,
        south: south,
        candidateStrains: ['nt', 'c'],
      );

      // 3NT requires only 9 tricks vs 11 tricks in 5C
      expect(strainDec.bestStrain, 'nt');
      expect(strainDec.strainRatings['nt']!, greaterThan(strainDec.strainRatings['c']!));
    });

    test('Domain 5: Preempt Decisions by Seat & Vulnerability (Rule of 2, 3, and 4)', () {
      // 7-card Spade suit with 5 HCP (QJT8542:42:32:432)
      final weakSevenSpades = Hand.fromString('QJT8542:42:32:432');

      // 1. 3rd Seat Favorable (White vs Red): Most aggressive -> Should Preempt 3S!
      final fav3rd = MLPowerEngine.evaluatePreempt(
        weakSevenSpades,
        suit: Suit.spades,
        level: 3,
        seat: SeatPosition.third,
        vuln: Vulnerability.favorable,
      );
      expect(fav3rd.shouldPreempt, isTrue);
      expect(fav3rd.allowedUndertricks, 5); // Down 4 base + 1 for 3rd seat
      expect(fav3rd.recommendedCall, '3♠');

      // 2. 2nd Seat Unfavorable (Red vs White): Strict discipline -> Deficit too large, should pass!
      final ragSevenSpades = Hand.fromString('9876542:42:32:432');
      final unfav2nd = MLPowerEngine.evaluatePreempt(
        ragSevenSpades,
        suit: Suit.spades,
        level: 3,
        seat: SeatPosition.second,
        vuln: Vulnerability.unfavorable,
      );
      expect(unfav2nd.shouldPreempt, isFalse);

      // 3. 4th Seat Principle: NEVER preempt in 4th seat!
      final seat4th = MLPowerEngine.evaluatePreempt(
        weakSevenSpades,
        suit: Suit.spades,
        level: 3,
        seat: SeatPosition.fourth,
      );
      expect(seat4th.shouldPreempt, isFalse);
      expect(seat4th.reason, contains('4th Seat Principle: Never preempt'));
    });

    test('Domain 6: Defensive Actions (Power Double, Takeout Double, Unusual 2NT, Michaels, Overcall)', () {
      // 1. Power Double: 19 HCP monster hand over opponent 1H
      final monster = Hand.fromString('AKQ2:4:AKJ2:AQ32');
      final defMonster = MLPowerEngine.evaluateDefense(monster, oppCall: '1h');
      expect(defMonster.action, DefensiveAction.powerDouble);
      expect(defMonster.recommendedCall, 'Dbl');

      // 2. Takeout Double: 13 HCP with singleton Heart and 4-4-4 in unbid suits
      final takeout = Hand.fromString('KJ32:4:AJ32:KJ32');
      final defTakeout = MLPowerEngine.evaluateDefense(takeout, oppCall: '1h');
      expect(defTakeout.action, DefensiveAction.takeoutDouble);
      expect(defTakeout.recommendedCall, 'Dbl');

      // 3. Unusual 2NT: 5-5 in minors over opponent 1S
      final minors55 = Hand.fromString('4:42:KQJ32:AJ432');
      final defUnusual = MLPowerEngine.evaluateDefense(minors55, oppCall: '1s');
      expect(defUnusual.action, DefensiveAction.unusual2nt);
      expect(defUnusual.recommendedCall, '2NT');

      // 4. Michaels Cuebid: 5-5 in other major + minor over opponent 1H
      final michaels = Hand.fromString('KQJ32:4:KQJ32:42');
      final defMichaels = MLPowerEngine.evaluateDefense(michaels, oppCall: '1h');
      expect(defMichaels.action, DefensiveAction.michaels);
      expect(defMichaels.recommendedCall, '2♥');

      // 5. Simple 1-level Overcall: 11 HCP with 5 good Spades over opponent 1H
      final overcallHand = Hand.fromString('KQJ42:42:K32:432');
      final defOvercall = MLPowerEngine.evaluateDefense(overcallHand, oppCall: '1h');
      expect(defOvercall.action, DefensiveAction.overcall);
      expect(defOvercall.recommendedCall, '1♠');
    });
  });
}
