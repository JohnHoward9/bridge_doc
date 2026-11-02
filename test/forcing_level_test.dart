import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/evaluators/ml_strain_model.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/services/system_yaml_validator.dart';
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

  group('ForcingLevel Enum & Contract Satisfaction Tests', () {
    test('ForcingLevel parses strings and standard aliases', () {
      expect(ForcingLevel.fromString('game'), equals(ForcingLevel.game));
      expect(ForcingLevel.fromString('gf'), equals(ForcingLevel.game));
      expect(ForcingLevel.fromString('GF'), equals(ForcingLevel.game));
      expect(ForcingLevel.fromString('slam'), equals(ForcingLevel.slam));
      expect(ForcingLevel.fromString('sf'), equals(ForcingLevel.slam));
      expect(ForcingLevel.fromString('grandSlam'), equals(ForcingLevel.grandSlam));
      expect(ForcingLevel.fromString('grand_slam'), equals(ForcingLevel.grandSlam));
      expect(ForcingLevel.fromString('gsf'), equals(ForcingLevel.grandSlam));
      expect(ForcingLevel.fromString('partScore'), equals(ForcingLevel.partScore));
      expect(ForcingLevel.fromString('partscore'), equals(ForcingLevel.partScore));
      expect(ForcingLevel.fromString(null), equals(ForcingLevel.partScore));
      expect(ForcingLevel.fromString(''), equals(ForcingLevel.partScore));
    });

    test('isContractSatisfied evaluates game, slam, and grandSlam thresholds accurately', () {
      // Partscore: always satisfied
      expect(ForcingLevel.isContractSatisfied('2h', ForcingLevel.partScore), isTrue);

      // Game force
      expect(ForcingLevel.isContractSatisfied('2h', ForcingLevel.game), isFalse);
      expect(ForcingLevel.isContractSatisfied('3s', ForcingLevel.game), isFalse);
      expect(ForcingLevel.isContractSatisfied('4c', ForcingLevel.game), isFalse);
      expect(ForcingLevel.isContractSatisfied('3nt', ForcingLevel.game), isTrue);
      expect(ForcingLevel.isContractSatisfied('4h', ForcingLevel.game), isTrue);
      expect(ForcingLevel.isContractSatisfied('4s', ForcingLevel.game), isTrue);
      expect(ForcingLevel.isContractSatisfied('5c', ForcingLevel.game), isTrue);
      expect(ForcingLevel.isContractSatisfied('5d', ForcingLevel.game), isTrue);
      expect(ForcingLevel.isContractSatisfied('6c', ForcingLevel.game), isTrue);

      // Slam force
      expect(ForcingLevel.isContractSatisfied('4s', ForcingLevel.slam), isFalse);
      expect(ForcingLevel.isContractSatisfied('5h', ForcingLevel.slam), isFalse);
      expect(ForcingLevel.isContractSatisfied('6h', ForcingLevel.slam), isTrue);
      expect(ForcingLevel.isContractSatisfied('6nt', ForcingLevel.slam), isTrue);

      // Grand slam force
      expect(ForcingLevel.isContractSatisfied('6s', ForcingLevel.grandSlam), isFalse);
      expect(ForcingLevel.isContractSatisfied('7s', ForcingLevel.grandSlam), isTrue);
      expect(ForcingLevel.isContractSatisfied('7nt', ForcingLevel.grandSlam), isTrue);
    });
  });

  group('YAML Parser & Validator Tests for forceTo', () {
    test('SystemYamlParser parses forceTo on both BiddingNode and Fragment', () {
      const yaml = '''
system: "Test System"
fragments:
  fTestFrag:
    forceTo: game
    bids:
      2d:
        desc: "GF relay"
        forceTo: game
openings:
  1s:
    desc: "1S opening"
    bids:
      2c:
        forceTo: game
        desc: "2/1 GF"
      3c:
        forceTo: slam
        desc: "Slam try"
''';
      final system = SystemYamlParser.fromYaml(yaml);
      expect(system.fragments['fTestFrag']!.forceTo, equals(ForcingLevel.game));
      expect(system.fragments['fTestFrag']!.bids.first.forceTo, equals(ForcingLevel.game));

      final node1S = system.openingBids.first;
      final node2C = node1S.bids.firstWhere((b) => b.call == '2c');
      expect(node2C.forceTo, equals(ForcingLevel.game));

      final node3C = node1S.bids.firstWhere((b) => b.call == '3c');
      expect(node3C.forceTo, equals(ForcingLevel.slam));
    });

    test('SystemYamlValidator warns on invalid forceTo value', () {
      const invalidYaml = '''
system: "Invalid forceTo System"
openings:
  1h:
    forceTo: invalidForceTarget
    desc: "1H opening"
''';
      final result = SystemYamlValidator.validate(invalidYaml);
      expect(result.diagnostics.any((d) => d.category == 'Forcing Level'), isTrue);
      expect(result.diagnostics.any((d) => d.message.contains('Invalid forceTo value')), isTrue);
    });
  });

  group('Auction Graph Forcing Level Escalation & Pass Pruning', () {
    test('1S - 2C establishes Game Force and prunes Pass below game level', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      // 1. Check 1S - 2C state
      final state1S2C = engine.graph.getState(['1s', '2c']);
      expect(state1S2C, isNotNull);
      expect(state1S2C!.forcingLevel, equals(ForcingLevel.game),
          reason: '1S - 2C 2/1 must establish ForcingLevel.game');

      // 2. Opener candidate rebids must NOT contain 'pass'
      final openerCalls = state1S2C.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerCalls, isNot(contains('pass')),
          reason: 'Opener cannot pass partner\'s 2/1 Game Force');

      // 3. 1S - 2C - 2D state retains ForcingLevel.game
      final state1S2C2D = engine.graph.getState(['1s', '2c', '2d']);
      expect(state1S2C2D, isNotNull);
      expect(state1S2C2D!.forcingLevel, equals(ForcingLevel.game));
      final responderCalls = state1S2C2D.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(responderCalls, isNot(contains('pass')),
          reason: 'Responder cannot pass at 2-level in game force');
    });

    test('1D - 1H - 1S - 2D (XYZ GF) establishes Game Force and prunes Pass', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      // Check XYZ 2D enquiry state
      final stateXYZ = engine.graph.getState(['1d', '1h', '1s', '2d']);
      expect(stateXYZ, isNotNull);
      expect(stateXYZ!.forcingLevel, equals(ForcingLevel.game),
          reason: 'XYZ 2D is an artificial Game Force');

      final openerRebids = stateXYZ.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerRebids, isNot(contains('pass')),
          reason: 'Opener cannot pass artificial game-forcing 2D enquiry');
    });

    test('1NT - 2C - 2D - 3D (Stayman 4M-5m GF) establishes Game Force and prunes Pass', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final stateStayman3D = engine.graph.getState(['1nt', '2c', '2d', '3d']);
      expect(stateStayman3D, isNotNull);
      expect(stateStayman3D!.forcingLevel, equals(ForcingLevel.game),
          reason: 'Stayman 3D shows 5D+4M game force');

      final openerRebids = stateStayman3D.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerRebids, isNot(contains('pass')),
          reason: 'Opener cannot pass below game in Stayman 3D GF');
    });

    test('Pass is legal and available once Game is bid (e.g. 1NT - 2C - 2D - 3D - 3NT)', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final stateOver3NT = engine.graph.getState(['1nt', '2c', '2d', '3d', '3nt']);
      expect(stateOver3NT, isNotNull);
      final calls = stateOver3NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('pass'), reason: 'Pass is legal once game contract 3NT is reached');
    });
  });

  group('ML Strain Model with Forcing Level Tests', () {
    test('ML model recommends partscore when forcingLevel is partScore, but game when game-forced', () {
      // Sub-minimum hand with 8 HCP: Q432:K43:Q542:J3
      final hand = Hand.fromString('Q432:K43:Q542:J3');
      final partnerBelief = SeatBeliefState(
        seat: 'N',
        minHcp: 12,
        maxHcp: 14,
        minSuitLength: const {},
      );

      // 1. Without game force (forcingLevel = partScore):
      final evalPartscore = MLStrainBiddingModel.evaluatePartnership(
        hand,
        partnerBelief,
        forcingLevel: ForcingLevel.partScore,
      );
      expect(evalPartscore.recommendedLevel, lessThanOrEqualTo(3),
          reason: 'Sub-minimum hand without GF should sign off in partscore');

      // 2. With game force (forcingLevel = game):
      final evalGameForce = MLStrainBiddingModel.evaluatePartnership(
        hand,
        partnerBelief,
        forcingLevel: ForcingLevel.game,
      );
      expect(evalGameForce.recommendedLevel, greaterThanOrEqualTo(3),
          reason: 'In Game Force, target level must be at least Game (3NT, 4M, 5m)');
      expect(evalGameForce.recommendedCall, isNot(contains('Pass')),
          reason: 'ML model must never recommend Pass in a game-forced situation');
      expect(evalGameForce.reasoning.any((r) => r.toLowerCase().contains('game force') || r.toLowerCase().contains('game forced')), isTrue);
    });

    test('ML model respects slam force (level 6) and grand slam force (level 7)', () {
      final hand = Hand.fromString('AK32:AK43:AQ5:A3'); // 25 HCP powerhouse
      final partnerBelief = SeatBeliefState(
        seat: 'N',
        minHcp: 12,
        maxHcp: 15,
        minSuitLength: const {},
      );

      final evalSlam = MLStrainBiddingModel.evaluatePartnership(
        hand,
        partnerBelief,
        forcingLevel: ForcingLevel.slam,
      );
      expect(evalSlam.recommendedLevel, equals(6));

      final evalGrandSlam = MLStrainBiddingModel.evaluatePartnership(
        hand,
        partnerBelief,
        forcingLevel: ForcingLevel.grandSlam,
      );
      expect(evalGrandSlam.recommendedLevel, equals(7));
    });
  });
}
