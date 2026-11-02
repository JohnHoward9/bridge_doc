import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Gavin Checkback: North 13 HCP balanced and South 11 HCP with 6 Hearts reach 4H', () async {
    final engine = await loadGavinEngine();

    // North: ♠K86 ♥QJ3 ♦A87 ♣K432 (13 HCP, 3-3-3-4)
    final north = Hand.fromString('K86:QJ3:A87:K432');
    // South: ♠Q3 ♥A97654 ♦K2 ♣Q96 (11 HCP, 2-6-2-3)
    final south = Hand.fromString('Q3:A97654:K2:Q96');

    expect(north.hcp, equals(13));
    expect(south.hcp, equals(11));

    // North is dealer
    final sim = simulateAuction(
      north: north,
      south: south,
      engine: engine,
      dealer: 'N',
    );

    print('Simulated Auction: ${sim.auctionCalls.join(" ")}');
    print('Final Contract: ${sim.finalContract}');

    expect(sim.auctionCalls.first, equals('1c'), reason: 'North opens 1C');
    expect(sim.auctionCalls[1], equals('1h'), reason: 'South responds 1H');
    expect(sim.auctionCalls[2], equals('1nt'), reason: 'North rebids 1NT');
    expect(sim.finalContract, equals('4h'), reason: 'Partnership reaches 4H contract');
  });
}
