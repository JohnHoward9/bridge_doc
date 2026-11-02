import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Gavin Checkback: Weak responder (7 HCP, 5 Hearts) signs off in 2H over 1NT', () async {
    final engine = await loadGavinEngine();

    // North: ♠JT53 ♥A97 ♦K42 ♣KQ4 (13 HCP, balanced)
    final north = Hand.fromString('JT53:A97:K42:KQ4');
    // South: ♠7 ♥KQT54 ♦J65 ♣JT96 (7 HCP, 1-5-3-4)
    final south = Hand.fromString('7:KQT54:J65:JT96');

    expect(north.hcp, equals(13));
    expect(south.hcp, equals(7));

    // North opens 1C
    final sim = simulateAuction(
      north: north,
      south: south,
      engine: engine,
      dealer: 'N',
    );

    print('Simulated Auction: ${sim.auctionCalls.join(" ")}');
    print('Final Contract: ${sim.finalContract}');

    expect(sim.auctionCalls, equals(['1c', '1h', '1nt', '2h', 'Pass']),
        reason: 'Auction should be 1c - 1h - 1nt - 2h - Pass');
    expect(sim.finalContract, equals('2h'), reason: 'Contract should be 2h');
  });
}
