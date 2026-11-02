import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/evaluators/ml_strain_model.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';

void main() {
  group('Empirical Bridge & Opponent Activity Conditioning Tests', () {
    test('AuctionBeliefState correctly detects active vs silent opponents', () {
      final silentAuction = AuctionBeliefState();
      silentAuction.recordCall(seat: 'N', call: '1NT', rule: '15-17 hcp, balanced');
      silentAuction.recordCall(seat: 'E', call: 'Pass', rule: 'Pass');
      silentAuction.recordCall(seat: 'S', call: '2C', rule: 'Stayman');
      silentAuction.recordCall(seat: 'W', call: 'p', rule: 'Pass');

      expect(silentAuction.isOpponentActive('S'), isFalse);
      expect(silentAuction.isOpponentActive('N'), isFalse);
      expect(silentAuction.isAnyOpponentActive, isFalse);

      final activeAuction = AuctionBeliefState();
      activeAuction.recordCall(seat: 'N', call: '1NT', rule: '15-17 hcp, balanced');
      activeAuction.recordCall(seat: 'E', call: '2H', rule: '5+h, 10+ hcp', desc: 'Overcall');
      activeAuction.recordCall(seat: 'S', call: 'X', rule: 'penalty');
      activeAuction.recordCall(seat: 'W', call: 'Pass');

      expect(activeAuction.isOpponentActive('S'), isTrue);
      expect(activeAuction.isOpponentActive('N'), isTrue);
      expect(activeAuction.isAnyOpponentActive, isTrue);
      // For East or West, North and South are the opponents
      expect(activeAuction.isOpponentActive('E'), isTrue);
    });

    test('Empirical bad split probabilities reflect BBO Championship dataset', () {
      final auction = AuctionBeliefState();
      auction.recordCall(seat: 'N', call: '1H', rule: '5+h');
      auction.recordCall(seat: 'E', call: 'Pass');

      // 8-card fit: silent opponents split badly (4-1 or 5-0) ~26.1%
      final silent8 = auction.opponentTrumpBadSplitProb(Suit.hearts, 8);
      expect(silent8, closeTo(0.2612, 0.001));

      // Active opponents: split risk rises to ~29.9% (+3.8%)
      auction.recordCall(seat: 'E', call: '2S', rule: '5+s');
      final active8 = auction.opponentTrumpBadSplitProb(Suit.hearts, 8);
      expect(active8, closeTo(0.2987, 0.001));
      expect(active8, greaterThan(silent8));

      // 9-card fit: 4-0 split risk rises from 5.7% to 6.6%
      final active9 = auction.opponentTrumpBadSplitProb(Suit.hearts, 9);
      expect(active9, closeTo(0.0664, 0.001));
    });

    test('SeatBeliefState.expectedSuitLengths always sums to 13.0 cards', () {
      final seat = SeatBeliefState(
        seat: 'N',
        minHcp: 15,
        maxHcp: 17,
        isBalanced: true,
        minSuitLength: {Suit.hearts: 5},
      );

      final expectedSilent = seat.expectedSuitLengths(isOpponentActive: false);
      final sumSilent = expectedSilent.values.fold(0.0, (a, b) => a + b);
      expect(sumSilent, closeTo(13.0, 0.05));

      final expectedActive = seat.expectedSuitLengths(isOpponentActive: true);
      final sumActive = expectedActive.values.fold(0.0, (a, b) => a + b);
      expect(sumActive, closeTo(13.0, 0.05));

      // Major suit mean matches empirical opener length
      expect(expectedSilent[Suit.hearts], closeTo(5.38, 0.2));
    });

    test('MLStrainBiddingModel discounts contract power when opponents are active', () {
      // South hand: ♠K74 ♥Q93 ♦AK6 ♣KT82 (15 HCP)
      final southHand = Hand.fromString('K74:Q93:AK6:KT82');
      final partnerBelief = SeatBeliefState(
        seat: 'N',
        minHcp: 10,
        maxHcp: 14,
        minSuitLength: {Suit.hearts: 5, Suit.clubs: 4},
      );

      final evalSilent = MLStrainBiddingModel.evaluatePartnership(
        southHand,
        partnerBelief,
        isOpponentActive: false,
      );

      final evalActive = MLStrainBiddingModel.evaluatePartnership(
        southHand,
        partnerBelief,
        isOpponentActive: true,
      );

      // Active opponents penalize power due to bad-split risk and defensive threats
      expect(evalActive.combinedPowerFor(Suit.hearts), lessThan(evalSilent.combinedPowerFor(Suit.hearts)));
      expect(evalActive.combinedPowerFor(null), lessThan(evalSilent.combinedPowerFor(null))); // NT
      expect(evalActive.reasoning.any((r) => r.contains('Active opponent')), isTrue);
    });

    test('MLEdgeCaseEvaluator adjusts expectation with isOpponentActive', () {
      final evaluator = MLEdgeCaseEvaluator();
      final myHand = Hand.fromString('A83:KJ9:Q74:K962'); // 13 HCP
      final partnerBelief = SeatBeliefState(
        seat: 'N',
        minHcp: 11,
        maxHcp: 12, // Marginal game invitational range (24-25 HCP combined)
      );

      final predSilent = evaluator.evaluateWithBelief(
        myHand: myHand,
        partnerBelief: partnerBelief,
        contractLevel: 3,
        strain: 'NT',
        isOpponentActive: false,
      );

      final predActive = evaluator.evaluateWithBelief(
        myHand: myHand,
        partnerBelief: partnerBelief,
        contractLevel: 3,
        strain: 'NT',
        isOpponentActive: true,
      );

      // Expected result / probability of making is more conservative when opponents bid
      expect(predActive.expectedResult, lessThanOrEqualTo(predSilent.expectedResult));
    });
  });
}
