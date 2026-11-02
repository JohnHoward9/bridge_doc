import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

class SlamDealCase {
  final String title;
  final String matchBoard;
  final String northStr;
  final String southStr;
  final String dealer;
  final String expectedTarget;
  final String strain;

  SlamDealCase({
    required this.title,
    required this.matchBoard,
    required this.northStr,
    required this.southStr,
    required this.dealer,
    required this.expectedTarget,
    required this.strain,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Audit 20 Slam Auctions (2025 BBO Championship & Gavin 2/1)', () async {
    final engine = await loadGavinEngine();
    final mlVal = MLHandValuation(strictEffectiveHcp: false);

    final slamCases = [
      // 1. Major Slams (Hearts)
      SlamDealCase(
        matchBoard: '81564 B:17',
        title: 'BBO 2025 9-card Heart fit (30 HCP)',
        northStr: 'AQ752:863:A65:AJ',
        southStr: 'KT43:AKQT95:J3:Q',
        dealer: 'N',
        expectedTarget: '6H',
        strain: 'H',
      ),
      SlamDealCase(
        matchBoard: '81995 B:27',
        title: 'BBO 2025 9-card Heart fit (31 HCP)',
        northStr: 'KQJ2:K95:Q54:KJ7',
        southStr: 'A43:AT742:AKJT8:',
        dealer: 'S',
        expectedTarget: '6H',
        strain: 'H',
      ),
      SlamDealCase(
        matchBoard: '82593 B:29',
        title: 'BBO 2025 8-card Heart fit (31 HCP)',
        northStr: 'AK8:KQ832:32:AQ3',
        southStr: 'T64:J96:AKJ87:KJ',
        dealer: 'N',
        expectedTarget: '6H',
        strain: 'H',
      ),

      // 2. Major Slams (Spades)
      SlamDealCase(
        matchBoard: '81995 B:29',
        title: 'BBO 2025 8-card Spade fit (32 HCP)',
        northStr: 'AQJ5:T75:QJ8:K76',
        southStr: 'K964:AK93:AK73:Q',
        dealer: 'N',
        expectedTarget: '6S',
        strain: 'S',
      ),
      SlamDealCase(
        matchBoard: '82025 B:11',
        title: 'BBO 2025 9-card Spade fit (28 HCP, 5-4 fit)',
        northStr: 'AKJ:AK943:2:A974',
        southStr: 'QT954:Q5:AT94:J2',
        dealer: 'S',
        expectedTarget: '6S',
        strain: 'S',
      ),
      SlamDealCase(
        matchBoard: 'Gavin Jacoby Slam',
        title: 'Gavin 2/1 Classic Jacoby 2NT (32 HCP, 9-card ♠ fit)',
        northStr: 'AK872:QJ4:A3:KQ2',
        southStr: 'QJ93:K72:K85:A65',
        dealer: 'N',
        expectedTarget: '6S',
        strain: 'S',
      ),
      SlamDealCase(
        matchBoard: 'Gavin Splinter Slam',
        title: 'Gavin 2/1 Splinter to 6♠ (28 HCP, singleton ♣)',
        northStr: 'AQ875:AK42:K93:4',
        southStr: 'KJ94:Q6:AQ4:8762',
        dealer: 'N',
        expectedTarget: '6S',
        strain: 'S',
      ),

      // 3. Minor Slams (Clubs)
      SlamDealCase(
        matchBoard: '81557 B:9',
        title: 'BBO 2025 10-card Club fit (28 HCP)',
        northStr: ':AT62:AT42:AKQ85',
        southStr: 'K8:K54:KJ8:JT964',
        dealer: 'N',
        expectedTarget: '6C',
        strain: 'C',
      ),
      SlamDealCase(
        matchBoard: '81559 B:2',
        title: 'BBO 2025 11-card Club fit (30 HCP, 7-4 fit)',
        northStr: 'A53:A9:K:KQJ9753',
        southStr: 'KJ9:KT82:Q7:AT42',
        dealer: 'E',
        expectedTarget: '6C',
        strain: 'C',
      ),
      SlamDealCase(
        matchBoard: '81559 B:4',
        title: 'BBO 2025 Two-Suited Club fit (28 HCP, cross-voids)',
        northStr: ':AQJ965:AT2:AQT3',
        southStr: 'AKJ752::K65:9654',
        dealer: 'W',
        expectedTarget: '6C',
        strain: 'C',
      ),
      SlamDealCase(
        matchBoard: '81574 B:16',
        title: 'BBO 2025 2C Opening Club Slam (29 HCP, 6-card ♣)',
        northStr: 'QT:63:A75:J87532',
        southStr: 'A:AK5:Q43:AKQT94',
        dealer: 'W',
        expectedTarget: '6C',
        strain: 'C',
      ),
      SlamDealCase(
        matchBoard: '81578 B:14',
        title: 'BBO 2025 Solid Clubs vs Solid Diamonds (28 HCP)',
        northStr: 'KJT:853:3:KQJ976',
        southStr: 'A6:AQ6:AKJ984:53',
        dealer: 'E',
        expectedTarget: '6C',
        strain: 'C',
      ),
      SlamDealCase(
        matchBoard: '82583 B:5',
        title: 'BBO 2025 9-card Club fit (31 HCP)',
        northStr: 'JT5:AQ:AKJ:KJT96',
        southStr: 'AQ8:KJ54:63:Q872',
        dealer: 'N',
        expectedTarget: '6C',
        strain: 'C',
      ),
      SlamDealCase(
        matchBoard: '82601 B:8',
        title: 'BBO 2025 10-card Club fit (28 HCP, 6-4 fit)',
        northStr: 'AJ96:AT7:A4:QJ43',
        southStr: 'K742:9:Q6:AK9762',
        dealer: 'W',
        expectedTarget: '6C',
        strain: 'C',
      ),

      // 4. Minor Slams (Diamonds)
      SlamDealCase(
        matchBoard: '81566 B:15',
        title: 'BBO 2025 10-card Diamond fit (29 HCP, 6-4 fit)',
        northStr: 'QJ53:KQ53:A752:T',
        southStr: 'A72::KQT963:AKJ9',
        dealer: 'S',
        expectedTarget: '6D',
        strain: 'D',
      ),
      SlamDealCase(
        matchBoard: '81995 B:24',
        title: 'BBO 2025 Power Diamond Slam (32 HCP)',
        northStr: '64:Q97:AKT63:A96',
        southStr: 'AK32:AJ5:J2:KQJ4',
        dealer: 'W',
        expectedTarget: '6D',
        strain: 'D',
      ),

      // 5. NoTrump Slams (6NT)
      SlamDealCase(
        matchBoard: '82017 B:8',
        title: 'BBO 2025 32 HCP Balanced Power Slam',
        northStr: 'AKQJ2:AQ7:854:K9',
        southStr: '9843:K64:AQ7:A64',
        dealer: 'W',
        expectedTarget: '6N',
        strain: 'NT',
      ),
      SlamDealCase(
        matchBoard: '82029 B:28',
        title: 'BBO 2025 30 HCP NoTrump Slam',
        northStr: 'AK9:T8432:KQ9:KJ',
        southStr: '4:AQ9:AT874:A972',
        dealer: 'W',
        expectedTarget: '6N',
        strain: 'NT',
      ),

      // 6. Grand Slams (7-level)
      SlamDealCase(
        matchBoard: '82064 B:27',
        title: 'BBO 2025 37 HCP Grand Slam in Spades',
        northStr: 'KQ432:AQT4:A:832',
        southStr: 'AJ6:KJ7:KQ6:AKJ6',
        dealer: 'S',
        expectedTarget: '7S',
        strain: 'S',
      ),
      SlamDealCase(
        matchBoard: '82614 B:23',
        title: 'BBO 2025 34 HCP Grand Slam in Clubs',
        northStr: 'KQT3:2:A753:QT32',
        southStr: 'A2:AKQ:KT86:AK64',
        dealer: 'S',
        expectedTarget: '7C',
        strain: 'C',
      ),
    ];

    expect(slamCases.length, equals(20));

    final buffer = StringBuffer();
    buffer.writeln('# 20 Slam Hands Audit: 2025 BBO Championship & Gavin 2/1\n');
    buffer.writeln('Evaluated **20 slam and grand slam deals** across all 5 strains (♠, ♥, ♦, ♣, NT).\n');
    buffer.writeln('| # | Match / Deal | Strain | North Hand | South Hand | Comb HCP | Table / Target | Auto Auction | Auto Contract | Status & Diagnosis |');
    buffer.writeln('|---|---|:---:|---|---|:---:|:---:|---|:---:|---|');

    int index = 1;
    int slamsReached = 0;
    int gameStopped = 0;

    for (final c in slamCases) {
      final north = Hand.fromString(c.northStr);
      final south = Hand.fromString(c.southStr);

      final nEff = mlVal.evaluatePoints(north);
      final sEff = mlVal.evaluatePoints(south);

      String formatHand(Hand h, double eff) {
        String suit(Suit s) {
          final str = h.cardsInSuit(s).map((x) => x.rank.symbol).join('');
          return str.isEmpty ? '—' : str;
        }
        return '♠${suit(Suit.spades)} ♥${suit(Suit.hearts)} ♦${suit(Suit.diamonds)} ♣${suit(Suit.clubs)}<br>(${h.hcp} HCP → ${eff.toStringAsFixed(1)} Eff)';
      }

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: c.dealer,
      );

      final contract = sim.finalContract.toUpperCase();
      final isSlam = contract.startsWith('6') || contract.startsWith('7');

      if (isSlam) {
        slamsReached++;
      } else {
        gameStopped++;
      }

      final status = isSlam ? '✅ **SLAM_REACHED**' : '🚩 **STOPPED_IN_GAME**';

      buffer.writeln('| $index | **${c.matchBoard}**<br>${c.title} | **${c.strain}** | ${formatHand(north, nEff)} | ${formatHand(south, sEff)} | **${north.hcp + south.hcp} HCP** | **${c.expectedTarget}** | `${sim.auctionCalls.join(' ')}` | **${sim.finalContract}** | $status |');
      index++;
    }

    buffer.writeln('\n## Summary');
    buffer.writeln('- **Total Slam Hands Tested**: 20');
    buffer.writeln('- **Slams Reached**: $slamsReached / 20');
    buffer.writeln('- **Stopped in Game / Partscore**: $gameStopped / 20');

    final outPath = 'bbo_2025_slam_results.md';
    await File(outPath).writeAsString(buffer.toString());
    print('Slam audit results saved to: $outPath');
  });
}
