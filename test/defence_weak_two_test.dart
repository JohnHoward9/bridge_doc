import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Defense Against Weak Two Bids (defence_weak_two.yaml)', () {
    test('defence_weak_two.yaml parses standalone with unified fragment fWeakTwoDefense', () async {
      final yamlContent = await File('assets/libraries/conventions/defence_weak_two.yaml').readAsString();
      final lib = SystemYamlParser.fromYaml(yamlContent);

      expect(lib.fragments.containsKey('fWeakTwoDefense'), isTrue);
      final frag = lib.fragments['fWeakTwoDefense']!;
      expect(frag.bids, isNotEmpty);
    });

    test(r'Opposition Weak 2H: verifies $os=h and $OM=s substitution and continuations', () {
      final yamlContent = File('assets/libraries/conventions/defence_weak_two.yaml').readAsStringSync();
      final lib = SystemYamlParser.fromYaml(yamlContent);

      // Create a test system with OppositionOpeningBids containing (2h)
      final testSystem = BridgeSystem(
        name: 'Test Weak 2H Defense',
        player: 'North',
        partner: 'South',
        definitions: const {},
        openingBids: const [],
        oppositionOpeningBids: [
          BiddingNode(
            call: '(2h)',
            desc: 'Opponent Weak Two in Hearts',
            rule: r'6h 5-10hcp [$os=h, $OM=s]',
            ref: 'fWeakTwoDefense',
          ),
        ],
        fragments: lib.fragments,
      );

      final compiler = BiddingGraphCompiler(system: testSystem);
      final graph = compiler.compile();

      // State after opponent opens (2h)
      final state2H = graph.getState(['(2h)']);
      expect(state2H, isNotNull);
      final over2H = state2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      // Should include Pass, Dbl (Takeout), 2S (natural overcall), 2NT (bal stopper), 3C, 3D, 4C (LM), 4D (LM), 4S (to play), 4H (cue)
      expect(over2H, contains('pass'));
      expect(over2H, contains('dbl'));
      expect(over2H, contains('2s'), reason: r'Natural 2S overcall over 2H (<$os=h> 2s)');
      expect(over2H, contains('2nt'), reason: 'Natural 15-18 with Heart stopper');
      expect(over2H, contains('3c'), reason: 'Natural 3C overcall');
      expect(over2H, contains('3d'), reason: 'Natural 3D overcall');
      expect(over2H, isNot(contains('3h')), reason: '3H is not natural overcall over 2H');
      expect(over2H, contains('4c'), reason: r'Leaping Michaels (Clubs + Spades, $OM=s)');
      expect(over2H, contains('4d'), reason: r'Leaping Michaels (Diamonds + Spades, $OM=s)');
      expect(over2H, contains('4s'), reason: r'Natural jump to game in other major ($OM=s)');
      expect(over2H, contains('4h'), reason: r'Western cue-bid in opponent suit ($os=h)');

      // Continuations after (2H) - Dbl:
      final state2HDbl = graph.getState(['(2h)', 'dbl']);
      expect(state2HDbl, isNotNull);
      final advancerCalls = state2HDbl!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(advancerCalls, contains('pass'), reason: 'Penalty pass');
      expect(advancerCalls, contains('2nt'), reason: 'Lebensohl 2NT');
      expect(advancerCalls, contains('3c'), reason: 'Natural constructive Clubs');
      expect(advancerCalls, contains('3d'), reason: 'Natural constructive Diamonds');
      expect(advancerCalls, contains('3s'), reason: r'Natural constructive Spades (3$OM)');
      expect(advancerCalls, contains('3h'), reason: r'Direct cue-bid (3$os) denies stopper');
      expect(advancerCalls, contains('3nt'), reason: 'Direct 3NT to play');
      expect(advancerCalls, contains('4s'), reason: r'Jump to 4S game in other major (4$OM)');

      // Continuations after (2H) - Dbl - 2NT (Lebensohl):
      final state2NT = graph.getState(['(2h)', 'dbl', '2nt']);
      expect(state2NT, isNotNull);
      final over2NT = state2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(over2NT, contains('3c'), reason: 'Lebensohl relay to 3C');

      // Continuations after (2H) - Dbl - 2NT - 3C:
      final state3C = graph.getState(['(2h)', 'dbl', '2nt', '3c']);
      expect(state3C, isNotNull);
      final over3C = state3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(over3C, contains('pass'), reason: 'Signoff in Clubs');
      expect(over3C, contains('3d'), reason: 'Signoff in Diamonds');
      expect(over3C, contains('3h'), reason: r'Cue-bid (3$os) with stopper');
      expect(over3C, contains('3nt'), reason: '3NT with stopper');
      expect(over3C, contains('4s'), reason: r'4$OM game / slam try');
    });

    test(r'Opposition Weak 2S: verifies $os=s and $OM=h substitution and continuations', () {
      final yamlContent = File('assets/libraries/conventions/defence_weak_two.yaml').readAsStringSync();
      final lib = SystemYamlParser.fromYaml(yamlContent);

      // Create a test system with OppositionOpeningBids containing (2s)
      final testSystem = BridgeSystem(
        name: 'Test Weak 2S Defense',
        player: 'North',
        partner: 'South',
        definitions: const {},
        openingBids: const [],
        oppositionOpeningBids: [
          BiddingNode(
            call: '(2s)',
            desc: 'Opponent Weak Two in Spades',
            rule: r'6s 5-10hcp [$os=s, $OM=h]',
            ref: 'fWeakTwoDefense',
          ),
        ],
        fragments: lib.fragments,
      );

      final compiler = BiddingGraphCompiler(system: testSystem);
      final graph = compiler.compile();

      // State after opponent opens (2s)
      final state2S = graph.getState(['(2s)']);
      expect(state2S, isNotNull);
      final over2S = state2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      // Should include Pass, Dbl (Takeout), 3H (natural overcall <$os=s> 3h), 2NT (bal stopper), 3C, 3D, 4C (LM), 4D (LM), 4H (to play), 4S (cue)
      expect(over2S, contains('pass'));
      expect(over2S, contains('dbl'));
      expect(over2S, isNot(contains('2s')), reason: '2S is opponent suit');
      expect(over2S, contains('2nt'), reason: 'Natural 15-18 with Spade stopper');
      expect(over2S, contains('3c'), reason: 'Natural 3C overcall');
      expect(over2S, contains('3d'), reason: 'Natural 3D overcall');
      expect(over2S, contains('3h'), reason: r'Natural 3H overcall over 2S (<$os=s> 3h)');
      expect(over2S, contains('4c'), reason: r'Leaping Michaels (Clubs + Hearts, $OM=h)');
      expect(over2S, contains('4d'), reason: r'Leaping Michaels (Diamonds + Hearts, $OM=h)');
      expect(over2S, contains('4h'), reason: r'Natural jump to game in other major ($OM=h)');
      expect(over2S, contains('4s'), reason: r'Western cue-bid in opponent suit ($os=s)');

      // Continuations after (2S) - Dbl:
      final state2SDbl = graph.getState(['(2s)', 'dbl']);
      expect(state2SDbl, isNotNull);
      final advancerCalls = state2SDbl!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(advancerCalls, contains('pass'), reason: 'Penalty pass');
      expect(advancerCalls, contains('2nt'), reason: 'Lebensohl 2NT');
      expect(advancerCalls, contains('3c'), reason: 'Natural constructive Clubs');
      expect(advancerCalls, contains('3d'), reason: 'Natural constructive Diamonds');
      expect(advancerCalls, contains('3h'), reason: r'Natural constructive Hearts (3$OM)');
      expect(advancerCalls, contains('3s'), reason: r'Direct cue-bid (3$os) denies stopper');
      expect(advancerCalls, contains('3nt'), reason: 'Direct 3NT to play');
      expect(advancerCalls, contains('4h'), reason: r'Jump to 4H game in other major (4$OM)');

      // Continuations after (2S) - Dbl - 2NT - 3C:
      final state3C = graph.getState(['(2s)', 'dbl', '2nt', '3c']);
      expect(state3C, isNotNull);
      final over3C = state3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(over3C, contains('pass'), reason: 'Signoff in Clubs');
      expect(over3C, contains('3d'), reason: 'Signoff in Diamonds');
      expect(over3C, contains('3h'), reason: r'Signoff in Hearts (<$os=s> 3h)');
      expect(over3C, contains('3s'), reason: r'Cue-bid (3$os) with stopper');
      expect(over3C, contains('3nt'), reason: '3NT with stopper');
      expect(over3C, contains('4h'), reason: r'4$OM game / slam try');
    });

    test(r'Opposition Weak 2D: verifies $os=d substitution and 2-level major overcalls', () {
      final yamlContent = File('assets/libraries/conventions/defence_weak_two.yaml').readAsStringSync();
      final lib = SystemYamlParser.fromYaml(yamlContent);

      final testSystem = BridgeSystem(
        name: 'Test Weak 2D Defense',
        player: 'North',
        partner: 'South',
        definitions: const {},
        openingBids: const [],
        oppositionOpeningBids: [
          BiddingNode(
            call: '(2d)',
            desc: 'Opponent Weak Two in Diamonds',
            rule: r'6d 5-10hcp [$os=d]',
            ref: 'fWeakTwoDefense',
          ),
        ],
        fragments: lib.fragments,
      );

      final compiler = BiddingGraphCompiler(system: testSystem);
      final graph = compiler.compile();

      final state2D = graph.getState(['(2d)']);
      expect(state2D, isNotNull);
      final over2D = state2D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      expect(over2D, contains('pass'));
      expect(over2D, contains('dbl'), reason: 'Takeout Double');
      expect(over2D, contains('2h'), reason: r'Natural 2H overcall over 2D (<$os=d> [2h,2s])');
      expect(over2D, contains('2s'), reason: r'Natural 2S overcall over 2D (<$os=d> [2h,2s])');
      expect(over2D, contains('2nt'), reason: 'Natural 15-18 with Diamond stopper');
      expect(over2D, contains('3c'), reason: 'Natural 3C overcall');
      expect(over2D, contains('3d'), reason: r'Michaels cue-bid both majors (<$os=d> 3d)');
    });

    test('US Standard 2/1: seamlessly resolves fWeakTwoDefense over (2h) and (2s)', () async {
      final file = File('assets/core/systems/us_standard_2over1.yaml');
      final yamlStr = await file.readAsString();
      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async => File(path).readAsString(),
      );

      final engine = AuctionEngine.fromSystem(system);

      final state2H = engine.graph.getState(['(2h)']);
      expect(state2H, isNotNull);
      final calls2H = state2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2H, containsAll(['pass', 'dbl', '2s', '2nt', '3c', '3d', '4c', '4d', '4s', '4h']));

      final state2S = engine.graph.getState(['(2s)']);
      expect(state2S, isNotNull);
      final calls2S = state2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2S, containsAll(['pass', 'dbl', '2nt', '3c', '3d', '3h', '4c', '4d', '4h', '4s']));
    });

    test('Gavin Wolpert 2/1: seamlessly resolves fWeakTwoDefense over (2h) and (2s)', () async {
      final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
      final yamlStr = await file.readAsString();
      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async => File(path).readAsString(),
      );

      final engine = AuctionEngine.fromSystem(system);

      final state2H = engine.graph.getState(['(2h)']);
      expect(state2H, isNotNull);
      final calls2H = state2H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2H, containsAll(['pass', 'dbl', '2s', '2nt', '3c', '3d', '4c', '4d', '4s', '4h']));

      final state2S = engine.graph.getState(['(2s)']);
      expect(state2S, isNotNull);
      final calls2S = state2S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls2S, containsAll(['pass', 'dbl', '2nt', '3c', '3d', '3h', '4c', '4d', '4h', '4s']));
    });
  });
}
