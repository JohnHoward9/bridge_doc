import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadGavinSystem() async {
    const relativePath = 'assets/core/systems/gavin_wolpert_2over1.yaml';
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

  group('Gavin Wolpert Master Series (2/1 GF) System Suite', () {
    late BridgeSystem system;
    late AuctionEngine engine;

    setUpAll(() async {
      system = await loadGavinSystem();
      engine = AuctionEngine.fromSystem(system);
    });

    test('Graph compiles successfully with all Gavin Wolpert convention modules', () {
      expect(system.name, contains('Gavin Wolpert'));
      expect(engine.graph.stateCount, greaterThan(20));

      final rootCalls = engine.graph.rootState.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(rootCalls, contains('pass'));
      expect(rootCalls, contains('1c'));
      expect(rootCalls, contains('1d'));
      expect(rootCalls, contains('1h'));
      expect(rootCalls, contains('1s'));
      expect(rootCalls, contains('1nt'));
      expect(rootCalls, contains('2c'));
      expect(rootCalls, contains('2nt'));
    });

    test('1NT Response structure: 4-Way transfers, Range Ask, 5-5 Minors, Shortness, Gerber', () {
      final state1NT = engine.graph.getState(['1nt']);
      expect(state1NT, isNotNull);

      final calls1NT = state1NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls1NT, contains('pass'));
      expect(calls1NT, contains('2c'), reason: 'Regular Stayman');
      expect(calls1NT, contains('2d'), reason: 'Jacoby Transfer to Hearts');
      expect(calls1NT, contains('2h'), reason: 'Jacoby Transfer to Spades');
      expect(calls1NT, contains('2s'), reason: 'Range Ask / Clubs');
      expect(calls1NT, contains('2nt'), reason: 'Transfer to Diamonds');
      expect(calls1NT, contains('3c'), reason: 'Puppet Stayman');
      expect(calls1NT, contains('3d'), reason: '5-5 Minors GF');
      expect(calls1NT, contains('3h'), reason: 'Heart shortness slam try');
      expect(calls1NT, contains('3s'), reason: 'Spade shortness slam try');
      expect(calls1NT, contains('3nt'));
      expect(calls1NT, contains('4c'), reason: 'Gerber Ace Ask');
      expect(calls1NT, contains('4d'), reason: 'Texas Transfer to Hearts');
      expect(calls1NT, contains('4h'), reason: 'Texas Transfer to Spades');

      // 1NT -> 2S (Range Ask / Clubs)
      final state1NT2S = engine.graph.getState(['1nt', '2s']);
      expect(state1NT2S, isNotNull);
      final rangeAskRebids = state1NT2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(rangeAskRebids, contains('2nt'), reason: 'Minimum 14.5-15 HCP');
      expect(rangeAskRebids, contains('3c'), reason: 'Maximum 16-17 HCP');

      // 1NT -> 2NT (Diamond Transfer)
      final state1NT2NT = engine.graph.getState(['1nt', '2nt']);
      expect(state1NT2NT, isNotNull);
      final diamondTransfer = state1NT2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(diamondTransfer, contains('3d'), reason: 'Opener accepts transfer to Diamonds');
    });

    test('2C Strong Opening: Kokish Relay and Kokish Flip 3C Heart one-suiter', () {
      // 2C -> 2D (waiting)
      final state2C2D = engine.graph.getState(['2c', '2d']);
      expect(state2C2D, isNotNull);
      final openerRebids = state2C2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerRebids, contains('2h'), reason: 'Kokish Relay');
      expect(openerRebids, contains('2s'), reason: 'Natural 5+ Spades GF');
      expect(openerRebids, contains('2nt'), reason: '22-24 balanced');

      // 2C -> 2D -> 2H -> 2S (Forced puppet response)
      final stateKokish2S = engine.graph.getState(['2c', '2d', '2h', '2s']);
      expect(stateKokish2S, isNotNull);
      final kokishCont = stateKokish2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(kokishCont, contains('2nt'), reason: '25+ balanced');
      expect(kokishCont, contains('3c'), reason: 'Kokish Flip: GF Heart one-suiter');
    });

    test('2C Opening: 22+ balanced (23 HCP) opens 2C and rebids 2NT over 2D', () {
      final hand23Bal = Hand.fromString('AK8:AQ4:AQ5:KJ92'); // 23 HCP (7+6+6+4), 3-3-3-4 balanced
      final rootState = engine.graph.rootState;
      final openingBid = rootState.resolveBestBid(hand23Bal, engine.resolver, fragments: engine.graph.system.fragments);
      expect(openingBid, isNotNull);
      expect(openingBid!.displayCall.toLowerCase(), equals('2c'), reason: '23 HCP balanced opens 2C');

      final state2C2D = engine.graph.getState(['2c', '2d'])!;
      final rebid = state2C2D.resolveBestBid(hand23Bal, engine.resolver, fragments: engine.graph.system.fragments);
      expect(rebid, isNotNull);
      expect(rebid!.displayCall.toLowerCase(), equals('2nt'), reason: '23 HCP balanced rebids 2NT (22-24)');
    });

    test('2C Opening: 25+ balanced (25 HCP) opens 2C, bids 2H Kokish, and rebids 2NT over 2S', () {
      final hand25Bal = Hand.fromString('AK8:AK4:AK5:KJ92'); // 25 HCP, 3-3-3-4 balanced
      final rootState = engine.graph.rootState;
      final openingBid = rootState.resolveBestBid(hand25Bal, engine.resolver, fragments: engine.graph.system.fragments);
      expect(openingBid, isNotNull);
      expect(openingBid!.displayCall.toLowerCase(), equals('2c'), reason: '25 HCP balanced opens 2C');

      final state2C2D = engine.graph.getState(['2c', '2d'])!;
      final kokishRebid = state2C2D.resolveBestBid(hand25Bal, engine.resolver, fragments: engine.graph.system.fragments);
      expect(kokishRebid, isNotNull);
      expect(kokishRebid!.displayCall.toLowerCase(), equals('2h'), reason: '25+ HCP balanced bids Kokish Relay 2H');

      final stateKokish2S = engine.graph.getState(['2c', '2d', '2h', '2s'])!;
      final bal2NTRebid = stateKokish2S.resolveBestBid(hand25Bal, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bal2NTRebid, isNotNull);
      expect(bal2NTRebid!.displayCall.toLowerCase(), equals('2nt'), reason: '25+ HCP balanced completes Kokish with 2NT');
    });

    test('2C Opening: GF unbalanced with Spades (19 HCP, 6 spades, 3 losers) opens 2C and rebids 2S', () {
      final handGfSpades = Hand.fromString('AKQJ94:AK:84:A83'); // 19 HCP, 6-2-2-3, 3 losers (GF!)
      final rootState = engine.graph.rootState;
      final openingBid = rootState.resolveBestBid(handGfSpades, engine.resolver, fragments: engine.graph.system.fragments);
      expect(openingBid, isNotNull);
      expect(openingBid!.displayCall.toLowerCase(), equals('2c'), reason: 'GF hand with 19 HCP and 6 Spades opens 2C');

      final state2C2D = engine.graph.getState(['2c', '2d'])!;
      final spadeRebid = state2C2D.resolveBestBid(handGfSpades, engine.resolver, fragments: engine.graph.system.fragments);
      expect(spadeRebid, isNotNull);
      expect(spadeRebid!.displayCall.toLowerCase(), equals('2s'), reason: 'Natural 5+ Spades GF rebid over 2D');
    });

    test('2C Opening: GF Hearts (18 HCP, 6 hearts, 3 losers) opens 2C, bids 2H Kokish, and flips 3C', () {
      final handGfHearts = Hand.fromString('AK:AKJ873:85:AK2'); // 18 HCP, 2-6-2-3, 3 losers (GF!)
      final rootState = engine.graph.rootState;
      final openingBid = rootState.resolveBestBid(handGfHearts, engine.resolver, fragments: engine.graph.system.fragments);
      expect(openingBid, isNotNull);
      expect(openingBid!.displayCall.toLowerCase(), equals('2c'), reason: 'GF hand with 18 HCP and 6 Hearts opens 2C');

      final state2C2D = engine.graph.getState(['2c', '2d'])!;
      final kokishRebid = state2C2D.resolveBestBid(handGfHearts, engine.resolver, fragments: engine.graph.system.fragments);
      expect(kokishRebid, isNotNull);
      expect(kokishRebid!.displayCall.toLowerCase(), equals('2h'), reason: 'Kokish Relay 2H for GF Hearts');

      final stateKokish2S = engine.graph.getState(['2c', '2d', '2h', '2s'])!;
      final flipRebid = stateKokish2S.resolveBestBid(handGfHearts, engine.resolver, fragments: engine.graph.system.fragments);
      expect(flipRebid, isNotNull);
      expect(flipRebid!.displayCall.toLowerCase(), equals('3c'), reason: 'Kokish Flip 3C showing GF with Hearts');
    });

    test('Walsh Minor structure: 1C -> 1D, Inverted Minors, 1m-2NT GF', () {
      final state1C = engine.graph.getState(['1c']);
      expect(state1C, isNotNull);
      final resp1C = state1C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(resp1C, contains('1d'), reason: 'Walsh 1D bypasses 4M if weak');
      expect(resp1C, contains('1h'), reason: 'Natural 4+ Hearts');
      expect(resp1C, contains('1s'), reason: 'Natural 4+ Spades');
      expect(resp1C, contains('2c'), reason: 'Inverted minor 10+ HCP');
      expect(resp1C, contains('2nt'), reason: 'GF 12-15 or 18+');
      expect(resp1C, contains('3c'), reason: 'Preemptive minor raise');

      // 1C -> 1D continuations: 1M is unbalanced, 1NT does not deny 4M
      final state1C1D = engine.graph.getState(['1c', '1d']);
      expect(state1C1D, isNotNull);
      final openerRebids = state1C1D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerRebids, contains('1h'), reason: 'Unbalanced 4+ Hearts');
      expect(openerRebids, contains('1s'), reason: 'Unbalanced 4+ Spades');
      expect(openerRebids, contains('1nt'), reason: 'Balanced 12-14 does not deny 4M');
    });

    test('Gavin Major Openings: 2D shows 5+, 2M rebid shows 6, Jacoby 2NT, Mixed Raise, Reversed Bart', () {
      final state1H = engine.graph.getState(['1h']);
      expect(state1H, isNotNull);
      final resp1H = state1H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(resp1H, contains('1s'));
      expect(resp1H, contains('1nt'), reason: 'Semi-forcing 1NT');
      expect(resp1H, contains('2c'), reason: '2/1 GF');
      expect(resp1H, contains('2d'), reason: '2/1 GF (promises 5+ Diamonds)');
      expect(resp1H, contains('2h'), reason: 'Constructive 6-9 raise');
      expect(resp1H, contains('2nt'), reason: 'Jacoby 2NT GF');
      expect(resp1H, contains('3d'), reason: 'Limit raise (10-11 HCP 4+ support)');
      expect(resp1H, contains('3h'), reason: 'Mixed raise (6-9 HCP 4+ support)');

      // 1H -> 3D (Limit raise) -> 3H (decline) / 4H (accept)
      final state1H3D = engine.graph.getState(['1h', '3d']);
      expect(state1H3D, isNotNull);
      final opener3DRebids = state1H3D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(opener3DRebids, contains('3h'), reason: 'Decline with 12-13 HCP minimum');
      expect(opener3DRebids, contains('4h'), reason: 'Accept with 14+ HCP');

      // 1H -> 2C -> 2H guarantees 6-card Hearts
      final state1H2C = engine.graph.getState(['1h', '2c']);
      expect(state1H2C, isNotNull);
      final openerRebids = state1H2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerRebids, contains('2h'), reason: 'Rebid shows 6-card Hearts');

      // 1S -> 1NT -> 2C -> 2H (Reversed Bart relay)
      final state1S1NT2C = engine.graph.getState(['1s', '1nt', '2c']);
      expect(state1S1NT2C, isNotNull);
      final bartBids = state1S1NT2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(bartBids, contains('2h'), reason: 'Reversed Bart relay to 2S');
    });

    test('Wolpert 4-Card Limit Raise (1H -> 3D): North J53:AK862:A96:98 (12 HCP) & South A642:QT54:J5:KT6 (10 HCP)', () {
      final north = Hand.fromString('J53:AK862:A96:98');
      final south = Hand.fromString('A642:QT54:J5:KT6');
      expect(north.hcp, equals(12));
      expect(south.hcp, equals(10));

      // North opens 1H
      final northOpen = engine.graph.rootState.resolveBestBid(north, engine.resolver, fragments: system.fragments);
      expect(northOpen, isNotNull);
      expect(northOpen!.displayCall.toLowerCase(), equals('1h'));

      // South responds 3D (Limit raise, 10-11 HCP, 4+ Hearts)
      final state1H = engine.graph.getState(['1h'])!;
      final southResp = state1H.resolveBestBid(south, engine.resolver, fragments: system.fragments);
      expect(southResp, isNotNull);
      expect(southResp!.displayCall.toLowerCase(), equals('3d'), reason: 'South bids 3D Limit Raise with 10 HCP and 4-4 in majors');

      // North rebids 3H (minimum 12 HCP declines invitation)
      final state1H3D = engine.graph.getState(['1h', '3d'])!;
      final northRebid = state1H3D.resolveBestBid(north, engine.resolver, fragments: system.fragments);
      expect(northRebid, isNotNull);
      expect(northRebid!.displayCall.toLowerCase(), equals('3h'), reason: 'North with flat 12 HCP minimum declines invitation');

      // South passes 3H
      final state1H3D3H = engine.graph.getState(['1h', '3d', '3h'])!;
      final southFinal = state1H3D3H.resolveBestBid(south, engine.resolver, fragments: system.fragments);
      expect(southFinal, isNotNull);
      expect(southFinal!.isPass, isTrue, reason: 'South passes 3H to sign off in partscore major fit');
    });

    test('Three-Way Checkback over 1x -> 1y -> 1NT rebid', () {
      final stateCheckback = engine.graph.getState(['1c', '1s', '1nt']);
      expect(stateCheckback, isNotNull);
      final checkbackCalls = stateCheckback!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(checkbackCalls, contains('2c'), reason: 'Invitational checkback (forces 2D)');
      expect(checkbackCalls, contains('2d'), reason: 'Game-forcing checkback');
      expect(checkbackCalls, contains('2s'), reason: 'Signoff in Spades');
      expect(checkbackCalls, contains('2nt'));
      expect(checkbackCalls, contains('3nt'));
    });

    test('Defense vs Opponent 1NT: X = 5m+4M, 2C = Landy, 2D = Multi, 2M = 5M+4m', () {
      final stateOpp1NT = engine.graph.getState(['1nt']);
      expect(stateOpp1NT, isNotNull);

      // In Gavin defense fragment:
      final fragDef = system.fragments['fGavinDefense1NT'];
      expect(fragDef, isNotNull);
      final defCalls = fragDef!.bids.map((b) => b.displayCall.toLowerCase()).toSet();
      expect(defCalls, contains('dbl'), reason: '5m + 4M');
      expect(defCalls, contains('2c'), reason: 'Landy both majors');
      expect(defCalls, contains('2d'), reason: 'Multi one 6-card major');
      expect(defCalls, contains('2h'), reason: '5 Hearts + 4 minor');
      expect(defCalls, contains('2s'), reason: '5 Spades + 4 minor');
    });

    test('Puppet Stayman is fully integrated over 1NT and 2NT', () {
      // 1. Puppet Stayman over 1NT: 1NT -> 3C
      final state1NT3C = engine.graph.getState(['1nt', '3c']);
      expect(state1NT3C, isNotNull, reason: '1NT:3C Puppet Stayman state exists');
      final opener1NTResponses = state1NT3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(opener1NTResponses, contains('3d'), reason: 'Opener has one or two 4-card majors');
      expect(opener1NTResponses, contains('3h'), reason: 'Opener has 5-card Hearts');
      expect(opener1NTResponses, contains('3s'), reason: 'Opener has 5-card Spades');
      expect(opener1NTResponses, contains('3nt'), reason: 'Opener has no 4-card or 5-card major');

      // 1NT:3C:3D -> 3H shows 4 Spades, 3S shows 4 Hearts
      final state1NT3C3D = engine.graph.getState(['1nt', '3c', '3d']);
      expect(state1NT3C3D, isNotNull);
      final respContinuations = state1NT3C3D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respContinuations, contains('3h'), reason: '3H shows 4 Spades (other major)');
      expect(respContinuations, contains('3s'), reason: '3S shows 4 Hearts (other major)');
      expect(respContinuations, contains('3nt'), reason: 'To play 3NT');

      // 2. Puppet Stayman over 2NT: 2NT -> 3C
      final state2NT3C = engine.graph.getState(['2nt', '3c']);
      expect(state2NT3C, isNotNull, reason: '2NT:3C Puppet Stayman state exists');
      final opener2NTResponses = state2NT3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(opener2NTResponses, contains('3d'));
      expect(opener2NTResponses, contains('3h'));
      expect(opener2NTResponses, contains('3s'));
      expect(opener2NTResponses, contains('3nt'));

      // 2NT:3C:3D:3H -> 4S (Opener raises to game in Spades)
      final state2NT3C3D3H = engine.graph.getState(['2nt', '3c', '3d', '3h']);
      expect(state2NT3C3D3H, isNotNull);
      final openerFit = state2NT3C3D3H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerFit, contains('4s'), reason: 'Opener confirms 4S game');
    });

    test('1NT responses: K93:AQ65:Q3:J874 bids 3C Puppet Stayman (single 4-card major GF), not 2C Stayman', () {
      final state1NT = engine.graph.getState(['1nt'])!;

      // Hand: K93:AQ65:Q3:J874 (12 HCP, 3 Spades, 4 Hearts, 2 Diamonds, 4 Clubs, 4432 shape)
      final southSingleMajorGF = Hand.fromString('K93:AQ65:Q3:J874');
      final candidates = state1NT.evaluateCandidates(
        southSingleMajorGF,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );

      final cand3C = candidates.firstWhere((c) => c.displayCall.toLowerCase() == '3c');
      expect(cand3C.isMatch, isTrue, reason: '3C Puppet Stayman matches GF hand with exactly one 4-card major');

      final cand2C = candidates.firstWhere((c) => c.displayCall.toLowerCase() == '2c');
      expect(cand2C.isMatch, isFalse, reason: '2C Regular Stayman must NOT match GF hand with only one 4-card major');

      final bestBid = state1NT.resolveBestBid(
        southSingleMajorGF,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('3c'));

      // Test with AuctionEngine
      final deal = PartnershipDeal(
        north: Hand.fromString('AQ2:KJ4:KJ52:K63'), // 17 HCP balanced (15-17 1NT opening)
        east: Hand.fromString('864:T98:T984:QT5'),
        south: southSingleMajorGF,
        west: Hand.fromString('JT5:732:A76:J982'),
      );
      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);

      // Submitting 2C must be marked incorrect
      final wrong2CStep = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2c',
        deal: deal,
      );
      expect(wrong2CStep.isUserBidCorrect, isFalse, reason: '2C is incorrect with only one 4-card major GF');
      expect(wrong2CStep.expectedBestBid!.displayCall.toLowerCase(), equals('3c'));

      // Submitting 3C must be marked correct
      final correct3CStep = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '3c',
        deal: deal,
      );
      expect(correct3CStep.isUserBidCorrect, isTrue, reason: '3C Puppet Stayman is the correct call');
      final southEntry = correct3CStep.updatedHistory.firstWhere((e) => e.seat == 'S');
      expect(southEntry.call.toLowerCase(), equals('3c'));
      expect(correct3CStep.updatedHistory.any((e) => e.seat == 'N' && e.call.toLowerCase() == '3nt'), isTrue,
          reason: 'North (no 4/5-card major) rebids 3NT over 3C');
    });

    test('1NT responses: both 4-card majors (GF) or invitational (8-9 HCP) bid 2C Stayman; 4333 bids 3NT', () {
      final state1NT = engine.graph.getState(['1nt'])!;

      // Both 4-card majors GF (12 HCP, 4-4 in majors): K963:AQ65:Q3:874 -> 2C
      final southBothMajorsGF = Hand.fromString('K963:AQ65:Q3:874');
      final bestBothMajors = state1NT.resolveBestBid(
        southBothMajorsGF,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(bestBothMajors, isNotNull);
      expect(bestBothMajors!.displayCall.toLowerCase(), equals('2c'), reason: 'Both 4-card majors bid 2C Regular Stayman');

      // Invitational with 4 Hearts (9 HCP, 4-3 in majors): 963:AQ65:Q3:J874 -> 2C
      final southInvite = Hand.fromString('963:AQ65:Q3:J874');
      final bestInvite = state1NT.resolveBestBid(
        southInvite,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(bestInvite, isNotNull);
      expect(bestInvite!.displayCall.toLowerCase(), equals('2c'), reason: 'Invitational with 4-card major bids 2C');

      // Flat 4333 with 11 HCP: K93:AQ65:Q32:874 -> 3NT (bypassing Puppet Stayman)
      final south4333 = Hand.fromString('K93:AQ65:Q32:874');
      final best4333 = state1NT.resolveBestBid(
        south4333,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(best4333, isNotNull);
      expect(best4333!.displayCall.toLowerCase(), equals('3nt'), reason: '4333 flat hand bypasses Puppet Stayman and bids 3NT');
    });

    test('1NT responses: South bids 2D transfer to Hearts, North rebids 2H with 3 Hearts', () {
      final northHand = Hand.fromString('K962:AQ3:865:AKT'); // 16 HCP, 3 Hearts
      final southHand = Hand.fromString('J:JT976:A9:J8753'); // 7 HCP, 5 Hearts
      final deal = PartnershipDeal(
        north: northHand,
        east: Hand.fromString('864:T98:T984:QT5'),
        south: southHand,
        west: Hand.fromString('JT5:732:A76:J982'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

      // South submits 2D (Jacoby transfer to Hearts)
      final advanceStep = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2d',
        deal: deal,
      );

      expect(advanceStep.isUserBidCorrect, isTrue, reason: '2D is correct Jacoby transfer to Hearts');
      
      // North must rebid 2H (accepting the transfer)
      final northRebid = advanceStep.updatedHistory.firstWhere((e) => e.seat == 'N' && e.call.toLowerCase() != '1nt');
      expect(northRebid.call.toLowerCase(), equals('2h'), reason: 'North accepts transfer to Hearts with 2H');
      expect(northRebid.desc, contains('transfer to Hearts'));

      // State 1NT:2D should contain transfer acceptances (2H, 3H) and NOT Lebensohl bids like 3C
      final state1NT2D = engine.graph.getState(['1nt', '2d'])!;
      final candidateCalls = state1NT2D.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
      expect(candidateCalls, contains('2h'));
      expect(candidateCalls, isNot(contains('3c')), reason: '3C Lebensohl belongs to opponent overcall (2D), not 2D transfer');
    });

    test('1NT Stayman continuations: 1NT - 2C - 2D - 2NT (invitational) - 3NT (accept game)', () {
      final northHand = Hand.fromString('A3:A62:KQ2:KT532'); // 16 HCP, balanced (15-17 1NT)
      final southHand = Hand.fromString('T97:J753:87:AQJ9'); // 8 HCP, 4 Hearts (invitational)
      final deal = PartnershipDeal(
        north: northHand,
        east: Hand.fromString('864:T98:T964:865'),
        south: southHand,
        west: Hand.fromString('KJ52:Q4:AJ53:742'),
      );

      // 1. North opens 1NT
      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

      // 2. South bids 2C (Regular Stayman)
      final step2C = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2c',
        deal: deal,
      );
      expect(step2C.isUserBidCorrect, isTrue, reason: '2C Stayman is correct with 8 HCP and 4 Hearts');

      // North rebids 2D (no 4-card major)
      final north2D = step2C.updatedHistory.firstWhere((e) => e.seat == 'N' && e.call.toLowerCase() != '1nt');
      expect(north2D.call.toLowerCase(), equals('2d'), reason: 'North has no 4-card major (3H, 2S)');

      // 3. South bids 2NT (Invitational)
      final step2NT = engine.advanceAuction(
        history: step2C.updatedHistory,
        userCall: '2nt',
        deal: deal,
      );
      expect(step2NT.isUserBidCorrect, isTrue, reason: '2NT is correct invitational bid after 2D');

      // North with 16 HCP accepts the invitation with 3NT
      final north3NT = step2NT.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(north3NT.call.toLowerCase(), equals('3nt'), reason: 'North with 16 HCP accepts game in 3NT');
    });

    test('1NT Jacoby Transfer continuations: 8 HCP bids 2NT (invitational), 10+ HCP bids 3NT (choice of games)', () {
      // 1. South with 8 HCP (K4:J8764:Q984:Q7) from user screenshot
      final south8Hcp = Hand.fromString('K4:J8764:Q984:Q7');
      expect(south8Hcp.hcp, equals(8));
      expect(south8Hcp.heartsLength, equals(5));

      final deal8Hcp = PartnershipDeal(
        north: Hand.fromString('A3:A62:KJ2:KT532'), // 16 HCP (3 Hearts)
        east: Hand.fromString('865:T98:T76:J864'),
        south: south8Hcp,
        west: Hand.fromString('QJT972:K5:A53:A9'),
      );

      final startStep = engine.startDeal(deal: deal8Hcp, isNorthFirst: true);
      // South bids 2D
      final step2D = engine.advanceAuction(history: startStep.updatedHistory, userCall: '2d', deal: deal8Hcp);
      expect(step2D.isUserBidCorrect, isTrue);
      // North rebids 2H
      expect(step2D.updatedHistory.lastWhere((e) => e.seat == 'N').call.toLowerCase(), equals('2h'));

      // If South bids 3NT with 8 HCP, it is rejected (requires 2NT)
      final wrong3NTStep = engine.advanceAuction(history: step2D.updatedHistory, userCall: '3nt', deal: deal8Hcp);
      expect(wrong3NTStep.isUserBidCorrect, isFalse, reason: '8 HCP is not enough for 3NT (GF 10-15 HCP)');
      expect(wrong3NTStep.expectedBestBid!.displayCall.toLowerCase(), equals('2nt'));

      // South bids 2NT (correct invitational)
      final step2NT = engine.advanceAuction(history: step2D.updatedHistory, userCall: '2nt', deal: deal8Hcp);
      expect(step2NT.isUserBidCorrect, isTrue, reason: '2NT is correct with 8-9 HCP and 5 Hearts');

      // 2. South with 12 HCP Game-Forcing (K4:AJ764:Q984:Q7)
      final south12Hcp = Hand.fromString('K4:AJ764:Q984:Q7');
      expect(south12Hcp.hcp, equals(12));
      final deal12Hcp = PartnershipDeal(
        north: Hand.fromString('A3:A62:KJ2:KT532'), // 16 HCP (3 Hearts)
        east: Hand.fromString('865:T98:T76:J864'),
        south: south12Hcp,
        west: Hand.fromString('QJT972:K5:A53:86'),
      );

      final startStep12 = engine.startDeal(deal: deal12Hcp, isNorthFirst: true);
      final step2D12 = engine.advanceAuction(history: startStep12.updatedHistory, userCall: '2d', deal: deal12Hcp);
      
      // South bids 3NT (Choice of Games, 10-15 HCP)
      final step3NT12 = engine.advanceAuction(history: step2D12.updatedHistory, userCall: '3nt', deal: deal12Hcp);
      expect(step3NT12.isUserBidCorrect, isTrue, reason: '3NT is correct with 12 HCP (10-15 HCP range)');

      // North with 3 Hearts converts 3NT to 4H
      final northRebidOver3NT = step3NT12.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(northRebidOver3NT.call.toLowerCase(), equals('4h'), reason: 'North converts 3NT to 4H with 3-card Heart fit');
    });

    test('1NT responses: 5 Spades and 4 Hearts (10 HCP GF) bids 2C Stayman for Smolen (user screenshot 2)', () {
      // North from screenshot 2: 86:AJ74:AKQ:J965 (15 HCP, 2s 4h 3d 4c)
      final north = Hand.fromString('86:AJ74:AKQ:J965');
      // South from screenshot 2: AQJ97:QT83:J84:3 (10 HCP, 5s 4h 3d 1c)
      final south = Hand.fromString('AQJ97:QT83:J84:3');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('T54:K92:T72:A874'),
        south: south,
        west: Hand.fromString('K32:65:9653:KQT2'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

      // South must bid 2c Stayman
      final state1NT = engine.graph.getState(['1nt'])!;
      final bestBid = state1NT.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('2c'), reason: '5-4 in majors with GF (10+ HCP) must bid 2C Stayman for Smolen');

      // Advance auction: South bids 2c
      final step2C = engine.advanceAuction(history: startStep.updatedHistory, userCall: '2c', deal: deal);
      expect(step2C.isUserBidCorrect, isTrue);

      // North with 4 Hearts rebids 2h
      final north2H = step2C.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(north2H.call.toLowerCase(), equals('2h'), reason: 'North has 4 Hearts');

      // South with 4 Hearts raises to 4H game
      final step4H = engine.advanceAuction(history: step2C.updatedHistory, userCall: '4h', deal: deal);
      expect(step4H.isUserBidCorrect, isTrue);
    });

    test('2/1 GF balanced response: South with 3-3-4-3 (13 HCP) bids 2C over 1H, North rebids 2NT, South bids 4H', () {
      // North from user screenshot: AT5:KQT83:QJ3:72 (12 HCP, 3s 5h 3d 2c)
      final north = Hand.fromString('AT5:KQT83:QJ3:72');
      // South from user screenshot: 864:A52:K982:AQ9 (13 HCP, 3s 3h 4d 3c)
      final south = Hand.fromString('864:A52:K982:AQ9');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('J972:J7:A764:T63'),
        south: south,
        west: Hand.fromString('KQ3:964:T5:KJ854'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1h'), reason: 'North opens 1H with 12 HCP 5-card Hearts');

      // South must bid 2C (2/1 Game Force: Natural or Balanced GF 12+ HCP)
      final state1H = engine.graph.getState(['1h'])!;
      final bestBid = state1H.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('2c'), reason: 'South bids 2C with 13 HCP balanced GF');

      // Advance auction: South bids 2c
      final step2C = engine.advanceAuction(history: startStep.updatedHistory, userCall: '2c', deal: deal);
      expect(step2C.isUserBidCorrect, isTrue);

      // North with balanced minimum (3-5-3-2, 12 HCP) rebids 2NT
      final north2NT = step2C.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(north2NT.call.toLowerCase(), equals('2nt'), reason: 'North rebids 2NT with balanced 12-14 minimum');

      // South with 3-card Heart support signs off in 4H game
      final state1H2C2NT = engine.graph.getState(['1h', '2c', '2nt'])!;
      final southGameBid = state1H2C2NT.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
      expect(southGameBid, isNotNull);
      expect(southGameBid!.displayCall.toLowerCase(), equals('4h'), reason: 'South bids 4H with 3-card support');

      final step4H = engine.advanceAuction(history: step2C.updatedHistory, userCall: '4h', deal: deal);
      expect(step4H.isUserBidCorrect, isTrue);
      expect(step4H.isAuctionComplete, isTrue, reason: 'Auction finishes in 4H');
    });

    test('Nebulous 2C over 1S: South with 2-4-4-2 (15 HCP) bids 2C with only 2 clubs', () {
      // North opens 1S with 5 Spades balanced: AK964:75:862:AQ3 (13 HCP)
      final north = Hand.fromString('AK964:75:862:AQ3');
      // South has 2-4-4-2 GF: Q3:KJ82:AQ94:K2 (15 HCP, only 2 clubs, 4-4 red suits)
      final south = Hand.fromString('Q3:KJ82:AQ94:K2');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('T852:T64:JT3:985'),
        south: south,
        west: Hand.fromString('J7:AQ93:K75:JT76'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1s'));

      // South cannot bid 2H (requires 5+ Hearts) or 2D (requires 5+ Diamonds).
      // South must bid Nebulous 2C with 2+ clubs!
      final state1S = engine.graph.getState(['1s'])!;
      final bestBid = state1S.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('2c'), reason: 'South bids Nebulous 2C with 2=4=4=2 balanced GF');

      final step2C = engine.advanceAuction(history: startStep.updatedHistory, userCall: '2c', deal: deal);
      expect(step2C.isUserBidCorrect, isTrue);

      // North rebids 2NT (balanced minimum 5-2-3-3)
      final north2NT = step2C.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(north2NT.call.toLowerCase(), equals('2nt'), reason: 'North rebids 2NT with balanced minimum');

      // South without 3-card Spade fit signs off in 3NT
      final step3NT = engine.advanceAuction(history: step2C.updatedHistory, userCall: '3nt', deal: deal);
      expect(step3NT.isUserBidCorrect, isTrue);
      expect(step3NT.isAuctionComplete, isTrue, reason: 'Auction finishes in 3NT');
    });

    test('Nebulous 2C over 1D: South with 3-3-3-4 (15 HCP) and no 4M bids 2C over 1D', () {
      // North opens 1D with 5 Diamonds: K4:Q83:AK982:762 (13 HCP)
      final north = Hand.fromString('K4:Q83:AK982:762');
      // South has 3-3-3-4 shape (3 diamonds, not enough for 4+ inverted 2D): AJ3:K75:763:AK84 (15 HCP)
      final south = Hand.fromString('AJ3:K75:763:AK84');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('9862:JT6:JT4:T93'),
        south: south,
        west: Hand.fromString('QT75:A942:Q5:QJ5'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1d'), reason: 'North opens 1D');

      // South has no 4-card major, and only 3 diamonds.
      // South bids Nebulous 2C Game Force!
      final state1D = engine.graph.getState(['1d'])!;
      final bestBid = state1D.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('2c'), reason: 'South bids Nebulous 2C over 1D');

      final step2C = engine.advanceAuction(history: startStep.updatedHistory, userCall: '2c', deal: deal);
      expect(step2C.isUserBidCorrect, isTrue);

      // North rebids 2NT (balanced minimum)
      final northRebid = step2C.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(northRebid.call.toLowerCase(), equals('2nt'), reason: 'North rebids 2NT stopper inquiry');

      // South with balanced GF bids 3NT
      final step3NT = engine.advanceAuction(history: step2C.updatedHistory, userCall: '3nt', deal: deal);
      expect(step3NT.isUserBidCorrect, isTrue);
      expect(step3NT.isAuctionComplete, isTrue, reason: 'Auction finishes in 3NT');
    });

    test('Walsh 1C response: South with 5 Hearts and 4 Spades (8742:QJ843:96:AK, 10 HCP) bids 1H (user screenshot)', () {
      // North opens 1C: Q3:K97:AJ85:Q854 (12 HCP)
      final north = Hand.fromString('Q3:K97:AJ85:Q854');
      // South from user screenshot: 8742:QJ843:96:AK (10 HCP, 4s 5h 2d 2c)
      final south = Hand.fromString('8742:QJ843:96:AK');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('JT95:T2:KQT7:JT2'),
        south: south,
        west: Hand.fromString('AK6:A65:432:9763'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1c'), reason: 'North opens 1C');

      // South has 5 Hearts and 4 Spades: longer major (1H) MUST take precedence over 4-card Spades (1S)
      final state1C = engine.graph.getState(['1c'])!;
      final bestBid = state1C.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('1h'), reason: 'South bids 1H with 5 Hearts and 4 Spades (longer major first)');

      final step1H = engine.advanceAuction(history: startStep.updatedHistory, userCall: '1h', deal: deal);
      expect(step1H.isUserBidCorrect, isTrue, reason: '1H response is accepted as correct');
    });

    test('Three-Way Checkback: South with 3-3-4-3 (16 HCP) and 3-h 3-s bids 3NT over 1C - 1D - 1NT (user screenshot)', () {
      // North opens 1C: A52:A982:A95:632 (12 HCP)
      final north = Hand.fromString('A52:A982:A95:632');
      // South from user screenshot: KJ6:K64:QT72:AK4 (16 HCP, 3s 3h 4d 3c)
      final south = Hand.fromString('KJ6:K64:QT72:AK4');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('T98:QJ5:J84:T875'),
        south: south,
        west: Hand.fromString('Q743:T73:K63:QJ9'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1c'), reason: 'North opens 1C');

      // South responds 1D
      final step1D = engine.advanceAuction(history: startStep.updatedHistory, userCall: '1d', deal: deal);
      expect(step1D.isUserBidCorrect, isTrue);

      // North rebids 1NT (12-14 balanced)
      final north1NT = step1D.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(north1NT.call.toLowerCase(), equals('1nt'), reason: 'North rebids 1NT');

      // South has 3-3 in majors (no 4-card or 5-card major fit possible) and 16 HCP balanced.
      // South bids 3NT directly without needing artificial 2D checkback!
      final state1C1D1NT = engine.graph.getState(['1c', '1d', '1nt'])!;
      final bestBid = state1C1D1NT.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('3nt'), reason: 'South bids 3NT with 3-3 in majors and 16 HCP balanced');

      final step3NT = engine.advanceAuction(history: step1D.updatedHistory, userCall: '3nt', deal: deal);
      expect(step3NT.isUserBidCorrect, isTrue, reason: '3NT is correct');
      expect(step3NT.isAuctionComplete, isTrue, reason: 'Auction finishes in 3NT');
    });
  });
}
