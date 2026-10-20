import 'package:flutter_test/flutter_test.dart';
import '../lib/models/card.dart';
import '../lib/models/hand.dart';
import '../lib/engine/deal_generator.dart';
import '../lib/models/bidding_system.dart';
import '../lib/constraints/constraint_parser.dart';
import '../lib/constraints/specificity_resolver.dart';

void main() {
  test('PartnershipDeal deals 52 distinct cards across North, East, South, West', () {
    final generator = DealGenerator();
    final board = generator.dealFullBoard();

    expect(board.north.cards.length, 13);
    expect(board.east.cards.length, 13);
    expect(board.south.cards.length, 13);
    expect(board.west.cards.length, 13);

    // Verify all 52 cards are distinct
    final allCards = <BridgeCard>{
      ...board.north.cards,
      ...board.east.cards,
      ...board.south.cards,
      ...board.west.cards,
    };
    expect(allCards.length, 52, reason: 'All 52 cards across the four hands must be distinct');
  });

  test('Automated North opening bid matches North cards and South responds', () {
    final generator = DealGenerator();
    final resolver = SpecificityResolver(parser: ConstraintParser());

    // North has 14 HCP with 5 Hearts: ♠A3 ♥KQ864 ♦972 ♣AJ5
    final northHand = Hand.fromString('A3:KQ864:972:AJ5');
    // South has 8 HCP with 4 Spades: ♠KJ84 ♥65 ♦Q97 ♣J865
    final southHand = Hand.fromString('KJ84:65:Q97:J865');

    final openingCandidates = [
      BiddingNode(call: 'pass', rule: '10-hcp'),
      BiddingNode(call: '1c', rule: '10+hcp, 2+c'),
      BiddingNode(call: '1h', rule: '10+hcp, 5+h', bids: [
        BiddingNode(call: 'pass', rule: '5-hcp'),
        BiddingNode(call: '1s', rule: 'p#3 5-10hcp 4s 2-h'),
        BiddingNode(call: '1nt', rule: 'p#4 6-11hcp'),
      ]),
    ];

    // North bids automatically
    final northBid = resolver.resolveBestBid(northHand, openingCandidates);
    expect(northBid, isNotNull);
    expect(northBid!.call, '1h', reason: 'North holds 14 HCP and 5+H, so North automatically opens 1H');

    // South responds to North's 1h opening
    final southBid = resolver.resolveBestBid(southHand, northBid.bids);
    expect(southBid, isNotNull);
    expect(southBid!.call, '1s', reason: 'South holds 4s 2-h 8hcp, so South responds 1s (p#3)');
  });

  test('DealGenerator.dealTargetedBoard generates South hand matching HCP and Shape filters', () {
    final generator = DealGenerator();

    // Generate 10 boards with North 15-17 balanced (1NT) and South 10-15 HCP with 5-4 in majors
    for (int i = 0; i < 10; i++) {
      final board = generator.dealTargetedBoard(
        isNorthMatch: (n) => n.hcp >= 15 && n.hcp <= 17 && n.isBalanced,
        isSouthMatch: (s) =>
            SouthHcpFilter.choiceOfGames.matches(s) &&
            SouthShapeFilter.smolen54.matches(s),
      );

      // Verify North 1NT opening
      expect(board.north.hcp, inInclusiveRange(15, 17));
      expect(board.north.isBalanced, isTrue);

      // Verify South satisfies filters
      expect(board.south.hcp, inInclusiveRange(10, 15));
      final has54Majors = (board.south.heartsLength == 5 && board.south.spadesLength == 4) ||
          (board.south.spadesLength == 5 && board.south.heartsLength == 4);
      expect(has54Majors, isTrue, reason: 'South must have 5-4 in majors (Smolen candidate)');

      // Verify all 52 cards are distinct
      final allCards = <BridgeCard>{
        ...board.north.cards,
        ...board.east.cards,
        ...board.south.cards,
        ...board.west.cards,
      };
      expect(allCards.length, 52);
    }
  });

  test('SouthShapeFilter evaluates various bridge shapes accurately', () {
    final hand5h4s = Hand.fromString('A653:A9742:Q5:62');
    expect(SouthShapeFilter.smolen54.matches(hand5h4s), isTrue);
    expect(SouthShapeFilter.smolen5h4s.matches(hand5h4s), isTrue);
    expect(SouthShapeFilter.smolen5s4h.matches(hand5h4s), isFalse);
    expect(SouthShapeFilter.transferHearts.matches(hand5h4s), isTrue);
    expect(SouthShapeFilter.transferSpades.matches(hand5h4s), isFalse);

    final hand5s4h = Hand.fromString('AQJ97:QT83:J84:3');
    expect(SouthShapeFilter.smolen54.matches(hand5s4h), isTrue);
    expect(SouthShapeFilter.smolen5s4h.matches(hand5s4h), isTrue);
    expect(SouthShapeFilter.smolen5h4s.matches(hand5s4h), isFalse);
    expect(SouthShapeFilter.transferSpades.matches(hand5s4h), isTrue);

    final handBalanced = Hand.fromString('A86:AQ2:K63:Q854');
    expect(SouthShapeFilter.balanced.matches(handBalanced), isTrue);
    expect(SouthShapeFilter.smolen54.matches(handBalanced), isFalse);
  });
}
