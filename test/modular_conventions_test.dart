import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadSystem(String relativePath) async {
    final file = File(relativePath);
    final yamlStr = await file.readAsString();
    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
  }

  group('Modular Convention Deduplication Tests', () {
    test('Smolen and Stayman modules load and integrate cleanly into US Standard 2/1', () async {
      final system = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      expect(system.fragments.containsKey('fSmolen'), isTrue, reason: 'fSmolen loaded from smolen.yaml');
      expect(system.fragments.containsKey('fStayman'), isTrue, reason: 'fStayman loaded from stayman.yaml');
      expect(system.fragments.containsKey('fJacobyTransferAcceptance'), isTrue, reason: 'fJacobyTransferAcceptance loaded from jacoby_transfers.yaml');

      final engine = AuctionEngine.fromSystem(system);

      // Verify 1NT:2C:2D has Smolen 3H and 3S
      final state2D = engine.graph.getState(['1nt', '2c', '2d']);
      expect(state2D, isNotNull);
      final calls = state2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('3h'), reason: 'Smolen 3H available');
      expect(calls, contains('3s'), reason: 'Smolen 3S available');
    });

    test('Smolen and Stayman modules integrate cleanly into Gavin Wolpert 2/1', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      expect(system.fragments.containsKey('fSmolen'), isTrue);
      expect(system.fragments.containsKey('fStayman'), isTrue);
      expect(system.fragments.containsKey('fJacobyTransferAcceptance'), isTrue);

      final engine = AuctionEngine.fromSystem(system);

      // Verify Gavin Wolpert system resolves Smolen after 1NT:2C:2D
      final state2D = engine.graph.getState(['1nt', '2c', '2d']);
      expect(state2D, isNotNull);
      final calls = state2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls, contains('3h'));
      expect(calls, contains('3s'));


      // Test full auction with Gavin Wolpert engine:
      // South has 4 Spades, 5 Hearts, 10 HCP GF: A653:A9742:Q5:62
      final north = Hand.fromString('K82:K63:AT84:AJ5'); // 16 HCP, 3 Hearts, 3 Spades
      final south = Hand.fromString('A653:A9742:Q5:62');

      final deal = PartnershipDeal(
        north: north,
        east: Hand.fromString('72:J8:KJ92:T8732'),
        south: south,
        west: Hand.fromString('QT94:QT5:763:K94'),
      );

      final startStep = engine.startDeal(deal: deal, isNorthFirst: true);
      expect(startStep.updatedHistory.first.call.toLowerCase(), equals('1nt'));

      // 1. South bids 2c Stayman
      final step2C = engine.advanceAuction(
        history: startStep.updatedHistory,
        userCall: '2c',
        deal: deal,
      );
      expect(step2C.isUserBidCorrect, isTrue);

      // North rebids 2d (no 4-card major)
      final north2D = step2C.updatedHistory.firstWhere((e) => e.seat == 'N' && e.call.toLowerCase() != '1nt');
      expect(north2D.call.toLowerCase(), equals('2d'));

      // 2. South bids 3S (Smolen with 5 Hearts, 4 Spades)
      final step3S = engine.advanceAuction(
        history: step2C.updatedHistory,
        userCall: '3s',
        deal: deal,
      );
      expect(step3S.isUserBidCorrect, isTrue, reason: 'Gavin Wolpert system recognizes Smolen 3S rebid');

      // North accepts in 4H
      final north4H = step3S.updatedHistory.lastWhere((e) => e.seat == 'N');
      expect(north4H.call.toLowerCase(), equals('4h'));
    });

    test('Reversed Bart convention resolves across Gavin Wolpert and US Standard 2/1 systems', () async {
      final gavinSystem = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final gavinEngine = AuctionEngine.fromSystem(gavinSystem);

      // 1. Check 1S -> 1NT -> 2C candidates under Gavin 2/1
      final state1S1NT2C = gavinEngine.graph.getState(['1s', '1nt', '2c']);
      expect(state1S1NT2C, isNotNull, reason: '1S -> 1NT -> 2C state exists');
      final bartCalls = state1S1NT2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(bartCalls, containsAll(['pass', '2d', '2h', '2s', '2nt']));

      // 2. Check 2H relay forces opener to 2S
      final state2HRelay = gavinEngine.graph.getState(['1s', '1nt', '2c', '2h']);
      expect(state2HRelay, isNotNull);
      final opener2SRebid = state2HRelay!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(opener2SRebid, contains('2s'), reason: 'Opener forced to 2S over 2H relay');

      // 3. Check responder continuations over 2S
      final stateOver2S = gavinEngine.graph.getState(['1s', '1nt', '2c', '2h', '2s']);
      expect(stateOver2S, isNotNull);
      final respCont = stateOver2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCont, containsAll(['pass', '2nt', '3c', '3s']));

      // 4. Verify 1H -> 1NT -> 2C has natural responses without 2S relay
      final state1H1NT2C = gavinEngine.graph.getState(['1h', '1nt', '2c']);
      expect(state1H1NT2C, isNotNull);
      final heartCont = state1H1NT2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(heartCont, containsAll(['pass', '2d', '2h', '2s', '2nt', '3c', '3h']));
      expect(heartCont, isNot(contains('3s')), reason: 'No spade splinter or jump over 1H-1NT-2C');

      // 5. Verify US Standard 2/1 also resolves Reversed Bart via five_card_majors_2over1.yaml
      final usSystem = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      final usEngine = AuctionEngine.fromSystem(usSystem);
      final usState1S1NT2C = usEngine.graph.getState(['1s', '1nt', '2c']);
      expect(usState1S1NT2C, isNotNull);
      final usBartCalls = usState1S1NT2C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(usBartCalls, containsAll(['pass', '2d', '2h', '2s', '2nt']));
    });
  });
}
