import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuctionEngine engine;

  setUpAll(() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    if (!file.existsSync()) {
      throw Exception('System file not found');
    }
    final yamlStr = await file.readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
    engine = AuctionEngine.fromSystem(system);
  });

  group('Competitive Conventions: Michaels Cuebid & Defense', () {
    test('Overcall Michaels over 1m: 2C over (1C) shows 5-5 in majors', () {
      final hand = Hand.fromString('KJ942:QJ983:4:52'); // 5-5 majors, 9 HCP (weak range 6-11)
      final seq = ['(1c)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('2c'));
    });

    test('Overcall Michaels over 1M: 2S over (1S) shows 5-5 Hearts and minor', () {
      final hand = Hand.fromString('4:KQ985:4:KQ983'); // 5-5 Hearts and Clubs, 10 HCP (weak range 6-11)
      final seq = ['(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('2s'));
    });

    test('Advancer preference after Michaels: 2H with Heart preference', () {
      final hand = Hand.fromString('84:Q983:J842:752'); // 4 Hearts, 2 Spades, weak
      final seq = ['(1c)', '2c'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('2h'));
    });
  });

  group('Competitive Conventions: Unusual 2NT', () {
    test('Overcall Unusual 2NT over 1M: 2NT over (1S) shows 5-5 in minors', () {
      final hand = Hand.fromString('4:52:KQ983:AJ984'); // 5-5 minors, 12 HCP (or 6-11 / 16+)
      final seq = ['(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('2nt'));
    });

    test('Advancer preference after Unusual 2NT: 3C with Club preference', () {
      final hand = Hand.fromString('84:752:842:Q9832'); // 5 Clubs, weak
      final seq = ['(1s)', '2nt'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('3c'));
    });
  });

  group('Competitive Conventions: Leaping Michaels', () {
    test('Leaping Michaels over weak 2S: 4C shows 5+ Clubs and 5+ Hearts', () {
      final hand = Hand.fromString('4:AKJ85:4:AKJ832'); // 5H, 6C, 16 HCP
      final seq = ['(2s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('4c'));
    });

    test('Leaping Michaels over weak 2S cuebid: 4S shows 5-5 in both minors', () {
      final hand = Hand.fromString('4:4:AKJ85:AKJ832'); // 5D, 6C, 16 HCP
      final seq = ['(2s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('4s'));
    });

    test('Leaping Michaels over 3-level preempt 3S: 4C shows 5+ Clubs and 5+ Hearts', () {
      final hand = Hand.fromString('4:AKJ85:4:AKJ832'); // 5H, 6C, 16 HCP
      final seq = ['(3s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('4c'));
    });
  });

  group('Competitive Conventions: Takeout Doubles & Negative Doubles', () {
    test('Takeout Double over 1S opening: short Spades with support for unbid suits', () {
      final hand = Hand.fromString('4:KJ85:AJ83:KQ82'); // 14 HCP, singleton spade
      final seq = ['(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('Takeout Double over 3S preempt: 14+ HCP with shortness in Spades', () {
      final hand = Hand.fromString('4:AK85:KJ83:KQ82'); // 16 HCP, singleton spade
      final seq = ['(3s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('Negative Double by Responder after 1C - (1H): shows exactly 4 Spades', () {
      final hand = Hand.fromString('K852:84:AJ52:Q84'); // 4 Spades, 10 HCP
      final seq = ['1c', '(1h)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('Negative Double by Responder after 1H - (1S): shows minor length / balanced values without Heart fit', () {
      final hand = Hand.fromString('84:84:KJ52:AJ84'); // 10 HCP, 3-s, 2 Hearts, 4-4 minors
      final seq = ['1h', '(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('dbl'));
    });
  });

  group('Competitive Conventions: Support Doubles & Redoubles', () {
    test('Support Double over interference: 1C - 1H - (1S) - dbl shows exactly 3-card Heart support', () {
      final hand = Hand.fromString('84:KJ5:AQ82:K842'); // 14 HCP, 3 Hearts
      final seq = ['1c', '1h', '(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('Support Redouble over Takeout Double: 1C - 1H - (X) - rdbl shows exactly 3-card Heart support', () {
      final hand = Hand.fromString('84:KJ5:AQ82:K842'); // 14 HCP, 3 Hearts
      final seq = ['1c', '1h', '(x)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('rdbl'));
    });

    test('Support Double after 1H - 1S: 1H - 1S - (2C) - dbl shows exactly 3-card Spade support', () {
      final hand = Hand.fromString('KJ5:AK842:Q82:84'); // 14 HCP, 3 Spades, 5 Hearts
      final seq = ['1h', '1s', '(2c)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('dbl'));
    });
  });

  group('Competitive Conventions: Limit Raise Cuebids & LoTT', () {
    test('Responder Cuebid Limit Raise after 1H - (1S): 2S shows 10+ HCP with 3+ Heart support', () {
      final hand = Hand.fromString('84:AQ5:KQ82:8432'); // 11 HCP, 3 Hearts (10+ HCP)
      final seq = ['1h', '(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('2s'));
    });

    test('Responder LoTT simple raise after 1H - (1S): 2H shows 6-9 HCP with 3 Hearts', () {
      final hand = Hand.fromString('84:Q85:K842:J532'); // 7 HCP, 3 Hearts
      final seq = ['1h', '(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('2h'));
    });

    test('Responder LoTT preemptive jump raise after 1H - (1S): 3H shows 5-9 HCP with 4 Hearts', () {
      final hand = Hand.fromString('8:Q852:K842:8532'); // 6 HCP, 4 Hearts
      final seq = ['1h', '(1s)'];
      final state = engine.graph.getState(seq);
      expect(state, isNotNull);
      final bid = state!.resolveBestBid(hand, engine.resolver);
      expect(bid, isNotNull);
      expect(bid!.displayCall.toLowerCase(), equals('3h'));
    });
  });

  group('LTC (Losing Trick Count) Integrity', () {
    test('Calculates exact Losing Trick Count on textbook hands', () {
      // AKQ = 0, AKx = 1, Axx = 2, xxx = 3
      final hand1 = Hand.fromString('AKQ:AK:AK8:AK842'); // 0 + 0 + 1 + 1 = 2 LTC
      expect(hand1.losingTrickCount, equals(2));

      final hand2 = Hand.fromString('842:842:842:8432'); // 3 + 3 + 3 + 3 = 12 LTC
      expect(hand2.losingTrickCount, equals(12));

      final hand3 = Hand.fromString('AQ942:KJ8:Q84:52'); // 1 + 2 + 2 + 2 = 7 LTC
      expect(hand3.losingTrickCount, equals(7));
    });
  });
}
