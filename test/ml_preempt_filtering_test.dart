import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ML Live Auction Preempt Candidate Filtering', () {
    late dynamic gavinEngine;

    setUpAll(() async {
      gavinEngine = await loadGavinEngine();
    });

    test('4th Seat Principle: Normal Weak Two in 1st seat opens 2S, but PASSES in 4th seat', () async {
      // 6-card Spade suit (7 HCP, KQ9853)
      final weakTwoSpades = Hand.fromString('KQ9853:94:84:Q42');
      final otherHand = Hand.fromString('A6:A82:T754:J875');

      // 1. First Seat (Dealer N holding weakTwoSpades): Opens 2S!
      final res1st = simulateAuction(
        north: weakTwoSpades,
        south: otherHand,
        engine: gavinEngine,
        dealer: 'N',
      );
      expect(res1st.auctionCalls.first, '2s', reason: '1st seat should open 2S with sound 6-card suit');

      // 2. Fourth Seat: Dealer N passes, E passes, S passes, W is in 4th seat
      // In simulateAuction, if North is responder and South is weakTwoSpades, but dealer is N and N passes:
      // Let's create an explicit 4th seat context:
      final context4th = BiddingStateContext(
        holding: weakTwoSpades,
        auctionHistory: [
          const AuctionEntry(seat: 'N', call: 'Pass'),
          const AuctionEntry(seat: 'E', call: 'Pass'),
          const AuctionEntry(seat: 'S', call: 'Pass'),
        ],
        activeSeat: 'W',
        explicitSeatPosition: SeatPosition.fourth,
      );

      final candidates4th = gavinEngine.graph.rootState.evaluateCandidates(
        weakTwoSpades,
        gavinEngine.resolver,
        fragments: gavinEngine.graph.system.fragments,
        context: context4th,
      );

      // 2S must be filtered out by 4th Seat Principle!
      final match2s = candidates4th.where((c) => c.call == '2s' && c.isMatch).toList();
      expect(match2s, isEmpty, reason: '4th Seat Principle must filter out 2S weak two opening');

      final bestBid4th = gavinEngine.graph.rootState.resolveBestBid(
        weakTwoSpades,
        gavinEngine.resolver,
        fragments: gavinEngine.graph.system.fragments,
        context: context4th,
      );
      expect(bestBid4th?.displayCall.toLowerCase(), 'pass', reason: 'Must pass out in 4th seat instead of preempting');
    });

    test('2nd Seat Discipline: Ragged suit rejected in 2nd seat', () async {
      // 6-card Heart suit without top honors (987654:84:K4:Q42, 5 HCP, 0 honors in hearts >= 10)
      final raggedHearts = Hand.fromString('84:987654:K4:Q42');

      // 2nd Seat context (1 prior pass)
      final context2nd = BiddingStateContext(
        holding: raggedHearts,
        auctionHistory: [
          const AuctionEntry(seat: 'N', call: 'Pass'),
        ],
        activeSeat: 'E',
        vulnerability: Vulnerability.unfavorable,
      );
      expect(context2nd.seatPosition, SeatPosition.second);

      final candidates2nd = gavinEngine.graph.rootState.evaluateCandidates(
        raggedHearts,
        gavinEngine.resolver,
        fragments: gavinEngine.graph.system.fragments,
        context: context2nd,
      );

      // 2H must be rejected in 2nd seat due to ragged suit and unfavorable vulnerability!
      final match2h = candidates2nd.where((c) => c.call == '2h' && c.isMatch).toList();
      expect(match2h, isEmpty, reason: '2nd seat with ragged suit at red must be filtered out');
    });

    test('3rd Seat Tactical Aggression: Allowed with favorable vulnerability', () async {
      // 6-card Heart suit with decent body in 3rd seat (84:KT8754:84:Q42, 7 HCP)
      final aggressiveHearts = Hand.fromString('84:KT8754:84:Q42');

      // 3rd Seat context (2 prior passes) at favorable vulnerability
      final context3rd = BiddingStateContext(
        holding: aggressiveHearts,
        auctionHistory: [
          const AuctionEntry(seat: 'N', call: 'Pass'),
          const AuctionEntry(seat: 'E', call: 'Pass'),
        ],
        activeSeat: 'S',
        vulnerability: Vulnerability.favorable,
      );
      expect(context3rd.seatPosition, SeatPosition.third);

      final candidates3rd = gavinEngine.graph.rootState.evaluateCandidates(
        aggressiveHearts,
        gavinEngine.resolver,
        fragments: gavinEngine.graph.system.fragments,
        context: context3rd,
      );

      // 2H should match in 3rd seat favorable!
      final match2h = candidates3rd.where((c) => c.call == '2h' && c.isMatch).toList();
      expect(match2h, isNotEmpty, reason: '3rd seat tactical aggression allows 2H at favorable vulnerability');
    });
  });
}
