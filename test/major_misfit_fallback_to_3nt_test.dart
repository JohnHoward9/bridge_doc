import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/evaluators/ml_game_selector.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Major Misfit Fallback to 3NT and ML Game Selection', () async {
    final engine = await loadGavinEngine();

    // 1. Exemplar Hand: 1D - 1H - 1S - 2D - 2S - 3NT (No 5-1 Heart Fit!)
    // North: ♠AK84 ♥J ♦KQ72 ♣KJ64 (17 HCP, 4-1-4-4)
    // South: ♠QJ ♥K9743 ♦A96 ♣Q93 (12 HCP, 2-5-3-3)
    final north1 = Hand.fromString('AK84:J:KQ72:KJ64');
    final south1 = Hand.fromString('QJ:K9743:A96:Q93');

    final sim1 = simulateAuction(
      north: north1,
      south: south1,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 1: ${sim1.auctionCalls.join(" ")} -> ${sim1.finalContract}');
    expect(sim1.auctionCalls, equals(['1d', '1h', '1s', '2d', '2s', '3nt', 'Pass']));
    expect(sim1.finalContract.toLowerCase(), equals('3nt'),
        reason: 'Holding 5 hearts facing opener 2S rebid denying 3 hearts, responder must fall back on 3NT, never 4H!');

    // 2. Responder with 6+ Hearts over 2S bids 4H
    // South2: ♠QJ ♥KQ9743 ♦A9 ♣Q93 (14 HCP, 6 hearts)
    final south2 = Hand.fromString('QJ:KQ9743:A9:Q93');
    final sim2 = simulateAuction(
      north: north1,
      south: south2,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 2: ${sim2.auctionCalls.join(" ")} -> ${sim2.finalContract}');
    expect(sim2.auctionCalls, equals(['1d', '1h', '1s', '2d', '2s', '4h', 'Pass']));
    expect(sim2.finalContract.toLowerCase(), equals('4h'),
        reason: 'Holding 6+ hearts, responder can insist on 4H game!');

    // 3. Responder with 4+ Spades over 2S raises to 4S
    // South3: ♠QJ84 ♥K974 ♦A9 ♣Q93 (13 HCP, 4 spades)
    final south3 = Hand.fromString('QJ84:K974:A9:Q93');
    final sim3 = simulateAuction(
      north: north1,
      south: south3,
      engine: engine,
      dealer: 'N',
    );

    print('SIM AUCTION 3: ${sim3.auctionCalls.join(" ")} -> ${sim3.finalContract}');
    expect(sim3.auctionCalls, equals(['1d', '1h', '1s', '2d', '2s', '4s', 'Pass']));
    expect(sim3.finalContract.toLowerCase(), equals('4s'),
        reason: 'Holding 4 spades, responder completes the 4-4 major fit in 4S!');

    // 4. ML Game Selection Lookup (3NT vs 5 Minor)
    // Case A: 9-card diamond fit, all suits stopped -> 3NT
    final beliefA = SeatBeliefState(
      seat: 'N',
      minHcp: 13,
      maxHcp: 15,
      minSuitLength: {Suit.diamonds: 4, Suit.spades: 2, Suit.hearts: 3, Suit.clubs: 4},
    );
    final handA = Hand.fromString('AQ:KJ:K9764:AJ52'); // all suits stopped, 5 diamonds
    final decisionA = MLGameSelector.selectOptimalGame(
      myHand: handA,
      partnerBelief: beliefA,
      candidateMinor: Suit.diamonds,
    );
    expect(decisionA.recommendedGame, equals('3NT'));
    expect(decisionA.hasAllStoppers, isTrue);

    // Case B: 10-card diamond fit, unstopped heart hole with shortness -> 5D
    final beliefB = SeatBeliefState(
      seat: 'N',
      minHcp: 12,
      maxHcp: 14,
      minSuitLength: {Suit.diamonds: 5, Suit.spades: 3, Suit.hearts: 1, Suit.clubs: 4},
    );
    final handB = Hand.fromString('A94:4:KQ876:AJ52'); // heart singleton, unstopped hearts
    final decisionB = MLGameSelector.selectOptimalGame(
      myHand: handB,
      partnerBelief: beliefB,
      candidateMinor: Suit.diamonds,
    );
    expect(decisionB.recommendedGame, equals('5D'));
    expect(decisionB.hasAllStoppers, isFalse);
  });
}
