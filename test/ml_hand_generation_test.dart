import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';

void main() {
  final generator = DealGenerator();
  final mlValuation = MLHandValuation();
  final mlEvaluator = MLEdgeCaseEvaluator();

  group('ML Hand Generation & Decision Window Tests', () {
    test('dealMLBorderlineGameDeal generates hands strictly in 22-25 Combined HCP range', () {
      for (int i = 0; i < 20; i++) {
        final deal = generator.dealMLBorderlineGameDeal();
        final combHcp = deal.north.hcp + deal.south.hcp;
        expect(combHcp, greaterThanOrEqualTo(22), reason: 'Combined HCP below 22 on deal $i');
        expect(combHcp, lessThanOrEqualTo(25), reason: 'Combined HCP above 25 on deal $i');
        expect(deal.north.heartsLength, greaterThanOrEqualTo(5));
        expect(deal.south.heartsLength, greaterThanOrEqualTo(3));
      }
    });

    test('dealMLBorderlineGameDeal(expectAccept: true) produces high controls and low LTC', () {
      for (int i = 0; i < 10; i++) {
        final deal = generator.dealMLBorderlineGameDeal(expectAccept: true);
        final combControls = deal.north.controls + deal.south.controls;
        final combLtc = deal.north.losingTrickCount + deal.south.losingTrickCount;
        expect(combControls, greaterThanOrEqualTo(5));
        expect(combLtc, lessThanOrEqualTo(14));

        final pred = mlEvaluator.evaluateHands(
          north: deal.north,
          south: deal.south,
          contractLevel: 4,
          strain: 'h',
        );
        expect(pred.shouldAcceptInvite, isTrue, reason: 'ML model should accept game with high controls/low LTC');
      }
    });

    test('dealMLBorderlineGameDeal(expectAccept: false) produces deals that ML model declines', () {
      for (int i = 0; i < 10; i++) {
        final deal = generator.dealMLBorderlineGameDeal(expectAccept: false);
        final pred = mlEvaluator.evaluateHands(
          north: deal.north,
          south: deal.south,
          contractLevel: 4,
          strain: 'h',
        );
        expect(pred.shouldAcceptInvite, isFalse, reason: 'ML model should decline game with weak mesh');
      }
    });

    test('dealMLMarginalSlamDeal generates hands strictly in 29-32 Combined HCP range', () {
      for (int i = 0; i < 10; i++) {
        final deal = generator.dealMLMarginalSlamDeal();
        final combHcp = deal.north.hcp + deal.south.hcp;
        expect(combHcp, greaterThanOrEqualTo(29));
        expect(combHcp, lessThanOrEqualTo(32));
      }
    });

    test('dealMLValuationUpgradeDeal generates raw 10-11 HCP hand upgraded to 12+ Effective HCP', () {
      for (int i = 0; i < 10; i++) {
        final deal = generator.dealMLValuationUpgradeDeal();
        final raw = deal.north.hcp;
        final eff = mlValuation.evaluatePoints(deal.north);
        expect(raw, inInclusiveRange(10, 11));
        expect(eff, greaterThanOrEqualTo(12.0));
      }
    });

    test('dealExtremeShapeMajorDeal generates 8+ card major with low LTC (<=5 losers)', () {
      for (int i = 0; i < 10; i++) {
        final deal = generator.dealExtremeShapeMajorDeal();
        final maxMajor = deal.north.heartsLength > deal.north.spadesLength
            ? deal.north.heartsLength
            : deal.north.spadesLength;
        expect(maxMajor, greaterThanOrEqualTo(8));
        expect(deal.north.losingTrickCount, lessThanOrEqualTo(5));
      }
    });

    test('User Hand: 1H - (2D) interference leads to 4H game contract', () async {
      const relativePath = 'assets/core/systems/gavin_wolpert_2over1.yaml';
      final file = File(relativePath);
      final yamlStr = await file.readAsString();

      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async {
          final f = File(path);
          if (f.existsSync()) return await f.readAsString();
          return '';
        },
      );

      final engine = AuctionEngine.fromSystem(system, mlEvaluator: mlEvaluator);

      // User's exact hand:
      // North: S:K87, H:AJT976543, D:K, C:- (11 raw HCP, 12.7 EffHCP, 9 Hearts, LTC=4)
      final north = Hand.fromString('K87.AJT976543.K.-');
      // South: S:AQ2, H:Q, D:J9742, C:QJ75 (12 HCP, 1 Heart, 5 Diamonds)
      final south = Hand.fromString('AQ2.Q.J9742.QJ75');
      // East: S:JT5, H:82, D:AQT83, C:A64 (11 HCP, 5 Diamonds)
      final east = Hand.fromString('JT5.82.AQT83.A64');
      // West: S:9643, H:K, D:65, C:KT9832
      final west = Hand.fromString('9643.K.65.KT9832');

      final deal = PartnershipDeal(
        north: north,
        east: east,
        south: south,
        west: west,
      );

      // Verify that after North opens 1H and East bids (2D):
      final state1h2d = engine.graph.getState(['1h', '(2d)']);
      expect(state1h2d, isNotNull);

      // If South passes (2D) because of no diamond stopper or spade length:
      final stateOverPass = engine.graph.getState(['1h', '(2d)', 'pass', 'pass']);
      expect(stateOverPass, isNotNull);

      // North reopening rebid: North with 9 hearts and low LTC reopens 4H!
      final northReopening = stateOverPass!.resolveBestBid(north, engine.resolver, fragments: engine.graph.system.fragments);
      expect(northReopening, isNotNull);
      expect(northReopening!.call, equals('4h'), reason: 'North should reopen 4H holding 9 hearts and 4 losers');
    });
  });
}
