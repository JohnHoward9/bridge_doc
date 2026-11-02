import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';

void main() {
  group('ConstraintParser (5-6)h Parenthesized Range Notation', () {
    final parser = ConstraintParser();
    final valuation = MiltonWorkValuation();

    test('(5-6)h matches 5 and 6 hearts, fails 4 and 7 hearts', () {
      final constraint = parser.parse('(5-6)h');

      final hand6H = Hand.fromString('K62.QT9873.84.32');
      expect(hand6H.heartsLength, equals(6));
      expect(constraint.evaluate(hand6H, valuation).isMatch, isTrue);

      final hand5H = Hand.fromString('K62.QT987.842.32');
      expect(hand5H.heartsLength, equals(5));
      expect(constraint.evaluate(hand5H, valuation).isMatch, isTrue);

      final hand7H = Hand.fromString('K62.QT98732.84.3');
      expect(hand7H.heartsLength, equals(7));
      expect(constraint.evaluate(hand7H, valuation).isMatch, isFalse, reason: '7-card suit must FAIL (5-6)h');

      final hand4H = Hand.fromString('K62.QT98.8432.32');
      expect(hand4H.heartsLength, equals(4));
      expect(constraint.evaluate(hand4H, valuation).isMatch, isFalse, reason: '4-card suit must FAIL (5-6)h');
    });

    test('(5-6)s and (5-6)d parenthesized ranges evaluate correctly', () {
      final constraintS = parser.parse('(5-6)s');
      final constraintD = parser.parse('(5-6)d');

      final hand6S = Hand.fromString('AK9873.62.84.32');
      expect(constraintS.evaluate(hand6S, valuation).isMatch, isTrue);

      final hand7S = Hand.fromString('AK98732.6.84.32');
      expect(constraintS.evaluate(hand7S, valuation).isMatch, isFalse);

      final hand5D = Hand.fromString('AK.62.AQ987.432');
      expect(constraintD.evaluate(hand5D, valuation).isMatch, isTrue);
    });
  });

  group('DealGenerator Dynamic Rule Execution from BridgeSystem & Graph', () {
    final generator = DealGenerator();

    test('Custom Weak 1NT system (11-13 HCP): DealGenerator executes rule dynamically, dealing 11-13 HCP (not 15-17)', () {
      final customSystem = BridgeSystem(
        name: 'Custom Weak NT',
        openingBids: [
          BiddingNode(
            call: '1nt',
            desc: 'Mini Weak NT (11-13 HCP)',
            rule: '11-13hcp balanced',
          ),
        ],
      );

      final graph = BiddingGraphCompiler(system: customSystem).compile();

      for (int i = 0; i < 15; i++) {
        final deal = generator.dealBoardForSequence(['1nt'], graph: graph);
        final north = deal.north;

        expect(north.hcp, inInclusiveRange(11, 13), reason: 'Dynamic rule execution: North HCP must be 11-13');
        expect(north.isBalanced, isTrue, reason: 'North hand must be balanced as required by rule');
        expect(north.hcp, isNot(greaterThan(13)), reason: 'Should not generate default 15-17 NT');
      }
    });

    test('Custom Weak Two in Hearts with (5-6)h: DealGenerator deals 5-6 hearts without 7-card suits', () {
      final customSystem = BridgeSystem(
        name: 'Custom Weak Two System',
        openingBids: [
          BiddingNode(
            call: '2h',
            desc: 'Disciplined Weak Two in Hearts',
            rule: '(5-6)h 5-10hcp',
          ),
        ],
      );

      final graph = BiddingGraphCompiler(system: customSystem).compile();

      for (int i = 0; i < 20; i++) {
        final deal = generator.dealBoardForSequence(['2h'], graph: graph);
        final north = deal.north;

        expect(north.hcp, inInclusiveRange(5, 10));
        expect(north.heartsLength, inInclusiveRange(5, 6));
        expect(north.heartsLength, isNot(greaterThan(6)), reason: '7-card hearts must never be dealt for (5-6)h rule');
      }
    });

    test('Sequence with responder bid: DealGenerator filters both North and South dynamically from system rules', () {
      final customSystem = BridgeSystem(
        name: 'Custom Major Opening with GF Response',
        openingBids: [
          BiddingNode(
            call: '1h',
            desc: 'Hearts opening',
            rule: '12-14hcp 5+h',
            bids: [
              BiddingNode(
                call: '2nt',
                desc: 'Jacoby 2NT GF',
                rule: '13+hcp 4+h',
              ),
            ],
          ),
        ],
      );

      final graph = BiddingGraphCompiler(system: customSystem).compile();

      for (int i = 0; i < 15; i++) {
        final deal = generator.dealBoardForSequence(['1h', '2nt'], graph: graph);

        // North opened 1h: 12-14 HCP, 5+ hearts
        expect(deal.north.hcp, inInclusiveRange(12, 14));
        expect(deal.north.heartsLength, greaterThanOrEqualTo(5));

        // South responded 2nt: 13+ HCP, 4+ hearts
        expect(deal.south.hcp, greaterThanOrEqualTo(13));
        expect(deal.south.heartsLength, greaterThanOrEqualTo(4));
      }
    });
  });

  group('Priority Field and Rule Tag Equivalence', () {
    test('node.effectivePriority resolves cleanly from priority field without p# in rule', () {
      // 1. Clean modern syntax: priority: 1, rule: "14+hcp" (no p#)
      final modernNode = BiddingNode(
        call: '2nt',
        priority: 1,
        rule: '14+hcp',
      );
      expect(modernNode.effectivePriority, equals(1));

      // 2. Legacy BBS syntax: priority: null, rule: "p#2 14+hcp"
      final legacyNode = BiddingNode(
        call: '2nt',
        rule: 'p#2 14+hcp',
      );
      expect(legacyNode.effectivePriority, equals(2));

      // 3. Both present: priority property takes precedence
      final bothNode = BiddingNode(
        call: '2nt',
        priority: 1,
        rule: 'p#3 14+hcp',
      );
      expect(bothNode.effectivePriority, equals(1));
    });
  });
}
