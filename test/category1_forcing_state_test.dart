import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Exemplar 1.1: Opener must not pass after 1H - 1S', () async {
    final engine = await loadGavinEngine();

    // North: 17 HCP with 5 Hearts, 4 Clubs, 3 Spades, 1 Diamond
    final north = Hand.fromString('AK3:KQ853:6:A832');
    // South: 6 HCP with 6 Spades, 3 Hearts, 4 Diamonds, 0 Clubs
    final south = Hand.fromString('J98752:A64:J874:');

    final sim = simulateAuction(
      north: north,
      south: south,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION: ${sim.auctionCalls.join(" ")}');
    expect(sim.auctionCalls.first, '1h');
    expect(sim.auctionCalls[1], '1s');
    expect(sim.auctionCalls[2], isNot('Pass'), reason: 'Opener must not pass after 1H - 1S!');
    expect(sim.finalContract, '4s');
  });

  test('Exemplar 1.2: After 1C - 1D, Opener with 15-17 balanced must rebid 1NT, not Pass', () async {
    final engine = await loadGavinEngine();

    // North: 16 HCP balanced (4-4-2-3)
    final north = Hand.fromString('Q832:AQJ3:A3:J63');
    // South: 10 HCP with 5 Diamonds (2-3-5-3)
    final south = Hand.fromString('K6:842:KQT82:K54');

    final sim = simulateAuction(
      north: north,
      south: south,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 1.2: ${sim.auctionCalls.join(" ")}');
    expect(sim.auctionCalls.first, '1c');
    expect(sim.auctionCalls[1], '1d');
    expect(sim.auctionCalls[2], isNot('Pass'), reason: 'Opener must not pass after 1C - 1D!');
  });

  test('Exemplar 1.3: Opener with 18 HCP 6-card minor rebids over 1NT, driving to 6C', () async {
    final engine = await loadGavinEngine();

    // North: 18 HCP with 6 Diamonds (2-3-6-2)
    final north = Hand.fromString('A6:AQ6:AKJ984:53');
    // South: 10 HCP with 6 Clubs (3-3-1-6)
    final south = Hand.fromString('KJT:853:3:KQJ976');

    final sim = simulateAuction(
      north: north,
      south: south,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 1.3: ${sim.auctionCalls.join(" ")}');
    expect(sim.auctionCalls.first, '1d');
    expect(sim.auctionCalls[1], '1nt');
    expect(sim.auctionCalls[2], isNot('Pass'), reason: 'Opener with 18 HCP must not pass 1NT!');
    expect(sim.finalContract, '6c', reason: 'Should reach 6C slam');
  });
}
