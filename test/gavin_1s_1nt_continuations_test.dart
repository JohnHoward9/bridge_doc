import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Gavin 2/1: 1S - 1NT - 2H continuations and 4H game reach', () async {
    final engine = await loadGavinEngine();

    // 1. Problem hand: 20261028_153337_1s_opening_with_5_5_in_major.pbn
    // North: ♠AQJ98 ♥QT974 ♦K ♣K7 (15 HCP, 5-5 majors)
    // South: ♠74 ♥KJ83 ♦Q52 ♣AJ95 (11 HCP, 4-card heart fit)
    final north1 = Hand.fromString('AQJ98:QT974:K:K7');
    final south1 = Hand.fromString('74:KJ83:Q52:AJ95');

    final sim1 = simulateAuction(
      north: north1,
      south: south1,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 1 (5-5 Majors Game): ${sim1.auctionCalls.join(" ")} -> ${sim1.finalContract}');
    expect(sim1.finalContract.toLowerCase(), equals('4h'),
        reason: 'North (15 HCP 5-5) and South (11 HCP 4-card heart fit) must reach 4H game!');

    // 2. Weak South with Heart fit (7 HCP, 4 hearts): Bids 1NT then passes 2H
    // South2: ♠74 ♥K832 ♦Q52 ♣J954 (3 + 2 + 1 = 6-7 HCP)
    final south2 = Hand.fromString('74:K832:Q52:J954');
    final sim2 = simulateAuction(
      north: north1,
      south: south2,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 2 (Weak Heart Signoff): ${sim2.auctionCalls.join(" ")} -> ${sim2.finalContract}');
    expect(sim2.finalContract.toLowerCase(), equals('2h'),
        reason: 'Holding 7 HCP with heart fit, responder responds 1NT and then passes 2H!');

    // 3. Weak South with 2 Spades preferring Spades (6 HCP, 2 hearts): Bids 1NT then 2S
    // South3: ♠74 ♥83 ♦KJ52 ♣Q9542 (3 + 1 + 2 = 6 HCP, 13 cards: 2-2-4-5)
    final south3 = Hand.fromString('74:83:KJ52:Q9542');
    final sim3 = simulateAuction(
      north: north1,
      south: south3,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 3 (Spade False Preference): ${sim3.auctionCalls.join(" ")} -> ${sim3.finalContract}');
    expect(sim3.finalContract.toLowerCase(), equals('2s'),
        reason: 'Holding 2 spades and 7 HCP lacking heart fit, responder responds 1NT and then prefers 2S!');
  });
}
