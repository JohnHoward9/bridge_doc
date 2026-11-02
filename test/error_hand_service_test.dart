import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/hand_review_service.dart';

void main() {
  late Directory tempErrorDir;
  late HandReviewService errorService;

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
    tempErrorDir = await Directory.systemTemp.createTemp('errors_test_');
    errorService = HandReviewService(directory: tempErrorDir);
  });

  tearDown(() async {
    if (await tempErrorDir.exists()) {
      await tempErrorDir.delete(recursive: true);
    }
  });

  group('Error Hand Service: ErrorType, Fixed status, and Category persistence', () {
    test('saveBoard writes [ErrorType] and [Fixed "No"] correctly', () async {
      final file = await errorService.saveBoard(
        deal: sampleDeal,
        dealer: 'N',
        shortDescription: '1S Opening with 5-5 Majors',
        longDescription: 'Opened 1H instead of 1S with 5-5 majors.',
        errorType: 'Wrong Opening Bid',
        isFixed: false,
        vulnerable: 'None',
        systemName: 'Gavin Wolpert 2/1 GF',
        history: const [
          AuctionEntry(seat: 'N', call: '1H'),
        ],
        timestamp: DateTime(2026, 10, 29, 10, 30, 0),
      );

      expect(file.existsSync(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('[ErrorType "Wrong Opening Bid"]'));
      expect(content, contains('[Fixed "No"]'));
      expect(content, contains('[Description "1S Opening with 5-5 Majors"]'));

      final board = errorService.parsePbn(content, filename: file.uri.pathSegments.last);
      expect(board.errorType, equals('Wrong Opening Bid'));
      expect(board.isFixed, isFalse);
    });

    test('updateBoardFixedStatus updates [Fixed] tag from No to Yes and back', () async {
      final file = await errorService.saveBoard(
        deal: sampleDeal,
        dealer: 'S',
        shortDescription: 'Premature Pass over 2H reverse',
        longDescription: 'Partner passed forcing 3S rebid.',
        errorType: 'Premature Pass',
        isFixed: false,
      );

      final filename = file.uri.pathSegments.last;
      var board = (await errorService.loadBoard(filename))!;
      expect(board.isFixed, isFalse);

      // Mark as fixed
      final success = await errorService.updateBoardFixedStatus(filename, true);
      expect(success, isTrue);

      board = (await errorService.loadBoard(filename))!;
      expect(board.isFixed, isTrue);

      final updatedContent = await file.readAsString();
      expect(updatedContent, contains('[Fixed "Yes"]'));

      // Reopen
      await errorService.updateBoardFixedStatus(filename, false);
      board = (await errorService.loadBoard(filename))!;
      expect(board.isFixed, isFalse);
    });

    test('Category persistence: default categories and adding new custom category', () async {
      final initialCategories = await errorService.getCategories();
      expect(initialCategories, contains('Premature Pass'));
      expect(initialCategories, contains('Wrong Opening Bid'));

      // Add custom category
      await errorService.addCategory('Reverse Bidding Defect');
      final updatedCategories = await errorService.getCategories();
      expect(updatedCategories, contains('Reverse Bidding Defect'));

      // Saving a board with a new category auto-adds it to categories.json
      await errorService.saveBoard(
        deal: sampleDeal,
        dealer: 'N',
        shortDescription: 'Double Fit Evaluation Error',
        longDescription: 'Missed slam due to discounting secondary fit.',
        errorType: 'ML Valuation Gap',
      );

      final finalCategories = await errorService.getCategories();
      expect(finalCategories, contains('ML Valuation Gap'));
    });
  });
}
