import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Exemplar 2.1: 2C - 3C - 3H - 3NT must pull to 4H with 7-card Hearts', () async {
    final engine = await loadGavinEngine();

    // North: 19 HCP with 7 solid Hearts (1-7-3-2)
    final north = Hand.fromString('K:AKQ9742:AT2:K2');
    // South: 8 HCP with 6 Clubs (3-1-3-6)
    final south = Hand.fromString('Q95:5:J53:AJT854');

    // South is dealer, passes; North opens 2C
    final sim = simulateAuction(
      north: north,
      south: south,
      engine: engine,
      dealer: 'S',
    );

    print('SIM AUCTION 2.1: ${sim.auctionCalls.join(" ")}');
    expect(sim.auctionCalls.first, 'Pass');
    expect(sim.auctionCalls[1], '2c');
    expect(sim.auctionCalls[2], '3c');
    expect(sim.auctionCalls[3], '3h');
    expect(sim.auctionCalls[4], '3nt');
    expect(sim.auctionCalls[5], '4h', reason: 'North must pull 3NT to 4H with 7 Hearts!');
    expect(sim.finalContract, '4h');
  });
}
