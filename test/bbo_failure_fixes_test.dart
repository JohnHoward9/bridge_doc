import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BBO Failure Fixes Verification Tests', () {
    test('Deal 81577 B:5: 21 HCP balanced with 5 spades opens 2NT', () async {
      final engine = await loadGavinEngine();

      // North: ♠AKJ42 ♥KQ7 ♦A9 ♣A86 (21 HCP, 5323 balanced)
      final north = Hand.fromString('AKJ42:KQ7:A9:A86');
      // South: ♠973 ♥8 ♦QJ6532 ♣K75 (6 HCP)
      final south = Hand.fromString('973:8:QJ6532:K75');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 81577 B:5: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '2nt', reason: 'North opens 2NT with 21 HCP balanced 5323');
    });

    test('Deal 82672 B:13: 21 HCP balanced with 5 hearts opens 2NT', () async {
      final engine = await loadGavinEngine();

      // North: ♠Q2 ♥KJ963 ♦AKT ♣AKJ (21 HCP, 2533 balanced)
      final north = Hand.fromString('Q2:KJ963:AKT:AKJ');
      // South: ♠J8 ♥QT75 ♦J952 ♣QT6 (6 HCP)
      final south = Hand.fromString('J8:QT75:J952:QT6');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 82672 B:13: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '2nt', reason: 'North opens 2NT with 21 HCP balanced 2533');
    });

    test('Deal 81774 B:23: 1NT - 2C - 2H - 2NT reaches 4S with 4-4 major opener', () async {
      final engine = await loadGavinEngine();

      // South: ♠AQ85 ♥AQ42 ♦A75 ♣T8 (16 HCP, 4-4 majors)
      final south = Hand.fromString('AQ85:AQ42:A75:T8');
      // North: ♠T642 ♥KJ ♦T943 ♣A76 (8 HCP, 4 spades)
      final north = Hand.fromString('T642:KJ:T943:A76');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81774 B:23: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1nt');
      expect(sim.auctionCalls[1].toLowerCase(), '2c');
      expect(sim.auctionCalls[2].toLowerCase(), '2h');
      expect(sim.auctionCalls[3].toLowerCase(), '2nt');
      expect(sim.auctionCalls[4].toLowerCase(), '4s', reason: 'South fits 4-4 spades over 2NT invite');
      expect(sim.finalContract.toLowerCase(), '4s');
    });

    test('Deal 81774 B:29: Responder with 5 hearts transfers with 2D instead of 3C', () async {
      final engine = await loadGavinEngine();

      // South: ♠A6 ♥J83 ♦AK3 ♣QJT32 (15 HCP balanced)
      final south = Hand.fromString('A6:J83:AK3:QJT32');
      // North: ♠4 ♥A7542 ♦J65 ♣A976 (9 HCP, 5 hearts, 4 clubs)
      final north = Hand.fromString('4:A7542:J65:A976');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81774 B:29: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1nt');
      expect(sim.auctionCalls[1].toLowerCase(), '2d', reason: 'North transfers to 2H with 5-card heart suit');
    });

    test('Deal 82680 B:21: 11 HCP with 5-5 minors avoids 4NT runaway overbid', () async {
      final engine = await loadGavinEngine();

      // North: ♠96 ♥T ♦AK973 ♣A8762 (11 HCP, 5D 5C)
      final north = Hand.fromString('96:T:AK973:A8762');
      // South: ♠A72 ♥J7532 ♦Q64 ♣43 (7 HCP)
      final south = Hand.fromString('A72:J7532:Q64:43');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 82680 B:21: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), isNot('4nt'), reason: 'North must not open 4NT with 11 HCP 5-5 minors');
      expect(sim.finalContract.toLowerCase(), isNot('5c'), reason: 'Partnership must not overbid to 5C on 18 HCP');
    });

    test('Deal 81570 B:10: Weak two feature ask over minimum passes 3H', () async {
      final engine = await loadGavinEngine();

      // North: ♠J64 ♥AQT764 ♦T73 ♣3 (7 HCP, 6 hearts)
      final north = Hand.fromString('J64:AQT764:T73:3');
      // South: ♠2 ♥J5 ♦AQJ862 ♣AT54 (12 HCP, minimum game interest)
      final south = Hand.fromString('2:J5:AQJ862:AT54');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 81570 B:10: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '2h');
      expect(sim.auctionCalls[1].toLowerCase(), '2nt');
      expect(sim.auctionCalls[2].toLowerCase(), '3h');
      expect(sim.auctionCalls[3].toLowerCase(), 'pass', reason: 'South passes 3H after North shows minimum');
      expect(sim.finalContract.toLowerCase(), '3h');
    });
  });
}
