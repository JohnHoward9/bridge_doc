import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AuctionEngine with MLBidEvaluator evaluates edge cases dynamically', () async {
    const relativePath = 'assets/core/systems/gavin_wolpert_2over1.yaml';
    final file = File(relativePath);
    expect(file.existsSync(), isTrue);
    final yamlStr = await file.readAsString();

    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) {
          return await f.readAsString();
        }
        return '';
      },
    );

    final mlEvaluator = MLEdgeCaseEvaluator();
    final engine = AuctionEngine.fromSystem(system, mlEvaluator: mlEvaluator);

    expect(engine.mlEvaluator, isNotNull);

    // North has 14 HCP with 5 Hearts
    // South has 10 HCP with 4 Hearts (24 HCP combined - borderline edge case)
    final north = Hand.fromString('A5.AKJ86.986.K98');
    final south = Hand.fromString('K742.QT54.AJ.T76');

    final deal = PartnershipDeal(
      north: north,
      east: Hand.fromString('QJ8.73.KJT74.A54'),
      south: south,
      west: Hand.fromString('T963.92.Q32.QJ32'),
    );

    // Start deal: North opens 1H
    final startRes = engine.startDeal(deal: deal, isNorthFirst: true);
    expect(startRes.updatedHistory.first.call, equals('1h'));

    // South responds 3D (Limit raise: 10-11 HCP, 4+ Hearts)
    final stepRes = engine.advanceAuction(
      history: startRes.updatedHistory,
      userCall: '3d',
      deal: deal,
      activeSeat: 'S',
    );

    expect(stepRes.isUserBidCorrect, isTrue, reason: stepRes.feedbackMessage);
    // Partner (North with 14 HCP and good controls) accepts game 4H via rules and ML
    final lastPartnerCall = stepRes.updatedHistory.lastWhere((e) => e.seat == 'N');
    expect(lastPartnerCall.call, equals('4h'));
  });
}
