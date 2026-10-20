import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
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

  group('Comprehensive Opening Bids & Responses Suite (Pass -> 4NT)', () {
    late BridgeSystem system;
    late AuctionEngine engine;

    setUpAll(() async {
      system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      engine = AuctionEngine.fromSystem(system);
    });

    test('All opening bids from Pass through 4NT exist in rootState candidate nodes', () {
      final rootCalls = engine.graph.rootState.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      
      final expectedOpenings = [
        'pass',
        '1c', '1d', '1h', '1s', '1nt',
        '2c', '2d', '2h', '2s', '2nt',
        '3c', '3d', '3h', '3s', '3nt',
        '4c', '4d', '4h', '4s', '4nt',
      ];

      for (final call in expectedOpenings) {
        expect(rootCalls, contains(call), reason: 'Opening bid $call should be present in rootState');
      }
    });

    test('2C Strong Opening has 2D waiting and natural positive responses', () {
      final state2C = engine.graph.getState(['2c']);
      expect(state2C, isNotNull);
      final calls = state2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('2d'), reason: '2D waiting relay exists');
      expect(calls, contains('2h'), reason: '2H positive exists');
      expect(calls, contains('2s'), reason: '2S positive exists');
      expect(calls, contains('2nt'), reason: '2NT positive exists');
      expect(calls, contains('3c'), reason: '3C positive exists');
      expect(calls, contains('3d'), reason: '3D positive exists');
    });

    test('Weak Two Openings (2D, 2H, 2S) provide full response suites including Feature Ask 2NT', () {
      // 2D Weak Two
      final state2D = engine.graph.getState(['2d']);
      expect(state2D, isNotNull);
      final calls2D = state2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2D, containsAll(['pass', '2h', '2s', '2nt', '3c', '3d', '3nt', '5d']));

      // 2H Weak Two
      final state2H = engine.graph.getState(['2h']);
      expect(state2H, isNotNull);
      final calls2H = state2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2H, containsAll(['pass', '2s', '2nt', '3c', '3d', '3h', '3nt', '4h']));

      // 2S Weak Two
      final state2S = engine.graph.getState(['2s']);
      expect(state2S, isNotNull);
      final calls2S = state2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2S, containsAll(['pass', '2nt', '3c', '3d', '3h', '3s', '3nt', '4s']));

      // 2S -> 2NT Feature Ask continuations:
      final state2S2NT = engine.graph.getState(['2s', '2nt']);
      expect(state2S2NT, isNotNull);
      final featureCalls = state2S2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(featureCalls, contains('3s'), reason: 'Minimum rebids original suit');
      expect(featureCalls, contains('3c'), reason: 'Max with Club feature');
      expect(featureCalls, contains('3d'), reason: 'Max with Diamond feature');
      expect(featureCalls, contains('3h'), reason: 'Max with Heart feature');
      expect(featureCalls, contains('3nt'), reason: 'Max with solid suit');
    });

    test('3-Level Preempts (3C, 3D, 3H, 3S) have full response suites', () {
      // 3C
      final state3C = engine.graph.getState(['3c']);
      expect(state3C, isNotNull);
      final calls3C = state3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls3C, containsAll(['pass', '3d', '3h', '3s', '3nt', '4c', '5c']));

      // 3H
      final state3H = engine.graph.getState(['3h']);
      expect(state3H, isNotNull);
      final calls3H = state3H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls3H, containsAll(['pass', '3s', '3nt', '4h', '4nt']));

      // 3S
      final state3S = engine.graph.getState(['3s']);
      expect(state3S, isNotNull);
      final calls3S = state3S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls3S, containsAll(['pass', '3nt', '4s', '4nt']));
    });

    test('Gambling 3NT opening resolves 4C pass-or-correct and 4D shortness ask', () {
      final state3NT = engine.graph.getState(['3nt']);
      expect(state3NT, isNotNull);
      final calls3NT = state3NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls3NT, containsAll(['pass', '4c', '4d', '4h', '4s', '5c']));

      // 3NT -> 4C (Pass or Correct)
      final state3NT4C = engine.graph.getState(['3nt', '4c']);
      expect(state3NT4C, isNotNull);
      final calls4C = state3NT4C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls4C, containsAll(['pass', '4d']));

      // 3NT -> 4D (Shortness enquiry)
      final state3NT4D = engine.graph.getState(['3nt', '4d']);
      expect(state3NT4D, isNotNull);
      final calls4D = state3NT4D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls4D, containsAll(['4h', '4s', '4nt']));
    });

    test('4-Level Namyats (4C/4D) and Preempts (4H/4S/4NT) resolve cleanly', () {
      // 4C Namyats (Hearts)
      final state4C = engine.graph.getState(['4c']);
      expect(state4C, isNotNull);
      final calls4C = state4C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls4C, containsAll(['4d', '4h', '4nt']));

      // 4D Namyats (Spades)
      final state4D = engine.graph.getState(['4d']);
      expect(state4D, isNotNull);
      final calls4D = state4D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls4D, containsAll(['4h', '4s', '4nt']));

      // 4H Preempt
      final state4H = engine.graph.getState(['4h']);
      expect(state4H, isNotNull);
      final calls4H = state4H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls4H, containsAll(['pass', '4nt', '5h']));

      // 4S Preempt
      final state4S = engine.graph.getState(['4s']);
      expect(state4S, isNotNull);
      final calls4S = state4S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls4S, containsAll(['pass', '4nt', '5s']));

      // 4NT Extreme Minors
      final state4NT = engine.graph.getState(['4nt']);
      expect(state4NT, isNotNull);
      final calls4NT = state4NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls4NT, containsAll(['5c', '5d', '5h', '5s']));
    });
  });
}
