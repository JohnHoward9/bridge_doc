import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/board_exporter.dart';

void main() {
  group('BoardExporter (PBN & BBO LIN)', () {
    late PartnershipDeal deal;
    late List<AuctionEntry> history;

    setUp(() {
      deal = PartnershipDeal(
        north: Hand.fromString('KT4:Q98:AQJT2:QT'),
        east: Hand.fromString('985:KJ72:76:K864'),
        south: Hand.fromString('AJ73:AT4:K94:J95'),
        west: Hand.fromString('Q62:653:853:A732'),
      );

      history = const [
        AuctionEntry(seat: 'N', call: '1NT', desc: '15-17 Strong NT (ML Upgraded)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '3NT', desc: 'Signoff in 3NT'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ];
    });

    test('handToPbn converts hands to standard dot-delimited format', () {
      final pbn = BoardExporter.handToPbn(deal.north);
      expect(pbn, equals('KT4.Q98.AQJT2.QT'));
    });

    test('handToLin converts hands to standard BBO LIN format', () {
      final lin = BoardExporter.handToLin(deal.north);
      expect(lin, equals('SKT4HQ98DAQJT2CQT'));
    });

    test('exportToPbn generates valid PBN v2.1 document', () {
      final pbn = BoardExporter.exportToPbn(
        deal: deal,
        history: history,
        options: const BoardExportOptions(
          boardNumber: '5',
          dealer: 'N',
          vulnerable: 'NS',
        ),
      );

      expect(pbn, contains('[Board "5"]'));
      expect(pbn, contains('[Dealer "N"]'));
      expect(pbn, contains('[Vulnerable "NS"]'));
      expect(pbn, contains('[Deal "N:KT4.Q98.AQJT2.QT 985.KJ72.76.K864 AJ73.AT4.K94.J95 Q62.653.853.A732"]'));
      expect(pbn, contains('[Auction "N"]'));
      expect(pbn, contains('1NT Pass 3NT Pass'));
    });

    test('exportToLin generates valid BBO LIN sequence with call alerts', () {
      final lin = BoardExporter.exportToLin(
        deal: deal,
        history: history,
        options: const BoardExportOptions(
          boardNumber: '1',
          dealer: 'N',
          vulnerable: 'None',
        ),
      );

      expect(lin, startsWith('qx|o1|ah|Board 1|sv|o|md|3'));
      expect(lin, contains('SKT4HQ98DAQJT2CQT'));
      expect(lin, contains('mb|1N|'));
      expect(lin, contains('an|15-17 Strong NT (ML Upgraded)|'));
      expect(lin, contains('mb|p|'));
      expect(lin, contains('mb|3N|'));
      expect(lin, endsWith('pg||'));
    });
  });
}
