import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/services/hand_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Parameterized Two-Way Checkback (xy-1NT) & XYZ Definition Tests', () {
    test('Gavin Wolpert 2/1 (Strong NT) derives 1ntRebid* and 1ntOpening* globals from 1NTOpening: 15-17', () async {
      final yamlContent = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlContent,
        fileLoader: (path) => File(path).readAsString(),
      );

      // Verify canonical 1NT Opening globals
      expect(system.definitions['1NTOpening'], equals('15-17'));
      expect(system.definitions['1ntOpeningRange'], equals('15-17hcp'));
      expect(system.definitions['1ntOpeningInvite'], equals('8-9hcp'));
      expect(system.definitions['1ntOpeningGf'], equals('10+hcp'));

      // Verify canonical 1NT Rebid globals
      expect(system.definitions['1ntRebidRange'], equals('12-14hcp'));
      expect(system.definitions['1ntRebidInviteRange'], equals('10-11hcp'));
      expect(system.definitions['1ntRebidGfRange'], equals('12+hcp'));
      expect(system.definitions['1ntRebidMinRange'], equals('12-13hcp'));
      expect(system.definitions['1ntRebidMaxRange'], equals('14hcp'));
      expect(system.definitions['1ntRebidPassRange'], equals('7-hcp'));

      final compiler = BiddingGraphCompiler(system: system);
      final graph = compiler.compile();

      // 1. Direct pass over 1NT
      final state1NT = graph.sequenceIndex['1c:1h:1nt'];
      expect(state1NT, isNotNull);
      final nodePass = state1NT!.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == 'pass',
      );
      expect(nodePass.rule, contains('7-hcp'));

      // 2. Direct 2D GF checkback in 1c:1h:1nt
      final node2D = state1NT.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2d',
      );
      expect(node2D.rule, contains('12+hcp'));
      expect(node2D.desc, contains('12+hcp'));

      // 3. 2C puppet in 1c:1h:1nt
      final node2C = state1NT.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2c',
      );
      expect(node2C.rule, contains('10-11hcp'));
      expect(node2C.desc, contains('10-11hcp'));

      // 4. Continuations after 1c -> 1h -> 1nt -> 2c -> 2d
      final state2D = graph.sequenceIndex['1c:1h:1nt:2c:2d'];
      expect(state2D, isNotNull, reason: 'Sequence 1c:1h:1nt:2c:2d must exist in graph');

      final node2H = state2D!.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2h',
      );
      expect(node2H.rule, contains('10-11hcp'));
      expect(node2H.desc, contains('10-11hcp'));

      final node2NT = state2D.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2nt',
      );
      expect(node2NT.rule, contains('10-11hcp'));
      expect(node2NT.desc, contains('10-11hcp'));

      // 5. Opener acceptance over 2H invitation (1c:1h:1nt:2c:2d:2h)
      final state2H = graph.sequenceIndex['1c:1h:1nt:2c:2d:2h'];
      expect(state2H, isNotNull);
      final node3H = state2H!.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '3h',
      );
      expect(node3H.rule, contains('14hcp'));

      // 6. XYZ where z is a suit: 1c -> 1d -> 1h -> 2c -> 2d
      final stateXYZ2D = graph.sequenceIndex['1c:1d:1h:2c:2d'];
      expect(stateXYZ2D, isNotNull);
      final nodeXYZ2H = stateXYZ2D!.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2h',
      );
      // XYZ when z is suit must be fixed 8-10 HCP
      expect(nodeXYZ2H.rule, contains('8-10hcp'));
    });

    test('Kokish-Kraft Weak NT derives 1ntRebid* and 1ntOpening* globals from 1NTOpening: 11-14', () async {
      final yamlContent = await File('assets/core/systems/kokish_kraft_weak_nt.yaml').readAsString();
      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlContent,
        fileLoader: (path) => File(path).readAsString(),
      );

      // Verify weak NT opening globals
      expect(system.definitions['1NTOpening'], equals('11-14'));
      expect(system.definitions['1ntOpeningRange'], equals('11-14hcp'));
      expect(system.definitions['1ntOpeningInvite'], equals('11-12hcp'));
      expect(system.definitions['1ntOpeningGf'], equals('13+hcp'));

      // Verify weak NT rebid globals
      expect(system.definitions['1ntRebidRange'], equals('15-17hcp'));
      expect(system.definitions['1ntRebidInviteRange'], equals('8-10hcp'));
      expect(system.definitions['1ntRebidGfRange'], equals('11+hcp'));
      expect(system.definitions['1ntRebidMinRange'], equals('15-16hcp'));
      expect(system.definitions['1ntRebidMaxRange'], equals('17hcp'));

      final compiler = BiddingGraphCompiler(system: system);
      final graph = compiler.compile();

      // Check 1c -> 1h -> 1nt
      final state1NT = graph.sequenceIndex['1c:1h:1nt'];
      expect(state1NT, isNotNull);

      final node2C = state1NT!.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2c',
      );
      expect(node2C.rule, contains('8-10hcp'));
      expect(node2C.desc, contains('8-10hcp'));

      final node2D = state1NT.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2d',
      );
      expect(node2D.rule, contains('11+hcp'));
      expect(node2D.desc, contains('11+hcp'));

      // Check continuations after forced 2D relay
      final state2D = graph.sequenceIndex['1c:1h:1nt:2c:2d'];
      expect(state2D, isNotNull);

      final node2H = state2D!.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2h',
      );
      expect(node2H.rule, contains('8-10hcp'));
      expect(node2H.desc, contains('8-10hcp'));

      // Opener acceptance uses 17hcp in Weak NT
      final state2H = graph.sequenceIndex['1c:1h:1nt:2c:2d:2h'];
      expect(state2H, isNotNull);
      final node3H = state2H!.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '3h',
      );
      expect(node3H.rule, contains('17hcp'));
    });

    test('Gavin Wolpert strongnt matches any balanced shape (4333/4432/5332 including 5M), 2452/2425/2245, and 6322 minor', () async {
      final yamlContent = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlContent,
        fileLoader: (path) => File(path).readAsString(),
      );

      final parser = ConstraintParser(definitions: system.definitions);
      final constraint = parser.parse(r'$strongnt');
      final valuation = MiltonWorkValuation();

      // 1. Standard balanced: 4-3-3-3 with 17 HCP (3S, 3H, 3D, 4C)
      final hand4333 = HandParser.parseSingleHand('AK4.KJ3.AQ4.9842');
      expect(constraint.evaluate(hand4333, valuation).isMatch, isTrue);

      // 2. Balanced 5-3-3-2 with 5-card major (5 Spades, 15 HCP) MUST BE OPENED 1NT
      final hand5S = HandParser.parseSingleHand('AK985.QJ.KQ6.842');
      expect(constraint.evaluate(hand5S, valuation).isMatch, isTrue);

      // 3. Balanced 5-3-3-2 with 5-card Hearts (5 Hearts, 16 HCP) MUST BE OPENED 1NT
      final hand5H = HandParser.parseSingleHand('QJ.AK985.KQ6.842');
      expect(constraint.evaluate(hand5H, valuation).isMatch, isTrue);

      // 4. Semi-balanced 2-4-5-2 with 15 HCP (2S, 4H, 5D, 2C)
      final hand2452 = HandParser.parseSingleHand('AK.QJ98.KQ765.82');
      expect(constraint.evaluate(hand2452, valuation).isMatch, isTrue);

      // 5. Semi-balanced 2-4-2-5 with 16 HCP (2S, 4H, 2D, 5C)
      final hand2425 = HandParser.parseSingleHand('AK.QJ98.82.AK765');
      expect(constraint.evaluate(hand2425, valuation).isMatch, isTrue);

      // 6. Semi-balanced 2-2-4-5 with 16 HCP (2S, 2H, 4D, 5C)
      final hand2245 = HandParser.parseSingleHand('AK.82.QJ98.AK765');
      expect(constraint.evaluate(hand2245, valuation).isMatch, isTrue);

      // 7. Semi-balanced 6-3-2-2 with 6 Diamonds (2S, 3H, 6D, 2C) with 16 HCP
      final hand6D = HandParser.parseSingleHand('AK.QJ8.KQ7654.82');
      expect(constraint.evaluate(hand6D, valuation).isMatch, isTrue);

      // 8. 6-card major (6 Spades, 2-2-3, 15 HCP) should NOT match $strongnt (opens 1S)
      final hand6S = HandParser.parseSingleHand('AK9865.QJ.KQ.842');
      expect(constraint.evaluate(hand6S, valuation).isMatch, isFalse);

      // 9. 5-4 in majors (5S, 4H, 2D, 2C, 16 HCP) should NOT match $strongnt (opens 1S)
      final hand54M = HandParser.parseSingleHand('AK985.QJ98.KQ.82');
      expect(constraint.evaluate(hand54M, valuation).isMatch, isFalse);
    });
  });
}
