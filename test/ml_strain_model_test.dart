import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/evaluators/ml_strain_model.dart';

void main() {
  group('5-Strain Machine Learning Bidding Model', () {
    test('Hand AK985.QJ.KQ6.J42 (16 HCP) evaluates across 5 strains', () {
      // 16 Milton Work HCP: ♠AK (7), ♥QJ (3), ♦KQ (5), ♣J (1) = 16 HCP
      final hand = Hand.fromString('AK985:QJ:KQ6:J42');
      expect(hand.hcp, equals(16));
      expect(hand.isBalanced, isTrue);

      final strains = MLStrainBiddingModel.evaluateHand(hand);

      // Notrump power matches 15-17 1NT range
      expect(strains.notrump, greaterThanOrEqualTo(15.5));
      expect(strains.notrump, lessThanOrEqualTo(16.5));

      // Spades power is boosted due to 5-card length with top Ace-King honors
      expect(strains.spades, greaterThan(strains.notrump));
      expect(strains.spades, greaterThanOrEqualTo(17.0));

      // Clubs power is lower due to weak 3-card holding
      expect(strains.clubs, lessThan(strains.notrump));
      expect(strains.bestSuit, equals(Suit.spades));
    });

    test('Shapely hand with 6 hearts and singleton spade evaluates high in Hearts, low in NT', () {
      // ♠4 ♥AQJT85 ♦K94 ♣Q62 (12 raw HCP)
      final hand = Hand.fromString('4:AQJT85:K94:Q62');
      expect(hand.hcp, equals(12));

      final strains = MLStrainBiddingModel.evaluateHand(hand);

      // In NT: singleton spade and lacking stoppers makes hand weak
      expect(strains.notrump, lessThanOrEqualTo(12.0));

      // In Hearts: 6-card powerhouse with AQJT + singleton ruffing value
      expect(strains.hearts, greaterThanOrEqualTo(15.0));
      expect(strains.hearts - strains.notrump, greaterThanOrEqualTo(3.0));
    });

    test('Auction sequence 1nt - 2d - 2h - 3c updates South Belief State correctly', () {
      final belief = AuctionBeliefState();

      // North opens 1NT
      belief.recordCall(seat: 'N', call: '1NT', rule: '15-17 hcp, balanced');
      expect(belief.get('N').minHcp, equals(15));
      expect(belief.get('N').maxHcp, equals(17));
      expect(belief.get('N').isBalanced, isTrue);

      // South transfers with 2D
      belief.recordCall(seat: 'S', call: '2D', rule: '5+h', desc: 'Transfer to hearts');
      expect(belief.get('S').minSuitLength[Suit.hearts], equals(5));

      // North accepts transfer with 2H
      belief.recordCall(seat: 'N', call: '2H', rule: '2+h', desc: 'Forced transfer completion');

      // South bids 3C (Game Forcing, 4+ Clubs, 5+ Hearts, 10+ HCP)
      belief.recordCall(seat: 'S', call: '3C', rule: '10+ hcp, 5+h, 4+c, game_force', desc: 'Game force with 5+ hearts and 4+ clubs');
      final southState = belief.get('S');

      expect(southState.minHcp, equals(10));
      expect(southState.minSuitLength[Suit.hearts], equals(5));
      expect(southState.minSuitLength[Suit.clubs], equals(4));
      expect(southState.maxSuitLength[Suit.spades], lessThanOrEqualTo(4)); // at most 4 outside cards
      expect(southState.isGameForcing, isTrue);
    });

    test('After 1nt-2d-2h-3c, North with 3 Hearts picks 4H over 3NT', () {
      final belief = AuctionBeliefState();
      belief.recordCall(seat: 'N', call: '1NT', rule: '15-17 hcp, balanced');
      belief.recordCall(seat: 'S', call: '2D', rule: '5+h');
      belief.recordCall(seat: 'N', call: '2H', rule: '2+h');
      belief.recordCall(seat: 'S', call: '3C', rule: '10+ hcp, 5+h, 4+c, game_force');

      // North holds 3 Hearts, working honors in partner's suits (♥Q, ♣K):
      // ♠K74 (3), ♥Q93 (2), ♦AK6 (7), ♣KT82 (3) = 15 HCP
      final northHand = Hand.fromString('K74:Q93:AK6:KT82');
      expect(northHand.hcp, equals(15));
      expect(northHand.heartsLength, equals(3));

      final eval = MLStrainBiddingModel.evaluatePartnership(northHand, belief.get('S'));

      expect(eval.hasGoldenFit(Suit.hearts), isTrue); // 3 + 5 = 8 fit
      expect(eval.recommendedStrain, equals(Suit.hearts));
      expect(eval.recommendedCall, equals('4H'));
      expect(eval.probMakeGame, greaterThanOrEqualTo(0.85));
      expect(eval.reasoning.any((r) => r.contains('Heart fit confirmed')), isTrue);
    });

    test('After 1nt-2d-2h-3c, North with only 2 Hearts and solid stoppers picks 3NT', () {
      final belief = AuctionBeliefState();
      belief.recordCall(seat: 'N', call: '1NT', rule: '15-17 hcp, balanced');
      belief.recordCall(seat: 'S', call: '2D', rule: '5+h');
      belief.recordCall(seat: 'N', call: '2H', rule: '2+h');
      belief.recordCall(seat: 'S', call: '3C', rule: '10+ hcp, 5+h, 4+c, game_force');

      // North holds only 2 Hearts, but solid stoppers in ♠ and ♦:
      // ♠KQ4 (5), ♥K3 (3), ♦AQ85 (6), ♣J842 (1) = 15 HCP
      final northHand = Hand.fromString('KQ4:K3:AQ85:J842');
      expect(northHand.hcp, equals(15));
      expect(northHand.heartsLength, equals(2));

      final eval = MLStrainBiddingModel.evaluatePartnership(northHand, belief.get('S'));

      expect(eval.hasGoldenFit(Suit.hearts), isFalse); // only 7-card fit
      expect(eval.recommendedStrain, isNull); // NT
      expect(eval.recommendedCall, equals('3NT'));
      expect(eval.probMakeGame, greaterThanOrEqualTo(0.85));
      expect(eval.reasoning.any((r) => r.contains('No major fit found; 3NT chosen')), isTrue);
    });

    test('After 1nt-2d-2h-3c, North with 17 HCP and 4 Clubs detects slam potential', () {
      final belief = AuctionBeliefState();
      belief.recordCall(seat: 'N', call: '1NT', rule: '15-17 hcp, balanced');
      belief.recordCall(seat: 'S', call: '2D', rule: '5+h');
      belief.recordCall(seat: 'N', call: '2H', rule: '2+h');
      belief.recordCall(seat: 'S', call: '3C', rule: '10+ hcp, 5+h, 4+c, game_force');

      // North holds 17 HCP, 3 Hearts, 4 Clubs with prime Aces and Kings:
      // ♠A4 ♥KQ5 ♦K6 ♣AKJ82 (Wait: 4 + 5 + 3 + 8 = 20; let's do 17 HCP: ♠A4 ♥K85 ♦K6 ♣AK982 -> 4+3+3+7 = 17)
      final northHand = Hand.fromString('A4:K85:K6:AK982');
      expect(northHand.hcp, equals(17));

      final eval = MLStrainBiddingModel.evaluatePartnership(northHand, belief.get('S'));

      // Both Hearts (8-fit) and Clubs (9-fit: 5+4) are available, with combined power >= 32.5
      expect(eval.hasGoldenFit(Suit.clubs), isTrue); // 5 + 4 = 9 fit
      expect(eval.probMakeSlam, greaterThanOrEqualTo(0.40));
      expect(eval.recommendedLevel, equals(6));
    });

    test('Rule suit bound extraction parses 5h 4s, 6s, 4=h, 3-s, dist#2452 without requiring literal +', () {
      final smolen = SeatBeliefState.parseRuleSuitBounds('10+hcp 5h 4s');
      expect(smolen.minSuit[Suit.hearts], equals(5));
      expect(smolen.minSuit[Suit.spades], equals(4));

      final weakTwo = SeatBeliefState.parseRuleSuitBounds('5-10hcp 6s');
      expect(weakTwo.minSuit[Suit.spades], equals(6));

      final exact = SeatBeliefState.parseRuleSuitBounds('4=h 3-s');
      expect(exact.minSuit[Suit.hearts], equals(4));
      expect(exact.maxSuit[Suit.hearts], equals(4));
      expect(exact.maxSuit[Suit.spades], equals(3));

      final dist = SeatBeliefState.parseRuleSuitBounds('dist#2452');
      expect(dist.minSuit[Suit.spades], equals(2));
      expect(dist.minSuit[Suit.hearts], equals(4));
      expect(dist.minSuit[Suit.diamonds], equals(5));
      expect(dist.minSuit[Suit.clubs], equals(2));
    });

    test('Double-fit synergy: partnership with Spades AND Clubs has higher power than single-fit', () {
      final beliefDoubleFit = AuctionBeliefState();
      // Partner shows 5+ Spades and 4+ Clubs:
      beliefDoubleFit.recordCall(seat: 'S', call: '1S', rule: '12-21hcp 5+s');
      beliefDoubleFit.recordCall(seat: 'S', call: '2C', rule: '12-15hcp 4+c');

      final beliefSingleFit = AuctionBeliefState();
      // Partner shows 5+ Spades and 4+ Diamonds:
      beliefSingleFit.recordCall(seat: 'S', call: '1S', rule: '12-21hcp 5+s');
      beliefSingleFit.recordCall(seat: 'S', call: '2D', rule: '12-15hcp 4+d');

      // North hand has 4 Spades and 4 Clubs (double fit with 1st partner, but not 2nd!):
      // ♠KJ84 (4), ♥Q6 (2), ♦73 (0), ♣KJ842 (4) -> wait, 13 cards: 4S, 2H, 2D, 5C = 13 cards.
      // HCP: ♠KJ (4), ♥Q (2), ♣KJ (4) = 10 HCP
      final northHand = Hand.fromString('KJ84:Q6:73:KJ842');
      expect(northHand.spadesLength, equals(4));
      expect(northHand.clubsLength, equals(5));

      final evalDoubleFit = MLStrainBiddingModel.evaluatePartnership(northHand, beliefDoubleFit.get('S'));
      final evalSingleFit = MLStrainBiddingModel.evaluatePartnership(northHand, beliefSingleFit.get('S'));

      expect(beliefDoubleFit.get('S').hasDoubleFit(northHand, Suit.spades), isTrue);
      expect(beliefSingleFit.get('S').hasDoubleFit(northHand, Suit.spades), isFalse);

      // In spades: double fit in clubs provides extra ruffing/establishment trick power
      expect(evalDoubleFit.combinedSpades, greaterThan(evalSingleFit.combinedSpades));
      expect(evalDoubleFit.reasoning.any((r) => r.contains('Double-fit synergy')), isTrue);
    });
  });
}
