import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Deal 25 North 4-0-5-4 with 16 HCP opens 1D and reaches 4S', () async {
    final engine = await loadGavinEngine();

    // North: ♠J743 ♥— ♦AKQT3 ♣KQJ3 (16 HCP, 4-0-5-4)
    final north = Hand.fromString('J743::AKQT3:KQJ3');
    // South: ♠A986 ♥AT4 ♦J954 ♣54 (9 HCP, 4-3-4-2)
    final south = Hand.fromString('A986:AT4:J954:54');

    expect(north.hcp, equals(16));
    expect(south.hcp, equals(9));

    // Board 24: West passes, North opens
    final sim = simulateAuction(
      north: north,
      south: south,
      engine: engine,
      dealer: 'W',
    );

    expect(sim.auctionCalls, equals(['Pass', '1d', '1s', '3s', '4s', 'Pass']));
    expect(sim.finalContract, equals('4s'));
  });
}
