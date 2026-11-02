import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadGavinSystem() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
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

  group('5-4-2-2 Hands: 1NT vs Bidding Out Suits & Opener Reverses', () {
    late BridgeSystem system;
    late AuctionEngine engine;

    setUpAll(() async {
      system = await loadGavinSystem();
      engine = AuctionEngine.fromSystem(system);
    });

    test('Rule 1: 5-card Major and 4-card lower suit (5S-4H-2-2, 16 HCP) opens 1S, NOT 1NT', () {
      // ♠AK985 (7), ♥KQ62 (5), ♦J4 (1), ♣K2 (3) = 16 HCP
      final hand5422 = Hand.fromString('AK985:KQ62:J4:K2');
      expect(hand5422.spadesLength, equals(5));
      expect(hand5422.heartsLength, equals(4));
      expect(hand5422.hcp, equals(16));

      final rootState = engine.graph.rootState;
      final bestBid = rootState.resolveBestBid(hand5422, engine.resolver, fragments: system.fragments);

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('1s'));
      expect(bestBid.displayCall.toLowerCase(), isNot(equals('1nt')));
    });

    test('Rule 1b: 5-card Major and 4-card minor (5S-4C-2-2, 16 HCP) opens 1S, NOT 1NT', () {
      // ♠AK864 (7), ♥K3 (3), ♦A7 (4), ♣KJ82 (4) = 18 -> let's make 16 HCP: ♠AK864 (7), ♥K3 (3), ♦87 (0), ♣AJ82 (5) -> wait: 7+3+0+5 = 15; plus 10 = 16:
      // ♠AQ864 (6), ♥K3 (3), ♦K7 (3), ♣AJ82 (5) = 17 -> let's do 16 HCP: ♠AQ864 (6), ♥K3 (3), ♦Q7 (2), ♣AJ82 (5) = 16 HCP
      final hand5S4C = Hand.fromString('AQ864:K3:Q7:AJ82');
      expect(hand5S4C.spadesLength, equals(5));
      expect(hand5S4C.clubsLength, equals(4));
      expect(hand5S4C.hcp, equals(16));

      final rootState = engine.graph.rootState;
      final bestBid = rootState.resolveBestBid(hand5S4C, engine.resolver, fragments: system.fragments);

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('1s'));
    });

    test('Rule 2: 4S and 5m (4S-5C-2-2, 16 HCP) opens 1C and rebids 1S at 1-level', () {
      // ♠AK84 (7), ♥Q7 (2), ♦K2 (3), ♣AJ853 (5) -> wait: 7+2+3+5 = 17 -> let's do 16: ♠AJ84 (5), ♥Q7 (2), ♦K2 (3), ♣AK853 (7) = 17;
      // ♠AJ84 (5), ♥Q7 (2), ♦K2 (3), ♣AQ853 (6) = 16 HCP
      final hand4S5C = Hand.fromString('AJ84:Q7:K2:AQ853');
      expect(hand4S5C.spadesLength, equals(4));
      expect(hand4S5C.clubsLength, equals(5));
      expect(hand4S5C.hcp, equals(16));

      final rootState = engine.graph.rootState;
      final bestBid = rootState.resolveBestBid(hand4S5C, engine.resolver, fragments: system.fragments);

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('1c'));
      expect(bestBid.displayCall.toLowerCase(), isNot(equals('1nt')));

      // Over partner's 1H response, opener rebids 1S at the one-level (NOT a reverse)
      final state1C_1H = engine.graph.getState(['1c', '1h']);
      expect(state1C_1H, isNotNull);

      final rebid = state1C_1H!.resolveBestBid(hand4S5C, engine.resolver, fragments: system.fragments);
      expect(rebid, isNotNull);
      expect(rebid!.displayCall.toLowerCase(), equals('1s'));
    });

    test('Rule 3a: 4H and 5C (2S-4H-2D-5C) with 15 HCP opens 1NT to avoid rebid trap', () {
      // ♠K7 (3), ♥KJ84 (4), ♦Q6 (2), ♣AQ842 (6) = 15 HCP
      final hand15HCP = Hand.fromString('K7:KJ84:Q6:AQ842');
      expect(hand15HCP.spadesLength, equals(2));
      expect(hand15HCP.heartsLength, equals(4));
      expect(hand15HCP.diamondsLength, equals(2));
      expect(hand15HCP.clubsLength, equals(5));
      expect(hand15HCP.hcp, equals(15));

      final rootState = engine.graph.rootState;
      final bestBid = rootState.resolveBestBid(hand15HCP, engine.resolver, fragments: system.fragments);

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('1nt'));
    });

    test('Rule 3b: 4H and 5C (2S-4H-2D-5C) with good 17 HCP opens 1C and rebids 2H Reverse over 1S', () {
      // ♠A7 (4), ♥AK84 (7), ♦86 (0), ♣AKJ82 (8) -> wait: 4 + 7 + 0 + 8 = 19; let's do 17 HCP:
      // ♠A7 (4), ♥AK84 (7), ♦86 (0), ♣AJ942 (5) = 16;
      // ♠A7 (4), ♥AK84 (7), ♦86 (0), ♣AQ942 (6) = 17 HCP
      final hand17HCP = Hand.fromString('A7:AK84:86:AQ942');
      expect(hand17HCP.spadesLength, equals(2));
      expect(hand17HCP.heartsLength, equals(4));
      expect(hand17HCP.diamondsLength, equals(2));
      expect(hand17HCP.clubsLength, equals(5));
      expect(hand17HCP.hcp, equals(17));

      final rootState = engine.graph.rootState;
      final bestBid = rootState.resolveBestBid(hand17HCP, engine.resolver, fragments: system.fragments);

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('1c'));
      expect(bestBid.displayCall.toLowerCase(), isNot(equals('1nt')));

      // When responder bids 1S (1C - 1S), opener executes the 2H Reverse!
      final state1C_1S = engine.graph.getState(['1c', '1s']);
      expect(state1C_1S, isNotNull);

      final rebid = state1C_1S!.resolveBestBid(hand17HCP, engine.resolver, fragments: system.fragments);
      expect(rebid, isNotNull);
      expect(rebid!.displayCall.toLowerCase(), equals('2h'));
      expect(rebid.desc, contains('reverse'));
    });

    test('Continuations after 1C - 1S - 2H reverse: responder choices are available', () {
      final state1C_1S_2H = engine.graph.getState(['1c', '1s', '2h']);
      expect(state1C_1S_2H, isNotNull);

      final candidates = state1C_1S_2H!.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();

      // Check available response branches:
      // 3C (preference to clubs)
      expect(candidates, contains('3c'));
      // 2S (rebid 5+ spades)
      expect(candidates, contains('2s'));
      // 3H (raise hearts with 4-fit)
      expect(candidates, contains('3h'));
      // 2NT (stopper / minimum)
      expect(candidates, contains('2nt'));
      // 3D (fourth suit forcing)
      expect(candidates, contains('3d'));
      // 4H / 4S (games)
      expect(candidates, containsAll(['4h', '4s']));

      // Responder with 4 Spades, 6 HCP, and 3 Clubs gives preference to 3C
      // ♠Q854 (2), ♥J6 (1), ♦7532 (0), ♣K94 (3) = 6 HCP
      final respMin = Hand.fromString('Q854:J6:7532:K94');
      final respBid = state1C_1S_2H.resolveBestBid(respMin, engine.resolver, fragments: system.fragments);
      expect(respBid, isNotNull);
      expect(respBid!.displayCall.toLowerCase(), equals('3c'));

      // Responder with 5 Spades and 6 HCP rebids 2S
      final resp5S = Hand.fromString('Q8542:J6:752:K94');
      final respBid5S = state1C_1S_2H.resolveBestBid(resp5S, engine.resolver, fragments: system.fragments);
      expect(respBid5S, isNotNull);
      expect(respBid5S!.displayCall.toLowerCase(), equals('2s'));
    });
  });
}
