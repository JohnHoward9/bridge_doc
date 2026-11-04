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
      expect(sim.finalContract.toLowerCase(), '4h', reason: 'South converts to 4H with 3-card heart fit');
    });

    test('Deal 81995 B:16: Responder with 11 HCP and 3 spades does not pass 1S', () async {
      final engine = await loadGavinEngine();

      // North: ♠K8732 ♥KJ9 ♦AT85 ♣A (15 HCP, 5 spades)
      final north = Hand.fromString('K8732:KJ9:AT85:A');
      // South: ♠A95 ♥75 ♦KJ62 ♣QJ85 (11 HCP, 3 spades)
      final south = Hand.fromString('A95:75:KJ62:QJ85');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81995 B:16: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls.length, greaterThan(2), reason: 'South must not pass out 1S');
      expect(sim.finalContract.toLowerCase(), '4s', reason: 'Partnership reaches 4S with 26 combined HCP and 8-card fit');
    });

    test('Deal 81580 B:12: 1C - 1H - 1S: Responder invites in 4-4 Spades reaching 4S', () async {
      final engine = await loadGavinEngine();

      // South: ♠AJ64 ♥Q ♦9 ♣AK65432 (14 HCP, 4 spades, 7 clubs)
      final south = Hand.fromString('AJ64:Q:9:AK65432');
      // North: ♠K532 ♥KJ76 ♦Q743 ♣7 (9 HCP, 4 spades, 4 hearts)
      final north = Hand.fromString('K532:KJ76:Q743:7');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81580 B:12: ${sim.auctionCalls.join(" ")}');
      expect(sim.finalContract.toLowerCase(), contains('s'), reason: 'Partnership finds 4-4 Spade fit instead of playing 2H');
    });

    test('Deal 81995 B:27: Opener 16 HCP with 5H-5D rebids 2D over 1S', () async {
      final engine = await loadGavinEngine();

      // South: ♠A43 ♥AT742 ♦AKJT8 ♣— (16 HCP, 5H 5D)
      final south = Hand.fromString('A43:AT742:AKJT8:');
      // North: ♠KQJ2 ♥K95 ♦Q54 ♣KJ7 (15 HCP, 4 spades)
      final north = Hand.fromString('KQJ2:K95:Q54:KJ7');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81995 B:27: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls.length, greaterThan(2), reason: 'Opener must not pass 1S');
      expect(sim.finalContract.toLowerCase(), isNot('1s'), reason: 'Partnership must not stall at 1S');
    });

    test('Deal 82005 B:18: Responder with 6-card Diamonds does not pass 1C', () async {
      final engine = await loadGavinEngine();

      // North: ♠JT ♥AKJ8 ♦K82 ♣AK86 (19 HCP)
      final north = Hand.fromString('JT:AKJ8:K82:AK86');
      // South: ♠K82 ♥Q72 ♦J97643 ♣7 (6 HCP, 6 diamonds)
      final south = Hand.fromString('K82:Q72:J97643:7');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 82005 B:18: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[1].toLowerCase(), '1d', reason: 'South bids 1D with 6-card diamond suit');
      expect(sim.finalContract.toLowerCase(), isNot('1c'), reason: 'Must not pass out 1C with 25 combined HCP');
    });

    test('Deal 82060 B:8: Opener with 18 HCP unbalanced rebids 2NT over 1NT reaching game', () async {
      final engine = await loadGavinEngine();

      // South: ♠QJT65 ♥A ♦KQ6 ♣KQJ9 (18 HCP, 5 spades)
      final south = Hand.fromString('QJT65:A:KQ6:KQJ9');
      // North: ♠K92 ♥KJ9 ♦AT952 ♣T4 (11 HCP, 3 spades)
      final north = Hand.fromString('K92:KJ9:AT952:T4');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 82060 B:8: ${sim.auctionCalls.join(" ")}');
      expect(sim.finalContract.toLowerCase(), isNot('1nt'), reason: 'Opener must not pass 1NT with 18 HCP');
      expect(sim.finalContract.toLowerCase(), anyOf('4s', '3nt'), reason: 'Reaches game with 29 combined HCP');
    });

    test('Deal 81557 B:6: Opener with 6 hearts and spade void converts 3S to 4H', () async {
      final engine = await loadGavinEngine();

      // North: ♠— ♥AJT865 ♦AKJ94 ♣A2 (17 HCP, 6 hearts, 0 spades)
      final north = Hand.fromString(':AJT865:AKJ94:A2');
      // South: ♠AKJT2 ♥74 ♦— ♣JT9843 (9 HCP, 5 spades)
      final south = Hand.fromString('AKJT2:74::JT9843');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 81557 B:6: ${sim.auctionCalls.join(" ")}');
      expect(sim.finalContract.toLowerCase(), '4h', reason: 'North converts to 4H with 6-card self-sufficient hearts');
    });

    test('Deal 81558 B:14: Reversed Bart prioritizes 3-card Spade invite reaching 4S', () async {
      final engine = await loadGavinEngine();

      // South: ♠QJT62 ♥K9 ♦A ♣K9652 (13 HCP, 5 spades, 5 clubs)
      final south = Hand.fromString('QJT62:K9:A:K9652');
      // North: ♠K95 ♥JT8 ♦J3 ♣AJ743 (10 HCP, 3 spades, 5 clubs)
      final north = Hand.fromString('K95:JT8:J3:AJ743');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81558 B:14: ${sim.auctionCalls.join(" ")}');
      expect(sim.finalContract.toLowerCase(), contains('s'), reason: 'Partnership reaches Spade contract via Reversed Bart');
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

    test('Deal 82067 B:19: Opener 19 HCP with 5D-4C rebids 3C over 1S reaching game', () async {
      final engine = await loadGavinEngine();

      // North: ♠A ♥J93 ♦AKQ73 ♣AJ54 (19 HCP)
      final north = Hand.fromString('A:J93:AKQ73:AJ54');
      // South: ♠QT842 ♥K ♦J942 ♣Q83 (8 HCP)
      final south = Hand.fromString('QT842:K:J942:Q83');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 82067 B:19: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1d');
      expect(sim.auctionCalls[1].toLowerCase(), '1s');
      expect(sim.auctionCalls[2].toLowerCase(), isNot('pass'), reason: 'Opener with 19 HCP must not pass 1S');
      expect(sim.finalContract.toLowerCase(), anyOf('3nt', '4s', '5d'));
    });

    test('Deal 82583 B:4: Responder with 6 raw HCP does not pass 1H', () async {
      final engine = await loadGavinEngine();

      // South: ♠K85 ♥KQJ95 ♦K9 ♣AK9 (19 HCP)
      final south = Hand.fromString('K85:KQJ95:K9:AK9');
      // North: ♠Q973 ♥74 ♦Q82 ♣Q852 (6 raw HCP, 4 spades)
      final north = Hand.fromString('Q973:74:Q82:Q852');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 82583 B:4: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1h');
      expect(sim.auctionCalls[1].toLowerCase(), isNot('pass'), reason: 'Responder with 6 raw HCP must not pass 1H');
      expect(sim.finalContract.toLowerCase(), anyOf('3nt', '4s'));
    });

    test('Deal 81797 B:3: Weak two feature ask over minimum rebids 3S reaching 4S', () async {
      final engine = await loadGavinEngine();

      // South: ♠KJT743 ♥QJ87 ♦64 ♣3 (7 HCP, 6 spades, no outside A/K)
      final south = Hand.fromString('KJT743:QJ87:64:3');
      // North: ♠82 ♥K64 ♦AKQ3 ♣AK75 (19 HCP)
      final north = Hand.fromString('82:K64:AKQ3:AK75');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81797 B:3: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '2s');
      expect(sim.auctionCalls[1].toLowerCase(), '2nt');
      expect(sim.auctionCalls[2].toLowerCase(), '3s', reason: 'South rebids 3S showing minimum with no feature');
      expect(sim.auctionCalls[3].toLowerCase(), '4s', reason: 'North raises to 4S game');
    });

    test('Deal 81797 B:9: Weak two Vinny 2NT inquiry shows maximum good suit reaching 4S', () async {
      final engine = await loadGavinEngine();

      // North: ♠KQJ862 ♥Q ♦J2 ♣T953 (9 HCP, 6 spades with KQJ)
      final north = Hand.fromString('KQJ862:Q:J2:T953');
      // South: ♠A95 ♥A952 ♦Q84 ♣KQ7 (15 HCP, 3 spades)
      final south = Hand.fromString('A95:A952:Q84:KQ7');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION DEAL 81797 B:9: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '2s', reason: 'North opens weak two 2S');
      expect(sim.auctionCalls[1].toLowerCase(), '2nt', reason: 'South inquires with Vinny 2NT');
      expect(sim.auctionCalls[2].toLowerCase(), anyOf('3nt', '3s', '4s'), reason: 'North must not pass 2NT');
      expect(sim.finalContract.toLowerCase(), '4s', reason: 'Partnership reaches 4S game with 24 combined HCP and 9 spades');
    });

    test('Deal 81987 B:3: Preempt 3C opening and 3S major investigation reaching 4S', () async {
      final engine = await loadGavinEngine();

      // South: ♠T32 ♥QJ ♦4 ♣KJ87432 (7 HCP, 7 clubs)
      final south = Hand.fromString('T32:QJ:4:KJ87432');
      // North: ♠AQ654 ♥T65 ♦AQ8 ♣A9 (16 HCP, 5 spades)
      final north = Hand.fromString('AQ654:T65:AQ8:A9');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'S',
      );

      print('AUCTION DEAL 81987 B:3: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '3c', reason: 'South opens preempt 3C');
      expect(sim.auctionCalls[1].toLowerCase(), '3s', reason: 'North bids 3S GF');
      expect(sim.auctionCalls[2].toLowerCase(), '4s', reason: 'South raises to 4S');
    });
  });
}
