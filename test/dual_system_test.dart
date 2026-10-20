import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/ui/practice_quiz_view.dart';

void main() {
  group('Dual-System Support Tests (NS & EW)', () {
    late BridgeSystem nsSystem;
    late BridgeSystem ewSystem;

    setUp(() {
      nsSystem = BridgeSystem(
        name: 'Gavin Wolpert 2/1 (NS)',
        openingBids: [
          BiddingNode(
            call: '1h',
            desc: '5+ Hearts, 12-21 HCP',
            rule: '12-21hcp 5+h',
          ),
          BiddingNode(
            call: 'pass',
            desc: 'Pass',
            rule: '11-hcp',
          ),
        ],
        oppositionOpeningBids: [
          BiddingNode(
            call: '(1s)',
            desc: 'Opponent opened 1S',
            rule: '12-21hcp 5+s',
          ),
        ],
      );

      ewSystem = BridgeSystem(
        name: 'UK Acol 4CM (EW)',
        openingBids: [
          BiddingNode(
            call: '1s',
            desc: '4+ Spades, 12-20 HCP',
            rule: '12-20hcp 4+s',
          ),
          BiddingNode(
            call: 'pass',
            desc: 'Pass',
            rule: '11-hcp',
          ),
        ],
        oppositionOpeningBids: [
          BiddingNode(
            call: '(1h)',
            desc: 'Opponent opened 1H',
            rule: '12-21hcp 5+h',
            bids: [
              BiddingNode(
                call: '1s',
                desc: 'Overcall 1S (8-16 HCP, 5+ Spades)',
                rule: '8-16hcp 5+s',
              ),
              BiddingNode(
                call: 'pass',
                desc: 'Pass over 1H',
                rule: '7-hcp',
              ),
            ],
          ),
        ],
      );
    });

    test('AuctionEngine compiles both NS and EW graphs independently', () {
      final engine = AuctionEngine.fromSystem(nsSystem, ewSystem: ewSystem);

      expect(engine.nsSystem.name, equals('Gavin Wolpert 2/1 (NS)'));
      expect(engine.ewSystem?.name, equals('UK Acol 4CM (EW)'));
      expect(engine.graph, isNotNull);
      expect(engine.ewGraph, isNotNull);
    });

    test('extractSystemSequence correctly separates perspective for NS and EW', () {
      final engine = AuctionEngine.fromSystem(nsSystem, ewSystem: ewSystem);

      final history = [
        const AuctionEntry(seat: 'N', call: '1H', desc: 'Opening'),
        const AuctionEntry(seat: 'E', call: '1S', desc: 'Overcall'),
        const AuctionEntry(seat: 'S', call: '2H', desc: 'Raise'),
        const AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ];

      // Perspective for North-South:
      // N and S calls are unbracketed, E and W calls are in parentheses: ['1h', '(1s)', '2h']
      final nsSeq = engine.extractSystemSequence(history, forEastWest: false);
      expect(nsSeq, equals(['1h', '(1s)', '2h']));

      // Perspective for East-West:
      // E and W calls are friendly (including friendly pass), N and S calls are in parentheses:
      final ewSeq = engine.extractSystemSequence(history, forEastWest: true);
      expect(ewSeq, equals(['(1h)', '1s', '(2h)', 'pass']));
    });

    test('East overcalls using EW system when holding suitable values over North 1H', () {
      final engine = AuctionEngine.fromSystem(nsSystem, ewSystem: ewSystem);

      // Deal where North opens 1H and East has 5 Spades and 11 HCP (qualifying for 1S overcall in Acol)
      final northHand = Hand.fromString('A3:KQ543:432:K43'); // 14 HCP, 5 hearts
      final eastHand = Hand.fromString('KQJT4:A2:987:654'); // 11 HCP, 5 spades -> qualifies for EW (1h) -> 1s
      final southHand = Hand.fromString('98:JT98:AKJ:Q876'); // 11 HCP
      final westHand = Hand.fromString('7652:76:Q65:JT92');

      final deal = PartnershipDeal(
        north: northHand,
        east: eastHand,
        south: southHand,
        west: westHand,
      );

      final result = engine.startDeal(deal: deal, isNorthFirst: true);

      expect(result.updatedHistory.length, equals(2));
      expect(result.updatedHistory[0].seat, equals('N'));
      expect(result.updatedHistory[0].call.toLowerCase(), equals('1h'));

      // East should have overcalled 1S based on EW system!
      expect(result.updatedHistory[1].seat, equals('E'));
      expect(result.updatedHistory[1].call.toLowerCase(), equals('1s'));
      expect(result.feedbackMessage, contains('East bid 1s'));
    });

    test('East passes when holding weak values over North 1H', () {
      final engine = AuctionEngine.fromSystem(nsSystem, ewSystem: ewSystem);

      // Deal where North opens 1H and East has weak values (passes)
      final northHand = Hand.fromString('A3:KQ543:432:K43');
      final eastHand = Hand.fromString('432:32:8765:6543'); // 0 HCP -> passes
      final southHand = Hand.fromString('KQJ:AJT:AKJ:AKQJ');
      final westHand = Hand.fromString('T987:9876:T9:T98');

      final deal = PartnershipDeal(
        north: northHand,
        east: eastHand,
        south: southHand,
        west: westHand,
      );

      final result = engine.startDeal(deal: deal, isNorthFirst: true);

      expect(result.updatedHistory.length, equals(2));
      expect(result.updatedHistory[0].seat, equals('N'));
      expect(result.updatedHistory[0].call.toLowerCase(), equals('1h'));
      expect(result.updatedHistory[1].seat, equals('E'));
      expect(result.updatedHistory[1].call.toLowerCase(), equals('pass'));
      expect(result.feedbackMessage, contains('North opened 1h. Your turn to respond.'));
    });

    testWidgets('PracticeQuizView renders both NS and EW system badges', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeQuizView(
              system: nsSystem,
              ewSystem: ewSystem,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify NS badge and system name
      expect(find.text('NS'), findsWidgets);
      expect(find.text('Gavin Wolpert 2/1 (NS)'), findsOneWidget);

      // Verify EW badge and system name
      expect(find.text('EW'), findsWidgets);
      expect(find.text('UK Acol 4CM (EW)'), findsOneWidget);
    });
  });
}
