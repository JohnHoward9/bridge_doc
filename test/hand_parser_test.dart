import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/hand_parser.dart';

void main() {
  group('HandParser Tests', () {
    test('parseSingleHand parses dot-separated string with void', () {
      final hand = HandParser.parseSingleHand('K87.AJT976543.K.-');
      expect(hand.cards.length, equals(13));
      expect(hand.spadesLength, equals(3));
      expect(hand.heartsLength, equals(9));
      expect(hand.diamondsLength, equals(1));
      expect(hand.clubsLength, equals(0));
      expect(hand.hcp, equals(11));
    });

    test('parseSingleHand parses multiline suit format', () {
      const text = '''
S: K87
H: AJT976543
D: K
C: -
''';
      final hand = HandParser.parseSingleHand(text);
      expect(hand.cards.length, equals(13));
      expect(hand.spadesLength, equals(3));
      expect(hand.heartsLength, equals(9));
      expect(hand.diamondsLength, equals(1));
      expect(hand.clubsLength, equals(0));
      expect(hand.hcp, equals(11));
    });

    test('parseSingleHand parses LIN format', () {
      final hand = HandParser.parseSingleHand('SK87HAJT976543DKC');
      expect(hand.cards.length, equals(13));
      expect(hand.spadesLength, equals(3));
      expect(hand.heartsLength, equals(9));
      expect(hand.diamondsLength, equals(1));
      expect(hand.clubsLength, equals(0));
    });

    test('parseDealText parses multiline labeled format from user prompt', () {
      const text = '''
North:
S:K87
H:AJT976543
D:K
C:-

South:
S:AQ2
H:Q
D:J9742
C:QJ75

East:
S:JT5
H:82
D:AQT83
C:A64
''';
      final map = HandParser.parseDealText(text);
      expect(map.containsKey('N'), isTrue);
      expect(map.containsKey('S'), isTrue);
      expect(map.containsKey('E'), isTrue);

      final north = map['N']!;
      expect(north.hcp, equals(11));
      expect(north.heartsLength, equals(9));

      final south = map['S']!;
      expect(south.hcp, equals(12));
      expect(south.spadesLength, equals(3));

      final east = map['E']!;
      expect(east.hcp, equals(11));
      expect(east.diamondsLength, equals(5));

      // Complete deal to fill West
      final deal = HandParser.completeDeal(map);
      expect(deal.north.cards.length, equals(13));
      expect(deal.east.cards.length, equals(13));
      expect(deal.south.cards.length, equals(13));
      expect(deal.west.cards.length, equals(13));

      // Verify no duplicates across all 4 hands (52 unique cards)
      final allCards = {
        ...deal.north.cards,
        ...deal.east.cards,
        ...deal.south.cards,
        ...deal.west.cards,
      };
      expect(allCards.length, equals(52));
    });

    test('parseDealText parses PBN deal string', () {
      const pbn = '[Deal "N:K87.AJT976543.K. JT5.82.AQT83.A64 AQ2.Q.J9742.QJ75 9643.K.65.KT9832"]';
      final map = HandParser.parseDealText(pbn);
      expect(map.length, equals(4));
      expect(map['N']!.heartsLength, equals(9));
      expect(map['E']!.diamondsLength, equals(5));
      expect(map['S']!.hcp, equals(12));
      expect(map['W']!.clubsLength, equals(6));
    });

    test('completeDeal detects duplicate cards across hands', () {
      final north = Hand.fromString('AKQ.JT9.876.5432');
      final south = Hand.fromString('AKQ.JT9.876.5432'); // Exact duplicate
      expect(
        () => HandParser.completeDeal({'N': north, 'S': south}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
