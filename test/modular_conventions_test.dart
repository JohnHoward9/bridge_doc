import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/hand_parser.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadSystem(String relativePath) async {
    final file = File(relativePath);
    final yamlStr = await file.readAsString();
    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
  }

  group('Modular Convention Deduplication Tests', () {
    test('Smolen and Stayman modules load and integrate cleanly into US Standard 2/1', () async {
      final system = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      expect(system.fragments.containsKey('fSmolen'), isTrue, reason: 'fSmolen loaded from smolen.yaml');
      expect(system.fragments.containsKey('fStayman'), isTrue, reason: 'fStayman loaded from stayman.yaml');
      expect(system.fragments.containsKey('fJacobyTransferAcceptance'), isTrue, reason: 'fJacobyTransferAcceptance loaded from jacoby_transfers.yaml');

      final engine = AuctionEngine.fromSystem(system);

      // Verify 1NT:2C:2D has Smolen 3H and 3S
      final state2D = engine.graph.getState(['1nt', '2c', '2d']);
      expect(state2D, isNotNull);
      final calls = state2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('3h'), reason: 'Smolen 3H available');
      expect(calls, contains('3s'), reason: 'Smolen 3S available');
    });

    test('Smolen and Stayman modules integrate cleanly into Gavin Wolpert 2/1', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      expect(system.fragments.containsKey('fSmolen'), isTrue);
      expect(system.fragments.containsKey('fStayman'), isTrue);
      expect(system.fragments.containsKey('fJacobyTransferAcceptance'), isTrue);

      final engine = AuctionEngine.fromSystem(system);

      // Verify Gavin Wolpert system resolves Smolen after 1NT:2C:2D
      final state2D = engine.graph.getState(['1nt', '2c', '2d']);
      expect(state2D, isNotNull);
      final calls = state2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('3h'));
      expect(calls, contains('3s'));


      // Test full auction with Gavin Wolpert engine:
      // South has 4 Spades, 5 Hearts, 10 HCP GF: A653:A9742:Q5:62
      final north = Hand.fromString('K82:K63:AT84:AJ5'); // 16 HCP, 3 Hearts, 3 Spades
      final south = Hand.fromString('A653:A9742:Q5:62');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('72:J8:KJ92:T8732'),
        south: south,
        west: Hand.fromString('QT94:QT5:763:K94'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

      // 1. South bids 2c Stayman
      final step2C = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2c',
        deal: deal,
      );
      expect(step2C.isUserBidCorrect, isTrue);

      // North rebids 2d (no 4-card major)
      final north2D = step2C.updatedHistory.firstWhere((e) => e.seat == 'N' && e.call.toLowerCase() != '1nt');
      expect(north2D.call.toLowerCase(), equals('2d'));

      // 2. South bids 3S (Smolen with 5 Hearts, 4 Spades)
      final step3S = engine.advanceAuction(
        history: step2C.updatedHistory,
        userCall: '3s',
        deal: deal,
      );
      expect(step3S.isUserBidCorrect, isTrue, reason: 'Gavin Wolpert system recognizes Smolen 3S rebid');

      // North accepts in 4H
      final north4H = step3S.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(north4H.call.toLowerCase(), equals('4h'));
    });

    test('Reversed Bart convention resolves across Gavin Wolpert and US Standard 2/1 systems', () async {
      final gavinSystem = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final gavinEngine = AuctionEngine.fromSystem(gavinSystem);

      // 1. Check 1S -> 1NT -> 2C candidates under Gavin 2/1
      final state1S1NT2C = gavinEngine.graph.getState(['1s', '1nt', '2c']);
      expect(state1S1NT2C, isNotNull, reason: '1S -> 1NT -> 2C state exists');
      final bartCalls = state1S1NT2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(bartCalls, containsAll(['pass', '2d', '2h', '2s', '2nt']));

      // 2. Check 2H relay forces opener to 2S
      final state2HRelay = gavinEngine.graph.getState(['1s', '1nt', '2c', '2h']);
      expect(state2HRelay, isNotNull);
      final opener2SRebid = state2HRelay!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(opener2SRebid, contains('2s'), reason: 'Opener forced to 2S over 2H relay');

      // 3. Check responder continuations over 2S
      final stateOver2S = gavinEngine.graph.getState(['1s', '1nt', '2c', '2h', '2s']);
      expect(stateOver2S, isNotNull);
      final respCont = stateOver2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCont, containsAll(['pass', '2nt', '3c', '3s']));

      // 4. Verify 1H -> 1NT -> 2C has natural responses without 2S relay
      final state1H1NT2C = gavinEngine.graph.getState(['1h', '1nt', '2c']);
      expect(state1H1NT2C, isNotNull);
      final heartCont = state1H1NT2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(heartCont, containsAll(['pass', '2d', '2h', '2s', '2nt', '3c', '3h']));
      expect(heartCont, isNot(contains('3s')), reason: 'No spade splinter or jump over 1H-1NT-2C');

      // 5. Verify US Standard 2/1 also resolves Reversed Bart via five_card_majors_2over1.yaml
      final usSystem = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      final usEngine = AuctionEngine.fromSystem(usSystem);
      final usState1S1NT2C = usEngine.graph.getState(['1s', '1nt', '2c']);
      expect(usState1S1NT2C, isNotNull);
      final usBartCalls = usState1S1NT2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(usBartCalls, containsAll(['pass', '2d', '2h', '2s', '2nt']));
    });

    test('Multi-Landy is active in Gavin Wolpert 2/1 and provides competitive calls over 1NT', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      expect(system.fragments.containsKey('fMultiLandy'), isTrue, reason: 'fMultiLandy loaded from multi_landy.yaml');

      final engine = AuctionEngine.fromSystem(system);

      // 1. Verify 1NT has competitive Multi-Landy opponent calls
      final state1NT = engine.graph.getState(['1nt']);
      expect(state1NT, isNotNull);
      final rawCalls = state1NT!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(rawCalls, containsAll(['(x)', '(2c)', '(2d)', '(2h)', '(2s)', '(2nt)']));

      // 2. Verify (1nt) Opposition opening resolves to Multi-Landy
      final stateOpp1NT = engine.graph.getState(['(1nt)']);
      expect(stateOpp1NT, isNotNull);
      final callsOpp1NT = stateOpp1NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOpp1NT, containsAll(['2c', '2d', '2h', '2s', '2nt', 'dbl']));

      // 3. Verify opponent intervention (2d) resolves to Transfer Lebensohl, not Jacoby transfer acceptance
      final stateOpp2D = engine.graph.getState(['1nt', '(2d)']);
      expect(stateOpp2D, isNotNull, reason: '1NT - (2d) state exists in compiled graph');
      final opp2DCalls = stateOpp2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(opp2DCalls, containsAll(['pass', 'dbl', '2h', '2s', '2nt', '3c', '3d', '3h', '3nt']));
      expect(opp2DCalls, isNot(contains('4h')), reason: 'No Jacoby super-accept runouts over opponent 2D');

      // Contrast: friendly responder 2d is Jacoby Transfer to Hearts
      final stateFriendly2D = engine.graph.getState(['1nt', '2d']);
      expect(stateFriendly2D, isNotNull);
      final friendly2DCalls = stateFriendly2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(friendly2DCalls, containsAll(['pass', '2h', '3h']));
      expect(friendly2DCalls, isNot(contains('2s')), reason: 'Jacoby 2D transfer does not have natural 2S response');

      // 4. Verify opponent advancer responses after 1NT - (2D) - Pass
      final stateAdvancer2D = engine.graph.getState(['1nt', '(2d)', 'pass']);
      expect(stateAdvancer2D, isNotNull, reason: '1NT - (2d) - pass state exists for opponent advancer');
      final advancer2DCalls = stateAdvancer2D!.candidateNodes.map((n) => n.auctionCall.toLowerCase()).toSet();
      expect(advancer2DCalls, containsAll(['(2h)', '(2s)', '(2nt)', '(3h)', '(3s)']));

      // 5. Verify overcaller pass or correct over advancer's 2H
      final stateOver2H = engine.graph.getState(['1nt', '(2d)', 'pass', '(2h)']);
      expect(stateOver2H, isNotNull, reason: 'Overcaller pass or correct state exists');
      final overcallerCalls = stateOver2H!.candidateNodes.map((n) => n.auctionCall.toLowerCase()).toSet();
      expect(overcallerCalls, containsAll(['pass', '(2s)']), reason: 'Overcaller can pass with Hearts or correct to 2S with Spades');

      // 6. Verify advancer relay after 1NT - (2C) - Pass
      final stateAdvancer2C = engine.graph.getState(['1nt', '(2c)', 'pass']);
      expect(stateAdvancer2C, isNotNull);
      final advancer2CCalls = stateAdvancer2C!.candidateNodes.map((n) => n.auctionCall.toLowerCase()).toSet();
      expect(advancer2CCalls, contains('(2d)'), reason: 'Advancer relay 2D asks for longer major');
    });

    test('Stayman, Puppet Stayman, and 1NT continuations follow user specifications', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      // 1. Verify 1NT - 2C - 2D - 2S invitational sequence exists and allows opener to pass with minimum
      final state2S = engine.graph.getState(['1nt', '2c', '2d', '2s']);
      expect(state2S, isNotNull, reason: '1NT - 2C - 2D - 2S invitational sequence exists');
      final callsAfter2S = state2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsAfter2S, containsAll(['pass', '2nt', '3s', '4s', '3nt']),
          reason: 'Opener can pass with minimum or raise with maximum');

      // 2. Verify Garbage Stayman 1NT - 2C - 2D - 2H pass or correct exists
      final state2H = engine.graph.getState(['1nt', '2c', '2d', '2h']);
      expect(state2H, isNotNull, reason: '1NT - 2C - 2D - 2H Garbage Stayman exists');
      final callsAfter2H = state2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsAfter2H, containsAll(['pass', '2s']), reason: 'Opener can pass 2H or correct to 2S');

      // 3. Verify 5-card minor rebids after 1NT - 2C - 2D
      final state2D = engine.graph.getState(['1nt', '2c', '2d']);
      expect(state2D, isNotNull);
      final callsAfter2D = state2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsAfter2D, containsAll(['2h', '2s', '2nt', '3c', '3d', '3nt']));

      // 4. Verify 5-card minor rebids after 1NT - 2C - 2H (showing other major)
      final stateOver2H = engine.graph.getState(['1nt', '2c', '2h']);
      expect(stateOver2H, isNotNull);
      final callsOver2H = stateOver2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOver2H, containsAll(['3c', '3d']), reason: 'Can bid 5-card minor after opener shows 2H');

      // 5. Hand evaluations over 1NT:
      final resolver = engine.resolver;
      final state1NT = engine.graph.getState(['1nt'])!;

      String bestCallFor(Hand hand) {
        final evals = state1NT.evaluateCandidates(hand, resolver, fragments: system.fragments);
        final matches = evals.where((c) => c.isMatch).toList();
        matches.sort((a, b) => (a.priority ?? 99).compareTo(b.priority ?? 99));
        return matches.first.displayCall.toLowerCase();
      }

      // 5a. 4333 with 4-card major and 10-15 HCP bids 3NT directly (not Stayman or Puppet)
      final hand4333GF = HandParser.parseSingleHand('AK32.K43.Q32.J43'); // 4-3-3-3 with 4S, 13 HCP
      expect(bestCallFor(hand4333GF), equals('3nt'), reason: '4333 GF with 4M bids 3NT directly');

      // 5b. 4333 with 4-card major and 8-9 HCP bids 2S (Range Ask / Clubs)
      final hand4333Inv = HandParser.parseSingleHand('Q432.K43.Q32.J43'); // 4-3-3-3 with 4S, 9 HCP
      expect(bestCallFor(hand4333Inv), equals('2s'), reason: '4333 invite with 4M bids 2S Range Ask');

      // 5c. 4432 with one major and 8-9 HCP bids 2C Stayman
      final handOneMajorInv = HandParser.parseSingleHand('Q432.K43.Q542.J3'); // 4S-3H-4D-2C, 9 HCP
      expect(bestCallFor(handOneMajorInv), equals('2c'), reason: '4432 with 1 major and 8-9 HCP bids 2C Stayman');

      // 5d. 4432 with one major and 10+ HCP bids 3C Puppet Stayman
      final handOneMajorGF = HandParser.parseSingleHand('A432.K43.Q542.A3'); // 4S-3H-4D-2C, 14 HCP
      expect(bestCallFor(handOneMajorGF), equals('3c'), reason: '4432 with 1 major and GF bids 3C Puppet Stayman');

      // 5e. 2-4-2-5 (4 Hearts, 5 Clubs) with 10+ HCP bids 2C Stayman (not Puppet)
      final hand2425GF = HandParser.parseSingleHand('A2.KJ43.A2.Q7654'); // 2-4-2-5, 13 HCP
      expect(bestCallFor(hand2425GF), equals('2c'), reason: '2-4-2-5 GF bids 2C Stayman to show 5C rebid later');

      // 5f. 4432 with both majors and weak 0-7 HCP bids 2C Stayman
      final handBothMajorsWeak = HandParser.parseSingleHand('J432.9876.J32.32'); // 4S-4H-3D-2C, 2 HCP
      expect(bestCallFor(handBothMajorsWeak), equals('2c'), reason: 'Weak hand with both majors bids 2C Garbage Stayman');
    });

    test('Puppet Stayman 1NT and 2NT are in separate libraries and resolve distinctly', () async {
      // 1. Verify 1NT Puppet Stayman loads independently
      final file1NT = File('assets/libraries/conventions/puppet_stayman_1nt.yaml');
      expect(file1NT.existsSync(), isTrue);
      final yaml1NT = await file1NT.readAsString();
      final system1NT = await SystemLibraryResolver.loadSystemWithLibraries(yaml1NT);
      expect(system1NT.fragments.containsKey('fPuppetStayman1NT'), isTrue);

      // 2. Verify 2NT Puppet Stayman loads independently
      final file2NT = File('assets/libraries/conventions/puppet_stayman_2nt.yaml');
      expect(file2NT.existsSync(), isTrue);
      final yaml2NT = await file2NT.readAsString();
      final system2NT = await SystemLibraryResolver.loadSystemWithLibraries(yaml2NT);
      expect(system2NT.fragments.containsKey('Strong2NTOpening'), isTrue);
      expect(system2NT.fragments.containsKey('fPuppetStayman2NT'), isTrue);

      // 3. Verify Gavin Wolpert system integrates both distinctly
      final gavinSystem = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(gavinSystem);

      // 1NT -> 3C resolves to 1NT Puppet Stayman
      final state1NT3C = engine.graph.getState(['1nt', '3c']);
      expect(state1NT3C, isNotNull);
      final calls1NT3C = state1NT3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls1NT3C, containsAll(['3d', '3h', '3s', '3nt']));

      // 2NT -> 3C resolves to 2NT Puppet Stayman
      final state2NT3C = engine.graph.getState(['2nt', '3c']);
      expect(state2NT3C, isNotNull);
      final calls2NT3C = state2NT3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2NT3C, containsAll(['3d', '3h', '3s', '3nt']));
    });

    test('Phase 1 & 2 Engine Composition: step#1..4, include:, vars:, and deduplicated conventions', () async {
      final gavinSystem = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(gavinSystem);

      // 1. Spiral Raises via step#1..step#4 over 1C - 1H - 2H
      final state1C1H2H = engine.graph.getState(['1c', '1h', '2h']);
      expect(state1C1H2H, isNotNull);
      final callsOver2H = state1C1H2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOver2H, contains('2s'), reason: 'step#1 over 2H resolves to 2S Spiral Ask');

      final stateSpiralH = engine.graph.getState(['1c', '1h', '2h', '2s']);
      expect(stateSpiralH, isNotNull);
      final spiralHResponses = stateSpiralH!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(spiralHResponses, containsAll(['2nt', '3c', '3d', '3h']),
          reason: 'step#1..4 over 2S resolves to 2NT, 3C, 3D, 3H');

      // 2. Spiral Raises via step#1..step#4 over 1C - 1S - 2S
      final state1C1S2S = engine.graph.getState(['1c', '1s', '2s']);
      expect(state1C1S2S, isNotNull);
      final callsOver2S = state1C1S2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOver2S, contains('2nt'), reason: 'step#1 over 2S resolves to 2NT Spiral Ask');

      final stateSpiralS = engine.graph.getState(['1c', '1s', '2s', '2nt']);
      expect(stateSpiralS, isNotNull);
      final spiralSResponses = stateSpiralS!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(spiralSResponses, containsAll(['3c', '3d', '3h', '3s']),
          reason: 'step#1..4 over 2NT resolves to 3C, 3D, 3H, 3S');

      // 3. Support Doubles via include: "fSupportDoubles" in Walsh Minors
      final stateSupportDbl = engine.graph.getState(['1c', '1h', '(1s)']);
      expect(stateSupportDbl, isNotNull, reason: 'include: fSupportDoubles merges competitive (1s) branch');
      final supportCalls = stateSupportDbl!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(supportCalls, containsAll(['dbl', '2h', 'pass']));

      // 4. Namyats 4C & 4D via vars: and step#1
      final state4C = engine.graph.getState(['4c']);
      expect(state4C, isNotNull);
      final callsOver4C = state4C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOver4C, containsAll(['4d', '4h', '4nt']),
          reason: r'Namyats 4C resolves step#1 to 4D and 4$M to 4H');

      final state4D = engine.graph.getState(['4d']);
      expect(state4D, isNotNull);
      final callsOver4D = state4D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(callsOver4D, containsAll(['4h', '4s', '4nt']),
          reason: r'Namyats 4D resolves step#1 to 4H and 4$M to 4S');

      // 5. Kickback & RKCB 1430 via step#1..step#4 and vars: { trump: ... }
      final state4C4NT = engine.graph.getState(['4c', '4nt']);
      expect(state4C4NT, isNotNull);
      final rkcbOver4NT = state4C4NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(rkcbOver4NT, containsAll(['5c', '5d', '5h', '5s']),
          reason: 'RKCB 4NT resolves step#1..4 to 5C, 5D, 5H, 5S');

      // Test Kickback fragments directly
      final kickbackFile = File('assets/libraries/conventions/serious_3nt_and_kickback.yaml');
      final rkcbFile = File('assets/libraries/conventions/rkcb_1430.yaml');
      final combinedYaml = '''
name: "Kickback Test"
imports:
  - "assets/libraries/conventions/rkcb_1430.yaml"
  - "assets/libraries/conventions/serious_3nt_and_kickback.yaml"
openings:
  "4s":
    ref: "fKickbackHearts"
  "4h":
    ref: "fKickbackDiamonds"
  "4d":
    ref: "fKickbackClubs"
''';
      final kbSystem = await SystemLibraryResolver.loadSystemWithLibraries(
        combinedYaml,
        fileLoader: (path) async {
          if (path.endsWith('rkcb_1430.yaml')) return await rkcbFile.readAsString();
          if (path.endsWith('serious_3nt_and_kickback.yaml')) return await kickbackFile.readAsString();
          return '';
        },
      );
      final kbEngine = AuctionEngine.fromSystem(kbSystem);

      final kbHearts = kbEngine.graph.getState(['4s'])!;
      expect(kbHearts.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet(),
          containsAll(['4nt', '5c', '5d', '5h']),
          reason: '4S Kickback for Hearts resolves step#1..4 to 4NT, 5C, 5D, 5H');

      final kbDiamonds = kbEngine.graph.getState(['4h'])!;
      expect(kbDiamonds.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet(),
          containsAll(['4s', '4nt', '5c', '5d']),
          reason: '4H Kickback for Diamonds resolves step#1..4 to 4S, 4NT, 5C, 5D');

      final kbClubs = kbEngine.graph.getState(['4d'])!;
      expect(kbClubs.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet(),
          containsAll(['4h', '4s', '4nt', '5c']),
          reason: '4D Kickback for Clubs resolves step#1..4 to 4H, 4S, 4NT, 5C');
    });

    test('Texas Transfers [4d-4h] and Gerber 4C expand and resolve after 1NT', () async {
      final gavinSystem = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(gavinSystem);

      final state1NT = engine.graph.getState(['1nt'])!;
      final calls = state1NT.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      // Texas Transfers 4D and 4H
      expect(calls, contains('4d'), reason: 'Texas Transfer 4D should be available over 1NT');
      expect(calls, contains('4h'), reason: 'Texas Transfer 4H should be available over 1NT');

      // Gerber 4C
      expect(calls, contains('4c'), reason: 'Gerber 4C should be available over 1NT');

      // Verify 1NT - 4D forces opener acceptance in 4H
      final state4D = engine.graph.getState(['1nt', '4d']);
      expect(state4D, isNotNull);
      final oppAccept4D = state4D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(oppAccept4D, contains('4h'), reason: 'Opener accepts Texas Transfer 4D by bidding 4H');

      // Verify 1NT - 4H forces opener acceptance in 4S
      final state4H = engine.graph.getState(['1nt', '4h']);
      expect(state4H, isNotNull);
      final oppAccept4H = state4H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(oppAccept4H, contains('4s'), reason: 'Opener accepts Texas Transfer 4H by bidding 4S');

      // Verify 1NT - 4C (Gerber) provides 4D, 4H, 4S, 4NT step responses
      final state4C = engine.graph.getState(['1nt', '4c']);
      expect(state4C, isNotNull);
      final gerberSteps = state4C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(gerberSteps, containsAll(['4d', '4h', '4s', '4nt']), reason: 'Gerber 4C provides 4D/4H/4S/4NT Ace responses');

      // Verify Major Shortness compound slam tries [3h-3s]
      expect(calls, contains('3h'), reason: 'Major shortness 3H should be available over 1NT');
      expect(calls, contains('3s'), reason: 'Major shortness 3S should be available over 1NT');
    });
  });
}
