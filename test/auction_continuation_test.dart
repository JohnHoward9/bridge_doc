import 'package:flutter_test/flutter_test.dart';
import '../lib/models/hand.dart';
import '../lib/models/bidding_system.dart';
import '../lib/constraints/constraint_parser.dart';
import '../lib/constraints/specificity_resolver.dart';

void main() {
  test('Auction continuation after 1h opening: evaluates responder bids with p# and conditions', () {
    // Parent node: [1h-1s]
    final nodeCompound = BiddingNode(
      call: '[1h-1s]',
      desc: '5 card major opening',
      rule: '1h:p#5 5+h 11+hcp h>=* [\$M=h, \$OM=s, \$os=h] ^ 1s:p#4 5+s s>=* 11+hcp [\$M=s, \$OM=h, \$os=s]',
      bids: [
        BiddingNode(
          call: 'pass',
          desc: 'Bad hand <5hcp',
          rule: 'p#5 5-hcp',
        ),
        BiddingNode(
          call: r'<$M=h>1s',
          desc: 'Spades',
          rule: 'p#3 5-10hcp 4s 2-h, 5-10hcp 5s 3-h, 11+hcp 4+s s>=*, 9+hcp 6+s',
        ),
        BiddingNode(
          call: '1nt',
          desc: 'Semi-forcing 1NT',
          rule: 'p#4 6-11hcp',
        ),
      ],
    );

    // Expand [1h-1s]
    final expanded = nodeCompound.expandCompoundBid();
    expect(expanded.length, 2);

    final node1h = expanded.firstWhere((n) => n.call == '1h');
    expect(node1h.variables['M'], 'h');

    // Get children under 1h (active variables M=h)
    final responderBids = node1h.getEffectiveChildren(node1h.variables);
    expect(responderBids.any((b) => b.displayCall == '1s'), isTrue,
        reason: '<\$M=h>1s must be active when opening is 1h');
    expect(responderBids.any((b) => b.displayCall == 'pass'), isTrue);

    final resolver = SpecificityResolver(parser: ConstraintParser());

    // 1. Responder Hand with 4 Spades, 2 Hearts, 8 HCP (♠KJ84 ♥65 ♦Q97 ♣J865)
    final handWithSpades = Hand.fromString('KJ84:65:Q97:J865');
    expect(handWithSpades.spadesLength, 4);
    expect(handWithSpades.heartsLength, 2);
    expect(handWithSpades.hcp, 7);

    final bestBidForSpades = resolver.resolveBestBid(handWithSpades, responderBids);
    expect(bestBidForSpades, isNotNull);
    expect(bestBidForSpades!.displayCall, '1s',
        reason: 'Hand with 4s 2-h 8hcp must bid 1s (p#3 takes precedence over 1nt p#4)');

    // 2. Responder Hand with weak 3 HCP (♠987 ♥64 ♦8743 ♣J95)
    final weakHand = Hand.fromString('987:64:8743:J95');
    expect(weakHand.hcp, 1);

    final bestBidForWeak = resolver.resolveBestBid(weakHand, responderBids);
    expect(bestBidForWeak, isNotNull);
    expect(bestBidForWeak!.displayCall, 'pass',
        reason: 'Hand with <5hcp must pass');

    // 3. Condition check: If opening was 1s ($M=s), <$M=h>1s should NOT be available
    final node1s = expanded.firstWhere((n) => n.call == '1s');
    expect(node1s.variables['M'], 's');
    final responderBidsOver1s = node1s.getEffectiveChildren(node1s.variables);
    expect(responderBidsOver1s.any((b) => b.displayCall == '1s'), isFalse,
        reason: 'Cannot respond 1s to 1s opening because condition <\$M=h> fails');
  });
}
