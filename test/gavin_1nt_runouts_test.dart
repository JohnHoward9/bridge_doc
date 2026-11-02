import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/constraints/specificity_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CompiledBiddingGraph graph;
  final resolver = SpecificityResolver();

  setUpAll(() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    final yamlStr = await file.readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async => File(path).existsSync() ? await File(path).readAsString() : '',
    );

    final compiler = BiddingGraphCompiler(system: system);
    graph = compiler.compile();
  });

  group('Gavin Wolpert Webinar 24: 1NT Runouts after Penalty Double (DONT)', () {
    test('1NT - (X): DONT Runout options', () {
      final state = graph.getState(['1nt', '(x)']);
      expect(state, isNotNull, reason: 'Sequence 1nt:(x) must exist in graph');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // DONT runout calls: pass (values / forcing redouble), rdbl (single suiter), 2c (clubs+higher), 2d (diamonds+major), 2h (both majors), 2s (spades)
      expect(calls, containsAll(['pass', 'rdbl', '2c', '2d', '2h', '2s']));

      // 1. Both majors 4-4+ (0-8 HCP): 2H
      // ♠ T864, ♥ J975, ♦ 83, ♣ 762 (3 HCP, 4 Spades, 4 Hearts)
      final handMajors = Hand.fromString('T864.J975.83.762');
      final matchMajors = resolver.evaluateCandidates(handMajors, state.candidateNodes);
      expect(matchMajors.first.node.call.toLowerCase(), equals('2h'),
          reason: 'Both majors bids 2H');

      // 2. Clubs and higher suit 4-4+ (0-8 HCP): 2C
      // ♠ 83, ♥ 76, ♦ K975, ♣ T8642 (4 HCP, 5 Clubs, 4 Diamonds)
      final handClubsHigher = Hand.fromString('83.76.K975.T8642');
      final matchClubsHigher = resolver.evaluateCandidates(handClubsHigher, state.candidateNodes);
      expect(matchClubsHigher.first.node.call.toLowerCase(), equals('2c'),
          reason: 'Clubs and a higher suit bids 2C');

      // 3. Diamonds and a major 4-4+ (0-8 HCP): 2D
      // ♠ 76, ♥ T864, ♦ K9752, ♣ 83 (4 HCP, 5 Diamonds, 4 Hearts)
      final handDiamondsMajor = Hand.fromString('76.T864.K9752.83');
      final matchDiamondsMajor = resolver.evaluateCandidates(handDiamondsMajor, state.candidateNodes);
      expect(matchDiamondsMajor.first.node.call.toLowerCase(), equals('2d'),
          reason: 'Diamonds and a major bids 2D');

      // 4. Values (9+ HCP, penalty interest): pass (forces opener redouble)
      // ♠ KJ82, ♥ AQ7, ♦ Q86, ♣ 762 (12 HCP)
      final handPenalty = Hand.fromString('KJ82.AQ7.Q86.762');
      final matchPenalty = resolver.evaluateCandidates(handPenalty, state.candidateNodes);
      expect(matchPenalty.first.node.call.toLowerCase(), equals('pass'),
          reason: '9+ HCP with penalty interest passes to force redouble');
    });

    test('1NT - (X) - pass: Opener forced redouble', () {
      final statePass = graph.getState(['1nt', '(x)', 'pass']);
      expect(statePass, isNotNull);
      final calls = statePass!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('rdbl'), reason: 'Opener must redouble after responder pass');
    });

    test('1NT - (X) - rdbl: Opener forced relay to 2C', () {
      final stateRdbl = graph.getState(['1nt', '(x)', 'rdbl']);
      expect(stateRdbl, isNotNull);
      final calls = stateRdbl!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('2c'), reason: 'Opener must relay to 2C after responder single-suiter redouble');
    });
  });
}
