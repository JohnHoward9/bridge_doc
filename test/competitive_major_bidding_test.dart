import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/hand_parser.dart';
import 'package:bridge_bidding_system/constraints/specificity_resolver.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';

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

  late BridgeSystem system;
  late CompiledBiddingGraph graph;
  late SpecificityResolver resolver;
  late AuctionEngine engine;

  setUpAll(() async {
    system = await loadGavinSystem();
    graph = BiddingGraphCompiler(system: system).compile();
    resolver = SpecificityResolver(valuation: MLHandValuation());
    engine = AuctionEngine(graph: graph, resolver: resolver);
  });

  group('Competitive Bidding Over 1S (User Hand & Negative Double vs 2H)', () {
    test("User's Hand: 1S - (2D) - South with 6 Hearts and 8 HCP bids 2H, not Double", () {
      final northHand = HandParser.parseSingleHand('AK8653.Q6.J97.K9'); // 13 HCP, 6 Spades, 2 Hearts
      final southHand = HandParser.parseSingleHand('74.KJT732.A6.543');   // 8 HCP, 6 Hearts, 2 Spades
      final eastHand  = HandParser.parseSingleHand('JT5.82.AQT83.A64');   // 11 HCP, 5 Diamonds
      final westHand  = HandParser.parseSingleHand('Q92.A54.542.JT82');

      final deal = PartnershipDeal(north: northHand, south: southHand, east: eastHand, west: westHand);

      // North opens 1S
      final openStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(openStep.updatedHistory.first.call.toLowerCase(), contains('1s'));

      // In competition: North bids 1S, East overcalls 2D
      final auctionHistory = [
        AuctionEntry(seat: 'N', call: '1♠'),
        AuctionEntry(seat: 'E', call: '2♦', desc: 'Interference 2D'),
      ];

      // South's turn: evaluate best bid for South
      final state1S2D = graph.getState(['1s', '(2d)']);
      expect(state1S2D, isNotNull, reason: 'State 1s:(2d) must exist in graph');

      final southBestBid = state1S2D!.resolveBestBid(
        southHand,
        resolver,
        fragments: graph.system.fragments,
      );

      expect(southBestBid, isNotNull);
      expect(
        southBestBid!.call.toLowerCase(),
        '2h',
        reason: 'South holding 6 Hearts and 8 HCP over 1S-(2D) must bid 2H, NOT Double!',
      );
      expect(southBestBid.desc, contains('5+ Hearts in competition'));

      // Advance auction with 2H
      final step2H = engine.advanceAuction(
        history: auctionHistory,
        userCall: '2h',
        deal: deal,
      );

      expect(step2H.isUserBidCorrect, isTrue);

      // Verify North's rebid over 2H: holding 6 Spades (AK8653), North rebids 2S
      final northBids = step2H.updatedHistory.where((e) => e.seat == 'N').toList();
      expect(northBids.length, greaterThanOrEqualTo(2));
      final northRebid = northBids.last;
      expect(
        northRebid.call.toLowerCase(),
        contains('2s'),
        reason: 'North with 6 Spades (AK8653) rebids 2S over competitive 2H',
      );
    });

    test('4 Hearts bids Negative Double (dbl), whereas 5+ Hearts bids 2H over 1S - (2D)', () {
      final hand4H = HandParser.parseSingleHand('74.KJT7.A62.5432');   // 8 HCP, 4 Hearts
      final hand5H = HandParser.parseSingleHand('74.KJT73.A6.5432');   // 8 HCP, 5 Hearts
      final hand6H = HandParser.parseSingleHand('74.KJT732.A6.543');   // 8 HCP, 6 Hearts

      final state1S2D = graph.getState(['1s', '(2d)'])!;

      final bid4H = state1S2D.resolveBestBid(hand4H, resolver, fragments: graph.system.fragments);
      expect(bid4H, isNotNull);
      expect(
        bid4H!.call.toLowerCase(),
        'dbl',
        reason: 'Responder with exactly 4 Hearts must make a Negative Double (dbl)',
      );

      final bid5H = state1S2D.resolveBestBid(hand5H, resolver, fragments: graph.system.fragments);
      expect(bid5H, isNotNull);
      expect(
        bid5H!.call.toLowerCase(),
        '2h',
        reason: 'Responder with 5 Hearts must bid 2H (natural 5+ Hearts in competition)',
      );

      final bid6H = state1S2D.resolveBestBid(hand6H, resolver, fragments: graph.system.fragments);
      expect(bid6H, isNotNull);
      expect(
        bid6H!.call.toLowerCase(),
        '2h',
        reason: 'Responder with 6 Hearts must bid 2H',
      );
    });

    test('1S - (2C): 4 Hearts bids dbl, 5+ Hearts bids 2H', () {
      final hand4H = HandParser.parseSingleHand('74.KJT7.A62.5432');   // 8 HCP, 4 Hearts
      final hand5H = HandParser.parseSingleHand('74.KJT73.A6.5432');   // 8 HCP, 5 Hearts

      final state1S2C = graph.getState(['1s', '(2c)'])!;

      final bid4H = state1S2C.resolveBestBid(hand4H, resolver, fragments: graph.system.fragments);
      expect(bid4H, isNotNull);
      expect(bid4H!.call.toLowerCase(), 'dbl');

      final bid5H = state1S2C.resolveBestBid(hand5H, resolver, fragments: graph.system.fragments);
      expect(bid5H, isNotNull);
      expect(bid5H!.call.toLowerCase(), '2h');
    });

    test('1S - (X) Takeout Double: Support Redouble (10+ HCP) and Jordan 2NT (4+ Spades 10+ HCP)', () {
      final state1SX = graph.getState(['1s', '(x)']);
      expect(state1SX, isNotNull);

      // Balanced 11 HCP, 2 Spades: Redouble
      final handRdbl = HandParser.parseSingleHand('74.KJ7.AQ62.Q543');
      final bidRdbl = state1SX!.resolveBestBid(handRdbl, resolver, fragments: graph.system.fragments);
      expect(bidRdbl, isNotNull);
      expect(bidRdbl!.call.toLowerCase(), 'rdbl');

      // 10 HCP, 4 Spades: Jordan 2NT
      final handJordan = HandParser.parseSingleHand('KJ74.K7.Q62.J543');
      final bidJordan = state1SX.resolveBestBid(handJordan, resolver, fragments: graph.system.fragments);
      expect(bidJordan, isNotNull);
      expect(bidJordan!.call.toLowerCase(), '2nt');
    });
  });

  group('Competitive Bidding Over 1H (Negative Double vs 2S)', () {
    test('1H - (2D): 4 Spades bids dbl, 5+ Spades bids 2S', () {
      final hand4S = HandParser.parseSingleHand('KJT7.74.A62.5432');   // 8 HCP, 4 Spades
      final hand5S = HandParser.parseSingleHand('KJT73.74.A6.5432');   // 8 HCP, 5 Spades

      final state1H2D = graph.getState(['1h', '(2d)'])!;

      final bid4S = state1H2D.resolveBestBid(hand4S, resolver, fragments: graph.system.fragments);
      expect(bid4S, isNotNull);
      expect(
        bid4S!.call.toLowerCase(),
        'dbl',
        reason: 'Responder with exactly 4 Spades over 1H-(2D) must make a Negative Double',
      );

      final bid5S = state1H2D.resolveBestBid(hand5S, resolver, fragments: graph.system.fragments);
      expect(bid5S, isNotNull);
      expect(
        bid5S!.call.toLowerCase(),
        '2s',
        reason: 'Responder with 5 Spades over 1H-(2D) must bid 2S (natural 5+ Spades in competition)',
      );
    });

    test('1H - (2C): 4 Spades bids dbl, 5+ Spades bids 2S', () {
      final hand4S = HandParser.parseSingleHand('KJT7.74.A62.5432');
      final hand5S = HandParser.parseSingleHand('KJT73.74.A6.5432');

      final state1H2C = graph.getState(['1h', '(2c)'])!;

      final bid4S = state1H2C.resolveBestBid(hand4S, resolver, fragments: graph.system.fragments);
      expect(bid4S, isNotNull);
      expect(bid4S!.call.toLowerCase(), 'dbl');

      final bid5S = state1H2C.resolveBestBid(hand5S, resolver, fragments: graph.system.fragments);
      expect(bid5S, isNotNull);
      expect(bid5S!.call.toLowerCase(), '2s');
    });

    test('1H - (X) Takeout Double: Support Redouble (10+ HCP) and Jordan 2NT (4+ Hearts 10+ HCP)', () {
      final state1HX = graph.getState(['1h', '(x)']);
      expect(state1HX, isNotNull);

      final handRdbl = HandParser.parseSingleHand('74.KJ7.AQ62.Q543');
      final bidRdbl = state1HX!.resolveBestBid(handRdbl, resolver, fragments: graph.system.fragments);
      expect(bidRdbl, isNotNull);
      expect(bidRdbl!.call.toLowerCase(), 'rdbl');

      final handJordan = HandParser.parseSingleHand('74.KJ74.Q62.AJ43');
      final bidJordan = state1HX.resolveBestBid(handJordan, resolver, fragments: graph.system.fragments);
      expect(bidJordan, isNotNull);
      expect(bidJordan!.call.toLowerCase(), '2nt');
    });
  });
}
