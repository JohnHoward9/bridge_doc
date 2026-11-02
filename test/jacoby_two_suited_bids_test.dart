import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  group('Jacoby Transfer Continuations: Two-Suited & Concentration of Honors (3C / 3D vs 3NT)', () {
    late BridgeSystem system;
    late AuctionEngine engine;

    setUpAll(() async {
      final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
      final yamlStr = await file.readAsString();
      system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async {
          final libFile = File(path);
          if (libFile.existsSync()) {
            return await libFile.readAsString();
          }
          return '';
        },
      );
      engine = AuctionEngine.fromSystem(system);
    });

    test('User Hand from Screenshot: 3:AK632:Q3:AQT95 (15 HCP, 1-5-2-5) bids 3C over 2H, not 3NT', () {
      // North: ♠AQ6, ♥QT4, ♦KJ76, ♣K97 (15 HCP, 15.1 Eff HCP)
      final northHand = Hand.fromString('AQ6:QT4:KJ76:K97');
      // South: ♠3, ♥AK632, ♦Q3, ♣AQT95 (15 HCP, 5 Hearts, 5 Clubs, singleton Spade)
      final southHand = Hand.fromString('3:AK632:Q3:AQT95');

      final deal = PartnershipDeal(
        north: northHand,
        south: southHand,
        east: Hand.fromString('JT85:982:J54:J64'),
        west: Hand.fromString('K9742:J75:T982:32'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      // North opens 1NT
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

      // South transfers with 2D
      final step2d = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2d',
        deal: deal,
        activeSeat: 'S',
      );
      expect(step2d.isUserBidCorrect, isTrue);

      // North automatically accepts transfer with 2H
      expect(step2d.updatedHistory.lastWhere((e) => e.seat == 'N').call.toLowerCase(), equals('2h'));

      // Now it is South's turn.
      // South bids 3C (natural second suit, 5-5 GF):
      final step3c = engine.advanceAuction(
        history: step2d.updatedHistory,
        userCall: '3c',
        deal: deal,
        activeSeat: 'S',
      );

      expect(step3c.isUserBidCorrect, isTrue, reason: '3C should be accepted for 5-5 hand with points concentrated in 2 suits');
      expect(step3c.updatedHistory.lastWhere((e) => e.seat == 'S').call.toLowerCase(), equals('3c'));

      // Partner (North) has unbid suits Spades (KQ6) and Diamonds (AK76) stopped, plus 3 Hearts (QT4).
      // Partner can rebid 3NT or 4H:
      final northRebid = step3c.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(
        ['3nt', '4h', '4♥'].contains(northRebid.call.toLowerCase()),
        isTrue,
        reason: 'North rebids 3NT (stoppers in ♠ and ♦) or 4H with 3-card fit, actual: ${northRebid.call}',
      );
    });

    test('User 5422 Hand: 32:AKT43:Q2:KJT2 (13 HCP) with unstopped Spades bids 3C, not 3NT', () {
      final northHand = Hand.fromString('AK6:Q94:KT62:K87'); // 15 HCP (15.5 Eff HCP)
      // South: ♠32 (no honors!), ♥AKT43 (5 cards), ♦Q2, ♣KJT2 (4 cards)
      final southHand = Hand.fromString('32:AKT43:Q2:KJT2');
      expect(southHand.shortSuitsHaveHonors, isFalse, reason: 'Spades 32 lacks any honor');

      final deal = PartnershipDeal(
        north: northHand,
        south: southHand,
        east: Hand.fromString('JT85:82:J54:9654'),
        west: Hand.fromString('Q974:J765:983:32'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

      final step2d = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2d',
        deal: deal,
        activeSeat: 'S',
      );
      expect(step2d.isUserBidCorrect, isTrue);

      // South bids 3C to show the second suit because Spades is wide open
      final step3c = engine.advanceAuction(
        history: step2d.updatedHistory,
        userCall: '3c',
        deal: deal,
        activeSeat: 'S',
      );

      expect(step3c.isUserBidCorrect, isTrue, reason: '3C is correct for 5422 when short suit is unstopped');
    });

    test('Balanced 5422 Hand with stopped doubletons (K4:AJ764:Q984:Q7) bids 3NT', () {
      final northHand = Hand.fromString('A3:A62:KJ2:KT532');
      // South: ♠K4 (stopped!), ♥AJ764, ♦Q984, ♣Q7 (stopped!)
      final southHand = Hand.fromString('K4:AJ764:Q984:Q7');
      expect(southHand.shortSuitsHaveHonors, isTrue, reason: 'Both doubletons hold honors (♠K, ♣Q)');

      final deal = PartnershipDeal(
        north: northHand,
        south: southHand,
        east: Hand.fromString('865:T98:T76:J864'),
        west: Hand.fromString('QJT972:K5:A53:86'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      final step2d = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2d',
        deal: deal,
        activeSeat: 'S',
      );

      // South bids 3NT (Choice of Games, 10-15 HCP, short suits stopped)
      final step3nt = engine.advanceAuction(
        history: step2d.updatedHistory,
        userCall: '3nt',
        deal: deal,
        activeSeat: 'S',
      );

      expect(step3nt.isUserBidCorrect, isTrue, reason: '3NT is accepted when short suits hold honors');
      // North with 3 Hearts converts to 4H
      final northRebid = step3nt.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(northRebid.call.toLowerCase(), anyOf(equals('4h'), equals('4♥')));
    });
  });
}
