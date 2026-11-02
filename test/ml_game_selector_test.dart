import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/evaluators/ml_game_selector.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';

void main() {
  group('ML Game Selector (3NT vs 5-Minor Arbitration) Tests', () {
    final mlVal = MLHandValuation();

    test('All 4 suits stopped with balanced shape prefers 3NT over 5-Minor', () {
      // North: ♠KQ4 ♥AJ2 ♦KQ3 ♣J654 (17 HCP, 3-3-3-4 balanced)
      final northHand = Hand.fromString('KQ4.AJ2.KQ3.J654');
      // South: ♠A85 ♥K64 ♦J984 ♣A92 (12 HCP, 3-3-4-3 balanced)
      final southHand = Hand.fromString('A85.K64.J984.A92');

      final auction = AuctionBeliefState();
      auction.recordCall(seat: 'S', call: '1D', rule: '12-14 hcp, 4+d balanced');

      final decision = mlVal.selectOptimalGame(
        northHand,
        partnerBelief: auction.partnerOf('N'),
        candidateMinor: Suit.diamonds,
      );

      expect(decision.recommendedGame, '3NT');
      expect(decision.recommendedLevel, 3);
      expect(decision.hasAllStoppers, isTrue);
      expect(decision.unstoppedSuits, isEmpty);
      expect(decision.isOpponentSuitExposed, isFalse);
    });

    test('Opponent suit bid and unstopped with 11-card minor fit prefers 5D over 3NT', () {
      // North: ♠4 ♥62 ♦AKJT98 ♣AQT4 (14 HCP, singleton spade, 6 diamonds headed by AKJ)
      final northHand = Hand.fromString('4.62.AKJT98.AQT4');
      // South: ♠763 ♥K5 ♦Q7652 ♣K83 (8 HCP, 3 spades, 5 diamonds)
      final southHand = Hand.fromString('763.K5.Q7652.K83');

      final auction = AuctionBeliefState();
      auction.recordCall(seat: 'S', call: '1D', rule: '8-10 hcp, 5+d');
      // East (RHO relative to South, or LHO relative to North) overcalled Spades
      auction.recordCall(seat: 'E', call: '1S', rule: '10+ hcp, 5+s');

      final decision = MLGameSelector.selectOptimalGame(
        myHand: northHand,
        partnerBelief: auction.get('S'),
        lhoBelief: auction.get('E'),
        candidateMinor: Suit.diamonds,
      );

      // Spades are wide open with singleton in North and 763 in South
      expect(decision.recommendedGame, '5D');
      expect(decision.recommendedStrain, Suit.diamonds);
      expect(decision.recommendedLevel, 5);
      expect(decision.isOpponentSuitExposed, isTrue);
      expect(decision.unstoppedSuits.contains(Suit.spades), isTrue);
    });

    test('Mild unbid hole with 3 stoppers and 26 combined HCP prefers 3NT for 9-trick target', () {
      // North: ♠AK3 ♥K5 ♦KJ864 ♣Q92 (16 HCP, 5 diamonds)
      final northHand = Hand.fromString('AK3.K5.KJ864.Q92');

      final auction = AuctionBeliefState();
      auction.recordCall(seat: 'S', call: '1D', rule: '10-11 hcp, 4+d');

      final decision = MLGameSelector.selectOptimalGame(
        myHand: northHand,
        partnerBelief: auction.get('S'),
        candidateMinor: Suit.diamonds,
      );

      // Hearts only have Kx (partial), but 3 suits are stopped and opponents are silent
      expect(decision.recommendedGame, '3NT');
      expect(decision.recommendedLevel, 3);
      expect(decision.isOpponentSuitExposed, isFalse);
    });

    test('Club fit with multiple unstopped major suits chooses 5C', () {
      // Hand with monster club suit, singleton heart, singleton spade:
      // North: ♠5 ♥4 ♦AK3 ♣AKJT876 (16 HCP, 7 clubs, 2 diamonds, shortness in majors)
      final northHand = Hand.fromString('5.4.AK3.AKJT876');

      final auction = AuctionBeliefState();
      // Partner showed 8-10 HCP and 3+ clubs, no major stoppers
      auction.recordCall(seat: 'S', call: '2C', rule: '8-10 hcp, 3+c');

      final decision = MLGameSelector.selectOptimalGame(
        myHand: northHand,
        partnerBelief: auction.get('S'),
        candidateMinor: Suit.clubs,
      );

      expect(decision.recommendedGame, '5C');
      expect(decision.recommendedStrain, Suit.clubs);
      expect(decision.recommendedLevel, 5);
      expect(decision.unstoppedSuits.length, greaterThanOrEqualTo(2));
    });
  });
}
