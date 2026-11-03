import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gavin Wolpert 1D - 1H Continuations Tests', () {
    test('1D - 1H - 2C - 2D: Responder prefers 2D with weak hand and 3+ diamonds', () async {
      final engine = await loadGavinEngine();

      // North: ♠65 ♥K4 ♦AK762 ♣KJ94 (13 HCP, 5D 4C)
      final north = Hand.fromString('65:K4:AK762:KJ94');
      // South: ♠9732 ♥QJ962 ♦K85 ♣3 (6 HCP, 5H 3D, weak)
      final south = Hand.fromString('9732:QJ962:K85:3');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION 1D-1H-2C-2D: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1d');
      expect(sim.auctionCalls[1].toLowerCase(), '1h');
      expect(sim.auctionCalls[2].toLowerCase(), '2c');
      expect(sim.auctionCalls[3].toLowerCase(), '2d', reason: 'Responder gives simple preference to 2D');
    });

    test('1D - 1H - 2C - 2H: Responder rebids 2H with weak 5+ hearts', () async {
      final engine = await loadGavinEngine();

      // North: ♠65 ♥K4 ♦AK762 ♣KJ94 (13 HCP, 5D 4C)
      final north = Hand.fromString('65:K4:AK762:KJ94');
      // South: ♠973 ♥AQJ962 ♦8 ♣862 (7 HCP, 6H, weak, singleton diamond)
      final south = Hand.fromString('973:AQJ962:8:862');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION 1D-1H-2C-2H: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1d');
      expect(sim.auctionCalls[1].toLowerCase(), '1h');
      expect(sim.auctionCalls[2].toLowerCase(), '2c');
      expect(sim.auctionCalls[3].toLowerCase(), '2h', reason: 'Responder rebids 2H with 6 hearts and diamond shortness');
    });

    test('1D - 1H - 2C - 2S: Responder bids 2S as Fourth Suit Forcing GF', () async {
      final engine = await loadGavinEngine();

      // North: ♠65 ♥K4 ♦AK762 ♣KJ94 (13 HCP, 5D 4C)
      final north = Hand.fromString('65:K4:AK762:KJ94');
      // South: ♠AJ84 ♥AK962 ♦Q85 ♣7 (14 HCP, Game Force values, 4S 5H)
      final south = Hand.fromString('AJ84:AK962:Q85:7');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION 1D-1H-2C-2S: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1d');
      expect(sim.auctionCalls[1].toLowerCase(), '1h');
      expect(sim.auctionCalls[2].toLowerCase(), '2c');
      expect(sim.auctionCalls[3].toLowerCase(), '2s', reason: 'Responder bids 2S fourth suit forcing');
    });

    test('1D - 1H - 2D - 2S: Responder bids 2S with 5H-4S F1', () async {
      final engine = await loadGavinEngine();

      // North: ♠65 ♥K4 ♦AKJ762 ♣K4 (14 HCP, 6 Diamonds)
      final north = Hand.fromString('65:K4:AKJ762:K4');
      // South: ♠KJ84 ♥AQ873 ♦85 ♣73 (10 HCP, 5H-4S, F1)
      final south = Hand.fromString('KJ84:AQ873:85:73');

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: 'N',
      );

      print('AUCTION 1D-1H-2D-2S: ${sim.auctionCalls.join(" ")}');
      expect(sim.auctionCalls[0].toLowerCase(), '1d');
      expect(sim.auctionCalls[1].toLowerCase(), '1h');
      expect(sim.auctionCalls[2].toLowerCase(), '2d');
      expect(sim.auctionCalls[3].toLowerCase(), '2s', reason: 'Responder bids new suit 2S with 5H-4S');
    });
  });
}
