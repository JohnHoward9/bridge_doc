import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  test('Regression 20261029_184615: North with 14 HCP balanced rebids 1NT after 1C - 1D', () async {
    final yaml = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(yaml);
    final engine = AuctionEngine.fromSystem(system);

    // North: ♠Q832 ♥AQJ3 ♦A3 ♣J63 (14 HCP balanced, 4423)
    final northHand = Hand.fromString('Q832.AQJ3.A3.J63');
    expect(northHand.hcp, equals(14));
    expect(northHand.isBalanced, isTrue);

    final state1C1D = engine.graph.getState(['1c', '1d']);
    expect(state1C1D, isNotNull);

    final candidates = state1C1D!.evaluateCandidates(northHand, engine.botResolver);
    final match1NT = candidates.firstWhere((c) => c.displayCall.toLowerCase() == '1nt');
    expect(match1NT.isMatch, isTrue, reason: '1NT must match for 14 HCP balanced');

    final bestBid = state1C1D.resolveBestBid(northHand, engine.botResolver);
    expect(bestBid?.displayCall.toLowerCase(), equals('1nt'), reason: 'Opener must rebid 1NT, not pass');
  });
}
