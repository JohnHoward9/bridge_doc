import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deal 81565 B:11 Opener Balanced Major Support Rebid Tests', () {
    test('Deal 81565 B:11: Opener 12 HCP balanced with 4-card Heart support rebids 2H over 1H', () async {
      final engine = await loadGavinEngine();

      // North: ♠A973 ♥A875 ♦A73 ♣97 (12 HCP, 4-4-3-2 balanced, 4 hearts)
      final north = Hand.fromString('A973:A875:A73:97');
      // South: ♠T8 ♥T964 ♦KJ82 ♣KT4 (7 HCP, 2-4-4-3, 4 hearts)
      final south = Hand.fromString('T8:T964:KJ82:KT4');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81565 B:11: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls.length, greaterThanOrEqualTo(4));
      expect(sim.auctionCalls[0].toLowerCase(), 'pass', reason: 'South passes with 7 HCP');
      expect(sim.auctionCalls[1].toLowerCase(), '1c', reason: 'North opens 1C');
      expect(sim.auctionCalls[2].toLowerCase(), '1h', reason: 'South responds 1H with 4 hearts');
      expect(sim.auctionCalls[3].toLowerCase(), '2h', reason: 'North must raise to 2H with 4-card heart support!');
      expect(sim.auctionCalls[4].toLowerCase(), 'pass', reason: 'South passes with 7 HCP under Spiral Raises');
      expect(sim.finalContract.toLowerCase(), '2h');
    });

    test('Negative case 1: Opener balanced with 2 hearts rebids 1NT over 1H', () async {
      final engine = await loadGavinEngine();

      // North: ♠A842 ♥K3 ♦A52 ♣QJ32 (14 HCP, 4-2-3-4 balanced, 2 hearts)
      final northBalancedClub = Hand.fromString('A842:K3:A52:QJ32');
      // South: ♠T8 ♥T964 ♦KJ82 ♣KT4 (7 HCP)
      final south = Hand.fromString('T8:T964:KJ82:KT4');

      final sim = simulateAuction(
        north: northBalancedClub,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION 2-HEARTS OPENER: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), 'pass');
      expect(sim.auctionCalls[1].toLowerCase(), '1c');
      expect(sim.auctionCalls[2].toLowerCase(), '1h');
      expect(sim.auctionCalls[3].toLowerCase(), '1nt', reason: 'Opener without 4-card support rebids 1NT');
    });

    test('Negative case 2: Opener balanced with 4 spades and 2 hearts rebids 1NT over 1H (Walsh)', () async {
      final engine = await loadGavinEngine();

      // North: ♠A842 ♥K3 ♦Q932 ♣AJ2 (14 HCP, 4-2-4-3 balanced, opens 1D)
      final northHand = Hand.fromString('A842:K3:Q932:AJ2');
      // South: ♠T8 ♥T964 ♦KJ82 ♣KT4 (7 HCP)
      final south = Hand.fromString('T8:T964:KJ82:KT4');

      final sim = simulateAuction(
        north: northHand,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION WALSH 1NT: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), 'pass');
      expect(sim.auctionCalls[1].toLowerCase(), '1d');
      expect(sim.auctionCalls[2].toLowerCase(), '1h');
      expect(sim.auctionCalls[3].toLowerCase(), '1nt', reason: 'Opener balanced 12-14 bypasses 1S to rebid 1NT under Walsh');
    });
  });
}
