import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/board_exporter.dart';
import 'package:bridge_bidding_system/services/hand_review_service.dart';

void main() {
  late Directory tempDir;
  late HandReviewService reviewService;

  final sampleNorth = Hand.fromString('SAKQ.HKJT.DA432.CKQ');
  final sampleEast = Hand.fromString('S987.HQ98.DT98.CJ98');
  final sampleSouth = Hand.fromString('SJ654.HA765.DKQ.CT43');
  final sampleWest = Hand.fromString('ST32.H432.DJ765.CA76');
  final sampleDeal = PartnershipDeal(
    north: sampleNorth,
    east: sampleEast,
    south: sampleSouth,
    west: sampleWest,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('review_test_');
    reviewService = HandReviewService(directory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HandReviewService PBN Serialization and Parsing', () {
    test('saveBoard writes PBN with Description, Comment, and Deal tags', () async {
      final file = await reviewService.saveBoard(
        deal: sampleDeal,
        dealer: 'N',
        shortDescription: '5-4-2-2 1NT Rebid Trap',
        longDescription: 'North opened 1C with 16 HCP and 5 clubs, 4 hearts.\nShould test whether 1NT was rebid.',
        vulnerable: 'NS',
        systemName: 'Gavin Wolpert 2/1 GF',
        history: const [
          AuctionEntry(seat: 'N', call: '1C'),
          AuctionEntry(seat: 'E', call: 'Pass'),
          AuctionEntry(seat: 'S', call: '1S'),
        ],
        timestamp: DateTime(2026, 10, 27, 22, 15, 0),
      );

      expect(file.existsSync(), isTrue);
      expect(file.path.endsWith('20261027_221500_5_4_2_2_1nt_rebid_trap.pbn'), isTrue);

      final content = await file.readAsString();
      expect(content, contains('[Dealer "N"]'));
      expect(content, contains('[Vulnerable "NS"]'));
      expect(content, contains('[Description "5-4-2-2 1NT Rebid Trap"]'));
      expect(content, contains('[Comment "North opened 1C with 16 HCP and 5 clubs, 4 hearts. Should test whether 1NT was rebid."]'));
      expect(content, contains('{\n  North opened 1C with 16 HCP and 5 clubs, 4 hearts.\n  Should test whether 1NT was rebid.\n}'));
      expect(content, contains('[Deal "N:'));
      expect(content, contains('[Auction "N"]'));
      expect(content, contains('1C Pass 1S'));
    });

    test('loadBoard and parsePbn roundtrips deal and descriptions accurately', () async {
      await reviewService.saveBoard(
        deal: sampleDeal,
        dealer: 'S',
        shortDescription: 'Gavin Minor Transfer Test',
        longDescription: 'Shortness inquiry over 3D transfer.',
        vulnerable: 'All',
        timestamp: DateTime(2026, 10, 27, 20, 0, 0),
      );

      final boards = await reviewService.listReviewBoards();
      expect(boards.length, equals(1));

      final board = boards.first;
      expect(board.shortDescription, equals('Gavin Minor Transfer Test'));
      expect(board.longDescription, equals('Shortness inquiry over 3D transfer.'));
      expect(board.dealer, equals('S'));
      expect(board.vulnerable, equals('All'));

      // Verify hands
      expect(board.deal.north.cards.length, equals(13));
      expect(board.deal.east.cards.length, equals(13));
      expect(board.deal.south.cards.length, equals(13));
      expect(board.deal.west.cards.length, equals(13));
      expect(board.deal.north.cardsInSuit(Suit.spades).length, equals(3));
      expect(board.deal.south.cardsInSuit(Suit.hearts).length, equals(4));
    });

    test('listReviewBoards sorts newest first', () async {
      await reviewService.saveBoard(
        deal: sampleDeal,
        dealer: 'N',
        shortDescription: 'First Older Board',
        longDescription: 'Older problem',
        timestamp: DateTime(2026, 10, 25, 12, 0, 0),
      );

      await reviewService.saveBoard(
        deal: sampleDeal,
        dealer: 'E',
        shortDescription: 'Second Newer Board',
        longDescription: 'Newer problem',
        timestamp: DateTime(2026, 10, 27, 18, 0, 0),
      );

      final list = await reviewService.listReviewBoards();
      expect(list.length, equals(2));
      expect(list[0].shortDescription, equals('Second Newer Board'));
      expect(list[1].shortDescription, equals('First Older Board'));
    });

    test('deleteBoard removes board from disk', () async {
      final file = await reviewService.saveBoard(
        deal: sampleDeal,
        dealer: 'W',
        shortDescription: 'To Be Deleted',
        longDescription: 'Transient',
      );

      expect(file.existsSync(), isTrue);
      final filename = file.uri.pathSegments.last;

      final deleted = await reviewService.deleteBoard(filename);
      expect(deleted, isTrue);
      expect(file.existsSync(), isFalse);

      final list = await reviewService.listReviewBoards();
      expect(list.isEmpty, isTrue);
    });
  });
}
