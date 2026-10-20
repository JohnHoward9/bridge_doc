import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/constraints/specificity_resolver.dart';

Map<String, Hand> parseBboDeal(String dealStr) {
  final match = RegExp(r'md\|(\d)([^\|]+)\|').firstMatch(dealStr);
  if (match == null) return {};
  final startSeat = int.parse(match.group(1)!); // 1=S, 2=W, 3=N, 4=E
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

  bool isNorthTurn = (dealer.toUpperCase() == 'N' || dealer.toUpperCase() == 'E');

  Hand currentHand = isNorthTurn ? north : south;
  String currentSeat = isNorthTurn ? 'N' : 'S';

  var bestBid = graph.rootState.resolveBestBid(currentHand, resolver, fragments: fragments);

  if (bestBid == null || bestBid.isPass) {
    calls.add('Pass');
    isNorthTurn = !isNorthTurn;
    currentHand = isNorthTurn ? north : south;
    currentSeat = isNorthTurn ? 'N' : 'S';

    bestBid = graph.rootState.resolveBestBid(currentHand, resolver, fragments: fragments);
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

    final nextBid = state.resolveBestBid(currentHand, resolver, fragments: fragments);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Gavin Wolpert 2/1 System Audit on 2025 BBO Championship Deals', () async {
    final datasetFile = File('res/bbo_championships_2025_dataset.json');
    expect(datasetFile.existsSync(), isTrue, reason: 'Dataset file must exist');

    final engine = await loadGavinEngine();
    expect(engine.graph.stateCount, greaterThan(20));

    final jsonContent = await datasetFile.readAsString();
    final List<dynamic> rawList = jsonDecode(jsonContent);

    const int auditLimit = 500;
    int totalDeals = 0;
    int majorFitDeals = 0;
    int majorFitInMajor = 0;

    int obviousGameDeals = 0; // >= 26 HCP with fit or balanced
    int obviousGameReached = 0;

    int obviousSlamDeals = 0; // >= 33 HCP
    int obviousSlamReached = 0;

    int obviousPartscoreDeals = 0; // <= 21 HCP
    int obviousPartscoreStopped = 0;

    int edgeCaseGameInvites = 0; // 22-25 HCP
    int edgeCaseSlamMarginals = 0; // 29-32 HCP

    final List<String> failedObviousGameExamples = [];
    final List<String> failedMajorStrainExamples = [];
    final List<Map<String, dynamic>> edgeCaseRecords = [];

    for (final raw in rawList) {
      if (totalDeals >= auditLimit) break;
      final dealStr = raw['deal'] as String? ?? '';
      if (dealStr.isEmpty) continue;

      final hands = parseBboDeal(dealStr);
      final north = hands['N'];
      final south = hands['S'];
      if (north == null || south == null) continue;

      totalDeals++;

      final hcpN = north.hcp;
      final hcpS = south.hcp;
      final combHcp = hcpN + hcpS;

      final spadeLen = north.spadesLength + south.spadesLength;
      final heartLen = north.heartsLength + south.heartsLength;
      final hasMajorFit = (spadeLen >= 8 || heartLen >= 8);
      final bestMajor = spadeLen >= heartLen ? 'S' : 'H';
      final bestMajorLen = spadeLen >= heartLen ? spadeLen : heartLen;

      final dealer = (raw['dealer'] as String? ?? 'N');
      final auctionRes = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: dealer,
      );

      final contract = auctionRes.finalContract;
      final strain = _extractStrain(contract);
      final level = _extractLevel(contract) ?? 0;

      // 1. Strain Correctness Audit (Where at least one hand opens and partner has responding values >= 6 HCP)
      final hasOpeningAndRespondingValues =
          (hcpN >= 12 && hcpS >= 6) || (hcpS >= 12 && hcpN >= 6);
      if (hasOpeningAndRespondingValues && hasMajorFit && bestMajorLen >= 8) {
        majorFitDeals++;
        if (strain == bestMajor || (strain == 'S' && spadeLen >= 8) || (strain == 'H' && heartLen >= 8)) {
          majorFitInMajor++;
        } else {
          failedMajorStrainExamples.add(
            'CombHCP=$combHcp (N=$hcpN, S=$hcpS), Spades(N=${north.spadesLength}, S=${south.spadesLength}), Hearts(N=${north.heartsLength}, S=${south.heartsLength}) -> '
            'Auction: [${auctionRes.auctionCalls.join(" ")}] -> Contract: $contract'
          );
        }
      }

      // 2. Obvious Game Audit (>= 26 HCP)
      if (combHcp >= 26) {
        obviousGameDeals++;
        final isGame = (level >= 4 && (strain == 'S' || strain == 'H')) ||
            (level >= 3 && strain == 'NT') ||
            (level >= 5);
        if (isGame) {
          obviousGameReached++;
        } else if (failedObviousGameExamples.length < 8) {
          failedObviousGameExamples.add(
            'CombHCP=$combHcp (N=$hcpN, S=$hcpS), Fit(S=$spadeLen, H=$heartLen) -> '
            'Auction: [${auctionRes.auctionCalls.join(" ")}] -> Contract: $contract',
          );
        }
      }

      // 3. Obvious Slam Audit (>= 33 HCP)
      if (combHcp >= 33) {
        obviousSlamDeals++;
        if (level >= 6) {
          obviousSlamReached++;
        } else {
          print('SLAM GAP: CombHCP=$combHcp Auction: [${auctionRes.auctionCalls.join(" ")}] -> Contract: $contract');
        }
      }

      // 4. Obvious Partscore Audit (<= 21 HCP)
      if (combHcp <= 21 && !auctionRes.isPassOut) {
        obviousPartscoreDeals++;
        if (level <= 3) {
          obviousPartscoreStopped++;
        }
      }

      // 5. Partition Edge Cases for ML
      if (combHcp >= 22 && combHcp <= 25) {
        edgeCaseGameInvites++;
        edgeCaseRecords.add({
          'deal_id': raw['match_id'],
          'board': raw['board'],
          'type': 'GAME_INVITE_EDGE_CASE',
          'comb_hcp': combHcp,
          'hcp_n': hcpN,
          'hcp_s': hcpS,
          'spade_fit': spadeLen,
          'heart_fit': heartLen,
          'simulated_contract': contract,
          'simulated_auction': auctionRes.auctionCalls,
          'tricks_made': raw['tricks_made'],
        });
      } else if (combHcp >= 29 && combHcp <= 32) {
        edgeCaseSlamMarginals++;
        edgeCaseRecords.add({
          'deal_id': raw['match_id'],
          'board': raw['board'],
          'type': 'SLAM_MARGINAL_EDGE_CASE',
          'comb_hcp': combHcp,
          'hcp_n': hcpN,
          'hcp_s': hcpS,
          'spade_fit': spadeLen,
          'heart_fit': heartLen,
          'simulated_contract': contract,
          'simulated_auction': auctionRes.auctionCalls,
          'tricks_made': raw['tricks_made'],
        });
      }
    }

    final edgeCaseFile = File('res/gavin_ml_edge_cases.json');
    await edgeCaseFile.writeAsString(jsonEncode(edgeCaseRecords));

    print('\n================================================================');
    print('      GAVIN WOLPERT SYSTEM AUDIT SCORECARD (500 BBO DEALS)      ');
    print('================================================================');
    print('Total Deals Evaluated: $totalDeals\n');

    final strainPct = majorFitDeals > 0 ? (majorFitInMajor / majorFitDeals * 100).toStringAsFixed(1) : '100';
    print('1. MAJOR STRAIN ACCURACY (8+ Major Fits with 18+ HCP):');
    print('   $majorFitInMajor / $majorFitDeals ($strainPct% success)');
    if (failedMajorStrainExamples.isNotEmpty) {
      print('   All Major Strain Gaps (${failedMajorStrainExamples.length} total):');
      for (final ex in failedMajorStrainExamples) {
        print('     * $ex');
      }
    }

    final gamePct = obviousGameDeals > 0 ? (obviousGameReached / obviousGameDeals * 100).toStringAsFixed(1) : '100';
    print('\n2. OBVIOUS GAME RATE (Combined HCP >= 26):');
    print('   $obviousGameReached / $obviousGameDeals ($gamePct% reached game)');
    if (failedObviousGameExamples.isNotEmpty) {
      print('   Sample Rule Gaps (stopped before game):');
      for (final ex in failedObviousGameExamples) {
        print('     * $ex');
      }
    }

    final slamPct = obviousSlamDeals > 0 ? (obviousSlamReached / obviousSlamDeals * 100).toStringAsFixed(1) : '100';
    print('\n3. OBVIOUS SLAM RATE (Combined HCP >= 33):');
    print('   $obviousSlamReached / $obviousSlamDeals ($slamPct% reached slam)');

    final partPct = obviousPartscoreDeals > 0 ? (obviousPartscoreStopped / obviousPartscoreDeals * 100).toStringAsFixed(1) : '100';
    print('\n4. OBVIOUS PARTSCORE STOPS (Combined HCP <= 21):');
    print('   $obviousPartscoreStopped / $obviousPartscoreDeals ($partPct% stopped in <= 3-level)');

    print('\n================================================================');
    print('               ISOLATED EDGE CASES FOR MACHINE LEARNING         ');
    print('================================================================');
    print('• Borderline Game Invitations (22-25 HCP): $edgeCaseGameInvites deals');
    print('• Marginal Slam Judgments (29-32 HCP):     $edgeCaseSlamMarginals deals');
    print('• Total Edge-Case Training Samples:        ${edgeCaseRecords.length} deals');
    print('  -> Saved to: ${edgeCaseFile.path}');
    print('================================================================\n');

    expect(totalDeals, equals(auditLimit));
  });
}
