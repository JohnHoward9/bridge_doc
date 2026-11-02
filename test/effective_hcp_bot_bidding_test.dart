import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/hand_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BridgeSystem gavinSystem;
  late AuctionEngine engine;
  late MLHandValuation strictVal;
  late MLHandValuation userVal;

  setUpAll(() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    final yamlStr = await file.readAsString();
    gavinSystem = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
    engine = AuctionEngine.fromSystem(gavinSystem);
    strictVal = MLHandValuation(strictEffectiveHcp: true);
    userVal = MLHandValuation(strictEffectiveHcp: false);
  });

  group('Effective HCP (Adjusted Count) Bot Bidding Tests', () {
    test('North bot: 14 raw HCP upgraded to 15.2 Eff HCP opens 1NT (15 <= Eff HCP < 17)', () {
      // ♠AJT9 (5 HCP) ♥KT9 (3 HCP) ♦AQ8 (6 HCP) ♣T92 (0 HCP) + supported 10s/9s -> raw 14 HCP
      // With tens & nines intermediate adjustments, effective HCP >= 15.0 and < 17.0
      final hand = HandParser.parseSingleHand('AJT9.KT9.AQ8.T92');
      final raw = hand.hcp;
      final eff = strictVal.evaluatePoints(hand);
      expect(raw, equals(14));
      expect(eff, greaterThanOrEqualTo(15.0));
      expect(eff, lessThan(17.0));

      final rootState = engine.graph.rootState;
      final botBid = rootState.resolveBestBid(
        hand,
        engine.botResolver,
        fragments: engine.graph.system.fragments,
      );
      expect(botBid, isNotNull);
      expect(botBid!.displayCall.toLowerCase(), equals('1nt'),
          reason: 'Bot should open 1NT with 14 raw upgraded to 15+ Effective HCP');
    });

    test('North bot: 17 raw HCP upgraded to 17.5+ Eff HCP does NOT open 1NT (Eff HCP >= 17)', () {
      // ♠AK9 (7 HCP) ♥AQ8 (6 HCP) ♦KJ9 (4 HCP) ♣982 (0 HCP) -> raw 17 HCP, strong prime controls & intermediates
      final hand = HandParser.parseSingleHand('AK9.AQ8.KJ9.982');
      final raw = hand.hcp;
      final eff = strictVal.evaluatePoints(hand);
      expect(raw, equals(17));
      expect(eff, greaterThanOrEqualTo(17.0),
          reason: 'Prime controls and supported 9s push Eff HCP to 17+');

      final rootState = engine.graph.rootState;
      final botBid = rootState.resolveBestBid(
        hand,
        engine.botResolver,
        fragments: engine.graph.system.fragments,
      );
      expect(botBid, isNotNull);
      expect(botBid!.displayCall.toLowerCase(), isNot(equals('1nt')),
          reason: 'Bot should NOT open 1NT when Eff HCP >= 17.0 (upgrades out of 15-17 NT)');
    });

    test('North bot: 15 raw HCP downgraded to 14.x Eff HCP does NOT open 1NT (Eff HCP < 15)', () {
      // ♠KQ2 (5) ♥QJ3 (3) ♦KJ4 (4) ♣QJ42 (3) -> raw 15 HCP, flat 4333 and soft honours penalized
      final hand = HandParser.parseSingleHand('KQ2.QJ3.KJ4.QJ42');
      final raw = hand.hcp;
      final eff = strictVal.evaluatePoints(hand);
      expect(raw, equals(15));
      expect(eff, lessThan(15.0),
          reason: 'Flat 4333 with soft Q/J honors is downgraded below 15.0 Eff HCP');

      final rootState = engine.graph.rootState;
      final botBid = rootState.resolveBestBid(
        hand,
        engine.botResolver,
        fragments: engine.graph.system.fragments,
      );
      expect(botBid, isNotNull);
      expect(botBid!.displayCall.toLowerCase(), isNot(equals('1nt')),
          reason: 'Bot should NOT open 1NT when downgraded Eff HCP is below 15.0');
    });

    test('South learner (user): flexible dual-count allows raw 15 HCP or raw 17 HCP', () {
      // Hand with raw 15 HCP but downgraded Eff HCP: user can still bid 1NT
      final hand15 = HandParser.parseSingleHand('KQ2.QJ3.KJ4.QJ42');
      final candidates15 = engine.graph.rootState.evaluateCandidates(
        hand15,
        engine.resolver, // User resolver
        fragments: engine.graph.system.fragments,
      );
      final match1NT = candidates15.any((c) => c.displayCall.toLowerCase() == '1nt' && c.isMatch);
      expect(match1NT, isTrue,
          reason: 'South human learner should be permitted to bid 1NT with raw 15 HCP');

      // Hand with raw 17 HCP but upgraded Eff HCP: user can still bid 1NT
      final hand17 = HandParser.parseSingleHand('AK9.AQ8.KJ9.982');
      final candidates17 = engine.graph.rootState.evaluateCandidates(
        hand17,
        engine.resolver, // User resolver
        fragments: engine.graph.system.fragments,
      );
      final match1NT17 = candidates17.any((c) => c.displayCall.toLowerCase() == '1nt' && c.isMatch);
      expect(match1NT17, isTrue,
          reason: 'South human learner should be permitted to bid 1NT with raw 17 HCP');
    });
  });
}
