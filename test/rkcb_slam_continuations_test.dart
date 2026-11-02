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

  group('RKCB 1430 Captain Follow-ups & 5NT Specific King Ask', () {
    test('1. Over Step 1 (1 or 4 KC): Captain signs off with <=2 KC, bids 6 with 3 KC, bids 5NT with 4 KC + Q', () {
      final stateStep1 = graph.getState(['1s', '2nt', '4nt', '5c']);
      expect(stateStep1, isNotNull, reason: 'Sequence 1s:2nt:4nt:5c must exist');
      final calls = stateStep1!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Over Step 1 (partner has 1 KC): 5s (missing 2), 6s (missing 1), 5nt (King ask), 7s (grand)
      expect(calls, containsAll(['5s', '6s', '5nt']));

      // Hand with 2 Keycards (e.g. ♠ K8642, ♥ A74, ♦ K82, ♣ K3 = 2 KC in Spades):
      // Partner has 1 KC -> Total = 3 KC (missing 2 KC) -> Signoff in 5S!
      final hand2KC = Hand.fromString('K8642.A74.K82.K3');
      final match2KC = resolver.evaluateCandidates(hand2KC, stateStep1.candidateNodes);
      expect(match2KC.first.node.call.toLowerCase(), equals('5s'),
          reason: 'Captain holding 2 KC signs off in 5S when partner has 1 KC (missing 2)');

      // Hand with 3 Keycards (e.g. ♠ AK842, ♥ A74, ♦ K82, ♣ 73 = 3 KC in Spades):
      // Partner has 1 KC -> Total = 4 KC (missing 1 KC) -> Bid 6S!
      final hand3KC = Hand.fromString('AK842.A74.K82.73');
      final match3KC = resolver.evaluateCandidates(hand3KC, stateStep1.candidateNodes);
      expect(match3KC.first.node.call.toLowerCase(), equals('6s'),
          reason: 'Captain holding 3 KC bids 6S when partner has 1 KC (missing 1)');

      // Hand with 4 Keycards + Queen (e.g. ♠ AKQ42, ♥ A74, ♦ A82, ♣ 73 = 4 KC + QS):
      // Partner has 1 KC -> Total = ALL 5 KC + Queen (all 6 controls!) -> Bid 5NT King ask!
      final hand4KCWithQ = Hand.fromString('AKQ42.A74.A82.73');
      final match4KC = resolver.evaluateCandidates(hand4KCWithQ, stateStep1.candidateNodes);
      expect(match4KC.first.node.call.toLowerCase(), equals('5nt'),
          reason: 'Captain holding 4 KC + Queen bids 5NT King ask when partner has 1 KC (all controls held)');
    });

    test('2. Over Step 2 (0 or 3 KC): Captain signs off in 5S when missing 2+ KC', () {
      final stateStep2 = graph.getState(['1s', '2nt', '4nt', '5d']);
      expect(stateStep2, isNotNull);
      final calls = stateStep2!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('5s'));

      // Hand with 3 Keycards: partner has 0 KC (since 3+3=6 > 5) -> combined = 3 KC -> MUST sign off in 5S!
      final hand3KC = Hand.fromString('AK642.A74.82.83');
      final match3KC = resolver.evaluateCandidates(hand3KC, stateStep2.candidateNodes);
      expect(match3KC.first.node.call.toLowerCase(), equals('5s'),
          reason: 'Captain signs off in 5S when partner shows 0 KC');
    });

    test('3. 5NT King Ask: Specific King responses and Grand Slam 7S', () {
      final state5NT = graph.getState(['1s', '2nt', '4nt', '5c', '5nt']);
      expect(state5NT, isNotNull, reason: 'Sequence 1s:2nt:4nt:5c:5nt must exist');
      final calls5NT = state5NT!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Specific Kings: 6C (King of Clubs), 6D (King of Diamonds), 6H (King of Hearts), 6S (no side King)
      expect(calls5NT, containsAll(['6c', '6d', '6h', '6s']));

      // Responder holding King of Clubs: bids 6C
      final handWithKC = Hand.fromString('T74.J8.AQ62.KT52');
      final matchKC = resolver.evaluateCandidates(handWithKC, state5NT.candidateNodes);
      expect(matchKC.first.node.call.toLowerCase(), equals('6c'),
          reason: 'Responder holding King of Clubs bids 6C');

      // Responder holding King of Diamonds (no King of Clubs): bids 6D
      final handWithKD = Hand.fromString('T74.J8.KQ62.T542');
      final matchKD = resolver.evaluateCandidates(handWithKD, state5NT.candidateNodes);
      expect(matchKD.first.node.call.toLowerCase(), equals('6d'),
          reason: 'Responder holding King of Diamonds (no KC) bids 6D');

      // Responder with no side Kings: bids 6S
      final handNoKings = Hand.fromString('T74.J8.AQ62.T542');
      final matchNoKings = resolver.evaluateCandidates(handNoKings, state5NT.candidateNodes);
      expect(matchNoKings.first.node.call.toLowerCase(), equals('6s'),
          reason: 'Responder with no side Kings bids 6S');

      // Captain over 6C bids 7S grand slam
      final stateOver6C = graph.getState(['1s', '2nt', '4nt', '5c', '5nt', '6c']);
      expect(stateOver6C, isNotNull);
      final callsOver6C = stateOver6C!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(callsOver6C, contains('7s'), reason: 'Captain can bid 7S over 6C');
    });
  });
}
