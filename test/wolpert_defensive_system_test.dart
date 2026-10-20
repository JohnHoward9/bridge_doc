import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BridgeSystem system;
  late AuctionEngine engine;

  setUpAll(() async {
    final yamlString = await rootBundle.loadString('assets/core/systems/gavin_wolpert_2over1.yaml');
    system = await SystemLibraryResolver.loadSystemWithLibraries(yamlString);
    engine = AuctionEngine.fromSystem(system);
  });

  group('Wolpert Defensive System Tests', () {
    test('System compiles with all defensive convention modules loaded', () {
      expect(system.name, contains('Gavin Wolpert'));
      expect(system.oppositionOpeningBids, isNotEmpty);
      expect(engine.graph.getState(['(1c)']), isNotNull);
      expect(engine.graph.getState(['(1d)']), isNotNull);
      expect(engine.graph.getState(['(1h)']), isNotNull);
      expect(engine.graph.getState(['(1s)']), isNotNull);
      expect(engine.graph.getState(['(2d_multi)']), isNotNull);
      expect(engine.graph.getState(['(2d_ekren)']), isNotNull);
      expect(engine.graph.getState(['(1c_strong)']), isNotNull);
      expect(engine.graph.getState(['(2c_majors)']), isNotNull);
    });

    test('Simple Overcall: 1S over opponent 1H opening (8-16 HCP, 5+ Spades)', () {
      final overcallHand = Hand.fromString('KQJT4:A2:987:654'); // 11 HCP, 5 Spades
      final state = engine.graph.getState(['(1h)'])!;
      final best = state.resolveBestBid(overcallHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('1s'));
    });

    test('Simple Overcall: 2C over opponent 1H opening (10-16 HCP, 5+ Clubs)', () {
      final clubHand = Hand.fromString('A3:42:K54:KQJT4'); // 12 HCP, 5 Clubs
      final state = engine.graph.getState(['(1h)'])!;
      final best = state.resolveBestBid(clubHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('2c'));
    });

    test('Takeout Double: X over opponent 1H opening (12+ HCP, short hearts, 3+ unbid)', () {
      final dblHand = Hand.fromString('KQJ4:2:AJ43:K765'); // 14 HCP, singleton heart, 4-4-4 in other suits
      final state = engine.graph.getState(['(1h)'])!;
      final best = state.resolveBestBid(dblHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('1NT Overcall: 1NT over opponent 1H opening (15-18 HCP balanced with stopper)', () {
      final ntHand = Hand.fromString('KQ4:AJ2:KQ3:J654'); // 16 HCP, balanced, heart stopper
      final state = engine.graph.getState(['(1h)'])!;
      final best = state.resolveBestBid(ntHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('1nt'));
    });

    test('Unusual 2NT: 2NT over opponent 1H opening (5-5 Minors, 6-11 or 16+ HCP)', () {
      final unusualHand = Hand.fromString('2:43:KJT54:QJT54'); // 8 HCP, 5-5 minors (in 6-11 HCP range)
      final state = engine.graph.getState(['(1h)'])!;
      final best = state.resolveBestBid(unusualHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('2nt'));
    });

    test('Michaels Cuebid: 2C over opponent 1C opening (5-5 Majors, 6-11 or 16+ HCP)', () {
      final michaelsHand = Hand.fromString('KJT54:KJT54:2:43'); // 8 HCP, 5-5 majors (in 6-11 HCP range)
      final state = engine.graph.getState(['(1c)'])!;
      final best = state.resolveBestBid(michaelsHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('2c'));
    });

    test('Multi 2D Defense: 2S overcall over Multi 2D (11-16 HCP, 5+ Spades, unbalanced)', () {
      final multiDefHand = Hand.fromString('AQJT4:3:8765:KJ5'); // 13 HCP, 5 Spades, singleton heart (unbalanced)
      final state = engine.graph.getState(['(2d_multi)'])!;
      final best = state.resolveBestBid(multiDefHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('2s'));
    });

    test('Multi 2D Defense: 2NT overcall over Multi 2D (16-18 HCP balanced with major stoppers)', () {
      final multiNtHand = Hand.fromString('KQ4:AQ2:KJ3:Q654'); // 17 HCP, balanced, both major stoppers
      final state = engine.graph.getState(['(2d_multi)'])!;
      final best = state.resolveBestBid(multiNtHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('2nt'));
    });

    test('Ekren 2D Defense: X over Ekren 2D (13+ HCP values/takeout, unbalanced)', () {
      final ekrenHand = Hand.fromString('AQ4:3:AQJ4:J8654'); // 14 HCP values, singleton heart (unbalanced)
      final state = engine.graph.getState(['(2d_ekren)'])!;
      final best = state.resolveBestBid(ekrenHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('Strong 1C Defense: Mathe Double showing both Majors (8-15 HCP, 4+ Hearts and 4+ Spades)', () {
      final strongClubHand = Hand.fromString('KJ54:QJ54:K3:654'); // 10 HCP, 4-4 majors
      final state = engine.graph.getState(['(1c_strong)'])!;
      final best = state.resolveBestBid(strongClubHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('Strong 1C Defense: Mathe 1NT showing both Minors (8-15 HCP, 5+ Clubs and 5+ Diamonds)', () {
      final strongClubMinors = Hand.fromString('2:43:KQJT4:AQJT4'); // 11 HCP, 5-5 minors
      final state = engine.graph.getState(['(1c_strong)'])!;
      final best = state.resolveBestBid(strongClubMinors, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('1nt'));
    });

    test('2C Both Majors Defense: Natural 2D overcall (11-16 HCP, 5+ Diamonds)', () {
      final twoClubDefHand = Hand.fromString('A3:42:AKJT4:7654'); // 12 HCP, 5 Diamonds
      final state = engine.graph.getState(['(2c_majors)'])!;
      final best = state.resolveBestBid(twoClubDefHand, engine.resolver, fragments: system.fragments);

      expect(best, isNotNull);
      expect(best!.displayCall.toLowerCase(), equals('2d'));
    });
  });
}
