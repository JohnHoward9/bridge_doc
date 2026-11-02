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

  group('Gavin Wolpert Webinar 26: Transfers after 2NT Rebid', () {
    test('1C - 1H - 2NT: Modified Wolff (3C) and Major Transfers (3D, 3H)', () {
      final state = graph.getState(['1c', '1h', '2nt']);
      expect(state, isNotNull, reason: 'Sequence 1c:1h:2nt must exist in graph');
      final calls = state!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Over 18-19 2NT rebid: pass, 3c (Wolff), 3d (transfer to H), 3h (transfer to S), 3s (minor slam try), 3nt
      expect(calls, containsAll(['pass', '3c', '3d', '3h', '3s', '3nt']));

      // 1. Transfer to Hearts with 5+ Hearts (game-forcing or invitational): 3D
      // ♠ 82, ♥ KJT74, ♦ A86, ♣ 762 (8 HCP, 5 Hearts)
      final handHearts = Hand.fromString('82.KJT74.A86.762');
      final matchHearts = resolver.evaluateCandidates(handHearts, state.candidateNodes);
      expect(matchHearts.first.node.call.toLowerCase(), equals('3d'),
          reason: '5+ Hearts bids 3D (transfer to Hearts)');

      // 2. Transfer to Spades with 5+ Spades: 3H
      // ♠ KJT74, ♥ 82, ♦ A86, ♣ 762 (8 HCP, 5 Spades)
      final handSpades = Hand.fromString('KJT74.82.A86.762');
      final matchSpades = resolver.evaluateCandidates(handSpades, state.candidateNodes);
      expect(matchSpades.first.node.call.toLowerCase(), equals('3h'),
          reason: '5+ Spades bids 3H (transfer to Spades)');
    });

    test('Continuations after 1C - 1H - 2NT - 3C: Opener forced puppet to 3D', () {
      final state3C = graph.getState(['1c', '1h', '2nt', '3c']);
      expect(state3C, isNotNull);
      final calls = state3C!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('3d'), reason: 'Opener must puppet to 3D over 3C Wolff relay');
    });

    test('Continuations after 1C - 1H - 2NT - 3D: Opener accepts transfer with 3H', () {
      final state3D = graph.getState(['1c', '1h', '2nt', '3d']);
      expect(state3D, isNotNull);
      final calls = state3D!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls, contains('3h'), reason: 'Opener must accept transfer to Hearts with 3H');
    });
  });
}
