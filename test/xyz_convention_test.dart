import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';

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

  group('XYZ Convention Tests (Deduplicated fXYZ)', () {
    test('xyz.yaml contains only unified fXYZ with zero duplicate fragments', () async {
      final yamlContent = await File('assets/libraries/conventions/xyz.yaml').readAsString();
      final lib = SystemYamlParser.fromYaml(yamlContent);

      // Verify only ONE fragment exists in xyz.yaml
      expect(lib.fragments.keys.length, equals(1));
      expect(lib.fragments.containsKey('fXYZ'), isTrue);

      final fXYZ = lib.fragments['fXYZ']!;
      final topCalls = fXYZ.bids.map((b) => b.displayCall.toLowerCase()).toSet();
      expect(topCalls, containsAll(['pass', '1s', '2c', '2d', '2h', '2s', '2nt', '3c']));

      // 2C forces 2D
      final bid2C = fXYZ.bids.firstWhere((b) => b.displayCall.toLowerCase() == '2c');
      expect(bid2C.desc.toLowerCase(), contains('puppet to 2d'));
      final openerRelay = bid2C.bids.firstWhere((b) => b.displayCall.toLowerCase() == '2d');
      expect(openerRelay.desc.toLowerCase(), contains('forced'));

      // Continuations after 2C -> 2D
      final contCalls = openerRelay.bids.map((b) => b.displayCall.toLowerCase()).toSet();
      expect(contCalls, containsAll(['pass', '2h', '2s', '2nt', '3c', '3d']));

      // 2D is Game Forcing checkback
      final bid2D = fXYZ.bids.firstWhere((b) => b.displayCall.toLowerCase() == '2d');
      expect(bid2D.desc.toLowerCase(), contains('game-forcing'));
      final gfResponses = bid2D.bids.map((b) => b.displayCall.toLowerCase()).toSet();
      expect(gfResponses, containsAll(['2h', '2s', '2nt', '3c', '3d']));

      // Direct weak signoffs and direct 3C invitation
      final weak2H = fXYZ.bids.firstWhere((b) => b.displayCall.toLowerCase() == '2h');
      expect(weak2H.desc.toLowerCase(), contains('weak'));
      final weak2S = fXYZ.bids.firstWhere((b) => b.displayCall.toLowerCase() == '2s');
      expect(weak2S.desc.toLowerCase(), contains('weak'));
      final inv3C = fXYZ.bids.firstWhere((b) => b.displayCall.toLowerCase() == '3c');
      expect(inv3C.desc.toLowerCase(), contains('6-card invite'));
    });

    test('Sequence 1 (1D - 1H - 1S - ?): fXYZ resolves invitations and game forcing checkback', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final state1D1H1S = engine.graph.getState(['1d', '1h', '1s']);
      expect(state1D1H1S, isNotNull);
      final bids1D1H1S = state1D1H1S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      // Over 1D-1H-1S, 1S is not available (only over 1C-1D-1H where fourth_suit is active)
      expect(bids1D1H1S, isNot(contains('1s')));
      expect(bids1D1H1S, contains('2c'), reason: 'XYZ puppet to 2D');
      expect(bids1D1H1S, contains('2d'), reason: 'XYZ game forcing checkback');
      expect(bids1D1H1S, contains('2h'), reason: 'XYZ weak signoff in Hearts');
      expect(bids1D1H1S, contains('2s'), reason: 'XYZ weak raise in Spades');
      expect(bids1D1H1S, contains('3c'), reason: 'XYZ direct 6-card Club invitation');

      // Relay continuation: 1D - 1H - 1S - 2C - 2D - ?
      final stateRelay = engine.graph.getState(['1d', '1h', '1s', '2c', '2d']);
      expect(stateRelay, isNotNull);
      final bidsRelay = stateRelay!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(bidsRelay, contains('pass'), reason: 'Weak signoff in Diamonds');
      expect(bidsRelay, contains('2h'), reason: 'Invitational in Hearts');
      expect(bidsRelay, contains('2s'), reason: 'Invitational in Spades');
      expect(bidsRelay, contains('2nt'), reason: 'Natural balanced invitation');
      expect(bidsRelay, contains('3c'), reason: 'Weak Club escape');

      // Opener re-evaluation over invitational 2H: 1D - 1H - 1S - 2C - 2D - 2H
      final stateOver2H = engine.graph.getState(['1d', '1h', '1s', '2c', '2d', '2h']);
      expect(stateOver2H, isNotNull);
      final openerOver2H = stateOver2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerOver2H, containsAll(['pass', '2nt', '3h']));

      // Opener re-evaluation over invitational 2S: 1D - 1H - 1S - 2C - 2D - 2S
      final stateOver2S = engine.graph.getState(['1d', '1h', '1s', '2c', '2d', '2s']);
      expect(stateOver2S, isNotNull);
      final openerOver2S = stateOver2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerOver2S, containsAll(['pass', '3s', '4s']));

      // GF responses over 2D: 1D - 1H - 1S - 2D - ?
      final stateGF = engine.graph.getState(['1d', '1h', '1s', '2d']);
      expect(stateGF, isNotNull);
      final openerGF = stateGF!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerGF, containsAll(['2h', '2s', '2nt', '3c']));
    });

    test('Sequence 2 (1C - 1H - 1S - ?): fXYZ resolves correctly', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final state1C1H1S = engine.graph.getState(['1c', '1h', '1s']);
      expect(state1C1H1S, isNotNull);
      final bids1C1H1S = state1C1H1S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(bids1C1H1S, contains('2c'), reason: 'XYZ puppet to 2D');
      expect(bids1C1H1S, contains('2d'), reason: 'XYZ game forcing checkback');
      expect(bids1C1H1S, contains('2h'), reason: 'XYZ weak signoff in Hearts');
      expect(bids1C1H1S, contains('2s'), reason: 'XYZ weak signoff in Spades');
      expect(bids1C1H1S, contains('3c'), reason: 'XYZ direct 6-card Club invitation');
    });

    test('Sequence 3 (1C - 1D - 1H - ?): Fourth suit 1S is active alongside fXYZ', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final state1C1D1H = engine.graph.getState(['1c', '1d', '1h']);
      expect(state1C1D1H, isNotNull);
      final bids1C1D1H = state1C1D1H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      // 1S fourth suit forcing is active because fourth_suit=true
      expect(bids1C1D1H, contains('1s'), reason: 'Fourth suit forcing F1 enabled via variable');
      expect(bids1C1D1H, contains('2c'), reason: 'XYZ puppet to 2D');
      expect(bids1C1D1H, contains('2d'), reason: 'XYZ game forcing checkback');
      expect(bids1C1D1H, contains('2h'), reason: 'XYZ weak raise in Hearts');

      // Fourth suit node description check
      final node1S = state1C1D1H.candidateNodes.firstWhere((n) => n.displayCall.toLowerCase() == '1s');
      expect(node1S.desc.toLowerCase(), contains('fourth suit'));
    });
  });
}
