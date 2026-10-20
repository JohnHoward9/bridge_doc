import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Helper to load a system YAML profile and resolve its imports from disk
  Future<BridgeSystem> loadSystemProfile(String relativePath) async {
    final file = File(relativePath);
    if (!file.existsSync()) {
      throw Exception('System file not found at: ${file.absolute.path}');
    }
    final yamlStr = await file.readAsString();

    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) {
          return await f.readAsString();
        }
        return '';
      },
    );
  }

  group('Compiled Bidding Graph & IOC Auction Engine', () {
    test('Compiles 3-Way Club with Walrus Transfer continuations (~>)', () async {
      final system = await loadSystemProfile('assets/core/systems/three_way_club_5cm.yaml');
      expect(system.name, contains('3-Way Club'));

      final compiler = BiddingGraphCompiler(system: system);
      final graph = compiler.compile();

      expect(graph.stateCount, greaterThan(10));

      // 1. Root state has opening bids
      final root = graph.rootState;
      final openingCalls = root.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openingCalls, contains('1c'));
      expect(openingCalls, contains('1nt'));

      // 2. 1C response state has transfer responses
      final state1C = graph.getState(['1c']);
      expect(state1C, isNotNull);
      final respCalls = state1C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls, contains('1d'), reason: 'Transfer response [1d-1h] includes 1d');
      expect(respCalls, contains('1h'), reason: 'Transfer response [1d-1h] includes 1h');

      // 3. 1C:1H continuation state has unwrapped router bids for North
      final state1C1H = graph.getState(['1c', '1h']);
      expect(state1C1H, isNotNull, reason: 'Sequence 1c:1h must be compiled into graph');

      final northRebids = state1C1H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(northRebids, contains('1s'), reason: '1\$M with \$M=s unwraps to 1s');
      expect(northRebids, contains('1nt'), reason: 'Weak NT rebid should be indexed');
      expect(northRebids, contains('2c'), reason: 'Club rebids should be indexed');

      // 4. 1C:1H:1S state has South follow-up bids
      final state1C1H1S = graph.getState(['1c', '1h', '1s']);
      expect(state1C1H1S, isNotNull, reason: 'Sequence 1c:1h:1s must be compiled into graph');

      final southFollowUps = state1C1H1S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(southFollowUps, contains('pass'));
      expect(southFollowUps, contains('1nt'));
      expect(southFollowUps, contains('2c'));
      expect(southFollowUps, contains('2s'), reason: '2\$M unwraps to 2s');
      expect(southFollowUps, contains('3s'), reason: '3\$M unwraps to 3s');
      expect(southFollowUps, contains('4s'), reason: '4\$M unwraps to 4s');
    });

    test('Full multi-turn auction progression: 1C -> 1H -> 1S -> South bids', () async {
      final system = await loadSystemProfile('assets/core/systems/three_way_club_5cm.yaml');
      final engine = AuctionEngine.fromSystem(system);

      // North has 13 HCP, 3 Spades, 6 Clubs -> opens 1c, rebids 1s (limited 3-card support)
      final northHand = Hand.fromString('K82:Q4:J3:AK7642');
      // South has 8 HCP, 4 Spades -> responds 1h (transfer to spades), then 1nt (4M 6-10)
      final southHand = Hand.fromString('QJ94:83:K752:983');
      // East & West generic hands
      final eastHand = Hand.fromString('A75:J962:A94:JT5');
      final westHand = Hand.fromString('T63:AT75:QT86:Q4');

      final deal = PartnershipDeal(
        north: northHand,
        east: eastHand,
        south: southHand,
        west: westHand,
      );

      // 1. Start deal where North opens
      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.isUserBidCorrect, isTrue);
      expect(startStep.updatedHistory.length, equals(2));
      expect(startStep.updatedHistory[0].seat, equals('N'));
      expect(startStep.updatedHistory[0].call.toLowerCase(), equals('1c'));
      expect(startStep.updatedHistory[1].seat, equals('E'));
      expect(startStep.updatedHistory[1].call.toLowerCase(), equals('pass'));

      // South's candidates must include 1h
      final validSouthCalls = startStep.nextValidCandidatesForUser
          .where((c) => c.isMatch)
          .map((c) => c.displayCall.toLowerCase())
          .toSet();
      expect(validSouthCalls, contains('1h'), reason: 'South with 4+ spades should bid 1h transfer');

      // 2. User submits 1h
      final step2 = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '1h',
        deal: deal,
      );

      expect(step2.isUserBidCorrect, isTrue, reason: '1h is correct Walrus transfer response');
      // Updated history should be: N:1c, E:Pass, S:1h, W:Pass, N:1s, E:Pass
      expect(step2.updatedHistory.length, equals(6));
      expect(step2.updatedHistory[2].seat, equals('S'));
      expect(step2.updatedHistory[2].call.toLowerCase(), equals('1h'));
      expect(step2.updatedHistory[3].seat, equals('W'));
      expect(step2.updatedHistory[3].call.toLowerCase(), equals('pass'));
      expect(step2.updatedHistory[4].seat, equals('N'));
      expect(step2.updatedHistory[4].call.toLowerCase(), equals('1s'), reason: 'North rebids 1s with 3-card support');
      expect(step2.updatedHistory[5].seat, equals('E'));
      expect(step2.updatedHistory[5].call.toLowerCase(), equals('pass'));

      // South now has candidates for the next round of bidding!
      expect(step2.isAuctionComplete, isFalse);
      expect(step2.nextValidCandidatesForUser, isNotEmpty);
      final followUpCalls = step2.nextValidCandidatesForUser
          .map((c) => c.displayCall.toLowerCase())
          .toSet();
      expect(followUpCalls, contains('pass'));
      expect(followUpCalls, contains('1nt'));
      expect(followUpCalls, contains('2s'));

      // South with 8 HCP and 4 Spades best bid is 1nt (rule: p#5 4$M 6-10hcp)
      expect(step2.expectedBestBid, isNotNull);
      expect(step2.expectedBestBid!.displayCall.toLowerCase(), equals('1nt'));

      // 3. User submits 1nt to complete this part of the auction
      final step3 = engine.advanceAuction(
        history: step2.updatedHistory,
        userCall: '1nt',
        deal: deal,
      );

      expect(step3.isUserBidCorrect, isTrue);
      expect(step3.updatedHistory.any((e) => e.seat == 'S' && e.call.toLowerCase() == '1nt'), isTrue);
    });

    test('Rejects incorrect South bid and provides feedback without advancing history', () async {
      final system = await loadSystemProfile('assets/core/systems/three_way_club_5cm.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final northHand = Hand.fromString('K82:Q4:J3:AK7642');
      final southHand = Hand.fromString('QJ94:83:K752:983');
      final deal = PartnershipDeal(
        north: northHand,
        east: Hand.fromString('A75:J962:A94:JT5'),
        south: southHand,
        west: Hand.fromString('T63:AT75:QT86:Q4'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);

      // User wrongly bids 3NT
      final errorStep = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '3nt',
        deal: deal,
      );

      expect(errorStep.isUserBidCorrect, isFalse);
      expect(errorStep.updatedHistory.length, equals(startStep.updatedHistory.length));
      expect(errorStep.expectedBestBid, isNotNull);
      expect(errorStep.expectedBestBid!.displayCall.toLowerCase(), equals('1h'));
      expect(errorStep.feedbackMessage, contains('Incorrect bid 3nt'));
    });

    test('5-Card Majors & 2/1 Game Forcing: 1H -> 2C (2/1 GF) and Jacoby 2NT', () async {
      final system = await loadSystemProfile('assets/core/systems/us_standard_2over1.yaml');
      expect(system.name, contains('5-Card Majors'));

      final compiler = BiddingGraphCompiler(system: system);
      final graph = compiler.compile();

      // Check 1H responses
      final state1H = graph.getState(['1h']);
      expect(state1H, isNotNull);
      final calls1H = state1H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls1H, contains('1s'));
      expect(calls1H, contains('1nt'));
      expect(calls1H, contains('2c'), reason: '2/1 Game Force Clubs');
      expect(calls1H, contains('2d'), reason: '2/1 Game Force Diamonds');
      expect(calls1H, contains('2h'));
      expect(calls1H, contains('2nt'), reason: 'Jacoby 2NT');

      // Check Jacoby 2NT continuations: 1h:2nt (system20120910.bbs definition)
      final stateJacoby = graph.getState(['1h', '2nt']);
      expect(stateJacoby, isNotNull);
      final openerResponses = stateJacoby!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerResponses, contains('3c'), reason: 'Any minimum');
      expect(openerResponses, contains('3d'), reason: 'Non minimum no shortage');
      expect(openerResponses, contains('3h'), reason: 'Shortness in clubs');
      expect(openerResponses, contains('3s'), reason: 'Shortness in diamonds');
      expect(openerResponses, contains('3nt'), reason: 'Shortness in other major (Spades)');
    });

    test('User deal: North opens 1NT with 65:AKJT:AJT8:KJ8, South passes with Q43:765:KQ953:95', () async {
      final system = await loadSystemProfile('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final northHand = Hand.fromString('65:AKJT:AJT8:KJ8');
      final southHand = Hand.fromString('Q43:765:KQ953:95');
      final deal = PartnershipDeal(
        north: northHand,
        east: Hand.fromString('JT9:984:742:AT64'),
        south: southHand,
        west: Hand.fromString('A872:Q32:6:Q7532'),
      );

      // North opens 1NT
      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.isUserBidCorrect, isTrue);
      expect(startStep.updatedHistory.length, equals(2));
      expect(startStep.updatedHistory[0].seat, equals('N'));
      expect(startStep.updatedHistory[0].call.toLowerCase(), equals('1nt'));
      expect(startStep.updatedHistory[1].seat, equals('E'));
      expect(startStep.updatedHistory[1].call.toLowerCase(), equals('pass'));

      // South submits Pass
      final passStep = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: 'pass',
        deal: deal,
      );

      expect(passStep.isUserBidCorrect, isTrue, reason: 'Pass must be accepted as correct with 7 HCP over 1NT');
      expect(passStep.isAuctionComplete, isTrue);
      expect(passStep.feedbackMessage, contains('Pass'));
      expect(passStep.updatedHistory.last.seat, equals('S'));
      expect(passStep.updatedHistory.last.call.toLowerCase(), equals('pass'));
    });

    test('Targeted deal generation: generate board where North opens 1NT', () async {
      final system = await loadSystemProfile('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);
      final generator = DealGenerator();

      final targetedDeal = generator.dealWhereNorthOpensTarget(
        isTargetMatch: (northHand) {
          final bestBid = engine.graph.rootState.resolveBestBid(
            northHand,
            engine.resolver,
            fragments: engine.graph.system.fragments,
          );
          return bestBid != null && bestBid.displayCall.toLowerCase() == '1nt';
        },
      );

      // Verify North hand satisfies 1NT criteria (15-17 HCP, balanced)
      expect(targetedDeal.north.hcp, inInclusiveRange(15, 17));
      expect(targetedDeal.north.isBalanced, isTrue);

      // When starting the deal, North must open 1NT
      final startStep = engine.startDeal(deal: targetedDeal, isNorthFirst: true);
      expect(startStep.updatedHistory[0].seat, equals('N'));
      expect(startStep.updatedHistory[0].call.toLowerCase(), equals('1nt'));
    });

    test('1NT Response with 4 Spades and 7 Diamonds: AQ32:J:AJT5432:J', () async {
      final system = await loadSystemProfile('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final northHand = Hand.fromString('A86:AQ2:K63:Q854'); // 15 HCP balanced
      final southHand = Hand.fromString('AQ32:J:AJT5432:J'); // 13 HCP, 4s, 7d
      final deal = PartnershipDeal(
        north: northHand,
        east: Hand.fromString('75:KT94:Q94:KT92'),
        south: southHand,
        west: Hand.fromString('JT94:87653:87:A6'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory[0].call.toLowerCase(), equals('1nt'));

      // South's matching candidates must include Stayman 2c and natural 3d
      final state1NT = engine.graph.getState(['1nt'])!;
      final southCandidates = state1NT.evaluateCandidates(southHand, engine.resolver, fragments: engine.graph.system.fragments);
      final matchingCalls = southCandidates.where((c) => c.isMatch).map((c) => c.displayCall.toLowerCase()).toSet();

      expect(matchingCalls, contains('2c'), reason: 'Stayman 2C must match with 4 spades');
      expect(matchingCalls, contains('3d'), reason: 'Natural GF 3D must match with 7 diamonds');
      expect(matchingCalls, isNot(contains('pass')), reason: '13 HCP must not match Pass');

      // Best bid should be Stayman 2C (looking for 4-4 spade fit)
      final bestBid = state1NT.resolveBestBid(southHand, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('2c'));

      // Submitting 2C must be correct and advance auction
      final step2 = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2c',
        deal: deal,
      );
      expect(step2.isUserBidCorrect, isTrue);
      expect(step2.updatedHistory.any((e) => e.seat == 'S' && e.call.toLowerCase() == '2c'), isTrue);
    });

    test('Puppet Stayman over 2NT: 2NT -> 3C -> 3D -> 3H -> 4S', () async {
      final system = await loadSystemProfile('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      // Verify states are compiled in the sequence graph
      final state2NT = engine.graph.getState(['2nt']);
      expect(state2NT, isNotNull);
      final calls2NT = state2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2NT, contains('3c'), reason: '3C Puppet Stayman must be available over 2NT');
      expect(calls2NT, contains('3d'), reason: '3D Transfer to Hearts');
      expect(calls2NT, contains('3h'), reason: '3H Transfer to Spades');
      expect(calls2NT, contains('3nt'));

      // Sequence 2nt:3c:3d (opener shows 4-card major)
      final state2NT3C3D = engine.graph.getState(['2nt', '3c', '3d']);
      expect(state2NT3C3D, isNotNull);
      final respBids = state2NT3C3D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respBids, contains('3h'), reason: '3H shows 4 Spades (other major)');
      expect(respBids, contains('3s'), reason: '3S shows 4 Hearts (other major)');
      expect(respBids, contains('4d'), reason: '4D shows both majors');

      // Sequence 2nt:3c:3d:3h (opener raises to 4S)
      final state2NT3C3D3H = engine.graph.getState(['2nt', '3c', '3d', '3h']);
      expect(state2NT3C3D3H, isNotNull);
      final openerBids = state2NT3C3D3H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerBids, contains('4s'), reason: 'Opener raises to 4S game');
    });

    test('Transfer Lebensohl over 1NT interference: 1NT -> (2H) and 1NT -> (2S)', () async {
      final system = await loadSystemProfile('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      // 1. Interference over 1NT: 1NT -> (2H)
      final state1NT2H = engine.graph.getState(['1nt', '(2h)']);
      expect(state1NT2H, isNotNull, reason: 'Sequence 1nt:(2h) must be compiled in graph');

      final callsOver2H = state1NT2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOver2H, contains('dbl'), reason: 'Negative double showing 4 Spades');
      expect(callsOver2H, contains('2s'), reason: 'Natural competitive 2S');
      expect(callsOver2H, contains('2nt'), reason: 'Transfer to Clubs (forces 3C)');
      expect(callsOver2H, contains('3c'), reason: 'Transfer to Diamonds (5+ Diamonds)');
      expect(callsOver2H, contains('3d'), reason: 'Transfer to Hearts (Cuebid / Stayman enquiry)');
      expect(callsOver2H, contains('3h'), reason: 'Transfer to Spades (5+ Spades GF)');
      expect(callsOver2H, contains('3nt'), reason: 'Fast Denies Heart stopper to play');

      // 2. Transfer sequence 1nt:(2h):2nt:3c (Opener accepts transfer to Clubs)
      final state1NT2H2NT3C = engine.graph.getState(['1nt', '(2h)', '2nt', '3c']);
      expect(state1NT2H2NT3C, isNotNull, reason: 'Opener accepts club transfer 3c');
      final followUpCalls = state1NT2H2NT3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(followUpCalls, contains('pass'), reason: 'Signoff in 3C');
      expect(followUpCalls, contains('3d'), reason: 'Invitational with 5+ Diamonds');
      expect(followUpCalls, contains('3nt'), reason: 'Slow Shows 3NT invitation with Heart stopper');

      // 3. Interference over 1NT: 1NT -> (2S)
      final state1NT2S = engine.graph.getState(['1nt', '(2s)']);
      expect(state1NT2S, isNotNull, reason: 'Sequence 1nt:(2s) must be compiled in graph');

      final callsOver2S = state1NT2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOver2S, contains('dbl'), reason: 'Negative double showing 4 Hearts');
      expect(callsOver2S, contains('2nt'), reason: 'Transfer to Clubs');
      expect(callsOver2S, contains('3c'), reason: 'Transfer to Diamonds');
      expect(callsOver2S, contains('3d'), reason: 'Transfer to Hearts');
      expect(callsOver2S, contains('3h'), reason: 'Transfer to Spades (Cuebid / Stayman enquiry)');
      expect(callsOver2S, contains('3nt'), reason: 'Fast Denies Spade stopper');
    });
  });
}
