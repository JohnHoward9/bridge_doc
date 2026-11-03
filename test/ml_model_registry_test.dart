import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/models/ml_hand_valuation_model.dart';
import 'package:bridge_bidding_system/models/ml_preempt_model.dart';
import 'package:bridge_bidding_system/models/ml_model_registry.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MLModelRegistry & Multi-Model Architecture Tests', () {
    setUp(() {
      MLModelRegistry.instance.resetToDefaults();
    });

    test('Initializes with default empirical models across all domains', () {
      final registry = MLModelRegistry.instance;

      expect(registry.availableValuationModels, contains('bbo_empirical'));
      expect(registry.availableValuationModels, contains('milton_work_baseline'));
      expect(registry.activeValuationModel.dataset, contains('BBO Championships'));

      expect(registry.availablePreemptModels, contains('bbo_preempt'));
      expect(registry.activePreemptModel.modelName, 'BBOChampionshipPreemptModel');

      expect(registry.availableStrainModels, contains('bbo_strain'));
      expect(registry.availableEdgeCaseModels, contains('gavin_edge_tree'));
    });

    test('Switches active valuation model dynamically', () {
      final registry = MLModelRegistry.instance;
      expect(registry.activeValuationModel.version, contains('calibrated'));

      registry.setActiveValuationModel('milton_work_baseline');
      expect(registry.activeValuationModel.version, '1.0.0-milton-baseline');

      registry.setActiveValuationModel('bbo_empirical');
      expect(registry.activeValuationModel.version, contains('calibrated'));
    });

    test('Registers and switches to a custom MLPreemptModel', () {
      final registry = MLModelRegistry.instance;

      final customPreempt = MLPreemptModel(
        modelName: 'AggressivePreemptModel',
        version: '2.0.0-aggressive',
        description: 'Aggressive preemption with 5-card allowance in 3rd seat',
        parameters: const {
          'base_trick_constant': 13.0,
          'ltc_weight': -1.0,
          'length_surplus_weight': 1.5,
          'honor_density_weight': 0.5,
          'hcp_ceiling': 12.0,
          'sound_suit_second_seat_min_honors': 1.0,
        },
        allowedDownByVulnerability: const {
          'favorable': 5.0,
          'none': 4.0,
          'both': 3.0,
          'unfavorable': 2.0,
        },
        seatAllowedDownAdjustments: const {
          'first': 0.0,
          'second': 0.0,
          'third': 2.0,
          'fourth': -999.0,
        },
        minSuitLengthByLevel: const {2: 5, 3: 6, 4: 7},
      );

      registry.registerPreemptModel('aggressive', customPreempt);
      expect(registry.availablePreemptModels, contains('aggressive'));

      registry.setActivePreemptModel('aggressive');
      expect(registry.activePreemptModel.modelName, 'AggressivePreemptModel');
      expect(registry.activePreemptModel.hcpCeiling, 12.0);
    });

    test('Evaluates preempt decisions cleanly through MLPowerEngine delegation', () {
      // South: ♠T32 ♥QJ ♦4 ♣KJ87432 (7 HCP, 7 clubs)
      final south = Hand.fromString('T32:QJ:4:KJ87432');

      final decision = MLPowerEngine.evaluatePreempt(
        south,
        suit: Suit.clubs,
        level: 3,
        seat: SeatPosition.first,
        vuln: Vulnerability.none,
      );

      expect(decision.shouldPreempt, isTrue, reason: '7-card club suit with 7 HCP qualifies under MLPreemptModel');
      expect(decision.recommendedCall, '3♣');
      expect(decision.expectedTricks, greaterThanOrEqualTo(6.0));
    });

    test('Global profile switching updates all domain models coherently', () {
      final registry = MLModelRegistry.instance;

      registry.setProfile('milton_work');
      expect(registry.activeValuationModel.version, '1.0.0-milton-baseline');

      registry.setProfile('bbo_empirical');
      expect(registry.activeValuationModel.version, contains('calibrated'));
    });
  });
}
