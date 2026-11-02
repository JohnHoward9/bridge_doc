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

  group('Gavin Wolpert Fourth Suit Forcing (FSF / FSGF) Tests', () {
    test('1. Auction 1C - 1S - 2H - 3D (FSF): Opener priorities over 3D', () {
      final state = graph.sequenceIndex['1c:1s:2h:3d'];
      expect(state, isNotNull, reason: 'Sequence 1c:1s:2h:3d must exist');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Opener options: 3S (3-card spade support), 3NT (diamond stopper), 3H (5+ hearts), 4C (6+ clubs)
      expect(calls, containsAll(['3s', '3nt', '3h', '4c']));
      expect(calls, isNot(contains('pass')), reason: 'Auction is in a Game Force');

      // Hand A: Opener has 3-card Spade support (Priority 1)
      // ♠ K75, ♥ AQ42, ♦ 83, ♣ AKJ5 (16 HCP, 3=4=2=4)
      final handWithSpades = Hand.fromString('K75.AQ42.83.AKJ5');
      final matchesA = resolver.evaluateCandidates(handWithSpades, state.candidateNodes);
      expect(matchesA.first.node.call, equals('3s'), reason: '3-card major support has priority 1');

      // Hand B: Opener has Diamond stopper and no 3 spades (Priority 2)
      // ♠ 75, ♥ AQ42, ♦ KJ, ♣ AKJ54 (18 HCP, 2=4=2=5)
      final handWithDiamondStopper = Hand.fromString('75.AQ42.KJ.AKJ54');
      final matchesB = resolver.evaluateCandidates(handWithDiamondStopper, state.candidateNodes);
      expect(matchesB.first.node.call, equals('3nt'), reason: '3NT with stopper has priority 2');

      // Hand C: Opener has 5+ Hearts and no stopper (Priority 3)
      // ♠ Q5, ♥ AK942, ♦ 83, ♣ AKJ5 (17 HCP, 2=5=2=4)
      final handWith5Hearts = Hand.fromString('Q5.AK942.83.AKJ5');
      final matchesC = resolver.evaluateCandidates(handWith5Hearts, state.candidateNodes);
      expect(matchesC.first.node.call, equals('3h'), reason: 'Rebidding 5+ hearts has priority 3');
    });

    test('2. Auction 1D - 1S - 2C - 2H (FSF): Non-reverse minor auction', () {
      final state = graph.sequenceIndex['1d:1s:2c:2h'];
      expect(state, isNotNull, reason: 'Sequence 1d:1s:2c:2h must exist');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      expect(calls, containsAll(['2s', '2nt', '3c', '3d']));
      expect(calls, isNot(contains('pass')), reason: 'FSF is Game Forcing');

      // Opener with 3 spades -> 2S (Priority 1)
      // ♠ K75, ♥ 83, ♦ AQJ54, ♣ J5 (11 HCP, 3=2=5=3)
      final opener3s = Hand.fromString('K75.83.AQJ54.J5');
      final matches1 = resolver.evaluateCandidates(opener3s, state.candidateNodes);
      expect(matches1.first.node.call, equals('2s'), reason: 'Priority 1: 3-card spade support');

      // Opener with Heart stopper (Kx, 13 HCP) -> 2NT (Priority 2)
      // ♠ K5, ♥ K8, ♦ QJ954, ♣ KJ5 (13 HCP, 2=2=5=4) -> wait, K=3, K=3, QJ=3, KJ=4 = 13 HCP, 2+2+5+3=12 cards, add 4 to clubs: KJ54 (13 cards)
      final openerStopper = Hand.fromString('K5.K8.QJ954.KJ54');
      final matches2 = resolver.evaluateCandidates(openerStopper, state.candidateNodes);
      expect(matches2.first.node.call, equals('2nt'), reason: 'Priority 2: 2NT with stopper');
    });

    test('3. Auction 1H - 1S - 2C - 2D (FSF): Major-minor two-suited auction', () {
      final state = graph.sequenceIndex['1h:1s:2c:2d'];
      expect(state, isNotNull, reason: 'Sequence 1h:1s:2c:2d must exist');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      expect(calls, containsAll(['2s', '2nt', '2h', '3c']));
      expect(calls, isNot(contains('pass')), reason: 'FSF is Game Forcing');

      // Opener with 3 spades -> 2S (Priority 1)
      // ♠ K75, ♥ AQ942, ♦ 83, ♣ KJ3 (13 HCP, 3=5=2=3, 13 cards)
      final opener3s = Hand.fromString('K75.AQ942.83.KJ3');
      final matches1 = resolver.evaluateCandidates(opener3s, state.candidateNodes);
      expect(matches1.first.node.call, equals('2s'), reason: 'Priority 1: 3-card spade support');

      // Opener with Diamond stopper (QJ, 12 HCP) -> 2NT (Priority 2)
      // ♠ 75, ♥ KQ942, ♦ QJ, ♣ KJ54 (12 HCP, 2=5=2=4, 13 cards)
      final openerStopper = Hand.fromString('75.KQ942.QJ.KJ54');
      final matches2 = resolver.evaluateCandidates(openerStopper, state.candidateNodes);
      expect(matches2.first.node.call, equals('2nt'), reason: 'Priority 2: 2NT with stopper');

      // Opener with 6 hearts and no diamond stopper -> 2H (Priority 3)
      // ♠ Q5, ♥ AK9842, ♦ 83, ♣ KJ4 (13 HCP, 2=6=2=3, 13 cards)
      final opener6h = Hand.fromString('Q5.AK9842.83.KJ4');
      final matches3 = resolver.evaluateCandidates(opener6h, state.candidateNodes);
      expect(matches3.first.node.call, equals('2h'), reason: 'Priority 3: Rebid 6-card major');
    });

    test('4. Auction 1C - 1H - 2D - 2S (FSF): Opener priorities over 2S', () {
      final state = graph.sequenceIndex['1c:1h:2d:2s'];
      expect(state, isNotNull, reason: 'Sequence 1c:1h:2d:2s must exist');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      expect(calls, containsAll(['3h', '2nt', '3c', '3d']));
      expect(calls, isNot(contains('pass')), reason: 'FSF is Game Forcing');

      // Opener with 3 hearts -> 3H (Priority 1)
      // ♠ 83, ♥ KQ5, ♦ AQ75, ♣ AKJ5 (17 HCP, 2=3=4=4, 13 cards)
      final opener3h = Hand.fromString('83.KQ5.AQ75.AKJ5');
      final matches1 = resolver.evaluateCandidates(opener3h, state.candidateNodes);
      expect(matches1.first.node.call, equals('3h'), reason: 'Priority 1: 3-card heart support');

      // Opener with Spade stopper (Kx, 17 HCP) -> 2NT (Priority 2)
      // ♠ KJ, ♥ 95, ♦ AJ75, ♣ AKJ54 (17 HCP, 2=2=4=5, 13 cards)
      final openerStopper = Hand.fromString('KJ.95.AJ75.AKJ54');
      final matches2 = resolver.evaluateCandidates(openerStopper, state.candidateNodes);
      expect(matches2.first.node.call, equals('2nt'), reason: 'Priority 2: 2NT with stopper');
    });

    test('5. Auction 1H - 1S - 2D - 3C (FSF): Opener priorities over 3C', () {
      final state = graph.sequenceIndex['1h:1s:2d:3c'];
      expect(state, isNotNull, reason: 'Sequence 1h:1s:2d:3c must exist');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      expect(calls, containsAll(['3s', '3nt', '3h', '3d']));
      expect(calls, isNot(contains('pass')), reason: 'FSF is Game Forcing');

      // Opener with 3 spades -> 3S (Priority 1)
      // ♠ K75, ♥ AQ942, ♦ KJ5, ♣ 83 (13 HCP, 3=5=3=2, 13 cards)
      final opener3s = Hand.fromString('K75.AQ942.KJ5.83');
      final matches1 = resolver.evaluateCandidates(opener3s, state.candidateNodes);
      expect(matches1.first.node.call, equals('3s'), reason: 'Priority 1: 3-card spade support');

      // Opener with Club stopper -> 3NT (Priority 2)
      // ♠ 75, ♥ AQ942, ♦ KJ5, ♣ KJ3 (14 HCP, 2=5=3=3, 13 cards)
      final openerStopper = Hand.fromString('75.AQ942.KJ5.KJ3');
      final matches2 = resolver.evaluateCandidates(openerStopper, state.candidateNodes);
      expect(matches2.first.node.call, equals('3nt'), reason: 'Priority 2: 3NT with stopper');
    });
  });
}
