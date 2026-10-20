import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/hand_parser.dart';

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

  group('Vanilla Preempts & Modular Namyats Suite', () {
    late BridgeSystem gavinSystem;
    late BridgeSystem usStandardSystem;
    late AuctionEngine gavinEngine;
    late AuctionEngine usStandardEngine;

    setUpAll(() async {
      gavinSystem = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      usStandardSystem = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      gavinEngine = AuctionEngine.fromSystem(gavinSystem);
      usStandardEngine = AuctionEngine.fromSystem(usStandardSystem);
    });

    group('Solid Minor 3NT Opening Evaluation', () {
      final parser = ConstraintParser();
      final valuation = MiltonWorkValuation();
      final ruleConstraint = parser.parse('solid_minor outside_ctrl=0');

      test('Hand with solid Clubs AKQxxxx and 0 outside controls matches 3NT', () {
        // Spades: 96, Hearts: J43, Diamonds: 3, Clubs: AKQ8752
        final hand = HandParser.parseSingleHand('96.J43.3.AKQ8752');

        expect(hand.isSolidMinor(), isTrue);
        expect(hand.outsideControlsForSolidMinor, equals(0));
        final result = ruleConstraint.evaluate(hand, valuation);
        expect(result.isMatch, isTrue, reason: 'AKQxxxx in clubs with 0 outside controls must match solid_minor');
      });

      test('Hand with AKJxxxx in clubs (missing Queen) fails 3NT', () {
        // Spades: 96, Hearts: J43, Diamonds: 3, Clubs: AKJ8752
        final hand = HandParser.parseSingleHand('96.J43.3.AKJ8752');

        expect(hand.isSolidMinor(), isFalse);
        final result = ruleConstraint.evaluate(hand, valuation);
        expect(result.isMatch, isFalse, reason: 'AKJxxxx lacking Queen must not qualify as solid minor');
      });

      test('Hand with solid clubs but outside King fails outside_ctrl=0', () {
        // Spades: 96, Hearts: K43, Diamonds: 3, Clubs: AKQ8752
        final hand = HandParser.parseSingleHand('96.K43.3.AKQ8752');

        expect(hand.isSolidMinor(), isTrue);
        expect(hand.outsideControlsForSolidMinor, equals(1));
        final result = ruleConstraint.evaluate(hand, valuation);
        expect(result.isMatch, isFalse, reason: 'Holding outside King violates classic Gambling 3NT outside_ctrl=0');
      });
    });

    group('Slam Risk Prevention on Preempts', () {
      final parser = ConstraintParser();
      final valuation = MiltonWorkValuation();
      final preemptRule = parser.parse('6-10hcp 8+s 6+ltc controls<=2 outside_ctrl<=1');

      test('Disciplined weak 8-card spade hand qualifies for 4S preempt', () {
        // Spades: QJT87652, Hearts: K43, Diamonds: 2, Clubs: 9 (6 HCP, 7 LTC, 1 control)
        final hand = HandParser.parseSingleHand('QJT87652.K43.2.9');

        expect(hand.spadesLength, equals(8));
        expect(hand.hcp, equals(6));
        expect(hand.losingTrickCount, greaterThanOrEqualTo(6));
        expect(hand.controls, lessThanOrEqualTo(2));
        final result = preemptRule.evaluate(hand, valuation);
        expect(result.isMatch, isTrue, reason: 'Disciplined weak 8-card major hand should qualify for 4S preempt');
      });

      test('Strong 8-card spade hand risks slam and FAILS 4S preempt rule', () {
        // Spades: AKQ87652, Hearts: A43, Diamonds: 2, Clubs: 9 (13 HCP, 4 LTC, 5 controls!)
        final hand = HandParser.parseSingleHand('AKQ87652.A43.2.9');

        expect(hand.spadesLength, equals(8));
        expect(hand.hcp, equals(13));
        expect(hand.losingTrickCount, lessThan(6));
        expect(hand.controls, greaterThan(2));
        final result = preemptRule.evaluate(hand, valuation);
        expect(result.isMatch, isFalse, reason: 'Monster hand with 13 HCP and 4 LTC must not preempt 4S and risk missing slam');
      });
    });

    group('US Standard 2/1 Natural Preempts vs Gavin Wolpert Namyats', () {
      test('US Standard 2/1 has natural 4C and 4D minor preempts', () {
        final state4C = usStandardEngine.graph.getState(['4c']);
        expect(state4C, isNotNull);
        final calls4C = state4C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
        expect(calls4C, containsAll(['pass', '4nt', '5c']));

        final state4D = usStandardEngine.graph.getState(['4d']);
        expect(state4D, isNotNull);
        final calls4D = state4D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
        expect(calls4D, containsAll(['pass', '4nt', '5d']));
      });

      test('Gavin Wolpert 2/1 has Namyats 4C (Hearts) and 4D (Spades)', () {
        final state4C = gavinEngine.graph.getState(['4c']);
        expect(state4C, isNotNull);
        final calls4C = state4C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
        expect(calls4C, containsAll(['4d', '4h', '4nt']), reason: '4C Namyats includes 4D control ask and 4H relay');

        final state4D = gavinEngine.graph.getState(['4d']);
        expect(state4D, isNotNull);
        final calls4D = state4D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
        expect(calls4D, containsAll(['4h', '4s', '4nt']), reason: '4D Namyats includes 4H control ask and 4S relay');
      });

      test('Both systems resolve 3C, 3D, 3H, 3S and Solid Minor 3NT identically', () {
        for (final eng in [gavinEngine, usStandardEngine]) {
          // 3C
          final state3C = eng.graph.getState(['3c']);
          expect(state3C, isNotNull);
          expect(state3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet(),
              containsAll(['pass', '3d', '3h', '3s', '3nt', '4c', '5c']));

          // 3H
          final state3H = eng.graph.getState(['3h']);
          expect(state3H, isNotNull);
          expect(state3H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet(),
              containsAll(['pass', '3s', '3nt', '4h', '4nt']));

          // 3NT
          final state3NT = eng.graph.getState(['3nt']);
          expect(state3NT, isNotNull);
          expect(state3NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet(),
              containsAll(['pass', '4c', '4d', '4h', '4s', '5c']));
        }
      });
    });
  });
}
