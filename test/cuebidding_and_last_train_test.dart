import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/constraints/specificity_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CompiledBiddingGraph graph;
  final resolver = SpecificityResolver();

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

  group('Slam Bidding: Cuebids, Cuebid Doubles, and Last Train', () {
    test('1. Serious 3NT cuebids and lead-directing double defense', () {
      final state3NT = graph.getState(['1s', '2nt', '3nt']);
      expect(state3NT, isNotNull, reason: 'Sequence 1s:2nt:3nt must exist');
      final calls = state3NT!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // 4C and 4D cuebids must exist
      expect(calls, containsAll(['4c', '4d', '4s']));

      // Hand with 1st round Club control (Ace): 4C
      final handWithAce = Hand.fromString('KJ74.K7.A62.A543');
      final matchAce = resolver.evaluateCandidates(handWithAce, state3NT.candidateNodes);
      expect(matchAce.first.node.call.toLowerCase(), equals('4c'),
          reason: 'Hand with Ace of Clubs bids 4C cuebid');

      // Hand with 2nd round Club control (King): 4C
      final handWithKing = Hand.fromString('KJ74.A7.A62.K543');
      final matchKing = resolver.evaluateCandidates(handWithKing, state3NT.candidateNodes);
      expect(matchKing.first.node.call.toLowerCase(), equals('4c'),
          reason: 'Hand with King of Clubs bids 4C cuebid');

      // Over 1S - 2NT - 3NT - 4C - (X):
      final state4CX = graph.getState(['1s', '2nt', '3nt', '4c', '(x)']);
      expect(state4CX, isNotNull, reason: 'Sequence 1s:2nt:3nt:4c:(x) must exist');
      final calls4CX = state4CX!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
      expect(calls4CX, containsAll(['pass', 'rdbl']));

      // Responder with Ace of Clubs redoubles to show 1st round control
      final handFirstRound = Hand.fromString('AQ982.A8.KJ3.A82');
      final matchRdbl = resolver.evaluateCandidates(handFirstRound, state4CX.candidateNodes);
      expect(matchRdbl.first.node.call.toLowerCase(), equals('rdbl'),
          reason: 'Redouble shows 1st round control (Ace or Void)');

      // Responder with King of Clubs (no Ace, no void) passes (denies 1st round control)
      final handSecondRound = Hand.fromString('AQ982.A8.AJ3.K82');
      final matchPass = resolver.evaluateCandidates(handSecondRound, state4CX.candidateNodes);
      expect(matchPass.first.node.call.toLowerCase(), equals('pass'),
          reason: 'Pass denies 1st round control in doubled suit');
    });

    test('2. Last Train 4H when Spades is agreed', () {
      final state4C = graph.getState(['1s', '2nt', '3nt', '4c']);
      expect(state4C, isNotNull);
      final calls = state4C!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Under Spades, 4H is Last Train
      expect(calls, contains('4h'), reason: '4H must exist as Last Train below 4S');

      final state4H = graph.getState(['1s', '2nt', '3nt', '4c', '4h']);
      expect(state4H, isNotNull);
      final callsOver4H = state4H!.candidateNodes.map((n) => n.call.toLowerCase()).toSet();

      // Over Last Train: 4S (minimum signoff), 4NT (RKCB)
      expect(callsOver4H, containsAll(['4s', '4nt']));

      // Minimum hand signs off in 4S
      final handMin = Hand.fromString('KQ83.K94.A82.762'); // 12 HCP
      final matchMin = resolver.evaluateCandidates(handMin, state4H.candidateNodes);
      expect(matchMin.first.node.call.toLowerCase(), equals('4s'),
          reason: 'Minimum values signs off in 4S over Last Train');

      // Extra values (15 HCP) drives to RKCB 4NT
      final handExtras = Hand.fromString('KQ83.AK4.A82.762'); // 16 HCP
      final matchExtras = resolver.evaluateCandidates(handExtras, state4H.candidateNodes);
      expect(matchExtras.first.node.call.toLowerCase(), equals('4nt'),
          reason: 'Extras bids RKCB 4NT over Last Train');
    });

    test('3. SeatBeliefState correctly identifies uncontrolled side suits', () {
      final belief = SeatBeliefState(seat: 'N');

      // Hand with two quick losers in Clubs (762) and no honors or shortness
      // ♠ AKQ84, ♥ AK4, ♦ A82, ♣ 762 (Spades is trump)
      final handWithUncontrolledClubs = Hand.fromString('AKQ84.AK4.A82.762');
      expect(belief.hasUncontrolledSideSuit(handWithUncontrolledClubs, Suit.spades), isTrue,
          reason: 'Clubs is uncontrolled (3 small cards, no A/K/shortness, partner unconfirmed)');

      // Partner shows Club control
      final beliefWithClubControl = belief.copyWith(controlledSuits: {Suit.clubs});
      expect(beliefWithClubControl.hasUncontrolledSideSuit(handWithUncontrolledClubs, Suit.spades), isFalse,
          reason: 'All side suits controlled now that partner confirmed Club control');
    });
  });
}
