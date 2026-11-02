import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';

Map<String, Hand> parseBboDeal(String dealStr) {
  final match = RegExp(r'md\|(\d)([^\|]+)\|').firstMatch(dealStr);
  if (match == null) return {};
  final startSeat = int.parse(match.group(1)!);
  final seatOrder = ['S', 'W', 'N', 'E'];
  final handsRaw = match.group(2)!.split(',');
  final Map<String, Hand> result = {};

  for (int i = 0; i < handsRaw.length; i++) {
    final seat = seatOrder[(startSeat - 1 + i) % 4];
    final hStr = handsRaw[i];
    final sm = RegExp(r'S(.*?)H(.*?)D(.*?)C(.*)').firstMatch(hStr);
    if (sm != null) {
      final s = sm.group(1) ?? '';
      final h = sm.group(2) ?? '';
      final d = sm.group(3) ?? '';
      final c = sm.group(4) ?? '';
      try {
        result[seat] = Hand.fromString('$s:$h:$d:$c');
      } catch (_) {}
    }
  }
  return result;
}

Future<AuctionEngine> loadGavinEngine() async {
  const relativePath = 'assets/core/systems/gavin_wolpert_2over1.yaml';
  final file = File(relativePath);
  if (!file.existsSync()) {
    throw Exception('Gavin system file not found at: ${file.absolute.path}');
  }
  final yamlStr = await file.readAsString();

  final system = await SystemLibraryResolver.loadSystemWithLibraries(
    yamlStr,
    fileLoader: (path) async {
      final f = File(path);
      if (f.existsSync()) {
        return await f.readAsString();
      }
      return '';
    },
  );

  return AuctionEngine.fromSystem(system);
}

class SimulatedAuctionResult {
  final List<String> auctionCalls;
  final String finalContract;
  final String? declarer;
  final bool isPassOut;

  SimulatedAuctionResult({
    required this.auctionCalls,
    required this.finalContract,
    this.declarer,
    this.isPassOut = false,
  });
}

String? _extractStrain(String call) {
  final upper = call.toUpperCase().replaceAll('!', '').trim();
  if (upper.contains('NT') || upper.endsWith('N')) return 'NT';
  if (upper.contains('S')) return 'S';
  if (upper.contains('H')) return 'H';
  if (upper.contains('D')) return 'D';
  if (upper.contains('C')) return 'C';
  return null;
}

int? _extractLevel(String call) {
  final clean = call.trim();
  if (clean.isEmpty) return null;
  return int.tryParse(clean[0]);
}

SimulatedAuctionResult simulateAuction({
  required Hand north,
  required Hand south,
  required AuctionEngine engine,
  required String dealer,
}) {
  final graph = engine.graph;
  final resolver = engine.resolver;
  final fragments = graph.system.fragments;

  final List<String> calls = [];
  final List<String> systemSequence = [];

  BiddingStateContext buildContext(Hand hand, String seat) {
    final history = calls.map((c) => AuctionEntry(seat: seat, call: c)).toList();
    return BiddingStateContext(
      holding: hand,
      auctionHistory: history,
      activeSeat: seat,
      valuation: resolver.valuation,
      vulnerability: engine.vulnerability,
    );
  }

  bool isNorthTurn = (dealer.toUpperCase() == 'N' || dealer.toUpperCase() == 'E');

  Hand currentHand = isNorthTurn ? north : south;
  String currentSeat = isNorthTurn ? 'N' : 'S';

  var bestBid = graph.rootState.resolveBestBid(
    currentHand,
    resolver,
    fragments: fragments,
    context: buildContext(currentHand, currentSeat),
  );

  if (bestBid == null || bestBid.isPass) {
    calls.add('Pass');
    isNorthTurn = !isNorthTurn;
    currentHand = isNorthTurn ? north : south;
    currentSeat = isNorthTurn ? 'N' : 'S';

    bestBid = graph.rootState.resolveBestBid(
      currentHand,
      resolver,
      fragments: fragments,
      context: buildContext(currentHand, currentSeat),
    );
    if (bestBid == null || bestBid.isPass) {
      calls.add('Pass');
      return SimulatedAuctionResult(
        auctionCalls: calls,
        finalContract: 'Pass',
        isPassOut: true,
      );
    }
  }

  calls.add(bestBid.displayCall);
  systemSequence.add(CompiledAuctionState.normalizeCallKey(bestBid.displayCall));

  int consecutivePasses = 0;
  String lastContract = bestBid.displayCall;
  final Map<String, String> strainFirstBidder = {};

  final initialStrain = _extractStrain(bestBid.displayCall);
  if (initialStrain != null) {
    strainFirstBidder[initialStrain] = currentSeat;
  }

  while (consecutivePasses < 2 && calls.length < 16) {
    isNorthTurn = !isNorthTurn;
    currentHand = isNorthTurn ? north : south;
    currentSeat = isNorthTurn ? 'N' : 'S';

    final state = graph.getState(systemSequence);
    if (state == null) {
      break;
    }

    final nextBid = state.resolveBestBid(
      currentHand,
      resolver,
      fragments: fragments,
      context: buildContext(currentHand, currentSeat),
    );
    if (nextBid == null || nextBid.isPass) {
      calls.add('Pass');
      break;
    } else {
      calls.add(nextBid.displayCall);
      systemSequence.add(CompiledAuctionState.normalizeCallKey(nextBid.displayCall));
      consecutivePasses = 0;
      lastContract = nextBid.displayCall;

      final strain = _extractStrain(nextBid.displayCall);
      if (strain != null && !strainFirstBidder.containsKey(strain)) {
        strainFirstBidder[strain] = currentSeat;
      }
    }
  }

  final finalStrain = _extractStrain(lastContract);
  final declarer = finalStrain != null ? strainFirstBidder[finalStrain] : null;

  return SimulatedAuctionResult(
    auctionCalls: calls,
    finalContract: lastContract,
    declarer: declarer,
    isPassOut: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Auto-bid 2025 BBO Hands Subset and Log Optimum Contract Gaps', () async {
    final datasetFile = File('res/bbo_championships_2025_dataset.json');
    expect(datasetFile.existsSync(), isTrue);

    final engine = await loadGavinEngine();
    final jsonContent = await datasetFile.readAsString();
    final List<dynamic> rawList = jsonDecode(jsonContent);

    // Filter a diverse subset of 40 unique deals where South has opening values (HCP >= 12)
    // or NS has game/partscore interest (Comb HCP >= 20)
    final List<dynamic> subset = [];
    final Set<String> seenDeals = {};
    for (final raw in rawList) {
      final dealStr = raw['deal'] as String? ?? '';
      if (dealStr.isEmpty || seenDeals.contains(dealStr)) continue;
      final hands = parseBboDeal(dealStr);
      final s = hands['S'];
      final n = hands['N'];
      if (s == null || n == null) continue;
      if (s.hcp >= 12 || (s.hcp + n.hcp) >= 20) {
        seenDeals.add(dealStr);
        subset.add(raw);
        if (subset.length >= 40) break;
      }
    }

    final StringBuffer logBuffer = StringBuffer();
    logBuffer.writeln('# 2025 BBO Championship Hands: Auto-Bidding & Optimum Audit\n');
    logBuffer.writeln('| # | Match & Board | South Hand | North Hand | Combined Values | Table Contract | Auto-Bid Auction | Auto Contract | Status & Flags |');
    logBuffer.writeln('|---|---|---|---|:---:|:---:|---|:---:|---|');

    final mlVal = MLHandValuation(strictEffectiveHcp: false);

    String formatFullHand(Hand h, double effHcp) {
      String suit(Suit s) {
        final str = h.cardsInSuit(s).map((c) => c.rank.symbol).join('');
        return str.isEmpty ? '—' : str;
      }
      return '♠${suit(Suit.spades)} ♥${suit(Suit.hearts)} ♦${suit(Suit.diamonds)} ♣${suit(Suit.clubs)}<br>(${h.hcp} HCP → ${effHcp.toStringAsFixed(1)} Eff)';
    }

    int totalEvaluated = 0;
    int optimumReached = 0;
    int flaggedCount = 0;
    final Map<String, int> flagSummary = {};

    for (int i = 0; i < subset.length; i++) {
      final raw = subset[i];
      final dealStr = raw['deal'] as String;
      final matchId = raw['match_id'] ?? 'N/A';
      final board = raw['board'] ?? 'N/A';
      final bboAuction = (raw['auction'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final tricksMade = raw['tricks_made'];

      // Extract BBO table contract
      String tableContract = 'Pass';
      for (int k = bboAuction.length - 1; k >= 0; k--) {
        final c = bboAuction[k].replaceAll('!', '').trim();
        if (c.toLowerCase() != 'p' && c.toLowerCase() != 'pass' && c.toLowerCase() != 'd' && c.toLowerCase() != 'rd') {
          tableContract = c.toUpperCase();
          break;
        }
      }

      final hands = parseBboDeal(dealStr);
      final south = hands['S']!;
      final north = hands['N']!;

      final southEff = mlVal.evaluatePoints(south);
      final northEff = mlVal.evaluatePoints(north);

      final combHcp = south.hcp + north.hcp;
      final combEff = southEff + northEff;
      final spadeFit = south.spadesLength + north.spadesLength;
      final heartFit = south.heartsLength + north.heartsLength;
      final hasMajorFit = (spadeFit >= 8 || heartFit >= 8);
      final bestMajor = spadeFit >= heartFit ? 'S' : 'H';
      final bestMajorFit = spadeFit >= heartFit ? spadeFit : heartFit;

      final startSeatMatch = RegExp(r'md\|(\d)').firstMatch(dealStr);
      final dealerSeatNum = startSeatMatch != null ? int.parse(startSeatMatch.group(1)!) : 1;
      final dealerOrder = ['S', 'W', 'N', 'E'];
      final dealer = dealerOrder[(dealerSeatNum - 1) % 4];

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: dealer,
      );

      final autoContract = sim.finalContract;
      final autoStrain = _extractStrain(autoContract);
      final autoLevel = _extractLevel(autoContract) ?? 0;

      // Determine Optimum and Flags
      final List<String> flags = [];

      // 1. Obvious Game Missed: Comb HCP >= 25 but stopped below game
      final isAutoGame = (autoLevel >= 4 && (autoStrain == 'S' || autoStrain == 'H')) ||
                         (autoLevel >= 3 && autoStrain == 'NT') ||
                         (autoLevel >= 5);
      if (combHcp >= 25 && !isAutoGame) {
        flags.add('MISSED_GAME');
      }

      // 2. Major Fit Strain Missed: 8+ Major fit, opening values, but played in minor/NT
      if ((south.hcp >= 12 && north.hcp >= 6) || (north.hcp >= 12 && south.hcp >= 6)) {
        if (hasMajorFit && bestMajorFit >= 8) {
          final isMajorStrain = (autoStrain == 'S' && spadeFit >= 8) || (autoStrain == 'H' && heartFit >= 8);
          if (!isMajorStrain && autoContract != 'Pass') {
            flags.add('MISSED_MAJOR_STRAIN_${bestMajor}${bestMajorFit}');
          }
        }
      }

      // 3. Overbid: Comb HCP <= 21, but bid to game
      if (combHcp <= 21 && isAutoGame) {
        flags.add('OVERBID_GAME');
      }

      // 4. Stalled Auction: Stopped at 1-level after 2 non-pass calls with game values
      if (combHcp >= 25 && autoLevel <= 1 && autoContract != 'Pass') {
        flags.add('AUCTION_STALLED_AT_1');
      }

      // 5. Premature Passout: Comb HCP >= 22 but passed out
      if (combHcp >= 22 && sim.isPassOut) {
        flags.add('PREMATURE_PASSOUT');
      }

      totalEvaluated++;
      String status;
      if (flags.isEmpty) {
        optimumReached++;
        status = '✅ OPTIMUM';
      } else {
        flaggedCount++;
        status = '🚩 ' + flags.join(', ');
        for (final f in flags) {
          flagSummary[f] = (flagSummary[f] ?? 0) + 1;
        }
      }

      final southDisplay = formatFullHand(south, southEff);
      final northDisplay = formatFullHand(north, northEff);
      final combDisplay = '**$combHcp HCP**<br>(${combEff.toStringAsFixed(1)} Eff)';
      final tableStr = '$tableContract (${tricksMade ?? "-"})';
      final auctionStr = sim.auctionCalls.join(' ');

      logBuffer.writeln('| ${i+1} | ${matchId} B:${board} | $southDisplay | $northDisplay | $combDisplay | $tableStr | `$auctionStr` | **$autoContract** | $status |');
    }

    final summaryHeader = StringBuffer();
    summaryHeader.writeln('## Summary Statistics');
    summaryHeader.writeln('- **Total Deals Evaluated**: $totalEvaluated');
    final optPct = (optimumReached / totalEvaluated * 100).toStringAsFixed(1);
    summaryHeader.writeln('- **Optimum Contracts Reached**: $optimumReached / $totalEvaluated ($optPct%)');
    summaryHeader.writeln('- **Deals Flagged**: $flaggedCount / $totalEvaluated\n');
    summaryHeader.writeln('### Flag Breakdown');
    flagSummary.forEach((k, v) {
      summaryHeader.writeln('- **$k**: $v');
    });
    summaryHeader.writeln('\n---\n');

    final fullReport = summaryHeader.toString() + logBuffer.toString();
    final outFile = File('bbo_2025_autobid_results.md');
    await outFile.writeAsString(fullReport);

    print('\n================================================================');
    print('  2025 BBO SUBSET AUTO-BID AUDIT FINISHED: ${optimumReached}/${totalEvaluated} ($optPct% optimum)');
    print('================================================================');
    print('Results saved to: ${outFile.absolute.path}');
  });
}
