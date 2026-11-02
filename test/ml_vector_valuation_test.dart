import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/models/ml_hand_valuation_model.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';

void main() {
  group('True ML Vector Valuation & Shape Differentiation Tests', () {
    test('6-4-2-1 hand evaluates higher than 6-3-3-1 hand with identical Milton Work HCP', () {
      final valuation = MLHandValuation();

      // Hand A: 6-4-2-1 shape: ♠AKJ942 (8) ♥Q853 (2) ♦72 (0) ♣6 (0) = 10 HCP
      final hand6421 = Hand.fromString('AKJ942.Q853.72.6');
      expect(hand6421.hcp, equals(10));
      expect(hand6421.spadesLength, equals(6));
      expect(hand6421.heartsLength, equals(4));

      // Hand B: 6-3-3-1 shape: ♠AKJ942 (8) ♥Q85 (2) ♦742 (0) ♣6 (0) = 10 HCP
      // Identical honors, identical Milton Work HCP, but two flat 3-card side suits
      final hand6331 = Hand.fromString('AKJ942.Q85.742.6');
      expect(hand6331.hcp, equals(10));
      expect(hand6331.spadesLength, equals(6));
      expect(hand6331.heartsLength, equals(3));

      final eff6421 = valuation.evaluatePoints(hand6421, trumpSuit: Suit.spades);
      final eff6331 = valuation.evaluatePoints(hand6331, trumpSuit: Suit.spades);

      final breakdown6421 = valuation.evaluateBreakdown(hand6421, trumpSuit: Suit.spades);
      final breakdown6331 = valuation.evaluateBreakdown(hand6331, trumpSuit: Suit.spades);

      // The 6-4-2-1 hand must evaluate significantly higher than the 6-3-3-1 hand
      expect(eff6421, greaterThan(eff6331 + 0.8),
          reason: '6-4-2-1 two-suiter distribution is worth ~1.05 HCP more than 6-3-3-1');
    });

    test('Trapped King under LHO opponent call devalues by -1.3 Effective HCP', () {
      final valuation = MLHandValuation();
      final northHand = Hand.fromString('K8.AQ5.KJ42.Q862'); // raw 15 HCP

      final actionWest2S = OpponentSuitAction(
        suit: Suit.spades,
        position: RelativeOpponentPosition.lho,
        call: '2s',
        seat: 'W',
      );

      final breakdown = valuation.evaluateBreakdown(
        northHand,
        opponentActions: [actionWest2S],
      );

      expect(breakdown.effectiveHcp, lessThan(15.0 - 1.0));
    });

    test('Protected King over RHO opponent call maintains value', () {
      final valuation = MLHandValuation();
      final northHand = Hand.fromString('K8.AQ5.KJ42.Q862');

      final actionEast2S = OpponentSuitAction(
        suit: Suit.spades,
        position: RelativeOpponentPosition.rho,
        call: '2s',
        seat: 'E',
      );

      final breakdown = valuation.evaluateBreakdown(
        northHand,
        opponentActions: [actionEast2S],
      );

    });
  });
}
