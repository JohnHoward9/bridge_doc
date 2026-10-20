import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BridgeSystem system;
  late AuctionEngine engine;

  setUpAll(() async {
    const relativePath = 'assets/core/systems/gavin_wolpert_2over1.yaml';
    final file = File(relativePath);
    expect(file.existsSync(), isTrue);
    final yamlStr = await file.readAsString();

    system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) {
          return await f.readAsString();
        }
        return '';
      },
    );

    engine = AuctionEngine.fromSystem(system);
  });

  group('Gavin Wolpert Spiral Raises (1m - 1M - 2M)', () {
    test('1C -> 1H -> 2H -> 2S (Spiral Ask) branches correctly', () {
      final state = engine.graph.getState(['1c', '1h', '2h']);
      expect(state, isNotNull);

      // Verify candidates include pass, 2s (Spiral Ask), 3h (direct invite), 4h (game)
      final calls = state!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toList();
      expect(calls, contains('pass'));
      expect(calls, contains('2s'));
      expect(calls, contains('3h'));
      expect(calls, contains('4h'));

      // Check Opener responses over 2S inquiry
      final askState = engine.graph.getState(['1c', '1h', '2h', '2s']);
      expect(askState, isNotNull);
      final openerCalls = askState!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toList();
      expect(openerCalls, contains('2nt')); // 12-13 HCP min, 3=h
      expect(openerCalls, contains('3c'));  // 14-15 HCP max, 3=h
      expect(openerCalls, contains('3d'));  // 14-15 HCP max, 4+h
      expect(openerCalls, contains('3h'));  // 12-13 HCP min, 4+h
    });

    test('1D -> 1S -> 2S -> 2NT (Spiral Ask) branches correctly', () {
      final state = engine.graph.getState(['1d', '1s', '2s']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toList();
      expect(calls, contains('pass'));
      expect(calls, contains('2nt'));
      expect(calls, contains('3s'));
      expect(calls, contains('4s'));

      // Check Opener responses over 2NT inquiry
      final askState = engine.graph.getState(['1d', '1s', '2s', '2nt']);
      expect(askState, isNotNull);
      final openerCalls = askState!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toList();
      expect(openerCalls, contains('3c')); // 12-13 HCP min, 3=s
      expect(openerCalls, contains('3d')); // 14-15 HCP max, 3=s
      expect(openerCalls, contains('3h')); // 14-15 HCP max, 4+s
      expect(openerCalls, contains('3s')); // 12-13 HCP min, 4+s
    });
  });

  group('Support Doubles & Redoubles', () {
    test('1C -> 1H -> (1S) -> Dbl shows exactly 3-card Heart support', () {
      final state = engine.graph.getState(['1c', '1h', '(1s)']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toList();
      expect(calls, contains('dbl'));
      expect(calls, contains('2h'));

      // Opener with 3 Hearts and 14 HCP should select Dbl
      final opener3H = Hand.fromString('A5.KQ8.K986.QJ86'); // 3 Hearts, 14 HCP
      final bestBid = state.resolveBestBid(
        opener3H,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('dbl'));

      // Opener with 4 Hearts and 14 HCP should select 2H
      final opener4H = Hand.fromString('A5.KQ82.K98.QJ86'); // 4 Hearts, 14 HCP
      final bestBid4 = state.resolveBestBid(
        opener4H,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(bestBid4, isNotNull);
      expect(bestBid4!.displayCall.toLowerCase(), equals('2h'));
    });

    test('1D -> 1S -> (2C) -> Dbl shows exactly 3-card Spade support', () {
      final state = engine.graph.getState(['1d', '1s', '(2c)']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toList();
      expect(calls, contains('dbl'));
      expect(calls, contains('2s'));

      // Opener with 3 Spades should Double
      final opener3S = Hand.fromString('KQ8.A5.AJ986.862'); // 3 Spades, 14 HCP
      final bestBid = state.resolveBestBid(
        opener3S,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('dbl'));
    });

    test('1C -> 1H -> (X) -> RDbl shows exactly 3-card Heart support', () {
      final state = engine.graph.getState(['1c', '1h', '(x)']);
      expect(state, isNotNull);

      final calls = state!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toList();
      expect(calls, contains('rdbl'));
      expect(calls, contains('2h'));

      final opener3H = Hand.fromString('A5.KQ8.K986.QJ86');
      final bestBid = state.resolveBestBid(
        opener3H,
        engine.resolver,
        fragments: engine.graph.system.fragments,
      );
      expect(bestBid, isNotNull);
      expect(bestBid!.displayCall.toLowerCase(), equals('rdbl'));
    });
  });

  group('Targeted ML Partnership Deal Generation', () {
    test('PartnershipHcpFilter.borderlineGame deals boards with 22-25 combined HCP', () {
      final generator = DealGenerator();
      for (int i = 0; i < 5; i++) {
        final deal = generator.dealTargetedBoard(
          isPartnershipMatch: PartnershipHcpFilter.borderlineGame.matches,
        );
        final combHcp = deal.north.hcp + deal.south.hcp;
        expect(combHcp, greaterThanOrEqualTo(22));
        expect(combHcp, lessThanOrEqualTo(25));
      }
    });

    test('PartnershipHcpFilter.marginalSlam deals boards with 29-32 combined HCP', () {
      final generator = DealGenerator();
      for (int i = 0; i < 5; i++) {
        final deal = generator.dealTargetedBoard(
          isPartnershipMatch: PartnershipHcpFilter.marginalSlam.matches,
        );
        final combHcp = deal.north.hcp + deal.south.hcp;
        expect(combHcp, greaterThanOrEqualTo(29));
        expect(combHcp, lessThanOrEqualTo(32));
      }
    });
  });
}
