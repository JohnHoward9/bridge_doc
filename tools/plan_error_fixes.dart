import 'dart:io';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/board_exporter.dart';
import 'package:bridge_bidding_system/services/hand_review_service.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

Future<void> main([List<String> args = const []]) async {
  final targetFile = args.isNotEmpty ? args.first : null;
  final errorDir = Directory('errors');

  if (!await errorDir.exists()) {
    print('No errors/ directory found.');
    return;
  }

  final errorService = HandReviewService(directory: errorDir);
  final allBoards = await errorService.listReviewBoards();

  final unfixedBoards = targetFile != null
      ? allBoards.where((b) => b.filename == targetFile || b.filePath == targetFile).toList()
      : allBoards.where((b) => !b.isFixed).toList();

  if (unfixedBoards.isEmpty) {
    print('No unfixed error hands found in ./errors/');
    return;
  }

  print('================================================================');
  print('     BRIDGE BIDDING DEFECT PLANNER & DIAGNOSTICS (${unfixedBoards.length} Hand${unfixedBoards.length > 1 ? 's' : ''})     ');
  print('================================================================\n');

  // Load default Gavin Wolpert 2/1 system
  final systemFile = File('assets/core/systems/gavin_wolpert_2over1.yaml');
  if (!await systemFile.exists()) {
    print('Error: System file not found: ${systemFile.path}');
    return;
  }

  final systemYaml = await systemFile.readAsString();
  final system = await SystemLibraryResolver.loadSystemWithLibraries(
    systemYaml,
    fileLoader: (p) async => File(p).existsSync() ? await File(p).readAsString() : '',
  );

  final compiler = BiddingGraphCompiler(system: system);
  final graph = compiler.compile();
  final engine = AuctionEngine.fromSystem(system);

  for (int i = 0; i < unfixedBoards.length; i++) {
    final board = unfixedBoards[i];
    print('--- [Hand ${i + 1}/${unfixedBoards.length}] ${board.filename} ---');
    print('Description : ${board.shortDescription}');
    print('Error Type  : ${board.errorType ?? "Uncategorized"}');
    print('Dealer      : ${board.dealer} | Vul: ${board.vulnerable}');
    if (board.longDescription.isNotEmpty) {
      print('Notes       : ${board.longDescription}');
    }

    print('\nHands:');
    print('  North: ${BoardExporter.handToPbn(board.deal.north)} (HCP: ${board.deal.north.hcp})');
    print('  East : ${BoardExporter.handToPbn(board.deal.east)} (HCP: ${board.deal.east.hcp})');
    print('  South: ${BoardExporter.handToPbn(board.deal.south)} (HCP: ${board.deal.south.hcp})');
    print('  West : ${BoardExporter.handToPbn(board.deal.west)} (HCP: ${board.deal.west.hcp})');

    final recordedCalls = board.originalAuctionCalls;
    if (recordedCalls.isNotEmpty) {
      print('\nRecorded Auction: ${recordedCalls.join(" ")}');
    }

    // Step through auction simulation
    print('\nSimulation & Diagnosis:');
    final seats = ['N', 'E', 'S', 'W'];
    int seatIdx = seats.indexOf(board.dealer.toUpperCase());
    if (seatIdx == -1) seatIdx = 0;

    final history = <String>[];
    bool defectFound = false;

    Hand getHandForSeat(String s) {
      switch (s) {
        case 'N': return board.deal.north;
        case 'E': return board.deal.east;
        case 'S': return board.deal.south;
        case 'W': return board.deal.west;
        default: return board.deal.north;
      }
    }

    final maxSteps = recordedCalls.isNotEmpty ? recordedCalls.length : 12;

    for (int step = 0; step < maxSteps; step++) {
      final currentSeat = seats[seatIdx];
      final currentHand = getHandForSeat(currentSeat);
      final state = graph.getState(history);

      if (state == null) {
        print('  [!] Graph terminated at sequence [${history.join(" ")}] (no continuation node)');
        defectFound = true;
        break;
      }

      final candidates = state.candidateNodes;
      final evaluated = engine.resolver.evaluateCandidates(
        currentHand,
        candidates,
        activeVariables: state.activeVariables,
        fragments: system.fragments,
      );

      final expectedCall = step < recordedCalls.length ? recordedCalls[step].toLowerCase() : null;

      if (evaluated.isEmpty) {
        print('  [DEFECT] At [${history.join(" ")}], Seat $currentSeat has NO matching candidate rule!');
        print('    Hand: ${BoardExporter.handToPbn(currentHand)} (${currentHand.hcp} HCP)');
        print('    Available bids in graph: ${candidates.map((c) => c.call).join(", ")}');
        defectFound = true;
        break;
      }

      final selectedCandidate = evaluated.first.node;
      final selectedCall = selectedCandidate.displayCall.toLowerCase();

      print('  Step ${step + 1} ($currentSeat): Bot chose $selectedCall (Rule: "${selectedCandidate.rule ?? 'none'}")');

      if (expectedCall != null && expectedCall != selectedCall && expectedCall != 'pass') {
        print('    [NOTE] Discrepancy: Recorded auction had "$expectedCall", engine selected "$selectedCall"');
      }

      history.add(selectedCall);

      if (history.length >= 3 &&
          history[history.length - 1] == 'pass' &&
          history[history.length - 2] == 'pass' &&
          history[history.length - 3] == 'pass') {
        print('  Auction passed out at: ${history.join(" ")}');
        break;
      }

      seatIdx = (seatIdx + 1) % 4;
    }

    if (!defectFound && recordedCalls.isEmpty) {
      print('  Simulation finished without node collapse.');
    }
    print('\n================================================================\n');
  }
}
