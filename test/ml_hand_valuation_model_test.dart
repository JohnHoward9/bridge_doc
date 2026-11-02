import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/models/ml_hand_valuation_model.dart';
import 'package:bridge_bidding_system/models/ml_hand_feature_vector.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';

void main() {
  group('MLHandValuationModel Tests', () {
    test('Default model loads calibrated weights correctly', () {
      final model = MLHandValuationModel.current;
      expect(model.version, equals('v2.0-bbo-empirical-calibrated'));
      expect(model.trainingSamples, equals(25838));
      expect(model.featureNames.length, equals(23));
      expect(model.weights.length, equals(23));
      expect(model.kingUnsupportedLho, equals(-1.3));
      expect(model.kingProtectedRho, equals(0.2));
      expect(model.shape6421, equals(0.85));
      expect(model.shape6331, equals(-0.2));
    });

    test('assets/models/ml_hand_valuation_model.json parses and matches model structure', () {
      final file = File('assets/models/ml_hand_valuation_model.json');
      expect(file.existsSync(), isTrue, reason: 'assets/models/ml_hand_valuation_model.json must exist');
      final jsonStr = file.readAsStringSync();
      final model = MLHandValuationModel.fromJsonString(jsonStr);

      expect(model.version, equals('v2.0-bbo-empirical-calibrated'));
      expect(model.trainingSamples, equals(25838));
      expect(model.weightOf('shape_6421', 0.0), equals(0.85));
      expect(model.weightOf('shape_6331', 0.0), equals(-0.2));
      expect(model.weightOf('opp_king_lho_trapped', 0.0), equals(-1.3));
    });

    test('Custom MLHandValuationModel dynamically modifies valuation without hardcoding', () {
      // Create a custom model where 6-4-2-1 gets a huge +3.0 boost and King trapped is -2.5
      final customWeights = List<double>.filled(23, 0.0);
      customWeights[0] = 1.0; // raw_hcp
      final idx6421 = MLHandFeatureVector.featureNames.indexOf('shape_6421');
      final idxLho = MLHandFeatureVector.featureNames.indexOf('opp_king_lho_trapped');
      customWeights[idx6421] = 3.0;
      customWeights[idxLho] = -2.5;

      final customModel = MLHandValuationModel(
        version: 'v-custom-experimental',
        dataset: 'Test Custom',
        trainingSamples: 100,
        featureNames: MLHandFeatureVector.featureNames,
        weights: customWeights,
        bias: 0.0,
        explanationLabels: const {
          'shape_6421': 'Experimental Super 6-4-2-1 Boost',
        },
      );

      final valuation = MLHandValuation(model: customModel);
      final hand6421 = Hand.fromString('AKJ942.Q853.72.6'); // 10 HCP, 6-4-2-1

      final points = valuation.evaluatePoints(hand6421, trumpSuit: Suit.spades);
      // Under custom model: 10 + 3.0 = 13.0
      expect(points, equals(13.0));

      final oppAction = OpponentSuitAction(
        suit: Suit.spades,
        position: RelativeOpponentPosition.lho,
        call: '1s',
        seat: 'W',
      );
      final oppBreakdown = valuation.evaluateWithAuctionContext(
        Hand.fromString('K8.AQ5.KJ42.Q862'), // K in spades without Ace
        opponentActions: [oppAction],
      );
      // In custom model, opp_king_lho_trapped is -2.5
      expect(oppBreakdown.effectiveHcp, equals(15.0 - 2.5));
    });
  });
}
