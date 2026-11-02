import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  test('Regression 20261030_174856: Opener with balanced hand rebids 1NT after 1m - 1H, not 1S', () async {
    final yaml = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(yaml);
    final engine = AuctionEngine.fromSystem(system);

    // North from error hand: A842.K3.9632.A52 (4432 balanced, 11 HCP, 2 Aces + 1 King)
    final northHand = Hand.fromString('A842.K3.9632.A52');
    expect(northHand.isBalanced, isTrue);

    // 1D - 1H: North must rebid 1NT (not 1S)
    final state1D1H = engine.graph.getState(['1d', '1h']);
    expect(state1D1H, isNotNull);

    final bestBid1D = state1D1H!.resolveBestBid(northHand, engine.botResolver);
    expect(bestBid1D?.displayCall.toLowerCase(), equals('1nt'),
        reason: 'Opener 4432 balanced must rebid 1NT over 1H after 1D opening');

    // 1C - 1H with balanced 4=2=3=4: must rebid 1NT (not 1S)
    final northBalancedClub = Hand.fromString('A842.K3.A52.9632');
    final state1C1H = engine.graph.getState(['1c', '1h']);
    expect(state1C1H, isNotNull);

    final bestBid1C = state1C1H!.resolveBestBid(northBalancedClub, engine.botResolver);
    expect(bestBid1C?.displayCall.toLowerCase(), equals('1nt'),
        reason: 'Opener balanced must rebid 1NT over 1H after 1C opening');

    // Unbalanced hand with 4 spades: 4=1=4=4 (13 HCP)
    final northUnbalanced = Hand.fromString('AK84.3.J642.A852');
    expect(northUnbalanced.isBalanced, isFalse);

    final bestBidUnbal1D = state1D1H.resolveBestBid(northUnbalanced, engine.botResolver);
    expect(bestBidUnbal1D?.displayCall.toLowerCase(), equals('1s'),
        reason: 'Opener unbalanced with 4+ Spades must rebid 1S over 1H');

    final bestBidUnbal1C = state1C1H.resolveBestBid(northUnbalanced, engine.botResolver);
    expect(bestBidUnbal1C?.displayCall.toLowerCase(), equals('1s'),
        reason: 'Opener unbalanced with 4+ Spades must rebid 1S over 1H');
  });
}
