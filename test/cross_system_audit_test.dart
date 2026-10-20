import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';

void main() {
  group('Cross-System Bidding Graph & Engine Audit', () {
    Future<BridgeSystem> loadSystem(String relativePath) async {
      final file = File(relativePath);
      expect(file.existsSync(), isTrue, reason: 'System file $relativePath must exist');
      final yamlStr = await file.readAsString();
      return SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async {
          final f = File(path);
          return f.existsSync() ? await f.readAsString() : '';
        },
      );
    }

    test('US Standard 2/1 System: Graph compiles, 15-17 1NT, 5-card majors, 2C GF', () async {
      final system = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      expect(engine.graph.rootState.candidateNodes.length, greaterThanOrEqualTo(8));

      // 1NT opening with 15-17 balanced: ♠A(4) ♥KQ(5) ♦AQ(6) ♣10843(0) = 15 HCP
      final ntHand = Hand.fromString('A3:KQ4:AQ52:T843');
      expect(ntHand.hcp, equals(15));
      expect(ntHand.isBalanced, isTrue);

      final openNT = engine.graph.rootState.resolveBestBid(ntHand, engine.resolver, fragments: system.fragments);
      expect(openNT, isNotNull);
      expect(openNT!.displayCall.toLowerCase(), equals('1nt'));

      // 5-card major opening
      final majorHand = Hand.fromString('KQ984:A32:KJ4:82'); // 14 HCP, 5 spades
      final openMajor = engine.graph.rootState.resolveBestBid(majorHand, engine.resolver, fragments: system.fragments);
      expect(openMajor, isNotNull);
      expect(openMajor!.displayCall.toLowerCase(), equals('1s'));

      // 2C strong artificial
      final strongHand = Hand.fromString('AKQ:AKJ4:AK82:82'); // 23 HCP
      final open2C = engine.graph.rootState.resolveBestBid(strongHand, engine.resolver, fragments: system.fragments);
      expect(open2C, isNotNull);
      expect(open2C!.displayCall.toLowerCase(), equals('2c'));
    });

    test('UK Acol 4-Card Major System: Graph compiles, 12-14 Weak NT, 4-card major openings', () async {
      final system = await loadSystem('assets/core/systems/uk_acol_4cm.yaml');
      final engine = AuctionEngine.fromSystem(system);

      expect(engine.graph.rootState.candidateNodes.length, greaterThanOrEqualTo(6));

      // Weak 1NT opening (12-14 balanced): ♠K(3) ♥KJ(4) ♦AQ(6) ♣843(0) = 13 HCP
      final weakNtHand = Hand.fromString('K84:KJ4:AQ52:843');
      expect(weakNtHand.hcp, equals(13));
      expect(weakNtHand.isBalanced, isTrue);

      final openWeakNT = engine.graph.rootState.resolveBestBid(weakNtHand, engine.resolver, fragments: system.fragments);
      expect(openWeakNT, isNotNull);
      expect(openWeakNT!.displayCall.toLowerCase(), equals('1nt'));

      // 4-card heart opening with 15 HCP (outside weak NT range)
      final acolHeartHand = Hand.fromString('K3:AQ84:KJ52:843'); // 15 HCP, 4 hearts, 4 diamonds
      final openAcol = engine.graph.rootState.resolveBestBid(acolHeartHand, engine.resolver, fragments: system.fragments);
      expect(openAcol, isNotNull);
      expect(openAcol!.displayCall.toLowerCase(), equals('1h'));
    });

    test('Three-Way Club System: Graph compiles, 1C Polish/Swedish Club variations', () async {
      final system = await loadSystem('assets/core/systems/three_way_club_5cm.yaml');
      final engine = AuctionEngine.fromSystem(system);

      expect(engine.graph.rootState.candidateNodes.length, greaterThanOrEqualTo(8));

      // 1C opening covers weak balanced (11-14)
      final polishClubHand = Hand.fromString('K84:KJ4:AQ52:843'); // 13 HCP balanced
      expect(polishClubHand.hcp, equals(13));
      expect(polishClubHand.isBalanced, isTrue);

      final openClub = engine.graph.rootState.resolveBestBid(polishClubHand, engine.resolver, fragments: system.fragments);
      expect(openClub, isNotNull);
      expect(openClub!.displayCall.toLowerCase(), equals('1c'));
    });

    test('Kokish-Kraft Weak NT System: Graph compiles, 12-14 Weak NT, 2C Kokish controls', () async {
      final system = await loadSystem('assets/core/systems/kokish_kraft_weak_nt.yaml');
      final engine = AuctionEngine.fromSystem(system);

      expect(engine.graph.rootState.candidateNodes.length, greaterThanOrEqualTo(8));

      // 12-14 Weak NT
      final weakNtHand = Hand.fromString('K84:KJ4:AQ52:843'); // 13 HCP balanced
      expect(weakNtHand.hcp, equals(13));

      final openWeakNT = engine.graph.rootState.resolveBestBid(weakNtHand, engine.resolver, fragments: system.fragments);
      expect(openWeakNT, isNotNull);
      expect(openWeakNT!.displayCall.toLowerCase(), equals('1nt'));

      // 2C Strong Artificial
      final strongHand = Hand.fromString('AKQ:AKJ4:AK82:82'); // 23 HCP
      final open2C = engine.graph.rootState.resolveBestBid(strongHand, engine.resolver, fragments: system.fragments);
      expect(open2C, isNotNull);
      expect(open2C!.displayCall.toLowerCase(), equals('2c'));
    });
  });
}
