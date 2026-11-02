import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  test('Diagnose 20261029_160859_should_open_2nt hand', () async {
    final yaml = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(yaml);
    final engine = AuctionEngine.fromSystem(system);
    final hand = Hand.fromString('AK7.QT4.KQJ3.AJ5');
    print('HCP: ${hand.hcp}, isBalanced: ${hand.isBalanced}, exact: ${hand.exactDistribution}');
    
    final candidates = engine.graph.rootState.evaluateCandidates(hand, engine.botResolver);
    for (final c in candidates) {
      print('Candidate: ${c.displayCall} match=${c.isMatch} rule=${c.rule} desc=${c.desc} score=${c.specificityScore}');
    }

    final bestBid = engine.graph.rootState.resolveBestBid(hand, engine.botResolver);
    expect(bestBid?.displayCall.toLowerCase(), '2nt');
  });
}
