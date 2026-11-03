import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/evaluators/ml_game_selector.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deal 81565 B:5 8-Card Major Fit vs 3NT Tests', () {
    final mlVal = MLHandValuation();

    test('Deal 81565 B:5 ML Game Selector prefers 4H over 3NT with 8-card Heart fit and ruffing values', () {
      // North: ♠A8 ♥K9532 ♦86 ♣AJ86 (12 HCP, 5 hearts, 2-5-2-4 shape)
      final northHand = Hand.fromString('A8.K9532.86.AJ86');
      // South: ♠J532 ♥AQ4 ♦KT53 ♣K4 (13 HCP, 3 hearts, 4 diamonds)
      final southHand = Hand.fromString('J532.AQ4.KT53.K4');

      final auction = AuctionBeliefState();
      // North opened 1H, showing 12-14 HCP and 5+ hearts
      auction.recordCall(seat: 'N', call: '1H', rule: '12-14 hcp, 5+h');
      // North rebid 2C, showing 4+ clubs (unbalanced 5-4)
      auction.recordCall(seat: 'N', call: '2C', rule: '11-18 hcp, 4+c');

      final decision = mlVal.selectBestGame(
        southHand,
        partnerBelief: auction.get('N'),
        candidateMajor: Suit.hearts,
      );

      expect(decision.recommendedGame, '4H');
      expect(decision.recommendedStrain, Suit.hearts);
      expect(decision.recommendedLevel, 4);
      expect(decision.confidence, greaterThanOrEqualTo(0.85));
    });

    test('Deal 81565 B:5 simulateAuction bids 1h 1s 2c 4h Pass to reach optimal 4H contract', () async {
      final engine = await loadGavinEngine();

      // North: ♠A8 ♥K9532 ♦86 ♣AJ86
      final north = Hand.fromString('A8:K9532:86:AJ86');
      // South: ♠J532 ♥AQ4 ♦KT53 ♣K4
      final south = Hand.fromString('J532:AQ4:KT53:K4');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 81565 B:5: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls.length, greaterThanOrEqualTo(4));
      expect(sim.auctionCalls[0].toLowerCase(), '1h');
      expect(sim.auctionCalls[1].toLowerCase(), '1s');
      expect(sim.auctionCalls[2].toLowerCase(), '2c');
      expect(sim.auctionCalls[3].toLowerCase(), '4h', reason: 'South must select 4H in the guaranteed 8-card fit!');
      expect(sim.finalContract.toLowerCase(), '4h');
    });

    test('Negative case: Responder with only 2 hearts uses 2D FSF and reaches 3NT', () async {
      final engine = await loadGavinEngine();

      // North: ♠A8 ♥K9532 ♦86 ♣AJ86 (5 hearts, 4 clubs, 2 diamonds without stopper)
      final north = Hand.fromString('A8:K9532:86:AJ86');
      // South: ♠J532 ♥A4 ♦KT53 ♣KQ4 (14 HCP, 2 hearts, diamond stopper)
      final south2 = Hand.fromString('J532:A4:KT53:KQ4');

      final sim = simulateAuction(
        north: north,
        south: south2,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION 2-HEARTS: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1h');
      expect(sim.auctionCalls[1].toLowerCase(), '1s');
      expect(sim.auctionCalls[2].toLowerCase(), '2c');
      expect(sim.auctionCalls[3].toLowerCase(), '2d', reason: 'Fourth suit forcing with game values and only 2 hearts');
      expect(sim.auctionCalls[4].toLowerCase(), '2h', reason: 'Opener waiting rebid with 5 hearts and no diamond stopper');
      expect(sim.auctionCalls[5].toLowerCase(), '3nt', reason: 'Responder bids 3NT with diamond stopper');
      expect(sim.finalContract.toLowerCase(), '3nt');
    });
  });
}
