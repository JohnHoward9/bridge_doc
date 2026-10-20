import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/constraints/hand_constraint.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
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

  group('Hand Key Card & Queen Evaluation', () {
    test('Correctly counts Key Cards (4 Aces + Trump King)', () {
      // ♠A6 ♥AT842 ♦KQ5 ♣Q82
      // Aces: ♠A, ♥A (2 Aces)
      // Trump is Hearts. Trump King: none
      final hand1 = Hand.fromString('A6.AT842.KQ5.Q82');
      expect(hand1.aceCount, equals(2));
      expect(hand1.keyCardCount(Suit.hearts), equals(2));
      expect(hand1.hasQueen(Suit.hearts), isFalse);

      // ♠82 ♥KQ75 ♦A94 ♣AJ43
      // Aces: ♦A, ♣A (2 Aces)
      // Trump King: ♥K (1 Trump King)
      // Total Key Cards: 2 + 1 = 3!
      // Trump Queen: ♥Q (has Queen)
      final hand2 = Hand.fromString('82.KQ75.A94.AJ43');
      expect(hand2.aceCount, equals(2));
      expect(hand2.keyCardCount(Suit.hearts), equals(3));
      expect(hand2.hasQueen(Suit.hearts), isTrue);
    });
  });

  group('ConstraintParser KeyCardConstraint Parsing', () {
    final parser = ConstraintParser();
    final valuation = MiltonWorkValuation();

    test('Parses kc=0|3 h and matches hand with 3 key cards', () {
      final hand3KC = Hand.fromString('82.KQ75.A94.AJ43');
      final constraint = parser.parse('kc=0|3 h');
      expect(constraint, isA<CompositeConstraint>());
      final res = constraint.evaluate(hand3KC, valuation);
      expect(res.isMatch, isTrue);

      final hand2KC = Hand.fromString('A6.AT842.KQ5.Q82');
      final res2 = constraint.evaluate(hand2KC, valuation);
      expect(res2.isMatch, isFalse);
    });

    test('Parses kc=2-q and kc=2+q correctly', () {
      final hand2NoQ = Hand.fromString('A6.AT842.KQ5.Q82');
      final cWithoutQ = parser.parse('kc=2-q h');
      expect(cWithoutQ.evaluate(hand2NoQ, valuation).isMatch, isTrue);

      final cWithQ = parser.parse('kc=2+q h');
      expect(cWithQ.evaluate(hand2NoQ, valuation).isMatch, isFalse);

      // Hand with 2 key cards and Queen of Hearts:
      // Aces: ♦A, ♣A (2 Aces). King of Hearts: none. Trump Queen: ♥Q.
      final hand2WithQ = Hand.fromString('82.QT75.A94.AJ43');
      expect(cWithQ.evaluate(hand2WithQ, valuation).isMatch, isTrue);
      expect(cWithoutQ.evaluate(hand2WithQ, valuation).isMatch, isFalse);
    });

    test('Parses kc>=2 h and kc<=1 h correctly', () {
      final hand2KC = Hand.fromString('A6.AT842.KQ5.Q82');
      final cGte2 = parser.parse('kc>=2 h');
      expect(cGte2.evaluate(hand2KC, valuation).isMatch, isTrue);

      final cLte1 = parser.parse('kc<=1 h');
      expect(cLte1.evaluate(hand2KC, valuation).isMatch, isFalse);
    });
  });

  group('Auction Tree Navigation & Variables for 1H -> 2NT -> 4NT -> 5D', () {
    late BridgeSystem system;
    late AuctionEngine engine;

    setUpAll(() async {
      system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      engine = AuctionEngine.fromSystem(system);
    });

    test('1H -> 2NT has 4NT RKCB candidate', () {
      final state1H2NT = engine.graph.getState(['1h', '2nt']);
      expect(state1H2NT, isNotNull);
      final calls = state1H2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('4nt'));
    });

    test('1H -> 2NT -> 4NT reaches fRKCBResponses with 5c, 5d, 5h, 5s', () {
      final state4NT = engine.graph.getState(['1h', '2nt', '4nt']);
      expect(state4NT, isNotNull);
      final calls = state4NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, containsAll(['5c', '5d', '5h', '5s']));
    });

    test('1H -> 2NT -> 4NT -> 5D binds M=h and reveals captain rebids 5h, 5nt, 6h, 7h', () {
      final state5D = engine.graph.getState(['1h', '2nt', '4nt', '5d']);
      expect(state5D, isNotNull);
      expect(state5D!.activeVariables['M'], equals('h'));

      final calls = state5D.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('6h'), reason: 'Small slam in agreed Hearts');
      expect(calls, contains('5h'), reason: 'Signoff in Hearts');
      expect(calls, contains('5nt'), reason: 'King ask / grand slam try');
      expect(calls, contains('7h'), reason: 'Grand slam in Hearts');
    });

    test('Opener with 2 Key Cards correctly selects 6H after partner responds 5D (0 or 3)', () {
      final northOpener = Hand.fromString('A6.AT842.KQ5.Q82');
      final state5D = engine.graph.getState(['1h', '2nt', '4nt', '5d'])!;

      final bestBid = engine.resolver.resolveBestBid(
        northOpener,
        state5D.candidateNodes,
        fragments: system.fragments,
        activeVariables: state5D.activeVariables,
      );

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('6h'), reason: 'Opener knows 2 + 3 = 5 key cards; bids 6H slam!');
    });

    test('Responder with 3 Key Cards correctly bids 5D over 4NT', () {
      final southResponder = Hand.fromString('82.KQ75.A94.AJ43');
      final state4NT = engine.graph.getState(['1h', '2nt', '4nt'])!;

      final bestBid = engine.resolver.resolveBestBid(
        southResponder,
        state4NT.candidateNodes,
        fragments: system.fragments,
        activeVariables: state4NT.activeVariables,
      );

      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('5d'), reason: '3 Key Cards in 1430 bids 5D (0 or 3)');
    });
  });
}
