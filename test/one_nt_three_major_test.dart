import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';

void main() {
  late AuctionEngine engine;

  setUpAll(() async {
    final yaml = await File('assets/core/systems/gavin_wolpert_2over1.yaml').readAsString();
    final system = await SystemLibraryResolver.loadSystemWithLibraries(yaml);
    engine = AuctionEngine.fromSystem(system);
  });

  test('1NT - 3H and 3S candidate descriptions and rules', () {
    final state1NT = engine.graph.getState(['1nt'])!;
    print('1NT candidate nodes: ${state1NT.candidateNodes.map((n) => "${n.call}:${n.displayCall}").toList()}');
    final node3H = state1NT.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '3h');
    final node3S = state1NT.candidateNodes.firstWhere((n) => n.call.toLowerCase() == '3s');

    expect(node3H.desc, contains('Shows a singleton/void in Hearts, exactly 3 Spades, and 5-4 or 4-5 in the minors (Game Forcing)'));
    expect(node3S.desc, contains('Shows a singleton/void in Spades, exactly 3 Hearts, and 5-4 or 4-5 in the minors (Game Forcing)'));

    // Verify 1NT - 3H has continuations 4S (5+ spades or good 4 spades), 3NT, 4C, 4D
    final state3H = engine.graph.getState(['1nt', '3h'])!;
    final calls3H = state3H.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
    expect(calls3H, containsAll(['4s', '3nt', '4c', '4d']));

    // Verify 1NT - 3S has continuations 4H (5+ hearts or good 4 hearts), 3NT, 4C, 4D
    final state3S = engine.graph.getState(['1nt', '3s'])!;
    final calls3S = state3S.candidateNodes.map((n) => n.call.toLowerCase()).toSet();
    expect(calls3S, containsAll(['4h', '3nt', '4c', '4d']));
  });

  test('Opener bids 4 of other major with 5 cards or good 4-card suit', () {
    final state3H = engine.graph.getState(['1nt', '3h'])!;

    // Hand with 4 good Spades (AK84) -> Should bid 4S
    final good4Spades = Hand.fromString('AK84.K52.QJ3.K42');
    final evalsGood = state3H.evaluateCandidates(good4Spades, engine.botResolver);
    final match4SGood = evalsGood.firstWhere((c) => c.call.toLowerCase() == '4s');
    expect(match4SGood.isMatch, isTrue);

    // Hand with 4 poor Spades (9862) -> Should NOT bid 4S, should bid 3NT
    final poor4Spades = Hand.fromString('9862.AK5.QJ3.AK2');
    final evalsPoor = state3H.evaluateCandidates(poor4Spades, engine.botResolver);
    final match4SPoor = evalsPoor.firstWhere((c) => c.call.toLowerCase() == '4s');
    expect(match4SPoor.isMatch, isFalse);

    // Hand with 5 Spades (AK842) -> Should bid 4S
    final fiveSpades = Hand.fromString('AK842.K5.QJ3.K42');
    final evals5 = state3H.evaluateCandidates(fiveSpades, engine.botResolver);
    final match4S5 = evals5.firstWhere((c) => c.call.toLowerCase() == '4s');
    expect(match4S5.isMatch, isTrue);
  });

  test('1NT - 3H matches exactly 3 spades, singleton/void hearts, and 5-4 / 4-5 minors', () {
    final state1NT = engine.graph.getState(['1nt'])!;

    // Hand A: 3-1-5-4 (3 spades, 1 heart, 5 diamonds, 4 clubs, 11 HCP) -> Should match 3H
    final handA = Hand.fromString('KQJ.4.AQJT4.K872');
    final evalsA = state1NT.evaluateCandidates(handA, engine.botResolver);
    final match3HA = evalsA.firstWhere((c) => c.call.toLowerCase() == '3h');
    expect(match3HA.isMatch, isTrue);

    // Hand B: 3-0-5-5 (3 spades, void hearts, 5 diamonds, 5 clubs, 12 HCP) -> Should match 3H
    final handB = Hand.fromString('KQJ..KJT54.AJ872');
    final evalsB = state1NT.evaluateCandidates(handB, engine.botResolver);
    final match3HB = evalsB.firstWhere((c) => c.call.toLowerCase() == '3h');
    expect(match3HB.isMatch, isTrue);

    // Hand C: 4-1-4-4 (4 spades, 1 heart, 4 diamonds, 4 clubs) -> Must NOT match 3H (4 spades, not 3)
    final handC = Hand.fromString('KQJ2.4.AQJT.K872');
    final evalsC = state1NT.evaluateCandidates(handC, engine.botResolver);
    final match3HC = evalsC.firstWhere((c) => c.call.toLowerCase() == '3h');
    expect(match3HC.isMatch, isFalse);

    // Hand D: 2-1-5-5 (2 spades, 1 heart, 5 diamonds, 5 clubs) -> Must NOT match 3H (2 spades, not 3)
    final handD = Hand.fromString('KQ.4.AQJT4.K8724');
    final evalsD = state1NT.evaluateCandidates(handD, engine.botResolver);
    final match3HD = evalsD.firstWhere((c) => c.call.toLowerCase() == '3h');
    expect(match3HD.isMatch, isFalse);

    // Hand E: 3-2-4-4 (3 spades, 2 hearts) -> Must NOT match 3H (2 hearts is not singleton/void)
    final handE = Hand.fromString('KQJ.42.AQJT.K872');
    final evalsE = state1NT.evaluateCandidates(handE, engine.botResolver);
    final match3HE = evalsE.firstWhere((c) => c.call.toLowerCase() == '3h');
    expect(match3HE.isMatch, isFalse);
  });

  test('1NT - 3S matches exactly 3 hearts, singleton/void spades, and 5-4 / 4-5 minors', () {
    final state1NT = engine.graph.getState(['1nt'])!;

    // Hand A: 1-3-5-4 (1 spade, 3 hearts, 5 diamonds, 4 clubs, 11 HCP) -> Should match 3S
    final handA = Hand.fromString('4.KQJ.AQJT4.K872');
    final evalsA = state1NT.evaluateCandidates(handA, engine.botResolver);
    final match3SA = evalsA.firstWhere((c) => c.call.toLowerCase() == '3s');
    expect(match3SA.isMatch, isTrue);

    // Hand B: 0-3-5-5 (void spades, 3 hearts, 5 diamonds, 5 clubs, 12 HCP) -> Should match 3S
    final handB = Hand.fromString('.KQJ.KJT54.AJ872');
    final evalsB = state1NT.evaluateCandidates(handB, engine.botResolver);
    final match3SB = evalsB.firstWhere((c) => c.call.toLowerCase() == '3s');
    expect(match3SB.isMatch, isTrue);

    // Hand C: 1-4-4-4 (1 spade, 4 hearts, 4 diamonds, 4 clubs) -> Must NOT match 3S (4 hearts, not 3)
    final handC = Hand.fromString('4.KQJ2.AQJT.K872');
    final evalsC = state1NT.evaluateCandidates(handC, engine.botResolver);
    final match3SC = evalsC.firstWhere((c) => c.call.toLowerCase() == '3s');
    expect(match3SC.isMatch, isFalse);

    // Hand D: 2-3-4-4 (2 spades) -> Must NOT match 3S (2 spades is not singleton/void)
    final handD = Hand.fromString('42.KQJ.AQJT.K872');
    final evalsD = state1NT.evaluateCandidates(handD, engine.botResolver);
    final match3SD = evalsD.firstWhere((c) => c.call.toLowerCase() == '3s');
    expect(match3SD.isMatch, isFalse);
  });
}
