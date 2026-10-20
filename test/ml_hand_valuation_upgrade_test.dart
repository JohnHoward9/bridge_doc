import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/constraints/hand_constraint.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  group('Machine Learning Hand Valuation & Dynamic Upgrades/Downgrades', () {
    final valuation = MLHandValuation();

    test('User Hand KTx:x98:AQJTx:QT (14 raw HCP) promotes to 15-17 Strong NT', () {
      // 14 Milton Work HCP: ♠K(3), ♥Q(2), ♦AQJT(7), ♣Q(2) = 14 HCP
      // 5-3-3-2 shape with rich intermediates (♠K10, ♦AQJ10, ♣Q10, ♥98)
      final hand = Hand.fromString('KT4:Q98:AQJT2:QT');
      expect(hand.hcp, equals(14));
      expect(hand.isBalanced, isTrue);

      final breakdown = valuation.evaluateBreakdown(hand);

      expect(breakdown.rawHcp, equals(14.0));
      expect(breakdown.intermediateAdjustment, greaterThanOrEqualTo(1.0));
      expect(breakdown.suitQualityAdjustment, greaterThanOrEqualTo(1.2));
      expect(breakdown.shapeAdjustment, equals(0.25));
      expect(breakdown.effectiveHcp, greaterThanOrEqualTo(16.0));
      expect(breakdown.isUpgraded, isTrue);

      // Verify that HcpConstraint(min: 15, max: 17) matches this 14-count via ML
      const ntConstraint = HcpConstraint(min: 15, max: 17);
      final match = ntConstraint.evaluate(hand, valuation);
      expect(match.isMatch, isTrue);
      expect(match.satisfiedCriteria.any((c) => c.contains('ML 🚀 Upgraded')), isTrue);
    });

    test('User Hand KTx:K98:AQJTx:QT evaluates with super-maximum strength', () {
      // 16 raw HCP: ♠K(3), ♥K(3), ♦AQJT(7), ♣Q(2) = 15 HCP (Wait: 3+3+7+2 = 15 HCP)
      final hand = Hand.fromString('KT4:K98:AQJT2:QT');
      expect(hand.hcp, equals(15));

      final breakdown = valuation.evaluateBreakdown(hand);
      expect(breakdown.effectiveHcp, greaterThanOrEqualTo(17.0));
      expect(breakdown.isUpgraded, isTrue);
    });

    test('3-card raise with 10 count, singleton, Ace, and partner honors upgrades to invitational limit raise', () {
      // South hand: ♠K94 ♥A876 ♦K8432 ♣5
      // 10 raw HCP: ♠K (3) + ♥A (4) + ♦K (3) = 10 HCP
      // In support of North's 1♠ opening:
      // - 3-card spade fit with working King in partner's suit
      // - Singleton club (+2.0 shortness)
      // - Prime controls (Ace + 2 Kings)
      // - Intermediates (♠9, ♥8, ♦8)
      // - No wasted honors in opps suit (♣5)
      final hand = Hand.fromString('K94:A876:K8432:5');
      expect(hand.hcp, equals(10));
      expect(hand.length(Suit.spades), equals(3));
      expect(hand.length(Suit.clubs), equals(1)); // singleton

      final breakdown = valuation.evaluateBreakdown(
        hand,
        trumpSuit: Suit.spades,
        partnerSuit: Suit.spades,
        oppSuit: Suit.clubs,
      );

      expect(breakdown.rawHcp, equals(10.0));
      expect(breakdown.shapeAdjustment, equals(2.0)); // singleton reward
      expect(breakdown.partnerMeshAdjustment, greaterThanOrEqualTo(0.75)); // working King
      expect(breakdown.controlAdjustment, greaterThanOrEqualTo(0.5)); // Ace + 2 Kings
      expect(breakdown.effectiveHcp, greaterThanOrEqualTo(13.0));
      expect(breakdown.isUpgraded, isTrue);

      // Verify that an invitational constraint (e.g. 11-12 or 10-12) easily matches
      const invitationalConstraint = HcpConstraint(min: 11, max: 12);
      final match = invitationalConstraint.evaluate(hand, valuation);
      // 13.4 rounds to 13, which is at or above invitational threshold
      expect(breakdown.effectiveHcp.round(), greaterThanOrEqualTo(11));
    });

    test('Flat aceless 15-count KQx:QJx:KQx:QJxx downgrades and does NOT open 1NT', () {
      // 15 raw Milton Work HCP: ♠KQ4 (5), ♥QJ5 (3), ♦KQ8 (5), ♣QJ52 (3) = 16?
      // Let's do ♠KQ4 (5), ♥QJ5 (3), ♦K98 (3), ♣QJ52 (3) = 14
      // Or ♠KQ4 (5), ♥QJ5 (3), ♦KJ8 (4), ♣QJ52 (3) = 15 HCP:
      final flatHand = Hand.fromString('KQ4:QJ5:KJ8:QJ52');
      expect(flatHand.hcp, equals(15));
      expect(flatHand.cards.where((c) => c.rank == Rank.ace).length, equals(0)); // 0 Aces

      final breakdown = valuation.evaluateBreakdown(flatHand);
      expect(breakdown.shapeAdjustment, equals(-0.5)); // flat 4333 deduction
      expect(breakdown.controlAdjustment, lessThan(0.0)); // lack of aces, soft honors penalty
      expect(breakdown.effectiveHcp, lessThan(14.5));
      expect(breakdown.isDowngraded, isTrue);

      // Because effective HCP is < 14.5 (rounds to 14), HcpConstraint(min: 15, max: 17) fails!
      const ntConstraint = HcpConstraint(min: 15, max: 17);
      final match = ntConstraint.evaluate(flatHand, valuation);
      expect(match.isMatch, isFalse);
    });

    test('AuctionEngine opens 1NT for upgraded 14-count KTx:x98:AQJTx:QT', () async {
      final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
      final yamlStr = await file.readAsString();
      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async {
          final f = File(path);
          return f.existsSync() ? await f.readAsString() : '';
        },
      );
      final engine = AuctionEngine.fromSystem(
        system,
        valuation: MLHandValuation(),
      );

      // North holds the upgraded 14-count
      final northHand = Hand.fromString('KT4:Q98:AQJT2:QT');
      final southHand = Hand.fromString('A83:KJ4:K74:J982');
      final deal = PartnershipDeal(
        north: northHand,
        east: Hand.fromString('9752:T63:985:A63'),
        south: southHand,
        west: Hand.fromString('J6:A752:63:K754'),
      );

      final result = engine.startDeal(deal: deal, isNorthFirst: true);

      // North opens 1NT due to ML upgrade!
      expect(result.updatedHistory.first.call.toLowerCase(), contains('1nt'));
      expect(result.mlUpgradeBreakdown, isNotNull);
      expect(result.mlUpgradeBreakdown!.isUpgraded, isTrue);
      expect(result.mlUpgradeBreakdown!.rawHcp, equals(14.0));
      expect(result.mlUpgradeBreakdown!.effectiveHcp, greaterThanOrEqualTo(16.0));
    });
  });
}
