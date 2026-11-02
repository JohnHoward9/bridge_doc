import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';

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
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
    engine = AuctionEngine.fromSystem(system);
  });

  test('1H - 3S Splinter preserves agreedSuit = h and Opener signs off in 4H', () {
    final graph = engine.graph;
    final resolver = engine.resolver;

    // North (Opener): ♠KQ3 ♥K87632 ♦T ♣KJ5 (12 HCP)
    final north = Hand.fromString('KQ3:K87632:T:KJ5');
    // South (Responder): ♠J ♥QJT5 ♦AK754 ♣Q97 (13 HCP)
    final south = Hand.fromString('J:QJT5:AK754:Q97');

    final b1 = graph.rootState.resolveBestBid(north, resolver, fragments: graph.system.fragments);
    expect(b1?.displayCall, equals('1h'));

    final s1 = graph.getState([b1!.displayCall]);
    expect(s1, isNotNull);

    final b2 = s1!.resolveBestBid(south, resolver, fragments: graph.system.fragments);
    expect(b2?.displayCall, equals('3s'), reason: 'South with singleton Spade and 4+ Hearts bids 3S Splinter');

    final s2 = graph.getState([b1.displayCall, b2!.displayCall]);
    expect(s2, isNotNull);
    expect(s2!.activeVariables['agreedSuit'], equals('h'), reason: 'Agreed suit must be Hearts');

    final b3 = s2.resolveBestBid(north, resolver, fragments: graph.system.fragments);
    expect(b3?.displayCall, equals('4h'), reason: 'North must sign off in 4H, NEVER 4S');
    expect(b3?.desc, contains('4h'));
  });

  test('RKCB Keycard determination correctly uses agreed suit King', () {
    // Hand holding: Ace of Spades, King of Spades, Ace of Clubs (no other aces or kings)
    final hand = Hand.fromString('AK54:876:954:A82');

    // In Spades agreement: K♠ is a keycard (3 keycards: A♠, K♠, A♣)
    expect(hand.keyCardCount(Suit.spades), equals(3));
    expect(hand.hasQueen(Suit.spades), isFalse);

    // In Hearts agreement: K♠ is NOT a keycard (only 2 keycards: A♠, A♣)
    expect(hand.keyCardCount(Suit.hearts), equals(2));
  });
}
