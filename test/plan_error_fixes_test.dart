import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/board_exporter.dart';
import 'package:bridge_bidding_system/services/hand_review_service.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  test('Bridge Bidding Defect Planner scans and diagnoses unfixed error hands', () async {
    final errorDir = Directory('errors');
    if (!await errorDir.exists()) {
      print('No errors/ directory found. Skipping error hand scan.');
      return;
    }

    final errorService = HandReviewService(directory: errorDir);
    final allBoards = await errorService.listReviewBoards();
    final targetBoards = allBoards;
    print('Testing ${targetBoards.length} total error hands in ./errors/');

    if (targetBoards.isEmpty) {
      return;
    }

    // Load default Gavin Wolpert 2/1 system
    final systemFile = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    expect(systemFile.existsSync(), isTrue);

    final systemYaml = await systemFile.readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      systemYaml,
      fileLoader: (p) async => File(p).existsSync() ? await File(p).readAsString() : '',
    );

    final compiler = BiddingGraphCompiler(system: system);
    final graph = compiler.compile();
    final engine = AuctionEngine.fromSystem(system);

    for (final board in targetBoards) {
      print('\n=== Diagnosing ${board.filename} ===');
      print('Description: ${board.shortDescription}');
      print('Error Type : ${board.errorType ?? "Uncategorized"}');
      print('Notes      : ${board.longDescription}');

      final seats = ['N', 'E', 'S', 'W'];
      int seatIdx = seats.indexOf(board.dealer.toUpperCase());
      if (seatIdx == -1) seatIdx = 0;

      final history = <String>[];
      final recordedCalls = board.originalAuctionCalls;

      Hand getHandForSeat(String s) {
        switch (s) {
          case 'N': return board.deal.north;
          case 'E': return board.deal.east;
          case 'S': return board.deal.south;
          case 'W': return board.deal.west;
          default: return board.deal.north;
        }
      }

      for (int step = 0; step < (recordedCalls.isNotEmpty ? recordedCalls.length : 10); step++) {
        final currentSeat = seats[seatIdx];
        final currentHand = getHandForSeat(currentSeat);
        final state = graph.getState(history);

        if (state == null) {
          print('  [!] Graph terminated at [${history.join(" ")}]');
          break;
        }

        final evaluated = engine.resolver.evaluateCandidates(
          currentHand,
          state.candidateNodes,
          activeVariables: state.activeVariables,
          fragments: system.fragments,
        );

        if (evaluated.isEmpty) {
          print('  [DEFECT] At [${history.join(" ")}], Seat $currentSeat has no matching candidate!');
          print('    Hand: ${BoardExporter.handToPbn(currentHand)} (${currentHand.hcp} HCP)');
          break;
        }

        final selected = evaluated.first.node;
        print('  Step ${step + 1} ($currentSeat): ${selected.displayCall} (rule: ${selected.rule ?? "none"})');
        history.add(selected.displayCall.toLowerCase());

        if (history.length >= 3 &&
            history[history.length - 1] == 'pass' &&
            history[history.length - 2] == 'pass' &&
            history[history.length - 3] == 'pass') {
          break;
        }
        seatIdx = (seatIdx + 1) % 4;
      }
    }
  });
}
