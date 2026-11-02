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

  group('Gavin Wolpert Webinar 12: Transfers after 1M (X)', () {
    test('1H - (X): Transfers and raises over 1H double', () {
      final state = graph.getState(['1h', '(x)']);
      expect(state, isNotNull, reason: 'Sequence 1h:(x) must exist in graph');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Over 1H-(X): rdbl, 1s, 1nt (clubs), 2c (diamonds), 2d (hearts constructive), 2h (weak raise), 2nt (Jordan)
      expect(calls, containsAll(['rdbl', '1s', '1nt', '2c', '2d', '2h', '2nt']));

      // 1. Constructive 3-card Heart raise (7-9 HCP): 2D transfer to Hearts
      // ♠ 82, ♥ K94, ♦ A863, ♣ 7652 (8 HCP, 3 Hearts)
      final handConstructive = Hand.fromString('82.K94.A863.7652');
      final matchConstructive = resolver.evaluateCandidates(handConstructive, state.candidateNodes);
      expect(matchConstructive.first.node.call.toLowerCase(), equals('2d'),
          reason: '7-9 HCP with 3 Hearts bids 2D (transfer to 2H)');

      // 2. Weak 3-card Heart raise (4-6 HCP): 2H direct
      // ♠ 82, ♥ K94, ♦ Q643, ♣ 7652 (5 HCP, 3 Hearts)
      final handWeak = Hand.fromString('82.K94.Q643.7652');
      final matchWeak = resolver.evaluateCandidates(handWeak, state.candidateNodes);
      expect(matchWeak.first.node.call.toLowerCase(), equals('2h'),
          reason: '4-6 HCP with 3 Hearts bids 2H directly');

      // 3. Transfer to Clubs (6-10 HCP, 5+ Clubs): 1NT
      // ♠ 82, ♥ 94, ♦ K63, ♣ KJT72 (7 HCP, 5 Clubs, 2 Hearts)
      final handClubs = Hand.fromString('82.94.K63.KJT72');
      final matchClubs = resolver.evaluateCandidates(handClubs, state.candidateNodes);
      expect(matchClubs.first.node.call.toLowerCase(), equals('1nt'),
          reason: '6-10 HCP with 5+ Clubs bids 1NT (transfer to Clubs)');

      // 4. Transfer to Diamonds (6-10 HCP, 5+ Diamonds): 2C
      // ♠ 82, ♥ 94, ♦ KJT72, ♣ K63 (7 HCP, 5 Diamonds, 2 Hearts)
      final handDiamonds = Hand.fromString('82.94.KJT72.K63');
      final matchDiamonds = resolver.evaluateCandidates(handDiamonds, state.candidateNodes);
      expect(matchDiamonds.first.node.call.toLowerCase(), equals('2c'),
          reason: '6-10 HCP with 5+ Diamonds bids 2C (transfer to Diamonds)');
    });

    test('1S - (X): Transfers and raises over 1S double', () {
      final state = graph.getState(['1s', '(x)']);
      expect(state, isNotNull, reason: 'Sequence 1s:(x) must exist in graph');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Over 1S-(X): rdbl, 1nt (clubs), 2c (diamonds), 2d (hearts), 2h (spades constructive), 2s (weak raise), 2nt (Jordan)
      expect(calls, containsAll(['rdbl', '1nt', '2c', '2d', '2h', '2s', '2nt']));

      // 1. Constructive 3-card Spade raise (7-9 HCP): 2H transfer to Spades
      // ♠ K94, ♥ 82, ♦ A863, ♣ 7652 (8 HCP, 3 Spades)
      final handConstructive = Hand.fromString('K94.82.A863.7652');
      final matchConstructive = resolver.evaluateCandidates(handConstructive, state.candidateNodes);
      expect(matchConstructive.first.node.call.toLowerCase(), equals('2h'),
          reason: '7-9 HCP with 3 Spades bids 2H (transfer to 2S)');

      // 2. Weak 3-card Spade raise (4-6 HCP): 2S direct
      // ♠ K94, ♥ 82, ♦ Q643, ♣ 7652 (5 HCP, 3 Spades)
      final handWeak = Hand.fromString('K94.82.Q643.7652');
      final matchWeak = resolver.evaluateCandidates(handWeak, state.candidateNodes);
      expect(matchWeak.first.node.call.toLowerCase(), equals('2s'),
          reason: '4-6 HCP with 3 Spades bids 2S directly');

      // 3. Transfer to Hearts (6-10 HCP, 5+ Hearts): 2D
      // ♠ 94, ♥ KJT72, ♦ K63, ♣ 82 (7 HCP, 5 Hearts, 2 Spades)
      final handHearts = Hand.fromString('94.KJT72.K63.82');
      final matchHearts = resolver.evaluateCandidates(handHearts, state.candidateNodes);
      expect(matchHearts.first.node.call.toLowerCase(), equals('2d'),
          reason: '6-10 HCP with 5+ Hearts bids 2D (transfer to Hearts)');
    });
  });
}
