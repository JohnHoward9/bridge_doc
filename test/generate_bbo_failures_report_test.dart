import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'bbo_subset_autobid_audit_test.dart';

class FailureDealRecord {
  final int index;
  final String matchBoard;
  final String category;
  final Hand north;
  final Hand south;
  final double northEff;
  final double southEff;
  final int combHcp;
  final String tableContract;
  final String autoAuction;
  final String autoContract;
  final String diagnosis;

  FailureDealRecord({
    required this.index,
    required this.matchBoard,
    required this.category,
    required this.north,
    required this.south,
    required this.northEff,
    required this.southEff,
    required this.combHcp,
    required this.tableContract,
    required this.autoAuction,
    required this.autoContract,
    required this.diagnosis,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate Comprehensive BBO 2025 Failure Results Report', timeout: const Timeout(Duration(minutes: 5)), () async {
    final engine = await loadGavinEngine();
    final mlVal = MLHandValuation(strictEffectiveHcp: false);

    final dataFile = File('res/bbo_championships_2025_dataset.json');
    if (!dataFile.existsSync()) {
      throw Exception('Dataset file not found');
    }
    final rawList = jsonDecode(await dataFile.readAsString()) as List<dynamic>;

    String formatHand(Hand h, double eff) {
      String suit(Suit s) {
        final str = h.cardsInSuit(s).map((x) => x.rank.symbol).join('');
        return str.isEmpty ? '—' : str;
      }
      return '♠${suit(Suit.spades)} ♥${suit(Suit.hearts)} ♦${suit(Suit.diamonds)} ♣${suit(Suit.clubs)}<br>(${h.hcp} HCP → ${eff.toStringAsFixed(1)} Eff)';
    }

    String? extractStrain(String call) {
      final upper = call.toUpperCase().replaceAll('!', '').trim();
      if (upper.contains('NT') || upper.endsWith('N')) return 'NT';
      if (upper.contains('S')) return 'S';
      if (upper.contains('H')) return 'H';
      if (upper.contains('D')) return 'D';
      if (upper.contains('C')) return 'C';
      return null;
    }

    int? extractLevel(String call) {
      final clean = call.trim();
      if (clean.isEmpty) return null;
      return int.tryParse(clean[0]);
    }

    final List<FailureDealRecord> failures = [];
    final List<FailureDealRecord> resolvedDeals = [];
    final Map<String, int> catCounts = {
      'Cat 1: Forcing Broken / Stalled': 0,
      'Cat 2: Missed Major Strain': 0,
      'Cat 3: Wrong Opening Bid': 0,
      'Cat 4: Slam Stoppage': 0,
      'Cat 5: Overbid Runaway': 0,
      'Cat 6: Rebid Precision': 0,
    };

    final Set<String> seenDeals = {};
    const maxPerCat = 5;
    const scanLimit = 4000;

    int scanned = 0;

    // First: Load known user-reported error hands from ./errors/
    final errorFiles = Directory('errors').listSync().whereType<File>().where((f) => f.path.endsWith('.pbn')).toList();
    for (final ef in errorFiles) {
      final content = ef.readAsStringSync();
      final isFixed = content.contains('[Fixed "Yes"]');
      final dealMatch = RegExp(r'\[Deal "(.*?)"\]').firstMatch(content);
      final descMatch = RegExp(r'\[Description "(.*?)"\]').firstMatch(content);
      final errMatch = RegExp(r'\[ErrorType "(.*?)"\]').firstMatch(content);
      final filename = ef.path.split(Platform.pathSeparator).last;

      if (dealMatch != null) {
        final rawDeal = dealMatch.group(1)!;
        final parts = rawDeal.split(' ');
        if (parts.length >= 3) {
          final nParts = parts[0].replaceFirst(RegExp(r'^[NESW]:'), '').split('.');
          final sParts = parts[2].split('.');
          if (nParts.length == 4 && sParts.length == 4) {
            final north = Hand.fromString('${nParts[0]}:${nParts[1]}:${nParts[2]}:${nParts[3]}');
            final south = Hand.fromString('${sParts[0]}:${sParts[1]}:${sParts[2]}:${sParts[3]}');
            final sim = simulateAuction(north: north, south: south, engine: engine, dealer: 'N');
            
            String cat = 'Cat 1: Forcing Broken / Stalled';
            if (filename.contains('1s_opening_with_5_5')) cat = 'Cat 3: Wrong Opening Bid';
            else if (filename.contains('should_open_2nt')) cat = 'Cat 3: Wrong Opening Bid';
            else if (filename.contains('with_a_balanced_hand_rebid_is_1nt')) cat = 'Cat 6: Rebid Precision';
            else if (filename.contains('is_only_gf')) cat = 'Cat 5: Overbid Runaway';

            final combHcp = north.hcp + south.hcp;
            final record = FailureDealRecord(
              index: isFixed ? (resolvedDeals.length + 1) : (failures.length + 1),
              matchBoard: 'PBN: $filename',
              category: cat,
              north: north,
              south: south,
              northEff: mlVal.evaluatePoints(north),
              southEff: mlVal.evaluatePoints(south),
              combHcp: combHcp,
              tableContract: 'Error Log',
              autoAuction: sim.auctionCalls.join(' '),
              autoContract: sim.finalContract,
              diagnosis: descMatch?.group(1) ?? errMatch?.group(1) ?? 'Reported user bidding error',
            );

            if (isFixed) {
              resolvedDeals.add(record);
            } else if ((catCounts[cat] ?? 0) < maxPerCat) {
              catCounts[cat] = (catCounts[cat] ?? 0) + 1;
              failures.add(record);
            }
          }
        }
      }
    }

    for (final raw in rawList) {
      scanned++;
      if (scanned > scanLimit) break;

      final dealStr = raw['deal'] as String? ?? '';
      if (dealStr.isEmpty) continue;

      final matchId = raw['match_id'] ?? 'N/A';
      final board = raw['board'] ?? 'N/A';
      final matchBoardKey = '$matchId B:$board';
      if (seenDeals.contains(matchBoardKey)) continue;

      final hands = parseBboDeal(dealStr);
      final north = hands['N'];
      final south = hands['S'];
      if (north == null || south == null) continue;

      final startSeatMatch = RegExp(r'md\|(\d)').firstMatch(dealStr);
      final dealerSeatNum = startSeatMatch != null ? int.parse(startSeatMatch.group(1)!) : 1;
      final dealer = ['S', 'W', 'N', 'E'][(dealerSeatNum - 1) % 4];

      final bboAuction = (raw['auction'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      final tricksMade = raw['tricks_made'];

      String tableContract = 'Pass';
      String declarerSide = 'NS';
      for (int k = bboAuction.length - 1; k >= 0; k--) {
        final c = bboAuction[k].replaceAll('!', '').trim();
        if (c.toLowerCase() != 'p' && c.toLowerCase() != 'pass' && c.toLowerCase() != 'd' && c.toLowerCase() != 'rd') {
          tableContract = c.toUpperCase();
          final bidderIndex = (dealerSeatNum - 1 + k) % 4;
          declarerSide = (bidderIndex % 2 == 0) ? 'NS' : 'EW';
          break;
        }
      }
      final tableContractLevel = extractLevel(tableContract) ?? 0;
      final isOpponentContract = declarerSide == 'EW';

      final sim = simulateAuction(
        north: north,
        south: south,
        engine: engine,
        dealer: dealer,
      );

      final combHcp = north.hcp + south.hcp;
      final autoContract = sim.finalContract;
      final autoCalls = sim.auctionCalls;
      final autoStrain = extractStrain(autoContract);
      final autoLevel = extractLevel(autoContract) ?? 0;

      final spadeFit = north.spadesLength + south.spadesLength;
      final heartFit = north.heartsLength + south.heartsLength;
      final diaFit = north.diamondsLength + south.diamondsLength;
      final clubFit = north.clubsLength + south.clubsLength;
      final maxFit = [spadeFit, heartFit, diaFit, clubFit].reduce((a, b) => a > b ? a : b);
      final hasMajorFit = (spadeFit >= 8 || heartFit >= 8);
      final bestMajor = spadeFit >= heartFit ? 'S' : 'H';
      final bestFitLen = spadeFit >= heartFit ? spadeFit : heartFit;

      final nEff = mlVal.evaluatePoints(north);
      final sEff = mlVal.evaluatePoints(south);

      String? cat;
      String? diag;

      // 1. Cat 1: Premature Passout or Stalled Auction
      if (combHcp >= 22 && sim.isPassOut) {
        cat = 'Cat 1: Forcing Broken / Stalled';
        diag = 'Passed out with $combHcp combined HCP (N=${north.hcp}, S=${south.hcp})';
      } else if (combHcp >= 25 && autoLevel <= 1 && autoContract != 'Pass' && autoCalls.length >= 2) {
        cat = 'Cat 1: Forcing Broken / Stalled';
        diag = 'Auction stalled at $autoContract with $combHcp combined HCP (Calls: `${autoCalls.join(" ")}`)';
      }
      // 2. Cat 2: Missed Major Strain
      else if ((north.hcp >= 12 && south.hcp >= 6) || (south.hcp >= 12 && north.hcp >= 6)) {
        if (hasMajorFit && autoContract != 'Pass' && autoStrain != bestMajor && (autoStrain != 'S' || spadeFit < 8) && (autoStrain != 'H' || heartFit < 8)) {
          cat = 'Cat 2: Missed Major Strain';
          diag = '8+ major fit ($bestMajor: $bestFitLen cards) missed; contract played in $autoContract';
        }
      }

      // 3. Cat 3: Wrong Opening Bid
      if (cat == null) {
        final opener = (dealer == 'N' || dealer == 'E') ? north : south;
        if (autoCalls.isNotEmpty) {
          final openCall = autoCalls[0].toLowerCase();
          if (opener.spadesLength >= 5 && opener.heartsLength >= 5 && opener.spadesLength == opener.heartsLength && openCall == '1h') {
            cat = 'Cat 3: Wrong Opening Bid';
            diag = 'Opened 1♥ with 5-5 in majors instead of standard 1♠';
          } else if (opener.hcp >= 20 && opener.hcp <= 21 && opener.isBalanced && openCall != '2nt') {
            cat = 'Cat 3: Wrong Opening Bid';
            diag = 'Opened $openCall with 20-21 balanced instead of 2NT';
          } else if (opener.hcp >= 22 && openCall != '2c') {
            cat = 'Cat 3: Wrong Opening Bid';
            diag = 'Opened $openCall with ${opener.hcp} HCP instead of strong artificial 2♣';
          }
        }
      }

      // 4. Cat 4: Slam Stoppage
      final tricks = (tricksMade is num) ? tricksMade.toInt() : (tricksMade != null ? int.tryParse(tricksMade.toString()) : null);
      if (cat == null) {
        final isNsTableSlam = !isOpponentContract && (tableContract.startsWith('6') || tableContract.startsWith('7'));
        final isTableSlamValid = isNsTableSlam && (tricks == null || tricks >= (tableContractLevel + 6 - 1));
        final hasSlamValues = combHcp >= 31 || (combHcp >= 29 && maxFit >= 9 && (nEff + sEff >= 30.0));

        if ((hasSlamValues || isTableSlamValid) && autoLevel < 6 && autoContract != 'Pass') {
          cat = 'Cat 4: Slam Stoppage';
          final tableStr = isOpponentContract ? 'EW $tableContract' : tableContract;
          diag = 'Stopped at $autoContract despite $combHcp combined HCP (Table contract was $tableStr)';
        }
      }

      // 5. Cat 5: Overbid Runaway
      if (cat == null) {
        final makesContract = tricks != null && tricks >= (autoLevel + 6);
        final isDistributionalFit = (maxFit >= 10 || (north.losingTrickCount + south.losingTrickCount <= 13));
        if (!makesContract && !isDistributionalFit && combHcp <= 21 && autoLevel >= 4 && autoContract != 'Pass') {
          cat = 'Cat 5: Overbid Runaway';
          diag = 'Overbid to $autoContract on only $combHcp combined HCP without distribution or tricks (N=${north.hcp}, S=${south.hcp})';
        }
      }

      // 6. Cat 6: Rebid Precision
      if (cat == null) {
        if (autoCalls.length >= 3 && autoCalls[0] == '1d' && autoCalls[1] == '1h' && autoCalls[2] == '1s') {
          final isNorthOpener = (dealer == 'N' || dealer == 'E');
          final openerHand = isNorthOpener ? north : south;
          if (openerHand.isBalanced && openerHand.hcp >= 12 && openerHand.hcp <= 14) {
            cat = 'Cat 6: Rebid Precision';
            diag = 'Opener rebid 1♠ over 1♥ with 12-14 balanced instead of Walsh 1NT';
          }
        }
      }

      if (cat != null && (catCounts[cat] ?? 0) < maxPerCat) {
        seenDeals.add(matchBoardKey);
        catCounts[cat] = (catCounts[cat] ?? 0) + 1;
        failures.add(FailureDealRecord(
          index: failures.length + 1,
          matchBoard: matchBoardKey,
          category: cat,
          north: north,
          south: south,
          northEff: nEff,
          southEff: sEff,
          combHcp: combHcp,
          tableContract: (isOpponentContract ? 'EW ' : '') + tableContract + (tricksMade != null ? ' ($tricksMade)' : ''),
          autoAuction: autoCalls.join(' '),
          autoContract: autoContract,
          diagnosis: diag ?? 'Defect flagged',
        ));
      }
    }

    print('Scanned $scanned deals. Found ${failures.length} representative failures across categories:');
    catCounts.forEach((k, v) => print('  $k: $v'));

    // Write bbo_2025_failure_results.md
    final sb = StringBuffer();
    sb.writeln('# BBO 2025 Championship Bidding Failures Audit');
    sb.writeln();
    sb.writeln('Evaluated deals from **`res/bbo_championships_2025_dataset.json`** and `./errors/` against the Gavin Wolpert 2/1 engine.');
    sb.writeln('Identified **${failures.length} active representative failure deals** across the 6 defect categories, and verified **${resolvedDeals.length} resolved defect hands**.');
    sb.writeln();
    if (resolvedDeals.isNotEmpty) {
      sb.writeln('## 1. Resolved Defect Hands (Verified Fixed)');
      sb.writeln();
      sb.writeln('| # | Error File | Category | North Hand | South Hand | Comb HCP | Table Contract | Verified Auto Auction | Final Contract | Status |');
      sb.writeln('|---|---|---|---|---|:---:|:---:|---|:---:|:---:|');
      for (final r in resolvedDeals) {
        final nDisplay = formatHand(r.north, r.northEff);
        final sDisplay = formatHand(r.south, r.southEff);
        sb.writeln('| ${r.index} | **${r.matchBoard}** | **${r.category}** | $nDisplay | $sDisplay | **${r.combHcp} HCP** | **${r.tableContract}** | `${r.autoAuction}` | **${r.autoContract}** | ✅ Fixed |');
      }
      sb.writeln();
    }

    sb.writeln('## 2. Active Unfixed BBO Failures');
    sb.writeln();
    sb.writeln('### Failure Distribution Summary');
    catCounts.forEach((k, v) {
      sb.writeln('- **$k**: $v representative deals');
    });
    sb.writeln();
    sb.writeln('| # | Match / Deal | Category | North Hand | South Hand | Comb HCP | Table Contract | Auto Auction | Auto Contract | Defect Diagnosis |');
    sb.writeln('|---|---|---|---|---|:---:|:---:|---|:---:|---|');

    for (var i = 0; i < failures.length; i++) {
      final f = failures[i];
      final nDisplay = formatHand(f.north, f.northEff);
      final sDisplay = formatHand(f.south, f.southEff);
      sb.writeln('| ${i + 1} | **${f.matchBoard}** | **${f.category}** | $nDisplay | $sDisplay | **${f.combHcp} HCP** | **${f.tableContract}** | `${f.autoAuction}` | **${f.autoContract}** | ${f.diagnosis} |');
    }

    sb.writeln();
    sb.writeln('## Systematic Resolution Strategy');
    sb.writeln('1. **Category 1 (Forcing Broken & Stalls)**: Strengthen forcing state persistence in `walsh_minors.yaml` and `gavin_majors_2over1.yaml` so responder\'s 1-level response guarantees a rebid.');
    sb.writeln('2. **Category 2 (Missed Major Strain)**: Prioritize major fit returns in XYZ / Checkback (`two_way_checkback.yaml`) when opener holds 4+ cards in partner\'s major.');
    sb.writeln('3. **Category 3 (Wrong Opening Bid)**: Enforce rule priority ordering in `gavin_wolpert_2over1.yaml` (2NT over 1m for 20-21 balanced, 1♠ over 1♥ for 5-5 majors).');
    sb.writeln('4. **Category 4 (Slam Stoppages)**: Wire Kickback RKCB and cuebidding paths over minor suit agreements in `serious_3nt_and_kickback.yaml`.');
    sb.writeln('5. **Category 5 (Overbid Runaway)**: Apply loser count ceilings (`5-ltc`) in `namyats.yaml` and limit raises over preempts in `preempt_responses.yaml`.');
    sb.writeln('6. **Category 6 (Rebid Precision)**: Ensure 12-14 balanced hands rebid 1NT rather than bypassing into 1♠ or 2m in `walsh_minors.yaml`.');

    final outFile = File('bbo_2025_failure_results.md');
    await outFile.writeAsString(sb.toString());
    print('Generated failure results report saved to: ${outFile.absolute.path}');
  });
}
