import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CompiledBiddingGraph graph;

  setUpAll(() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    final yamlStr = await file.readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async => File(path).existsSync() ? await File(path).readAsString() : '',
    );

    final compiler = BiddingGraphCompiler(system: system);
    graph = compiler.compile();
  });

  group('Unusual 2NT and Michaels Continuations & Defense Tests', () {
    test('1. Partnership Unusual 2NT over 1S: Advancer preferences and Overcaller rebids', () {
      final seq2nt = graph.sequenceIndex['(1s):2nt'];
      expect(seq2nt, isNotNull, reason: 'Sequence (1s):2nt must exist in graph');
      final calls = seq2nt!.candidateNodes.map((n) => n.call).toList();

      // Advancer options: pass, 3c, 3d, 3h, 3s, 3nt, 4c, 4d, 5c, 5d
      expect(calls, containsAll(['3c', '3d', '4c', '4d', '5c', '5d', 'pass']));

      // Overcaller rebids after advancer 3C preference: (1s):2nt:3c
      final seq3c = graph.sequenceIndex['(1s):2nt:3c'];
      expect(seq3c, isNotNull, reason: 'Sequence (1s):2nt:3c must exist');
      final rebids = seq3c!.candidateNodes.map((n) => n.call).toList();
      expect(rebids, containsAll(['pass', '4c', '5c']));
    });

    test('2. Partnership Michaels over 1S: Advancer 2NT inquiry, 3C pass-or-correct, and Overcaller rebids', () {
      final seq2s = graph.sequenceIndex['(1s):2s'];
      expect(seq2s, isNotNull, reason: 'Sequence (1s):2s must exist in graph');
      final calls = seq2s!.candidateNodes.map((n) => n.call).toList();

      // Advancer options: 2nt (minor inquiry), 3c (pass-or-correct), 3h, 4h
      expect(calls, containsAll(['2nt', '3c', '3h', '4h']));

      // Overcaller rebids after advancer 2NT minor inquiry: (1s):2s:2nt
      // Gavin Wolpert method: 3c = min clubs, 3d = min diamonds, 3s (3om) = max clubs, 3nt = max diamonds
      final seq2nt = graph.sequenceIndex['(1s):2s:2nt'];
      expect(seq2nt, isNotNull, reason: 'Sequence (1s):2s:2nt must exist');
      final rebids2nt = seq2nt!.candidateNodes.map((n) => n.call).toList();
      expect(rebids2nt, containsAll(['3c', '3d', '3s', '3nt']));

      // Overcaller rebids after advancer 3C pass-or-correct: (1s):2s:3c
      final seq3c = graph.sequenceIndex['(1s):2s:3c'];
      expect(seq3c, isNotNull, reason: 'Sequence (1s):2s:3c must exist');
      final rebids3c = seq3c!.candidateNodes.map((n) => n.call).toList();
      expect(rebids3c, containsAll(['pass', '3d']));
    });

    test('3. Unusual over Unusual Defense over 1S - (2NT): Lower-Lower 3C and Higher-Higher 3D', () {
      final seq = graph.sequenceIndex['1s:(2nt)'];
      expect(seq, isNotNull, reason: 'Sequence 1s:(2nt) must exist in graph');
      final calls = seq!.candidateNodes.map((n) => n.call).toList();

      // Gavin Wolpert UvU:
      // dbl: Penalty / values
      // 3c (Lower cuebid): 5+ Hearts, Game Forcing
      // 3d (Higher cuebid): Limit raise or better in Spades (10+ HCP, 3+ Spades)
      // 3h: Natural competitive Hearts
      // 3s: Simple competitive raise in Spades
      // 4s: Game in Spades
      expect(calls, containsAll(['dbl', '3c', '3d', '3h', '3s', '4s', 'pass']));

      final node3c = seq.candidateNodes.firstWhere((n) => n.call == '3c');
      expect(node3c.desc, contains('Hearts'));
      expect(node3c.rule, contains('10+hcp 5+h'));

      final node3d = seq.candidateNodes.firstWhere((n) => n.call == '3d');
      expect(node3d.desc, contains('Spades'));
      expect(node3d.rule, contains('10+hcp 3+s'));
    });

    test('4. Michaels Defense over 1H - (2H): Cuebid 3S is Limit Raise or better in Hearts', () {
      final seq = graph.sequenceIndex['1h:(2h)'];
      expect(seq, isNotNull, reason: 'Sequence 1h:(2h) must exist in graph');
      final calls = seq!.candidateNodes.map((n) => n.call).toList();

      // Gavin Wolpert Michaels Defense:
      // dbl: Penalty / values
      // 2nt: Natural balanced invitation with stopper in opponent's major
      // 3s (Cuebid of opponent's known major): Limit raise or better in opener's Hearts
      // 3h: Simple competitive raise in Hearts
      // 4h: Game in Hearts
      expect(calls, containsAll(['dbl', '2nt', '3s', '3h', '4h', 'pass']));

      final node3s = seq.candidateNodes.firstWhere((n) => n.call == '3s');
      expect(node3s.desc, contains('Hearts'));
      expect(node3s.rule, contains('10+hcp 3+h'));
    });

    test('5. Michaels Defense over 1C - (2C): Cuebid 3H is Limit Raise or better in Clubs', () {
      final seq = graph.sequenceIndex['1c:(2c)'];
      expect(seq, isNotNull, reason: 'Sequence 1c:(2c) must exist in graph');
      final calls = seq!.candidateNodes.map((n) => n.call).toList();

      // Michaels over 1m shows both majors 5-5.
      // 3h (Lower major cuebid): Limit raise or better in Clubs (10+ HCP, 4+ Clubs)
      // 3s (Higher major cuebid): Game forcing inquiry (11+ HCP)
      // 3c: Simple competitive raise in Clubs
      expect(calls, containsAll(['dbl', '2nt', '3c', '3h', '3s']));

      final node3h = seq.candidateNodes.firstWhere((n) => n.call == '3h');
      expect(node3h.desc, contains('Clubs'));
      expect(node3h.rule, contains('10+hcp 4+c'));
    });

    test('6. Unusual over Unusual Defense over 1C - (2NT): Lower cuebid 3D shows Clubs LR+, Higher cuebid 3H shows Spades GF', () {
      final seq = graph.sequenceIndex['1c:(2nt)'];
      expect(seq, isNotNull, reason: 'Sequence 1c:(2nt) must exist in graph');
      final calls = seq!.candidateNodes.map((n) => n.call).toList();

      // Over 1C - (2NT showing diamonds + hearts):
      // 3d (Lower cuebid): Limit raise or better in Clubs (10+ HCP, 4+ Clubs)
      // 3h (Higher cuebid): 5+ Spades, Game Forcing (10+ HCP)
      // 3s: Natural Spades, competitive
      // 3c: Simple competitive raise
      expect(calls, containsAll(['dbl', '3d', '3h', '3s', '3c', 'pass']));

      final node3d = seq.candidateNodes.firstWhere((n) => n.call == '3d');
      expect(node3d.desc, contains('Clubs'));
      expect(node3d.rule, contains('10+hcp 4+c'));

      final node3h = seq.candidateNodes.firstWhere((n) => n.call == '3h');
      expect(node3h.desc, contains('Spades'));
      expect(node3h.rule, contains('10+hcp 5+s'));
    });
  });
}
