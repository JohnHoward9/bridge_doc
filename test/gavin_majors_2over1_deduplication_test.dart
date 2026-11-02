import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  late AuctionEngine engine;

  setUpAll(() async {
    final yaml = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(yaml);
    engine = AuctionEngine.fromSystem(system);
  });

  group('Gavin 1H / 1S Deduplication & 2/1 GF Threshold Tests', () {
    test('1H and 1S candidate responses are expanded properly from Gavin1H1SOpening', () {
      final state1H = engine.graph.getState(['1h'])!;
      final calls1H = state1H.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls1H, containsAll(['pass', '1s', '1nt', '2c', '2d', '2h', '2nt', '3d', '3h', '3s', '4c', '4d', '4h']));
      expect(calls1H, isNot(contains('2s'))); // 2S is not a natural 2/1 response over 1H

      final state1S = engine.graph.getState(['1s'])!;
      final calls1S = state1S.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls1S, containsAll(['pass', '1nt', '2c', '2d', '2h', '2s', '2nt', '3d', '3s', '4c', '4d', '4h', '4s']));
      expect(calls1S, isNot(contains('1s')));
    });

    test('Unpassed Hand 2/1 responses require 12+ HCP and force to game', () {
      final state1H = engine.graph.getState(['1h'])!;
      final node2C = state1H.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2c');
      final node2D = state1H.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2d');
      expect(node2C.rule, contains('12+hcp'));
      expect(node2C.forceTo, equals(ForcingLevel.game));
      expect(node2D.rule, contains('12+hcp'));
      expect(node2D.forceTo, equals(ForcingLevel.game));

      final state1S = engine.graph.getState(['1s'])!;
      final node2H = state1S.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2h');
      expect(node2H.rule, contains('12+hcp'));
      expect(node2H.forceTo, equals(ForcingLevel.game));
    });

    test('Unpassed hand with 10-11 HCP cannot bid 2/1 GF, must bid 1NT Semi-Forcing', () {
      final state1H = engine.graph.getState(['1h'])!;
      // 10 HCP hand with 5 clubs: ♠84 ♥63 ♦QJ5 ♣AK862 (Q=2, J=1, A=4, K=3 -> 10 HCP)
      final hand10HCP = Hand.fromString('84.63.QJ5.AK862');
      expect(hand10HCP.hcp, equals(10));

      final evals = state1H.evaluateCandidates(hand10HCP, engine.botResolver);
      final match2C = evals.firstWhere((c) => c.call.toLowerCase() == '2c');
      final match1NT = evals.firstWhere((c) => c.call.toLowerCase() == '1nt');

      expect(match2C.isMatch, isFalse, reason: '10 HCP cannot bid 2C 2/1 GF (needs 12+)');
      expect(match1NT.isMatch, isTrue, reason: '10 HCP with 2 hearts bids 1NT Semi-Forcing');
    });

    test('Unpassed hand with 12+ HCP bids 2/1 GF', () {
      final state1H = engine.graph.getState(['1h'])!;
      // 12 HCP hand with 5 clubs: ♠84 ♥63 ♦AJ5 ♣AK862 (A=4, J=1, A=4, K=3 -> 12 HCP)
      final hand12HCP = Hand.fromString('84.63.AJ5.AK862');
      expect(hand12HCP.hcp, equals(12));

      final evals = state1H.evaluateCandidates(hand12HCP, engine.botResolver);
      final match2C = evals.firstWhere((c) => c.call.toLowerCase() == '2c');
      expect(match2C.isMatch, isTrue, reason: '12 HCP with 5 clubs bids 2C 2/1 GF');
    });

    test('Passed hand routes to Drury (2C) and natural 9-10 HCP bids (2D/2H)', () {
      // Auction: Pass - Pass - 1H (Responder is a passed hand in seat 1 or 2)
      final statePass1H = engine.graph.getState(['pass', '1h'])!;
      final callsPass1H = statePass1H.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(callsPass1H, containsAll(['pass', '2c', '2d', '2h', '1nt', '3h', '4h']));

      final node2C = statePass1H.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2c');
      expect(node2C.desc, contains('Reverse Drury'));
      expect(node2C.rule, contains('9+hcp'));

      final node2D = statePass1H.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2d');
      expect(node2D.desc, contains('Natural Diamonds'));
      expect(node2D.rule, contains('9-10hcp'));

      final statePass1S = engine.graph.getState(['pass', '1s'])!;
      final node2H = statePass1S.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '2h');
      expect(node2H.desc, contains('Natural Hearts'));
      expect(node2H.rule, contains('9-10hcp'));
    });
  });
}
