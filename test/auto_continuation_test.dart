import 'package:flutter_test/flutter_test.dart';
import '../lib/models/card.dart';
import '../lib/models/hand.dart';
import '../lib/models/bidding_system.dart';
import '../lib/constraints/constraint_parser.dart';
import '../lib/constraints/specificity_resolver.dart';

void main() {
  test('Automatic auction continuation: South bids 1s, auction automatically continues to North rebid', () {
    final resolver = SpecificityResolver(parser: ConstraintParser());

    // North holds 14 HCP with 5 Hearts: ♠A3 ♥KQ864 ♦972 ♣AJ5
    final northHand = Hand.fromString('A3:KQ864:972:AJ5');
    // South holds 8 HCP with 4 Spades: ♠KJ84 ♥65 ♦Q97 ♣J865
    final southHand = Hand.fromString('KJ84:65:Q97:J865');

    // System tree with follow-up bids
    final systemOpening = BiddingNode(
      call: '1h',
      desc: '5-card major opening (Hearts)',
      rule: 'p#5 10+hcp, 5+h',
      variables: {'M': 'h'},
      bids: [
        BiddingNode(
          call: '<\$M=h>1s',
          desc: 'Spades',
          rule: 'p#3 5-10hcp 4s 2-h',
          bids: [
            BiddingNode(
              call: '1nt',
              desc: 'Minimum balanced without spade support',
              rule: 'p#4 12-14hcp, 2-s',
            ),
            BiddingNode(
              call: '2h',
              desc: '6-card Heart rebid',
              rule: 'p#3 12-15hcp, 6+h',
            ),
          ],
        ),
        BiddingNode(
          call: 'pass',
          desc: 'Bad hand <5hcp',
          rule: 'p#5 5-hcp',
        ),
      ],
    );

    // 1. North opens 1h automatically
    expect(systemOpening.call, '1h');
    final activeVariables = Map<String, String>.from(systemOpening.variables);

    // 2. South receives candidates under 1h: pass or 1s
    final southCandidates = systemOpening.getEffectiveChildren(activeVariables);
    final southBestBid = resolver.resolveBestBid(southHand, southCandidates);
    expect(southBestBid, isNotNull);
    expect(southBestBid!.displayCall, '1s');

    // 3. When South's bid (1s) is correct, advance auction:
    activeVariables.addAll(southBestBid.variables);
    final northRebidCandidates = southBestBid.getEffectiveChildren(activeVariables);
    expect(northRebidCandidates.length, 2);

    // 4. North automatically evaluates North's hand for the rebid
    // North has 2 Spades, 5 Hearts, 14 HCP -> matches 1NT (12-14hcp, 2-s)
    final northRebid = resolver.resolveBestBid(northHand, northRebidCandidates);
    expect(northRebid, isNotNull);
    expect(northRebid!.call, '1nt', reason: 'North automatically rebids 1NT over Souths 1S response');
  });
}
