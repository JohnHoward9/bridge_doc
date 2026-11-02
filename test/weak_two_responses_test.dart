import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';

void main() {
  group('Weak Two Responses Suite (weak_two_responses.yaml)', () {
    late String yamlContent;
    late BridgeSystem library;

    setUpAll(() async {
      yamlContent = await File('assets/libraries/conventions/weak_two_responses.yaml').readAsString();
      library = SystemYamlParser.fromYaml(yamlContent);
    });

    test('weak_two_responses.yaml parses standalone and contains unified fragment fWeakTwo with all aliases', () {
      expect(library.fragments.containsKey('fWeakTwo'), isTrue);

      final expectedAliases = [
        'WeakTwoDiamonds',
        'WeakTwoHearts',
        'WeakTwoSpades',
        'fWeakTwoDiamondResponses',
        'fWeakTwoHeartResponses',
        'fWeakTwoSpadeResponses',
      ];

      for (final alias in expectedAliases) {
        expect(library.fragments.containsKey(alias), isTrue, reason: 'Missing alias: $alias');
        expect(library.fragments[alias]!.name, equals('fWeakTwo'));
      }
    });

    test('Weak Two in Diamonds (2d): resolves children with higher ranking suits 2h/2s and 2NT feature ask', () {
      final node = BiddingNode(call: '2d', ref: 'WeakTwoDiamonds');
      final resolved = node.withResolvedFragmentMetadata(library.fragments);

      final children = resolved.getEffectiveChildren({'suit': 'd', 'm': 'd', 'om': 'c'});
      final calls = children.map((c) => c.displayCall).toList();

      expect(calls, contains('2h'));
      expect(calls, contains('2s'));
      expect(calls, contains('2nt'));
      expect(calls, contains('3c'));
      expect(calls, contains('3d'));
      expect(calls, contains('3nt'));
      expect(calls, contains('5d'));

      // Hearts and Spades raises should not appear over 2d
      expect(calls, isNot(contains('4h')));
      expect(calls, isNot(contains('4s')));

      // Feature ask 2NT rebids over 2d
      final node2nt = children.firstWhere((c) => c.call == '2nt');
      final faChildren = node2nt.getEffectiveChildren({'suit': 'd', 'm': 'd'});
      final faCalls = faChildren.map((c) => c.displayCall).toList();

      expect(faCalls, contains('3c')); // Club feature
      expect(faCalls, contains('3d')); // Minimum rebid
      expect(faCalls, contains('3h')); // Heart feature
      expect(faCalls, contains('3s')); // Spade feature
      expect(faCalls, contains('3nt')); // Solid Diamonds
    });

    test('Weak Two in Hearts (2h): resolves 2s new suit, 2NT feature ask, 3h raise, and 4h game', () {
      final node = BiddingNode(call: '2h', ref: 'WeakTwoHearts');
      final resolved = node.withResolvedFragmentMetadata(library.fragments);

      final children = resolved.getEffectiveChildren({'suit': 'h', 'M': 'h', 'OM': 's'});
      final calls = children.map((c) => c.displayCall).toList();

      expect(calls, isNot(contains('2h'))); // cannot bid 2h over 2h
      expect(calls, contains('2s')); // 2s is higher ranking
      expect(calls, contains('2nt')); // Feature ask
      expect(calls, contains('3c')); // new suit
      expect(calls, contains('3d')); // new suit
      expect(calls, contains('3h')); // preemptive raise
      expect(calls, contains('3nt')); // to play
      expect(calls, contains('4h')); // game raise in hearts

      // 5d minor game should not appear over 2h
      expect(calls, isNot(contains('5d')));

      // Feature ask 2NT rebids over 2h
      final node2nt = children.firstWhere((c) => c.call == '2nt');
      final faChildren = node2nt.getEffectiveChildren({'suit': 'h', 'M': 'h', 'OM': 's'});
      final faCalls = faChildren.map((c) => c.displayCall).toList();

      expect(faCalls, contains('3c')); // Club feature
      expect(faCalls, contains('3d')); // Diamond feature
      expect(faCalls, contains('3h')); // Minimum rebid in hearts
      expect(faCalls, contains('3s')); // Spade feature
      expect(faCalls, contains('3nt')); // Solid hearts
    });

    test('Weak Two in Spades (2s): resolves 2NT feature ask, 3c/3d/3h new suits, 3s raise, and 4s game', () {
      final node = BiddingNode(call: '2s', ref: 'WeakTwoSpades');
      final resolved = node.withResolvedFragmentMetadata(library.fragments);

      final children = resolved.getEffectiveChildren({'suit': 's', 'M': 's', 'OM': 'h'});
      final calls = children.map((c) => c.displayCall).toList();

      // No 2-level suit can be bid over 2s
      expect(calls.where((c) => c.startsWith('2') && c != '2nt'), isEmpty);

      expect(calls, contains('2nt')); // Feature ask
      expect(calls, contains('3c')); // new suit
      expect(calls, contains('3d')); // new suit
      expect(calls, contains('3h')); // new suit
      expect(calls, contains('3s')); // preemptive raise
      expect(calls, contains('3nt')); // to play
      expect(calls, contains('4s')); // game raise in spades

      // Feature ask 2NT rebids over 2s
      final node2nt = children.firstWhere((c) => c.call == '2nt');
      final faChildren = node2nt.getEffectiveChildren({'suit': 's', 'M': 's', 'OM': 'h'});
      final faCalls = faChildren.map((c) => c.displayCall).toList();

      expect(faCalls, contains('3c')); // Club feature
      expect(faCalls, contains('3d')); // Diamond feature
      expect(faCalls, contains('3h')); // Heart feature
      expect(faCalls, contains('3s')); // Minimum rebid in spades
      expect(faCalls, contains('3nt')); // Solid spades
    });

    test(r'Clean rule and cond field parsing: 3h has cond "$suit=s", rule without p#2, and priority 2', () {
      final fWeakTwo = library.fragments['fWeakTwo']!;

      final node3h = fWeakTwo.bids.firstWhere((b) => b.call == '3h');
      expect(node3h.condition, equals(r'$suit=s'));
      expect(node3h.rule, equals('14+hcp 5+h'), reason: 'Redundant p#2 must be removed from rule');
      expect(node3h.priority, equals(2));
      expect(node3h.effectivePriority, equals(2));

      final node2h = fWeakTwo.bids.firstWhere((b) => b.call == '2h');
      expect(node2h.condition, equals(r'$suit=d'));
      expect(node2h.rule, equals('14+hcp 5+h'));
      expect(node2h.priority, equals(2));

      final node2s = fWeakTwo.bids.firstWhere((b) => b.call == '2s');
      expect(node2s.condition, equals(r'$suit=d,h'));
      expect(node2s.rule, equals('14+hcp 5+s'));
      expect(node2s.priority, equals(2));
    });

    test('SystemYamlParser parses cond alias in both mapping and list bid formats', () {
      const mapYaml = '''
system: "Test System Map"
openings:
  3h:
    cond: "\$suit=s"
    desc: "Natural new suit"
    rule: "14+hcp 5+h"
    priority: 2
''';
      final parsedMap = SystemYamlParser.fromYaml(mapYaml);
      expect(parsedMap.openingBids.length, 1);
      expect(parsedMap.openingBids.first.call, '3h');
      expect(parsedMap.openingBids.first.condition, r'$suit=s');
      expect(parsedMap.openingBids.first.rule, '14+hcp 5+h');
      expect(parsedMap.openingBids.first.priority, 2);

      const listYaml = '''
system: "Test System List"
openings:
  - call: 3h
    cond: "\$suit=s"
    desc: "Natural new suit"
    rule: "14+hcp 5+h"
    priority: 2
''';
      final parsedList = SystemYamlParser.fromYaml(listYaml);
      expect(parsedList.openingBids.length, 1);
      expect(parsedList.openingBids.first.call, '3h');
      expect(parsedList.openingBids.first.condition, r'$suit=s');
      expect(parsedList.openingBids.first.rule, '14+hcp 5+h');
      expect(parsedList.openingBids.first.priority, 2);
    });
  });

  group('Suit Length Constraint Range Parsing & Evaluation', () {
    final parser = ConstraintParser();
    final valuation = MiltonWorkValuation();

    test('Parses 5-6h range correctly (matches 5 and 6, fails 4 and 7)', () {
      final constraint = parser.parse('5-6h');

      // 6 hearts hand (5 HCP)
      final hand6H = Hand.fromString('K62.QT9873.84.32');
      expect(hand6H.heartsLength, equals(6));
      expect(constraint.evaluate(hand6H, valuation).isMatch, isTrue);

      // 5 hearts hand (6 HCP)
      final hand5H = Hand.fromString('K62.QT987.842.32');
      expect(hand5H.heartsLength, equals(5));
      expect(constraint.evaluate(hand5H, valuation).isMatch, isTrue);

      // 7 hearts hand (User reported bug hand: K62:QT98732:84:3)
      final hand7H = Hand.fromString('K62.QT98732.84.3');
      expect(hand7H.heartsLength, equals(7));
      expect(constraint.evaluate(hand7H, valuation).isMatch, isFalse, reason: '7-card suit must FAIL 5-6h');

      // 4 hearts hand
      final hand4H = Hand.fromString('K62.QT98.8432.32');
      expect(hand4H.heartsLength, equals(4));
      expect(constraint.evaluate(hand4H, valuation).isMatch, isFalse, reason: '4-card suit must FAIL 5-6h');
    });

    test('Parses 6=h exact length correctly (matches 6, fails 5 and 7)', () {
      final constraint = parser.parse('6=h');

      final hand6H = Hand.fromString('K62.QT9873.84.32');
      expect(constraint.evaluate(hand6H, valuation).isMatch, isTrue);

      final hand5H = Hand.fromString('K62.QT987.842.32');
      expect(constraint.evaluate(hand5H, valuation).isMatch, isFalse);

      final hand7H = Hand.fromString('K62.QT98732.84.3');
      expect(constraint.evaluate(hand7H, valuation).isMatch, isFalse);
    });

    test('Parses full Weak Two rule: 5-10hcp 5-6h', () {
      final rule = parser.parse('5-10hcp 5-6h');

      // 6 hearts, 6 HCP -> MATCH
      final validHand = Hand.fromString('K62.QT9873.84.32');
      expect(rule.evaluate(validHand, valuation).isMatch, isTrue);

      // 7 hearts, 5 HCP (User reported bug hand) -> MUST FAIL (belongs to 3H preempt)
      final bugHand7H = Hand.fromString('K62.QT98732.84.3');
      expect(rule.evaluate(bugHand7H, valuation).isMatch, isFalse);

      // 6 hearts, 12 HCP -> FAILS (too strong for weak two)
      final strongHand = Hand.fromString('AK2.KQ9873.84.32');
      expect(rule.evaluate(strongHand, valuation).isMatch, isFalse);
    });
  });

  group('DealGenerator Weak Two Suit Length Guarantee', () {
    final generator = DealGenerator();

    test('dealBoardForSequence("2h"): dealt North hand ALWAYS has 5-6 hearts, NEVER 7+ hearts', () {
      for (int i = 0; i < 30; i++) {
        final board = generator.dealBoardForSequence(['2h']);
        final north = board.north;

        expect(north.hcp, inInclusiveRange(5, 10), reason: 'North HCP must be 5-10');
        expect(north.heartsLength, inInclusiveRange(5, 6), reason: 'North Hearts length must be 5-6');
        expect(north.heartsLength, isNot(greaterThan(6)), reason: 'North Hearts length must NEVER be 7+');
      }
    });

    test('dealBoardForSequence("2h", isVulnerable: true): dealt North hand ALWAYS has exactly 6 hearts', () {
      for (int i = 0; i < 20; i++) {
        final board = generator.dealBoardForSequence(['2h'], isVulnerable: true);
        final north = board.north;

        expect(north.hcp, inInclusiveRange(5, 10));
        expect(north.heartsLength, equals(6), reason: 'Vulnerable Weak Two must hold disciplined 6-card suit');
      }
    });

    test('dealBoardForSequence("3h"): dealt North hand holds 7+ hearts (3-level preempt)', () {
      for (int i = 0; i < 15; i++) {
        final board = generator.dealBoardForSequence(['3h']);
        final north = board.north;

        expect(north.hcp, inInclusiveRange(6, 10));
        expect(north.heartsLength, greaterThanOrEqualTo(7), reason: '3H preempt must hold 7+ hearts');
      }
    });
  });
}
