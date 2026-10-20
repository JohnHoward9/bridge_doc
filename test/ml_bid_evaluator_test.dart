import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/card.dart';

void main() {
  group('Gavin Wolpert ML Edge-Case Evaluator Tests', () {
    test('Default embedded decision tree evaluates borderline game invitations correctly', () {
      final evaluator = MLEdgeCaseEvaluator();

      // Case 1: Borderline 24 HCP with an 8-card major fit at game level (4H)
      final pred8Fit = evaluator.evaluateEdgeCase(
        combHcp: 24.0,
        hcpDiff: 2.0,
        maxMajorFit: 8.0,
        contractLevel: 4,
        strainCode: 2, // Hearts
        isGameTarget: true,
        combLtc: 14.0,
        combControls: 6.0,
      );

      // Model calibrated on 3,720 deals predicts 61.4% make probability: positive EV at IMPs
      expect(pred8Fit.probMaking, greaterThanOrEqualTo(0.60));
      expect(pred8Fit.shouldAcceptInvite, isTrue);
      expect(pred8Fit.expectedResult, closeTo(-0.3071, 0.001));

      // Case 2: Borderline 24 HCP with a 9-card major fit
      final pred9Fit = evaluator.evaluateEdgeCase(
        combHcp: 24.0,
        hcpDiff: 2.0,
        maxMajorFit: 9.0,
        contractLevel: 4,
        strainCode: 2, // Hearts
        isGameTarget: true,
        combLtc: 13.0,
        combControls: 7.0,
      );

      expect(pred9Fit.probMaking, greaterThanOrEqualTo(0.80));
      expect(pred9Fit.expectedResult, greaterThan(0.0));
      expect(pred9Fit.shouldAcceptInvite, isTrue);

      // Case 3: Borderline 24 HCP with high LTC (bad shape, 15 LTC) and minor/NT
      final predBadShape = evaluator.evaluateEdgeCase(
        combHcp: 24.0,
        hcpDiff: 2.0,
        maxMajorFit: 7.0,
        contractLevel: 4,
        strainCode: 2, // Hearts
        isGameTarget: true,
        combLtc: 15.0,
        combControls: 4.0,
      );

      expect(predBadShape.expectedResult, lessThan(-1.0));
      expect(predBadShape.probMaking, lessThan(0.30));
      expect(predBadShape.shouldAcceptInvite, isFalse);
    });

    test('Loads and evaluates from exported assets/models/gavin_ml_edge_model.json', () async {
      final file = File('assets/models/gavin_ml_edge_model.json');
      expect(file.existsSync(), isTrue);

      final jsonStr = await file.readAsString();
      final evaluator = MLEdgeCaseEvaluator.fromJsonString(jsonStr);

      final pred = evaluator.evaluateEdgeCase(
        combHcp: 24.0,
        hcpDiff: 2.0,
        maxMajorFit: 8.0,
        contractLevel: 4,
        strainCode: 1, // Spades
        isGameTarget: true,
        combLtc: 14.0,
        combControls: 6.0,
      );

      expect(pred.shouldAcceptInvite, isTrue);
      expect(pred.expectedResult, closeTo(-0.3071, 0.001));
      expect(pred.probMaking, closeTo(0.6142, 0.001));
    });

    test('Evaluates directly from North and South Hand objects', () {
      final evaluator = MLEdgeCaseEvaluator();

      // North: 12 HCP, 4 Hearts
      final north = Hand.fromString('A.KJ102.K32.J5432');

      // South: 12 HCP, 4 Hearts (8-card fit total, combined 24 HCP)
      final south = Hand.fromString('KQ.Q987.A54.Q876');

      final pred = evaluator.evaluateHands(
        north: north,
        south: south,
        contractLevel: 4,
        strain: 'h',
      );

      expect(pred.shouldAcceptInvite, isTrue);
      expect(pred.expectedResult, closeTo(-0.3071, 0.001));
      expect(pred.probMaking, closeTo(0.6142, 0.001));
    });
  });
}
