import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/constraints/constraint_parser.dart';
import 'package:bridge_bidding_system/constraints/specificity_resolver.dart';

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

int _controls(Hand h) {
  int c = 0;
  for (final card in h.cards) {
    if (card.rank == Rank.ace) c += 2;
    if (card.rank == Rank.king) c += 1;
  }
  return c;
}

int _losingTrickCount(Hand h) {
  int ltc = 0;
  for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs]) {
    final cards = h.cardsInSuit(suit);
    final len = cards.length;
    if (len == 0) continue;
    if (len == 1) {
      if (cards.first.rank != Rank.ace) ltc += 1;
    } else if (len == 2) {
      final hasA = cards.any((c) => c.rank == Rank.ace);
      final hasK = cards.any((c) => c.rank == Rank.king);
      if (!hasA) ltc += 1;
      if (!hasK) ltc += 1;
    } else {
      final hasA = cards.any((c) => c.rank == Rank.ace);
      final hasK = cards.any((c) => c.rank == Rank.king);
      final hasQ = cards.any((c) => c.rank == Rank.queen);
      if (!hasA) ltc += 1;
      if (!hasK) ltc += 1;
      if (!hasQ) ltc += 1;
    }
  }
  return ltc;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Extract ML Edge Cases across Full 13,975 BBO Championship Dataset', () async {
    final datasetFile = File('res/bbo_championships_2025_dataset.json');
    expect(datasetFile.existsSync(), isTrue);

    final engine = await loadGavinEngine();
    final jsonContent = await datasetFile.readAsString();
    final List<dynamic> rawList = jsonDecode(jsonContent);

    print('Total deals available in raw dataset: ${rawList.length}');

    int totalDeals = 0;
    int edgeCaseGameInvites = 0;
    int edgeCaseSlamMarginals = 0;
    int validTricksCount = 0;

    final List<Map<String, dynamic>> edgeCaseRecords = [];

    final stopwatch = Stopwatch()..start();

    for (int i = 0; i < rawList.length; i++) {
      final raw = rawList[i];
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

      // Filter strictly for borderline edge cases:
      // 1. Game Invitations (22-25 HCP)
      // 2. Marginal Slams (29-32 HCP)
      final isGameInviteEdge = (combHcp >= 22 && combHcp <= 25);
      final isSlamMarginalEdge = (combHcp >= 29 && combHcp <= 32);

      if (!isGameInviteEdge && !isSlamMarginalEdge) {
        continue;
      }

      final dealer = (raw['dealer'] as String? ?? 'N');
      final vulStr = (raw['vulnerable'] as String? ?? 'None').toLowerCase();
      final isVul = vulStr.contains('both') ||
          (vulStr.contains('ns') && (dealer == 'N' || dealer == 'S'));

      final auctionRes = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: dealer,
      );

      if (auctionRes.isPassOut) continue;

      final contract = auctionRes.finalContract;
      final strain = _extractStrain(contract) ?? 'NT';
      final level = _extractLevel(contract) ?? 0;
      if (level == 0) continue;

      int strainCode = 0;
      if (strain == 'S') strainCode = 1;
      if (strain == 'H') strainCode = 2;
      if (strain == 'D') strainCode = 3;
      if (strain == 'C') strainCode = 4;

      final spadeLen = north.spadesLength + south.spadesLength;
      final heartLen = north.heartsLength + south.heartsLength;
      final diamondLen = north.diamondsLength + south.diamondsLength;
      final clubLen = north.clubsLength + south.clubsLength;
      final maxMajorFit = spadeLen >= heartLen ? spadeLen : heartLen;

      final isGame = (level >= 4 && (strain == 'S' || strain == 'H')) ||
          (level >= 3 && strain == 'NT') ||
          (level >= 5);

      final tricksMadeRaw = raw['tricks_made'];
      int? tricksMade;
      if (tricksMadeRaw is int) {
        tricksMade = tricksMadeRaw;
      } else if (tricksMadeRaw is String) {
        tricksMade = int.tryParse(tricksMadeRaw);
      }

      int? result;
      bool? isMake;
      if (tricksMade != null) {
        final targetTricks = 6 + level;
        result = tricksMade - targetTricks;
        isMake = result >= 0;
        validTricksCount++;
      }

      final controlsN = _controls(north);
      final controlsS = _controls(south);
      final ltcN = _losingTrickCount(north);
      final ltcS = _losingTrickCount(south);

      final record = <String, dynamic>{
        'deal_id': raw['match_id'],
        'board': raw['board'],
        'room': raw['room'] ?? 'Open',
        'type': isGameInviteEdge ? 'GAME_INVITE_EDGE_CASE' : 'SLAM_MARGINAL_EDGE_CASE',
        'comb_hcp': combHcp,
        'hcp_n': hcpN,
        'hcp_s': hcpS,
        'hcp_diff': (hcpN - hcpS).abs(),
        'controls_n': controlsN,
        'controls_s': controlsS,
        'comb_controls': controlsN + controlsS,
        'ltc_n': ltcN,
        'ltc_s': ltcS,
        'comb_ltc': ltcN + ltcS,
        'spade_fit': spadeLen,
        'heart_fit': heartLen,
        'diamond_fit': diamondLen,
        'club_fit': clubLen,
        'max_major_fit': maxMajorFit,
        'contract_level': level,
        'contract_strain': strain,
        'strain_code': strainCode,
        'is_game_target': isGame ? 1 : 0,
        'is_vulnerable': isVul ? 1 : 0,
        'simulated_contract': contract,
        'simulated_auction': auctionRes.auctionCalls,
        'tricks_made': tricksMade,
        'result': result,
        'made': isMake == true ? 1 : (isMake == false ? 0 : null),
      };

      if (isGameInviteEdge) edgeCaseGameInvites++;
      if (isSlamMarginalEdge) edgeCaseSlamMarginals++;
      edgeCaseRecords.add(record);
    }

    stopwatch.stop();

    print('\n================================================================');
    print('      GAVIN WOLPERT FULL DATASET EXTRACTION SUMMARY             ');
    print('================================================================');
    print('Total Deals Evaluated:      $totalDeals / ${rawList.length}');
    print('Elapsed Time:               ${stopwatch.elapsedMilliseconds} ms');
    print('Borderline Game Invites:    $edgeCaseGameInvites deals (22-25 HCP)');
    print('Marginal Slam Decisions:    $edgeCaseSlamMarginals deals (29-32 HCP)');
    print('Total Edge Cases Extracted: ${edgeCaseRecords.length}');
    print('Deals with Verified Tricks: $validTricksCount');
    print('================================================================\n');

    final fullDatasetFile = File('res/gavin_ml_edge_cases_full.json');
    await fullDatasetFile.writeAsString(jsonEncode(edgeCaseRecords));
    print('Saved full edge cases dataset to: ${fullDatasetFile.path}');

    expect(edgeCaseRecords.length, greaterThan(1000), reason: 'Should extract at least 1,000 edge cases from 13,975 deals');
  });
}
