import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one_nt_responses.yaml compiles and provides all Stayman and Jacoby transfer continuations', () async {
    final file = File('assets/core/systems/us_standard_2over1.yaml');
    final yamlStr = await file.readAsString();

    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );

    final compiler = BiddingGraphCompiler(system: system);
    final graph = compiler.compile();

    // 1. Root 1NT state has Stayman and Transfers
    final state1NT = graph.getState(['1nt'])!;
    final calls1NT = state1NT.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(calls1NT, contains('pass'));
    expect(calls1NT, contains('2c'));
    expect(calls1NT, contains('2d'));
    expect(calls1NT, contains('2h'));
    expect(calls1NT, contains('2s'));
    expect(calls1NT, contains('2nt'));
    expect(calls1NT, contains('3c'));
    expect(calls1NT, contains('3d'));
    expect(calls1NT, contains('3nt'));

    // 2. Stayman -> 2D (no major)
    final state2D = graph.getState(['1nt', '2c', '2d'])!;
    final callsOver2D = state2D.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsOver2D, contains('2nt'));
    expect(callsOver2D, contains('3h'));
    expect(callsOver2D, contains('3s'));
    expect(callsOver2D, contains('3nt'));

    // 3. Stayman -> 2H (Hearts)
    final stateStayman2H = graph.getState(['1nt', '2c', '2h'])!;
    final callsStayman2H = stateStayman2H.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsStayman2H, contains('2nt'));
    expect(callsStayman2H, contains('3h'));
    expect(callsStayman2H, contains('3nt'));
    expect(callsStayman2H, contains('4h'));

    // Opener responses to 3H raise
    final stateStayman2H3H = graph.getState(['1nt', '2c', '2h', '3h'])!;
    final callsStayman2H3H = stateStayman2H3H.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsStayman2H3H, contains('pass'));
    expect(callsStayman2H3H, contains('4h'));

    // 4. Stayman -> 2S (Spades)
    final stateStayman2S = graph.getState(['1nt', '2c', '2s'])!;
    final callsStayman2S = stateStayman2S.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsStayman2S, contains('2nt'));
    expect(callsStayman2S, contains('3s'));
    expect(callsStayman2S, contains('3nt'));
    expect(callsStayman2S, contains('4s'));

    // Opener responses to 3S raise
    final stateStayman2S3S = graph.getState(['1nt', '2c', '2s', '3s'])!;
    final callsStayman2S3S = stateStayman2S3S.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsStayman2S3S, contains('pass'));
    expect(callsStayman2S3S, contains('4s'));

    // 5. Jacoby Transfer to Hearts (1NT -> 2D -> 2H)
    final stateJacoby2H = graph.getState(['1nt', '2d', '2h'])!;
    final callsJacoby2H = stateJacoby2H.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsJacoby2H, contains('pass'));
    expect(callsJacoby2H, contains('2nt'));
    expect(callsJacoby2H, contains('3h'));
    expect(callsJacoby2H, contains('3nt'));
    expect(callsJacoby2H, contains('4h'));

    // Opener responses after 1NT -> 2D -> 2H -> 2NT
    final stateJacoby2H2NT = graph.getState(['1nt', '2d', '2h', '2nt'])!;
    final callsJacoby2H2NT = stateJacoby2H2NT.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsJacoby2H2NT, contains('pass'));
    expect(callsJacoby2H2NT, contains('3h'));
    expect(callsJacoby2H2NT, contains('3nt'));
    expect(callsJacoby2H2NT, contains('4h'));

    // 6. Jacoby Transfer to Spades (1NT -> 2H -> 2S)
    final stateJacoby2S = graph.getState(['1nt', '2h', '2s'])!;
    final callsJacoby2S = stateJacoby2S.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsJacoby2S, contains('pass'));
    expect(callsJacoby2S, contains('2nt'));
    expect(callsJacoby2S, contains('3s'));
    expect(callsJacoby2S, contains('3nt'));
    expect(callsJacoby2S, contains('4s'));

    // Opener responses after 1NT -> 2H -> 2S -> 2NT
    final stateJacoby2S2NT = graph.getState(['1nt', '2h', '2s', '2nt'])!;
    final callsJacoby2S2NT = stateJacoby2S2NT.candidateNodes.map((c) => c.displayCall.toLowerCase()).toSet();
    expect(callsJacoby2S2NT, contains('pass'));
    expect(callsJacoby2S2NT, contains('3s'));
    expect(callsJacoby2S2NT, contains('3nt'));
    expect(callsJacoby2S2NT, contains('4s'));
  });

  test('5-4 in majors with GF (10+ HCP) bids 2C Stayman for Smolen (user screenshot hand)', () async {
    final file = File('assets/core/systems/us_standard_2over1.yaml');
    final yamlStr = await file.readAsString();

    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );

    final engine = AuctionEngine.fromSystem(system);

    // North from user screenshot: KQJ9:53:AT8:AJ54 (15 HCP balanced)
    final north = Hand.fromString('KQJ9:53:AT8:AJ54');
    // South from user screenshot: A653:A9742:Q5:62 (10 HCP, 4s, 5h)
    final south = Hand.fromString('A653:A9742:Q5:62');

    final deal = PartnershipDeal(
      north: north,
      east: Hand.fromString('72:K86:KJ94:T873'),
      south: south,
      west: Hand.fromString('T84:QJT:7632:K95'),
    );

    final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
    expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

    final state1NT = engine.graph.getState(['1nt'])!;
    final bestBid = state1NT.resolveBestBid(south, engine.resolver, fragments: engine.graph.system.fragments);
    expect(bestBid, isNotNull);
    expect(bestBid!.displayCall.toLowerCase(), equals('2c'), reason: 'With 5-4 majors and 10+ HCP, responder must bid 2C Stayman for Smolen');

    // 2. South bids 2c
    final step2C = engine.advanceAuction(
      history: startStep.updatedHistory,
      userCall: '2c',
      deal: deal,
    );
    expect(step2C.isUserBidCorrect, isTrue);

    // North rebids 2s (4 Spades)
    final northRebid = step2C.updatedHistory.firstWhere((e) => e.seat == 'N' && e.call.toLowerCase() != '1nt');
    expect(northRebid.call.toLowerCase(), equals('2s'), reason: 'North with 4 Spades shows 2S');

    // 3. South with 4 Spades raises to 4S game
    final step4S = engine.advanceAuction(
      history: step2C.updatedHistory,
      userCall: '4s',
      deal: deal,
    );
    expect(step4S.isUserBidCorrect, isTrue);
  });

  test('5-4 in majors with GF (10+ HCP): 1NT - 2C - 2D - 3S (Smolen) - 4H', () async {
    final file = File('assets/core/systems/us_standard_2over1.yaml');
    final yamlStr = await file.readAsString();

    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );

    final engine = AuctionEngine.fromSystem(system);

    // North has no 4-card major: 3-3-4-3 (16 HCP, 3 Hearts): K82:K63:AT84:AJ5
    final north = Hand.fromString('K82:K63:AT84:AJ5');
    // South has 4 Spades, 5 Hearts, 10 HCP: A653:A9742:Q5:62
    final south = Hand.fromString('A653:A9742:Q5:62');

    final deal = PartnershipDeal(
      north: north,
      east: Hand.fromString('72:J8:KJ92:T8732'),
      south: south,
      west: Hand.fromString('QT94:QT5:763:K94'),
    );

    final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
    expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

    // 1. South bids 2c
    final step2C = engine.advanceAuction(
      history: startStep.updatedHistory,
      userCall: '2c',
      deal: deal,
    );
    expect(step2C.isUserBidCorrect, isTrue);

    // North has no 4M, rebids 2d
    final northRebid2D = step2C.updatedHistory.firstWhere((e) => e.seat == 'N' && e.call.toLowerCase() != '1nt');
    expect(northRebid2D.call.toLowerCase(), equals('2d'));

    // 2. South bids 3S (Smolen: 5H, 4S)
    final step3S = engine.advanceAuction(
      history: step2C.updatedHistory,
      userCall: '3s',
      deal: deal,
    );
    expect(step3S.isUserBidCorrect, isTrue);

    // North with 3 Hearts accepts in 4H
    final northAccept = step3S.updatedHistory.lastWhere((e) => e.seat == 'N');
    expect(northAccept.call.toLowerCase(), equals('4h'));
  });
}
