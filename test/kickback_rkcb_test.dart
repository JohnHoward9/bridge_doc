import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Kickback RKCB (One-Over Keycard) Tests', () {
    late BridgeSystem system;
    late AuctionEngine engine;

    setUpAll(() async {
      system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      engine = AuctionEngine.fromSystem(system);
    });

    test('1H -> 2NT offers Kickback 4S for Hearts alongside standard 4NT', () {
      final state1H2NT = engine.graph.getState(['1h', '2nt']);
      expect(state1H2NT, isNotNull);

      final calls = state1H2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('4s'), reason: 'Kickback for Hearts is 4S (one step over 4H)');
      expect(calls, contains('4nt'), reason: 'Standard 4NT RKCB also available');
    });

    test('1H -> 2NT -> 4S (Kickback Hearts) exposes 4NT, 5C, 5D, 5H steps', () {
      final state4S = engine.graph.getState(['1h', '2nt', '4s']);
      expect(state4S, isNotNull);

      final stepCalls = state4S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(stepCalls, containsAll(['4nt', '5c', '5d', '5h']),
          reason: 'Steps are 4NT (1|4), 5C (0|3), 5D (2-q), 5H (2+q)');
    });

    test('Responder with 3 Key Cards bids 5C (Step 2) over 4S Kickback', () {
      // ♠82 ♥KQ75 ♦A94 ♣AJ43 -> 3 Key Cards in Hearts: ♦A, ♣A, ♥K
      final southResponder = Hand.fromString('82.KQ75.A94.AJ43');
      expect(southResponder.keyCardCount(Suit.hearts), equals(3));

      final state4S = engine.graph.getState(['1h', '2nt', '4s'])!;
      final bestBid = engine.resolver.resolveBestBid(
        southResponder,
        state4S.candidateNodes,
        fragments: system.fragments,
        activeVariables: state4S.activeVariables,
      );

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('5c'),
          reason: 'In Kickback Hearts, Step 2 (0 or 3) is 5C');
    });

    test('1H -> 2NT -> 4S -> 5C: Opener with 2 Key Cards bids 6H (Small Slam)', () {
      final state5C = engine.graph.getState(['1h', '2nt', '4s', '5c']);
      expect(state5C, isNotNull);

      final rebids = state5C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(rebids, containsAll(['5h', '6h', '7h']));

      // Opener has 2 Key Cards: ♠A, ♥A
      final northOpener = Hand.fromString('A6.AT842.KQ5.Q82');
      expect(northOpener.keyCardCount(Suit.hearts), equals(2));

      final bestBid = engine.resolver.resolveBestBid(
        northOpener,
        state5C.candidateNodes,
        fragments: system.fragments,
        activeVariables: state5C.activeVariables,
      );

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('6h'),
          reason: 'Opener knows 2 + 3 = 5 Key Cards; places 6H small slam');
    });

    test('Safe 5H Signoff: When responder shows 1 key card (4NT), opener with 2 key cards signs off in 5H', () {
      final state4NT = engine.graph.getState(['1h', '2nt', '4s', '4nt']);
      expect(state4NT, isNotNull);

      final rebids = state4NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(rebids, contains('5h'), reason: 'Safe 5H signoff preserved below 5H');

      // Opener has 2 Key Cards; combined = 1 + 2 = 3 (missing 2 keycards)
      final northOpener = Hand.fromString('A6.AT842.KQ5.Q82');
      final bestBid = engine.resolver.resolveBestBid(
        northOpener,
        state4NT.candidateNodes,
        fragments: system.fragments,
        activeVariables: state4NT.activeVariables,
      );

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('5h'),
          reason: 'Opener missing 2 key cards signs off safely in 5H');
    });

    test('Kickback for Diamonds (fKickbackDiamonds): 4H ask exposes 4S, 4NT, 5C, 5D', () {
      expect(system.fragments.containsKey('fKickbackDiamonds'), isTrue);
      final fDiamonds = system.fragments['fKickbackDiamonds']!;

      final stepCalls = fDiamonds.bids.map((b) => b.displayCall.toLowerCase()).toSet();
      expect(stepCalls, containsAll(['4s', '4nt', '5c', '5d']));

      // Hand with 3 Key Cards in Diamonds:
      // ♠A ♠K ♥A ♦K ♦Q ♦9 ♦8 ♣J ♣9 ♣4 ♣3 ♣2
      // Diamonds trump: Aces (♠A, ♥A = 2), Trump King (♦K = 1) -> 3 Key Cards in Diamonds
      final hand3KC = Hand.fromString('AK.A.KQ98.J9432');
      expect(hand3KC.keyCardCount(Suit.diamonds), equals(3));

      final bestStep = engine.resolver.resolveBestBid(
        hand3KC,
        fDiamonds.bids,
        fragments: system.fragments,
      );
      expect(bestStep, isNotNull);
      expect(bestStep!.displayCall.toLowerCase(), equals('4nt'),
          reason: 'In Kickback Diamonds, Step 2 (0 or 3) is 4NT');
    });

    test('Kickback for Clubs (fKickbackClubs): 4D ask exposes 4H, 4S, 4NT, 5C', () {
      expect(system.fragments.containsKey('fKickbackClubs'), isTrue);
      final fClubs = system.fragments['fKickbackClubs']!;

      final stepCalls = fClubs.bids.map((b) => b.displayCall.toLowerCase()).toSet();
      expect(stepCalls, containsAll(['4h', '4s', '4nt', '5c']));

      // Hand with 3 Key Cards in Clubs:
      // ♠A ♥A ♦A ♣K ♣Q ♣9 ♣8 ♣4 ♣3 ♣2 (wait, 13 cards: 1S, 1H, 1D, 10C)
      final hand3KC = Hand.fromString('A.A.A.KQ98432');
      expect(hand3KC.keyCardCount(Suit.clubs), equals(4)); // 3 Aces + Trump King = 4
      
      // Hand with 3 Key Cards: 2 Aces + Club King
      final handClubs3KC = Hand.fromString('A.A.98.KQ98432');
      expect(handClubs3KC.keyCardCount(Suit.clubs), equals(3)); // 2 Aces + Club King = 3

      final bestStep = engine.resolver.resolveBestBid(
        handClubs3KC,
        fClubs.bids,
        fragments: system.fragments,
      );
      expect(bestStep, isNotNull);
      expect(bestStep!.displayCall.toLowerCase(), equals('4s'),
          reason: 'In Kickback Clubs, Step 2 (0 or 3) is 4S');
    });
  });
}
