import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';

void main() {
  test('Regression 20261030_182239: Opener continuations after 1H - 1S forcing response', () async {
    final yaml = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(yaml);
    final engine = AuctionEngine.fromSystem(system);

    // 1. North from error hand: AK3.KQ853.6.A832 (16 HCP, 3=5=1=4)
    final northHand = Hand.fromString('AK3.KQ853.6.A832');
    expect(northHand.hcp, equals(16));

    final state1H1S = engine.graph.getState(['1h', '1s']);
    expect(state1H1S, isNotNull);

    final bestBid = state1H1S!.resolveBestBid(northHand, engine.botResolver);
    expect(bestBid?.displayCall.toLowerCase(), equals('2c'),
        reason: 'Opener with 16 HCP and 4 Clubs must rebid 2C over 1S, not pass');

    // 2. Next round continuation: South rebids 2S (5+ Spades, minimum 6-10)
    // North holding AK3 (3 Spades) and 16 HCP raises to 4S (game)
    final state1H1S2C2S = engine.graph.getState(['1h', '1s', '2c', '2s']);
    expect(state1H1S2C2S, isNotNull);
    final bestBidOver2S = state1H1S2C2S!.resolveBestBid(northHand, engine.botResolver);
    expect(bestBidOver2S?.displayCall.toLowerCase(), equals('4s'),
        reason: 'Opener with 16+ HCP and 3-card Spade support raises to 4S game');

    // 3. Opener with 16-18 HCP and Diamonds: 3=5=4=1
    final northDiamonds = Hand.fromString('AK3.KQ853.A832.6');
    final bestBidD = state1H1S.resolveBestBid(northDiamonds, engine.botResolver);
    expect(bestBidD?.displayCall.toLowerCase(), equals('2d'),
        reason: 'Opener with 16 HCP and 4 Diamonds rebids 2D over 1S');

    // 4. Opener with 16-18 HCP and 4-card Spade support: 4=5=1=3
    final northSpadeRaise = Hand.fromString('AK43.KQ853.6.A82');
    final bestBid3S = state1H1S.resolveBestBid(northSpadeRaise, engine.botResolver);
    expect(bestBid3S?.displayCall.toLowerCase(), equals('3s'),
        reason: 'Opener with 16 HCP and 4 Spades jump raises to 3S');

    // 5. Opener with 18-19 balanced: 18-19 HCP, 2 Spades, 5 Hearts
    final north1819 = Hand.fromString('K3.AQ853.KJ2.AJ3');
    final bestBid2NT = state1H1S.resolveBestBid(north1819, engine.botResolver);
    expect(bestBid2NT?.displayCall.toLowerCase(), equals('2nt'),
        reason: 'Opener with 18-19 balanced rebids 2NT over 1S');
  });
}
