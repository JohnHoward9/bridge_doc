import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/constraints/specificity_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadGavinSystem() async {
    const relativePath = 'assets/core/systems/gavin_wolpert_2over1.yaml';
    final file = File(relativePath);
    if (!file.existsSync()) {
      throw Exception('System file not found at: ${file.absolute.path}');
    }
    final yamlStr = await file.readAsString();

    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) {
          return await f.readAsString();
        }
        return '';
      },
    );
  }

  group('Reverse Bidding Rules & Multi-Step Sequence Deal Generation', () {
    late BridgeSystem system;
    late AuctionEngine engine;
    final parser = ConstraintParser();
    final valuation = MiltonWorkValuation();
    final generator = DealGenerator();

    setUpAll(() async {
      system = await loadGavinSystem();
      engine = AuctionEngine.fromSystem(system);
    });

    test('dealBoardForSequence(["1c", "1s", "2h"]) generates authentic reverse hands for North and South', () {
      for (int i = 0; i < 15; i++) {
        final deal = generator.dealBoardForSequence(['1c', '1s', '2h'], graph: engine.graph);
        final north = deal.north;
        final south = deal.south;

        // North (Opener who reversed into 2H):
        expect(north.hcp, greaterThanOrEqualTo(16), reason: 'North reverse must have 16+ HCP');
        expect(north.clubsLength, greaterThanOrEqualTo(5), reason: 'North must have 5+ Clubs');
        expect(north.heartsLength, greaterThanOrEqualTo(4), reason: 'North must have 4+ Hearts');
        expect(north.clubsLength, greaterThan(north.heartsLength), reason: 'First suit must be longer than reverse suit (c > h)');
        expect(north.spadesLength, lessThanOrEqualTo(3), reason: 'Reverse denies 4-card spade support (3-s)');
        expect(north.isBalanced, isFalse, reason: 'Reverse hand must be unbalanced');

        // South (Responder who bid 1S):
        expect(south.hcp, greaterThanOrEqualTo(6), reason: 'South 1S response has 6+ HCP');
        expect(south.spadesLength, greaterThanOrEqualTo(4), reason: 'South 1S response has 4+ Spades');
      }
    });

    test('dealBoardForSequence 4-bid sequence ["1c", "1s", "2h", "2s"] filters both opener and responder', () {
      for (int i = 0; i < 10; i++) {
        final deal = generator.dealBoardForSequence(['1c', '1s', '2h', '2s'], graph: engine.graph);
        final north = deal.north;
        final south = deal.south;

        // North (Opener reverse):
        expect(north.hcp, greaterThanOrEqualTo(16));
        expect(north.clubsLength, greaterThanOrEqualTo(5));
        expect(north.heartsLength, greaterThanOrEqualTo(4));

        // South (Responder 2S rebid: 6-8 HCP, 5+ Spades):
        expect(south.hcp, inInclusiveRange(6, 8), reason: 'South 2S rebid shows 6-8 HCP');
        expect(south.spadesLength, greaterThanOrEqualTo(5), reason: 'South 2S rebid shows 5+ Spades');
      }
    });

    test('User screenshot hand (14 HCP, 4=4=2=3) does NOT match 2H reverse after 1c - 1s', () {
      // ♠ AQ75, ♥ AJ97, ♦ 32, ♣ K42 (14 HCP, 4-4-2-3)
      final screenshotHand = Hand.fromString('AQ75.AJ97.32.K42');
      expect(screenshotHand.hcp, equals(14));
      expect(screenshotHand.spadesLength, equals(4));
      expect(screenshotHand.heartsLength, equals(4));
      expect(screenshotHand.diamondsLength, equals(2));
      expect(screenshotHand.clubsLength, equals(3));

      final state = engine.graph.getState(['1c', '1s']);
      expect(state, isNotNull);

      // Candidate 2H is the reverse
      final reverse2H = state!.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2h');
      final rule2H = reverse2H.rule!;
      final constraint2H = parser.parse(rule2H);
      final eval2H = constraint2H.evaluate(screenshotHand, valuation);

      expect(eval2H.isMatch, isFalse, reason: '14 HCP 4=4=2=3 hand must NEVER match 2H reverse rule ($rule2H)');

      // Candidate 2S is the spade raise with 4-card support
      final raise2S = state.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2s');
      final rule2S = raise2S.rule!;
      final constraint2S = parser.parse(rule2S);
      final eval2S = constraint2S.evaluate(screenshotHand, valuation);

      expect(eval2S.isMatch, isTrue, reason: '14 HCP 4=4=2=3 hand must match 2S raise ($rule2S)');
    });

    test('16 HCP hand with 4=4=1=4 shape does NOT match 2H reverse after 1c - 1s', () {
      // ♠ AK75, ♥ AJ97, ♦ 3, ♣ KJ42 (16 HCP, 4-4-1-4)
      final hand4414 = Hand.fromString('AK75.AJ97.3.KJ42');
      expect(hand4414.hcp, equals(16));

      final state = engine.graph.getState(['1c', '1s']);
      expect(state, isNotNull);

      final reverse2H = state!.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2h');
      final constraint2H = parser.parse(reverse2H.rule!);
      final eval2H = constraint2H.evaluate(hand4414, valuation);

      expect(eval2H.isMatch, isFalse, reason: '4-4 in majors denies reverse (has 4 spades and only 4 clubs)');
    });

    test('Genuine reverse hand (17 HCP, 2=4=2=5) matches 2H reverse after 1c - 1s', () {
      // ♠ K7, ♥ AK97, ♦ 32, ♣ AK852 (17 HCP, 2-4-2-5)
      final reverseHand = Hand.fromString('K7.AK97.32.AK852');
      expect(reverseHand.hcp, equals(17));
      expect(reverseHand.clubsLength, equals(5));
      expect(reverseHand.heartsLength, equals(4));
      expect(reverseHand.spadesLength, equals(2));

      final state = engine.graph.getState(['1c', '1s']);
      expect(state, isNotNull);

      final reverse2H = state!.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2h');
      final constraint2H = parser.parse(reverse2H.rule!);
      final eval2H = constraint2H.evaluate(reverseHand, valuation);

      expect(eval2H.isMatch, isTrue, reason: '17 HCP 5-4 unbalanced hand matches 2H reverse');
    });

    test('Responder continuations over 2H reverse offer complete standard bidding structure', () {
      final state = engine.graph.getState(['1c', '1s', '2h']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('2s'), reason: 'Cheapest rebid of responder major (5-8 HCP NF)');
      expect(calls, contains('2nt'), reason: 'Natural stopper inquiry');
      expect(calls, contains('3c'), reason: 'Preference to opener clubs (5-8 HCP NF)');
      expect(calls, contains('3d'), reason: 'Fourth suit forcing (9+ HCP GF)');
      expect(calls, contains('3h'), reason: 'Invitational raise of reverse suit (8-10 HCP)');
      expect(calls, contains('3s'), reason: 'Jump rebid 6+ spades (9+ HCP GF)');
      expect(calls, contains('3nt'), reason: 'Game to play (9-11 HCP)');
      expect(calls, contains('4h'), reason: 'Game in hearts');
      expect(calls, contains('4s'), reason: 'Game in spades');

      // Test South hand matching 3S jump rebid (GF with 6+ spades):
      // ♠ AKJ873 (8), ♥ 62 (0), ♦ K4 (3), ♣ 982 (0) -> 11 HCP, 6 spades
      final southHand6S = Hand.fromString('AKJ873.62.K4.982');
      expect(southHand6S.hcp, equals(11));
      expect(southHand6S.spadesLength, equals(6));

      final node3S = state.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '3s');
      final eval3S = parser.parse(node3S.rule!).evaluate(southHand6S, valuation);
      expect(eval3S.isMatch, isTrue);

      // Test South hand matching 3H invitational raise:
      // ♠ A874 (4), ♥ K982 (3), ♦ J4 (1), ♣ T32 (0) -> 8 HCP, 4 hearts
      final southHand3H = Hand.fromString('A874.K982.J4.T32');
      expect(southHand3H.hcp, equals(8));
      expect(southHand3H.heartsLength, equals(4));

      final node3H = state.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '3h');
      final eval3H = parser.parse(node3H.rule!).evaluate(southHand3H, valuation);
      expect(eval3H.isMatch, isTrue);
    });

    test('Opener continuations over responder 2S escape include pass, 3S invite, and 4S game', () {
      final state = engine.graph.getState(['1c', '1s', '2h', '2s']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('pass'), reason: 'Opener can pass with minimum 16-17 HCP');
      expect(calls, contains('3s'), reason: 'Opener can invite with 17-18 HCP and 3 spades');
      expect(calls, contains('4s'), reason: 'Opener can bid game with 19+ HCP and 3 spades');
    });

    test('Opener continuations over responder 3C preference include pass', () {
      final state = engine.graph.getState(['1c', '1s', '2h', '3c']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('pass'), reason: 'Opener can pass 3C with minimum 16-17 HCP');
    });

    test('Opener continuations over responder 3S jump rebid enforce Game Force and control cuebids (4C, 4D, 4H, 4S, 4NT)', () {
      final state = engine.graph.getState(['1c', '1s', '2h', '3s']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, containsAll(['4c', '4d', '4h', '4s', '4nt']));
      expect(calls, isNot(contains('pass')), reason: 'Partnership is in a Game Force and cannot pass');
    });

    test('North cuebids 4d on user deal (17 HCP, 2=4=2=5) over 3S and South continues with 4h / 4NT', () {
      final northHand = Hand.fromString('KQ.AQ42.KT.QJT54');
      final southHand = Hand.fromString('AJT9743.K9.J93.A');

      final state3s = engine.graph.getState(['1c', '1s', '2h', '3s']);
      expect(state3s, isNotNull);

      final resolver = SpecificityResolver();
      final northMatches = resolver.evaluateCandidates(northHand, state3s!.candidateNodes);
      expect(northMatches.isNotEmpty, isTrue);
      expect(northMatches.first.node.call, equals('4d'), reason: 'North must cuebid 4d with Diamond King control');

      final state4d = engine.graph.getState(['1c', '1s', '2h', '3s', '4d']);
      expect(state4d, isNotNull);

      final southMatches = resolver.evaluateCandidates(southHand, state4d!.candidateNodes);
      expect(southMatches.isNotEmpty, isTrue);
      expect(southMatches.first.node.call, equals('4h'), reason: 'South must cuebid 4h with Heart King control');
    });
  });
}
