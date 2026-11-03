import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deal 81574 B:17 Expectation-Based Effective HCP & Auction Tests', () {
    test('South hand expectation bonus elevates 9 raw HCP to >= 12.5 Eff HCP', () {
      final south = Hand.fromString('AQ86:98653:KT87:');
      expect(south.hcp, 9);
      expect(south.shortestSuitLength, 0); // Club void
      expect(south.spadesLength, 4);
      expect(south.heartsLength, 5);
      expect(south.diamondsLength, 4);

      // 1. Standalone context in constructive auction
      final contextPrior = BiddingStateContext(
        holding: south,
        auctionHistory: [
          AuctionEntry(seat: 'N', call: '1D'),
          AuctionEntry(seat: 'E', call: 'Pass'),
          AuctionEntry(seat: 'S', call: '1H'),
          AuctionEntry(seat: 'W', call: 'Pass'),
          AuctionEntry(seat: 'N', call: '1NT'),
          AuctionEntry(seat: 'E', call: 'Pass'),
        ],
        activeSeat: 'S',
      );

      print('South Prior Expectation Bonus: ${contextPrior.expectationBonus}');
      print('South Prior Effective HCP: ${contextPrior.effectiveHcp}');
      expect(contextPrior.expectationBonus, greaterThanOrEqualTo(3.5));
      expect(contextPrior.effectiveHcp, greaterThanOrEqualTo(12.5));

      // 2. Posterior context with agreed Spades
      final contextPosterior = BiddingStateContext(
        holding: south,
        auctionHistory: [
          AuctionEntry(seat: 'N', call: '1D'),
          AuctionEntry(seat: 'S', call: '1H'),
          AuctionEntry(seat: 'N', call: '1NT'),
          AuctionEntry(seat: 'S', call: '2D'),
          AuctionEntry(seat: 'N', call: '2S'),
        ],
        activeSeat: 'S',
        agreedTrump: Suit.spades,
      );

      print('South Posterior Effective HCP (with 4S fit): ${contextPosterior.effectiveHcp}');
      expect(contextPosterior.expectationBonus, greaterThanOrEqualTo(3.5));
      expect(contextPosterior.effectiveHcp, greaterThanOrEqualTo(13.0));
    });

    test('Deal 81574 B:17 Auction reaches 4S via Checkback Stayman', () async {
      final engine = await loadGavinEngine();

      // North: ♠K953 ♥KJ ♦A652 ♣K92 (14 HCP, 4-2-4-3 balanced)
      final north = Hand.fromString('K953:KJ:A652:K92');
      // South: ♠AQ86 ♥98653 ♦KT87 ♣— (9 HCP, 4-5-4-0 with club void)
      final south = Hand.fromString('AQ86:98653:KT87:');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 81574 B:17: ${sim.auctionCalls.join(" ")}');
      print('FINAL CONTRACT: ${sim.finalContract}');

      expect(sim.auctionCalls.length, greaterThanOrEqualTo(6));
      expect(sim.auctionCalls[0].toLowerCase(), '1d', reason: 'North opens 1D');
      expect(sim.auctionCalls[1].toLowerCase(), '1h', reason: 'South responds 1H with 5 hearts');
      expect(sim.auctionCalls[2].toLowerCase(), '1nt', reason: 'North rebids 1NT with 12-14 balanced');
      expect(sim.auctionCalls[3].toLowerCase(), '2d', reason: 'South bids 2D Game-Forcing Checkback');
      expect(sim.auctionCalls[4].toLowerCase(), '2s', reason: 'North reveals 4-card spade suit');
      expect(sim.auctionCalls[5].toLowerCase(), '4s', reason: 'South raises to 4S game');
      expect(sim.finalContract.toLowerCase(), '4s');
    });
  });
}
