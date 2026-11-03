import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deal 81570 B:4 Two-Way Checkback Tests', () {
    test('Deal 81570 B:4: 10 HCP responder with 5 spades invites with 2C-2D-2S, reaching 4S', () async {
      final engine = await loadGavinEngine();

      // North: ♠932 ♥AK53 ♦Q72 ♣AJ5 (14 HCP, 3-4-3-3 balanced)
      final north = Hand.fromString('932:AK53:Q72:AJ5');
      // South: ♠AJ876 ♥J7 ♦A53 ♣974 (10 HCP, 5-2-3-3 semi-balanced)
      final south = Hand.fromString('AJ876:J7:A53:974');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 81570 B:4: ${sim.auctionCalls.join(" ")}');
      print('FINAL CONTRACT: ${sim.finalContract}');

      expect(sim.auctionCalls.length, greaterThanOrEqualTo(6));
      expect(sim.auctionCalls[0].toLowerCase(), '1c', reason: 'North opens 1C');
      expect(sim.auctionCalls[1].toLowerCase(), '1s', reason: 'South responds 1S with 5 spades');
      expect(sim.auctionCalls[2].toLowerCase(), '1nt', reason: 'North rebids 1NT with 14 HCP balanced');
      expect(sim.auctionCalls[3].toLowerCase(), '2c', reason: 'South bids 2C puppet to 2D (invitational checkback)');
      expect(sim.auctionCalls[4].toLowerCase(), '2d', reason: 'North forced relay to 2D');
      expect(sim.auctionCalls[5].toLowerCase(), '2s', reason: 'South bids 2S inviting with 5 spades');
      expect(sim.auctionCalls[6].toLowerCase(), '4s', reason: 'North with 14 HCP and 3 spades accepts invite to 4S');
      expect(sim.finalContract.toLowerCase(), '4s');
    });

    test('Negative case: Opener with 12-13 HCP and 3 spades declines to 3S', () async {
      final engine = await loadGavinEngine();

      // North: ♠932 ♥AK53 ♦Q72 ♣K95 (12 HCP, 3 spades)
      final northMin = Hand.fromString('932:AK53:Q72:K95');
      // South: ♠AJ876 ♥J7 ♦A53 ♣974 (10 HCP, 5 spades)
      final south = Hand.fromString('AJ876:J7:A53:974');

      final sim = simulateAuction(
        north: northMin,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DECLINE 3S: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[5].toLowerCase(), '2s');
      expect(sim.auctionCalls[6].toLowerCase(), '3s', reason: 'Opener with minimum and 3-card support bids 3S');
    });

    test('Negative case: Opener with 12-13 HCP and 2 spades passes 2S', () async {
      final engine = await loadGavinEngine();

      // North: ♠92 ♥AK53 ♦Q72 ♣A952 (13 HCP, 2 spades)
      final north2S = Hand.fromString('92:AK53:Q72:A952');
      // South: ♠AJ876 ♥J7 ♦A53 ♣974 (10 HCP, 5 spades)
      final south = Hand.fromString('AJ876:J7:A53:974');

      final sim = simulateAuction(
        north: north2S,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION PASS 2S: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[5].toLowerCase(), '2s');
      expect(sim.auctionCalls[6].toLowerCase(), 'pass', reason: 'Opener with minimum and 2 spades passes 2S');
    });
  });
}
