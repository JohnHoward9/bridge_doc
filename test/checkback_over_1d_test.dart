import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BridgeSystem system;

  Future<BridgeSystem> loadSystem(String relativePath) async {
    final file = File(relativePath);
    final yamlStr = await file.readAsString();
    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
  }

  setUpAll(() async {
    system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
  });

  group('XYZ / Two-Way Checkback Differentiated Rules', () {
    test('1c - 1d - 1nt - 2d; 2h: Opener shows 4+ Hearts, South with 4 Spades and 3 Hearts bids 2s (screenshot deal)', () {
      final northHand = Hand.fromString('62.AQJ3.A73.QT52'); // 13 HCP, 2-4-3-4
      final southHand = Hand.fromString('J874.KT4.KQJ96.A'); // 14 HCP, 4-3-5-1
      final engine = AuctionEngine.fromSystem(system);

      // 1C - 1D - 1NT - 2D
      final stateOver2D = engine.graph.getState(['1c', '1d', '1nt', '2d']);
      expect(stateOver2D, isNotNull);

      // North shows 4 Hearts (2h)
      final northBid = stateOver2D!.resolveBestBid(northHand, engine.botResolver);
      expect(northBid?.call.toLowerCase(), equals('2h'));
      expect(northBid?.desc, contains('Hearts'));

      // South has 4 Spades and only 3 Hearts -> must bid 2S, NOT 4H!
      final stateOver2H = engine.graph.getState(['1c', '1d', '1nt', '2d', '2h']);
      expect(stateOver2H, isNotNull);

      final southCandidates = stateOver2H!.evaluateCandidates(southHand, engine.resolver);
      final southMatchingCalls = southCandidates.where((c) => c.isMatch).map((c) => c.call.toLowerCase()).toSet();
      expect(southMatchingCalls, contains('2s'));
      expect(southMatchingCalls, isNot(contains('4h')));

      final southBest = stateOver2H.resolveBestBid(southHand, engine.resolver);
      expect(southBest?.call.toLowerCase(), equals('2s'));
    });

    test('1c - 1d - 1nt - 2d; 2h: South with 4 Hearts bids 4h', () {
      final southHand4H = Hand.fromString('84.KJT4.KQJ96.A'); // 14 HCP, 2-4-5-2
      final engine = AuctionEngine.fromSystem(system);

      final stateOver2H = engine.graph.getState(['1c', '1d', '1nt', '2d', '2h']);
      expect(stateOver2H, isNotNull);

      // Over 2h, South holding 4 hearts bids 4h
      final southCandidates = stateOver2H!.evaluateCandidates(southHand4H, engine.resolver);
      final southMatchingCalls = southCandidates.where((c) => c.isMatch).map((c) => c.call.toLowerCase()).toSet();
      expect(southMatchingCalls, contains('4h'));

      final southBest = stateOver2H.resolveBestBid(southHand4H, engine.resolver);
      expect(southBest?.call.toLowerCase(), equals('4h'));
    });

    test('1c - 1h - 1nt - 2d; 2h: Opener shows 3-card support, South requires 5+ Hearts for 4h', () {
      final northHand = Hand.fromString('62.AJ3.AQ73.QT52'); // 13 HCP, 2-3-4-4
      final southHand5H = Hand.fromString('K84.KT874.KJ6.A'); // 13 HCP, 5 hearts
      final southHand4H = Hand.fromString('K874.KT84.KJ6.A'); // 13 HCP, 4 hearts
      final engine = AuctionEngine.fromSystem(system);

      // Over 2D, North bids 2h (3-card support)
      final stateOver2D = engine.graph.getState(['1c', '1h', '1nt', '2d']);
      expect(stateOver2D, isNotNull);
      final northBid = stateOver2D!.resolveBestBid(northHand, engine.botResolver);
      expect(northBid?.call.toLowerCase(), equals('2h'));

      final stateOver2H = engine.graph.getState(['1c', '1h', '1nt', '2d', '2h']);
      expect(stateOver2H, isNotNull);

      // South with 5 hearts bids 4h
      final south5Candidates = stateOver2H!.evaluateCandidates(southHand5H, engine.resolver);
      final south5Matching = south5Candidates.where((c) => c.isMatch).map((c) => c.call.toLowerCase()).toSet();
      expect(south5Matching, contains('4h'));

      // South with only 4 hearts does NOT bid 4h
      final south4Candidates = stateOver2H.evaluateCandidates(southHand4H, engine.resolver);
      final south4Matching = south4Candidates.where((c) => c.isMatch).map((c) => c.call.toLowerCase()).toSet();
      expect(south4Matching, isNot(contains('4h')));
    });

    test('1c - 1s - 1nt - 2d; 2s: Opener shows 3-card support, South requires 5+ Spades for 4s', () {
      final northHand = Hand.fromString('AJ3.62.AQ73.QT52'); // 13 HCP, 3-2-4-4
      final southHand5S = Hand.fromString('KT874.K84.KJ6.A'); // 13 HCP, 5 spades
      final southHand4S = Hand.fromString('KT84.K874.KJ6.A'); // 13 HCP, 4 spades
      final engine = AuctionEngine.fromSystem(system);

      // Over 2D, North bids 2s (3-card support)
      final stateOver2D = engine.graph.getState(['1c', '1s', '1nt', '2d']);
      expect(stateOver2D, isNotNull);
      final northBid = stateOver2D!.resolveBestBid(northHand, engine.botResolver);
      expect(northBid?.call.toLowerCase(), equals('2s'));

      final stateOver2S = engine.graph.getState(['1c', '1s', '1nt', '2d', '2s']);
      expect(stateOver2S, isNotNull);

      // South with 5 spades bids 4s
      final south5Candidates = stateOver2S!.evaluateCandidates(southHand5S, engine.resolver);
      final south5Matching = south5Candidates.where((c) => c.isMatch).map((c) => c.call.toLowerCase()).toSet();
      expect(south5Matching, contains('4s'));

      // South with only 4 spades does NOT bid 4s
      final south4Candidates = stateOver2S.evaluateCandidates(southHand4S, engine.resolver);
      final south4Matching = south4Candidates.where((c) => c.isMatch).map((c) => c.call.toLowerCase()).toSet();
      expect(south4Matching, isNot(contains('4s')));
    });
  });
}
