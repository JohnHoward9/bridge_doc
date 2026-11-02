import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/hand_review_service.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuctionEngine engine;

  setUpAll(() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    final yamlStr = await file.readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        return f.existsSync() ? await f.readAsString() : '';
      },
    );
    engine = AuctionEngine.fromSystem(system);
  });

  group('One-Level Suit Openings Tests', () {
    test('1. Problem review hand in review/ (5-5 majors) opens 1S (not 1H) and East passes', () async {
      final reviewService = HandReviewService(directory: Directory('review'));
      final board = await reviewService.loadBoard('20261028_153337_1s_opening_with_5_5_in_major.pbn');
      expect(board, isNotNull, reason: 'Review board should exist');

      final step = engine.startDeal(deal: board!.deal, isNorthFirst: true);

      expect(step.updatedHistory.isNotEmpty, isTrue);
      // North opening call must be 1s
      expect(step.updatedHistory[0].seat, equals('N'));
      expect(step.updatedHistory[0].call.toLowerCase(), equals('1s'), reason: 'Holding 5-5 in majors, North must open 1s, not 1h');

      // East call should be Pass
      expect(step.updatedHistory[1].seat, equals('E'));
      expect(step.updatedHistory[1].call.toLowerCase(), equals('pass'));
    });

    test('2. Problem review hand in review/ (4-1-4-4, 17 HCP) opens 1D and does not pass', () async {
      final reviewService = HandReviewService(directory: Directory('review'));
      final board = await reviewService.loadBoard('20261028_163108_incorrect_pass.pbn');
      expect(board, isNotNull, reason: 'Review board 20261028_163108_incorrect_pass.pbn should exist');

      final step = engine.startDeal(deal: board!.deal, isNorthFirst: true);

      expect(step.updatedHistory.isNotEmpty, isTrue);
      // North opening call must be 1d
      expect(step.updatedHistory[0].seat, equals('N'));
      expect(step.updatedHistory[0].call.toLowerCase(), equals('1d'), reason: 'Holding 4-1-4-4 with 17 HCP (d>=c and 4+d), North must open 1d');

      // East call should be Pass
      expect(step.updatedHistory[1].seat, equals('E'));
      expect(step.updatedHistory[1].call.toLowerCase(), equals('pass'));

      // Also verify standalone North hand: AK84.J.KQ72.KJ64 (17 HCP)
      final northHand = Hand.fromString('AK84.J.KQ72.KJ64');
      final bid = engine.graph.rootState.resolveBestBid(northHand, engine.botResolver);
      expect(bid?.call.toLowerCase(), equals('1d'), reason: '4-1-4-4 with 17 HCP opens 1D');
    });

    test('3. Two 5+ card suits: always opens the highest suit', () {
      // 5-5-2-1 (5S, 5H): opens 1S (15 HCP, LTC=6)
      final hand5521 = Hand.fromString('AQJ98.QT974.K.K7');
      final bid5521 = engine.graph.rootState.resolveBestBid(hand5521, engine.botResolver);
      expect(bid5521?.call.toLowerCase(), equals('1s'), reason: '5-5 in majors opens 1S');

      // 5-1-5-2 (5S, 5D): opens 1S (14 HCP, LTC=6)
      final hand5152 = Hand.fromString('QJ987.4.AQ987.KJ');
      final bid5152 = engine.graph.rootState.resolveBestBid(hand5152, engine.botResolver);
      expect(bid5152?.call.toLowerCase(), equals('1s'), reason: '5S-5D opens highest suit 1S');

      // 5-1-2-5 (5S, 5C): opens 1S (14 HCP, LTC=6)
      final hand5125 = Hand.fromString('QJ987.4.KJ.AQ987');
      final bid5125 = engine.graph.rootState.resolveBestBid(hand5125, engine.botResolver);
      expect(bid5125?.call.toLowerCase(), equals('1s'), reason: '5S-5C opens highest suit 1S');

      // 2-5-5-1 (5H, 5D): opens 1H (14 HCP, LTC=6)
      final hand2551 = Hand.fromString('42.AQJ98.KJ987.K');
      final bid2551 = engine.graph.rootState.resolveBestBid(hand2551, engine.botResolver);
      expect(bid2551?.call.toLowerCase(), equals('1h'), reason: '5H-5D opens highest suit 1H');

      // 2-5-1-5 (5H, 5C): opens 1H (14 HCP, LTC=6)
      final hand2515 = Hand.fromString('42.AQJ98.K.KJ987');
      final bid2515 = engine.graph.rootState.resolveBestBid(hand2515, engine.botResolver);
      expect(bid2515?.call.toLowerCase(), equals('1h'), reason: '5H-5C opens highest suit 1H');

      // 1-2-5-5 (5D, 5C): opens 1D (14 HCP, LTC=6)
      final hand1255 = Hand.fromString('4.K7.AQ987.KJ987');
      final bid1255 = engine.graph.rootState.resolveBestBid(hand1255, engine.botResolver);
      expect(bid1255?.call.toLowerCase(), equals('1d'), reason: '5D-5C opens highest suit 1D');
    });

    test('4. Minor openings when majors are 4 or less in length', () {
      // 3-2-4-4 (4D = 4C, 13 HCP): opens 1D
      final hand3244 = Hand.fromString('K98.75.AQ98.KJ98');
      final bid3244 = engine.graph.rootState.resolveBestBid(hand3244, engine.botResolver);
      expect(bid3244?.call.toLowerCase(), equals('1d'), reason: '4D-4C with 4-card minors opens 1D');

      // 2-3-4-4 (4D = 4C, 13 HCP): opens 1D
      final hand2344 = Hand.fromString('75.K98.AQ98.KJ98');
      final bid2344 = engine.graph.rootState.resolveBestBid(hand2344, engine.botResolver);
      expect(bid2344?.call.toLowerCase(), equals('1d'), reason: '4D-4C with 4-card minors opens 1D');

      // 3-3-4-3 (4D > 3C, 13 HCP): opens 1D
      final hand3343 = Hand.fromString('K98.J75.AQ98.K98');
      final bid3343 = engine.graph.rootState.resolveBestBid(hand3343, engine.botResolver);
      expect(bid3343?.call.toLowerCase(), equals('1d'), reason: '4D > 3C opens 1D');

      // 2-2-4-5 (5C > 4D, 14 HCP): opens 1C
      final hand2245 = Hand.fromString('K7.K7.QJ98.AJ987');
      final bid2245 = engine.graph.rootState.resolveBestBid(hand2245, engine.botResolver);
      expect(bid2245?.call.toLowerCase(), equals('1c'), reason: '5C > 4D opens 1C');

      // 3-3-3-4 (diamonds < 4, 13 HCP): opens 1C
      final hand3334 = Hand.fromString('KJ8.KJ8.J83.AJ98');
      final bid3334 = engine.graph.rootState.resolveBestBid(hand3334, engine.botResolver);
      expect(bid3334?.call.toLowerCase(), equals('1c'), reason: '3 diamonds (< 4) opens 1C');

      // 4-4-3-2 (diamonds < 4, 13 HCP): opens 1C
      final hand4432 = Hand.fromString('AJ98.KJ98.J83.K7');
      final bid4432 = engine.graph.rootState.resolveBestBid(hand4432, engine.botResolver);
      expect(bid4432?.call.toLowerCase(), equals('1c'), reason: '4-4-3-2 (3 diamonds < 4) opens 1C');
    });

    test('5. Unequal major and minor lengths (6-5 distribution)', () {
      // 6S-5H: opens 1S (longer suit, 13 HCP, LTC=5)
      final hand65 = Hand.fromString('AKJ987.KQ974.8.7');
      final bid65 = engine.graph.rootState.resolveBestBid(hand65, engine.botResolver);
      expect(bid65?.call.toLowerCase(), equals('1s'), reason: '6S-5H opens longer suit 1S');

      // 5S-6H: opens 1H (longer suit, 13 HCP, LTC=5)
      final hand56 = Hand.fromString('KQ974.AKJ987.8.7');
      final bid56 = engine.graph.rootState.resolveBestBid(hand56, engine.botResolver);
      expect(bid56?.call.toLowerCase(), equals('1h'), reason: '5S-6H opens longer suit 1H');

      // 6D-5S: opens 1D (longer suit, 13 HCP, LTC=5)
      final hand6d5s = Hand.fromString('KJ987.4.AQJ987.K');
      final bid6d5s = engine.graph.rootState.resolveBestBid(hand6d5s, engine.botResolver);
      expect(bid6d5s?.call.toLowerCase(), equals('1d'), reason: '6D-5S opens longer suit 1D');

      // 6C-5S: opens 1C (longer suit, 13 HCP, LTC=5)
      final hand6c5s = Hand.fromString('KJ987.4.K.AQJ987');
      final bid6c5s = engine.graph.rootState.resolveBestBid(hand6c5s, engine.botResolver);
      expect(bid6c5s?.call.toLowerCase(), equals('1c'), reason: '6C-5S opens longer suit 1C');
    });

    test('6. Strong two-suited hands (18-19 HCP, LTC >= 5) open at 1-level', () {
      // 5S-5H with 18 HCP, LTC=5 (AK842:KJ974:KJ:K)
      final hand18Hcp55 = Hand.fromString('AK842.KJ974.KJ.K');
      final bid55 = engine.graph.rootState.resolveBestBid(hand18Hcp55, engine.botResolver);
      expect(bid55?.call.toLowerCase(), equals('1s'), reason: '18 HCP 5S-5H opens 1S (not 2C)');

      // 5S-5D with 18 HCP, LTC=5 (AK842:K:KJ974:KJ)
      final hand18Hcp55d = Hand.fromString('AK842.K.KJ974.KJ');
      final bid55d = engine.graph.rootState.resolveBestBid(hand18Hcp55d, engine.botResolver);
      expect(bid55d?.call.toLowerCase(), equals('1s'), reason: '18 HCP 5S-5D opens 1S (not 2C)');

      // 5H-5C with 18 HCP, LTC=5 (K.AK842:KJ:KJ974)
      final hand18Hcp55h = Hand.fromString('K.AK842.KJ.KJ974');
      final bid55h = engine.graph.rootState.resolveBestBid(hand18Hcp55h, engine.botResolver);
      expect(bid55h?.call.toLowerCase(), equals('1h'), reason: '18 HCP 5H-5C opens 1H (not 2C)');
    });
  });
}
