import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Multi 2D & Sound Weak Twos convention test', () async {
    const multiSystemYaml = '''
system: "Multi 2D & Good Weak Twos Demo System"
style: "multi_twos"

imports:
  - "assets/libraries/conventions/multi_two_diamonds.yaml"
  - "assets/libraries/conventions/rkcb_1430.yaml"

OpeningBids:
  pass:
    desc: "Pass"
    rule: "11-hcp"

  1c:
    desc: "1C"
    rule: "12+hcp 3+c"

  2d:
    ref: "MultiTwoDiamonds"

  2h:
    ref: "GoodWeakTwoHearts"

  2s:
    ref: "GoodWeakTwoSpades"
''';

    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      multiSystemYaml,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );

    final engine = AuctionEngine.fromSystem(system);

    // 1. Poor 6-card Heart hand (6 HCP): Opens 2D Multi
    final poorHeartsHand = Hand.fromString('84:KQ8753:962:J4');
    expect(poorHeartsHand.hcp, 6);
    expect(poorHeartsHand.heartsLength, 6);

    // Partner with weak hand bids 2H (Pass or Correct)
    final responderHand = Hand.fromString('KJ6:94:AT85:9852');

    final res1 = simulateAuction(
      north: poorHeartsHand,
      south: responderHand,
      engine: engine,
      dealer: 'N',
    );

    expect(res1.auctionCalls.first, '2d');
    expect(res1.auctionCalls[1], '2h');
    expect(res1.auctionCalls[2], 'Pass');
    expect(res1.finalContract, '2h');

    // 2. Poor 6-card Spade hand (6 HCP): Opens 2D Multi, Responder bids 2H, Opener corrects to 2S
    final poorSpadesHand = Hand.fromString('KQ8753:84:962:J4');
    final res2 = simulateAuction(
      north: poorSpadesHand,
      south: responderHand,
      engine: engine,
      dealer: 'N',
    );

    expect(res2.auctionCalls.first, '2d');
    expect(res2.auctionCalls[1], '2h');
    expect(res2.auctionCalls[2], '2s');
    expect(res2.finalContract, '2s');

    // 3. Sound 6-card Heart hand (9 HCP): Opens 2H (Good Weak Two)
    final soundHeartsHand = Hand.fromString('84:AKJ853:962:J4');
    expect(soundHeartsHand.hcp, 9);
    final res3 = simulateAuction(
      north: soundHeartsHand,
      south: responderHand,
      engine: engine,
      dealer: 'N',
    );

    expect(res3.auctionCalls.first, '2h');

    // 4. Sound 6-card Spade hand (9 HCP): Opens 2S (Good Weak Two)
    final soundSpadesHand = Hand.fromString('AKJ853:84:962:J4');
    expect(soundSpadesHand.hcp, 9);
    final res4 = simulateAuction(
      north: soundSpadesHand,
      south: responderHand,
      engine: engine,
      dealer: 'N',
    );

    expect(res4.auctionCalls.first, '2s');
  });

  test('Gavin Wolpert system remains on Standard Tri-Two (Natural 2D, 2H, 2S)', () async {
    final gavinEngine = await loadGavinEngine();

    // Natural 6-card Diamond hand (7 HCP)
    final weakDiamondHand = Hand.fromString('84:94:KQ9853:Q42');
    expect(weakDiamondHand.hcp, 7);
    expect(weakDiamondHand.diamondsLength, 6);
    final responderHand = Hand.fromString('AK6:A82:T4:J8753');

    final res = simulateAuction(
      north: weakDiamondHand,
      south: responderHand,
      engine: gavinEngine,
      dealer: 'N',
    );

    // In Gavin 2/1, 2D is natural Weak Two in Diamonds!
    expect(res.auctionCalls.first, '2d');
  });
}
