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

  group('Kokish-Kraft Weak No-Trump System Tests', () {
    late BridgeSystem system;
    late AuctionEngine engine;

    setUpAll(() async {
      system = await loadSystem('assets/core/systems/kokish_kraft_weak_nt.yaml');
      engine = AuctionEngine.fromSystem(system);
    });

    test('System compiles and includes all core Kokish-Kraft fragments', () {
      expect(system.name, contains('Kokish-Kraft'));
      expect(system.fragments.containsKey('fKokishWeak1NTResponses'), isTrue);
      expect(system.fragments.containsKey('fKokish1NTEscape'), isTrue);
      expect(system.fragments.containsKey('fKokish1CResponses'), isTrue);
      expect(system.fragments.containsKey('fKokish1DResponses'), isTrue);
      expect(system.fragments.containsKey('fKokish1HResponses'), isTrue);
      expect(system.fragments.containsKey('fKokish1SResponses'), isTrue);
      expect(system.fragments.containsKey('fKokish2CControls'), isTrue);
      expect(system.fragments.containsKey('fKokishRelay'), isTrue);
      expect(system.fragments.containsKey('fKantar3NT'), isTrue);
    });

    test('1NT Opening (11+-14 HCP): Weak balanced hand opens 1NT', () {
      // ♠K82 ♥QJ4 ♦A865 ♣Q73 = 12 HCP balanced (4333)
      final weakBalHand = Hand.fromString('K82.QJ4.A865.Q73');
      expect(weakBalHand.hcp, equals(12));
      expect(weakBalHand.isBalanced, isTrue);

      final openBid = engine.resolver.resolveBestBid(
        weakBalHand,
        engine.graph.rootState.candidateNodes,
        fragments: system.fragments,
      );

      expect(openBid, isNotNull);
      expect(openBid!.displayCall.toLowerCase(), equals('1nt'),
          reason: 'Kokish opens 11+-14 balanced with 1NT');
    });

    test('1NT Responses: Stayman, 4-suit transfers, and Texas transfers resolve', () {
      final state1NT = engine.graph.getState(['1nt']);
      expect(state1NT, isNotNull);

      final calls = state1NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, containsAll(['2c', '2d', '2h', '2s', '2nt', '3c', '3d', '4c', '4d', '4h']),
          reason: '1NT responses include Stayman, transfers to all 4 suits, CONFIT, Gerber, and Texas');

      // 1NT -> 2C -> Opener responses: 2D, 2H, 2S
      final stateStayman = engine.graph.getState(['1nt', '2c']);
      expect(stateStayman, isNotNull);
      final staymanReplies = stateStayman!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(staymanReplies, containsAll(['2d', '2h', '2s']));

      // Smolen over 2D: 3H (5S/4H) and 3S (5H/4S)
      final stateSmolen = engine.graph.getState(['1nt', '2c', '2d']);
      expect(stateSmolen, isNotNull);
      final smolenCalls = stateSmolen!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(smolenCalls, containsAll(['3h', '3s']));

      // Texas transfers: 4D -> 4H and 4H -> 4S
      final stateTexasH = engine.graph.getState(['1nt', '4d']);
      expect(stateTexasH, isNotNull);
      expect(stateTexasH!.candidateNodes.map((n) => n.displayCall.toLowerCase()), contains('4h'));

      final stateTexasS = engine.graph.getState(['1nt', '4h']);
      expect(stateTexasS, isNotNull);
      expect(stateTexasS!.candidateNodes.map((n) => n.displayCall.toLowerCase()), contains('4s'));
    });

    test('Minor Openings: 15-18 balanced hands open 1C or 1D (not 1NT)', () {
      // ♠KQ4 ♥AJ5 ♦K82 ♣QJ84 = 16 HCP balanced
      final strongBalHand = Hand.fromString('KQ4.AJ5.K82.QJ84');
      expect(strongBalHand.hcp, equals(16));
      expect(strongBalHand.isBalanced, isTrue);

      final openBid = engine.resolver.resolveBestBid(
        strongBalHand,
        engine.graph.rootState.candidateNodes,
        fragments: system.fragments,
      );

      expect(openBid, isNotNull);
      expect(openBid!.displayCall.toLowerCase(), isNot(equals('1nt')),
          reason: '16 HCP balanced cannot open weak 1NT in Kokish-Kraft');
      expect(openBid.displayCall.toLowerCase(), equals('1c'),
          reason: '3-3 in minors opens 1C');
    });

    test('1C Inverted Minors: 1C -> 2C exposes 2H* Artificial Game Force', () {
      final state1C2C = engine.graph.getState(['1c', '2c']);
      expect(state1C2C, isNotNull);

      final openerRebids = state1C2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerRebids, contains('2h'), reason: '2H is Kokish artificial FG rebid over inverted minor');
      expect(openerRebids, contains('2d'), reason: '2D is unbalanced game try');
      expect(openerRebids, contains('2nt'), reason: '2NT is strong 15-17 balanced with 3 clubs');
    });

    test('Reverse Flannery responses exist over 1C and 1D', () {
      final state1C = engine.graph.getState(['1c']);
      expect(state1C, isNotNull);
      final cCalls = state1C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(cCalls, containsAll(['2d', '2h', '2s']),
          reason: '1C has Reverse Flannery 2D (weak), 2H (INV), 2S (INV 6S/4H)');

      final state1D = engine.graph.getState(['1d']);
      expect(state1D, isNotNull);
      final dCalls = state1D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(dCalls, containsAll(['2h', '2s']),
          reason: '1D has Reverse Flannery 2H (weak-to-INV) and 2S (INV 6S/4H)');
    });

    test('Major Openings: 1H has 3C* balanced GF raise and 3D* artificial limit raise', () {
      final state1H = engine.graph.getState(['1h']);
      expect(state1H, isNotNull);

      final calls = state1H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('3c'), reason: '3C is artificial balanced GF raise');
      expect(calls, contains('3d'), reason: '3D is artificial 4-trump limit raise (3M-1)');
      expect(calls, contains('3s'), reason: '3S is strong unknown splinter (3M+1)');
      expect(calls, contains('4s'), reason: '4S is Kickback RKCB for Hearts');
    });

    test('2C Opening: Step Controls (2D=0-1, 2H=2, 2S=3+) and Kokish Relay', () {
      final state2C = engine.graph.getState(['2c']);
      expect(state2C, isNotNull);

      final responses = state2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(responses, containsAll(['2d', '2h', '2s', '2nt']),
          reason: '2C responses use step controls');

      // 2C -> 2D -> 2H* Kokish Relay
      final state2C2D = engine.graph.getState(['2c', '2d']);
      expect(state2C2D, isNotNull);
      final rebids = state2C2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(rebids, contains('2h'), reason: '2H is Kokish Relay (Hearts or 24+ balanced)');

      // 2C -> 2D -> 2H -> 2S (forced puppet)
      final stateKokishRelay = engine.graph.getState(['2c', '2d', '2h']);
      expect(stateKokishRelay, isNotNull);
      expect(stateKokishRelay!.candidateNodes.map((n) => n.displayCall.toLowerCase()), contains('2s'));
    });

    test('Kantar 3NT Opening: Solid 7/8 major with 4C King Ask and 4D Bid Major', () {
      final state3NT = engine.graph.getState(['3nt']);
      expect(state3NT, isNotNull);

      final calls = state3NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, containsAll(['4c', '4d', '4h', '4nt']),
          reason: 'Kantar 3NT responses include 4C King Ask, 4D Bid major, and 4NT Queen Ask');
    });
  });
}
