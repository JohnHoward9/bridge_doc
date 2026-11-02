import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/hand_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BridgeSystem system;
  late AuctionEngine engine;

  setUpAll(() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    final yamlStr = await file.readAsString();
    system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
    engine = AuctionEngine.fromSystem(system);
  });

  group('Gavin Wolpert 1NT Minor Transfers & Shortness Rebids', () {
    test('1NT - 2NT (transfer to Diamonds) - 3D - 3H shows Heart shortness with 6+ Diamonds (qjx:x:a98765:KTx)', () {
      // ♠QJ2 ♥2 ♦A98765 ♣KT3 (10 HCP, 3-1-6-3)
      final responderHand = HandParser.parseSingleHand('QJ2.2.A98765.KT3');
      expect(responderHand.hcp, equals(10));
      expect(responderHand.diamondsLength, equals(6));
      expect(responderHand.heartsLength, equals(1));

      // 1. Over 1NT: responder bids 2NT (Transfer to Diamonds)
      final state1NT = engine.graph.getState(['1nt'])!;
      final candidate2NT = state1NT.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '2nt',
      );
      expect(candidate2NT, isNotNull);

      // 2. Over 3D: responder rebids 3H (Heart Shortness)
      final state3D = engine.graph.getState(['1nt', '2nt', '3d'])!;
      final candidateCalls = state3D.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(candidateCalls, contains('3h'));
      expect(candidateCalls, contains('3s'));
      expect(candidateCalls, contains('3nt'));
      expect(candidateCalls, contains('4c'));

      final candidate3H = state3D.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '3h',
      );
      expect(candidate3H.desc, contains('Heart shortness'));

      // Verify continuations after 3H: 3S, 3NT, 4C, 4D, 5D
      final state3H = engine.graph.getState(['1nt', '2nt', '3d', '3h'])!;
      final openerCalls = state3H.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerCalls, contains('3s'));
      expect(openerCalls, contains('3nt'));
      expect(openerCalls, contains('4c'));
      expect(openerCalls, contains('4d'));
      expect(openerCalls, contains('5d'));
    });

    test('1NT - 2NT - 3D - 4C shows Club shortness with 6+ Diamonds (qjx:ktx:a98765:2)', () {
      // ♠QJ3 ♥KT4 ♦A98765 ♣2 (10 HCP, 3-3-6-1)
      final responderHand = HandParser.parseSingleHand('QJ3.KT4.A98765.2');
      expect(responderHand.hcp, equals(10));
      expect(responderHand.diamondsLength, equals(6));
      expect(responderHand.clubsLength, equals(1));

      final state3D = engine.graph.getState(['1nt', '2nt', '3d'])!;
      final candidate4C = state3D.candidateNodes.firstWhere(
        (n) => n.displayCall.toLowerCase() == '4c',
      );
      expect(candidate4C.desc, contains('Club shortness'));

      // Verify continuations after 4C: 4D, 4H, 4S, 5D
      final state4C = engine.graph.getState(['1nt', '2nt', '3d', '4c'])!;
      final openerCalls = state4C.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(openerCalls, contains('4d'));
      expect(openerCalls, contains('4h'));
      expect(openerCalls, contains('4s'));
      expect(openerCalls, contains('5d'));
    });

    test('1NT - 2S (Range Ask or Clubs) allows shortness rebids over 2NT/3C', () {
      final state2NT = engine.graph.getState(['1nt', '2s', '2nt'])!;
      final calls2NT = state2NT.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2NT, contains('3d'));
      expect(calls2NT, contains('3h'));
      expect(calls2NT, contains('3s'));
      expect(calls2NT, contains('3nt'));

      final state3C = engine.graph.getState(['1nt', '2s', '3c'])!;
      final calls3C = state3C.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls3C, contains('3d'));
      expect(calls3C, contains('3h'));
      expect(calls3C, contains('3s'));
      expect(calls3C, contains('3nt'));
    });
  });
}
