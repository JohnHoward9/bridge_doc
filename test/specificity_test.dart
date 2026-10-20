import 'package:flutter_test/flutter_test.dart';
import '../lib/models/card.dart';
import '../lib/models/hand.dart';
import '../lib/models/bidding_system.dart';
import '../lib/constraints/constraint_parser.dart';
import '../lib/constraints/specificity_resolver.dart';

void main() {
  test('User example: A3:KQ5432:4:K432 resolves to 1H over 1C because 1H is more defined', () {
    // Hand: ♠A3  ♥KQ5432  ♦4  ♣K432
    final hand = Hand.fromString('A3:KQ5432:4:K432');

    expect(hand.spadesLength, 2);
    expect(hand.heartsLength, 6);
    expect(hand.diamondsLength, 1);
    expect(hand.clubsLength, 4);

    // HCP: A(4) + K(3) + Q(2) + K(3) = 12 HCP
    expect(hand.hcp, 12);

    final node1c = BiddingNode(
      call: '1c',
      desc: 'Clubs opening',
      rule: '10+hcp, 2+c',
    );

    final node1h = BiddingNode(
      call: '1h',
      desc: 'Hearts opening',
      rule: '10+hcp, 5+h',
    );

    final candidates = [node1c, node1h];
    final resolver = SpecificityResolver(parser: ConstraintParser());

    final evaluated = resolver.evaluateCandidates(hand, candidates);
    expect(evaluated.length, 2, reason: 'Both 1c and 1h are satisfied by this hand');

    print('Candidate 1c specificity: ${evaluated.firstWhere((c) => c.node.call == '1c').specificityScore}');
    print('Candidate 1h specificity: ${evaluated.firstWhere((c) => c.node.call == '1h').specificityScore}');

    final bestBid = resolver.resolveBestBid(hand, candidates);
    expect(bestBid, isNotNull);
    expect(bestBid!.call, '1h', reason: '1H must be chosen because it is more defined than 1C');
  });
}
