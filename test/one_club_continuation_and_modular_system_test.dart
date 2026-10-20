import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/card.dart';
import '../lib/models/hand.dart';
import '../lib/models/bidding_system.dart';
import '../lib/constraints/constraint_parser.dart';
import '../lib/constraints/specificity_resolver.dart';
import '../lib/services/system_library_resolver.dart';
import '../lib/services/system_yaml_parser.dart';

void main() {
  group('Compound Bids & Variable Substitution', () {
    test('[1d-1h] expands into 1d and 1h with bound major variables', () {
      final compound = BiddingNode(
        call: '[1d-1h]',
        desc: 'Transfer response showing 4+M',
        rule: '1d:p#4 4+h h>s, 4h 4s [\$M=h, \$OM=s] ^ 1h:p#5 4+s [\$M=s,\$OM=h]',
        bids: [
          BiddingNode(call: '1\$M', desc: '3 card support', rule: 'p#3 11-16hcp 3\$M'),
          BiddingNode(call: '3\$OM', desc: 'Splinter other major', rule: 'p#3 1-\$OM 18-21hcp 4\$M'),
        ],
      );

      final expanded = compound.expandCompoundBid();
      expect(expanded.length, 2);

      final node1d = expanded[0];
      expect(node1d.call, '1d');
      expect(node1d.variables['M'], 'h');
      expect(node1d.variables['OM'], 's');

      final node1h = expanded[1];
      expect(node1h.call, '1h');
      expect(node1h.variables['M'], 's');
      expect(node1h.variables['OM'], 'h');

      // Test effective children under 1h with active variables
      final childrenOf1h = node1h.getEffectiveChildren({'M': 's', 'OM': 'h'});
      expect(childrenOf1h.length, 2);
      expect(childrenOf1h[0].call, '1s', reason: '1\$M substituted with M=s becomes 1s');
      expect(childrenOf1h[0].rule, 'p#3 11-16hcp 3s');
      expect(childrenOf1h[1].call, '3h', reason: '3\$OM substituted with OM=h becomes 3h');
      expect(childrenOf1h[1].rule, 'p#3 1-h 18-21hcp 4s');
    });
  });

  group('1c:1h Inline Continuations (~>) and Rebid Resolution', () {
    test('Opener with 3-card Spade support bids 1S via ~>Support router', () {
      // Hand: ♠K43 ♥A5 ♦Q432 ♣KJ43 (13 HCP, 3 Spades)
      final openerHand = Hand.fromString('K43:A5:Q432:KJ43');
      expect(openerHand.spadesLength, 3);
      expect(openerHand.hcp, 13);

      final resolver = SpecificityResolver(
        parser: ConstraintParser(definitions: {'weakbal': '11-14hcp s#5332|4432|4333 4-h 4-s'}),
      );

      // Model the 1h node children exactly as defined in the Walrus convention
      final node1h = BiddingNode(
        call: '1h',
        desc: 'Transfer response showing 4+ Spades',
        rule: 'p#5 4+s',
        variables: {'M': 's', 'OM': 'h'},
        bids: [
          BiddingNode(
            call: '~>Support',
            rule: 'p#4 3+\$M',
            bids: [
              BiddingNode(
                call: '~>Limited hand support',
                rule: '16-hcp',
                bids: [
                  BiddingNode(call: '1\$M', desc: '3 card support', rule: 'p#3 11-16hcp 3\$M'),
                  BiddingNode(call: '2\$M', desc: 'Weak NT 4-card support', rule: 'p#2 \$weakbal 4\$M'),
                ],
              ),
            ],
          ),
          BiddingNode(
            call: '~>No Support',
            rule: 'p#5 2-\$M',
            bids: [
              BiddingNode(call: '1nt', desc: 'Weak NT no support', rule: 'p#5 \$weakbal 1\$M'),
              BiddingNode(call: '2c', desc: 'Clubs without support', rule: 'p#4 15-hcp 5+c'),
            ],
          ),
        ],
      );

      final rawCandidates = node1h.getEffectiveChildren({'M': 's', 'OM': 'h'});
      final playable = resolver.resolvePlayableCandidates(
        openerHand,
        rawCandidates,
        activeVariables: {'M': 's', 'OM': 'h'},
      );

      // With 3 spades and 13 HCP, ~>Support matches and unwraps 1s and 2s
      expect(playable.any((c) => c.call == '1s'), isTrue, reason: '1s must be unwrapped as a playable candidate');

      final bestBid = resolver.resolveBestBid(
        openerHand,
        rawCandidates,
        activeVariables: {'M': 's', 'OM': 'h'},
      );

      expect(bestBid, isNotNull);
      expect(bestBid!.call, '1s', reason: 'Opener with 3 spades must bid 1S');
    });

    test('Opener with 2-card Spade holding bids 1NT via ~>No Support router', () {
      // Hand: ♠K4 ♥A53 ♦Q432 ♣KJ43 (13 HCP balanced, 2 Spades)
      final openerHand = Hand.fromString('K4:A53:Q432:KJ43');
      expect(openerHand.spadesLength, 2);
      expect(openerHand.hcp, 13);

      final resolver = SpecificityResolver(
        parser: ConstraintParser(definitions: {'weakbal': '11-14hcp s#5332|4432|4333 4-h 4-s'}),
      );

      final node1h = BiddingNode(
        call: '1h',
        desc: 'Transfer response showing 4+ Spades',
        rule: 'p#5 4+s',
        variables: {'M': 's', 'OM': 'h'},
        bids: [
          BiddingNode(
            call: '~>Support',
            rule: 'p#4 3+\$M',
            bids: [
              BiddingNode(
                call: '~>Limited hand support',
                rule: '16-hcp',
                bids: [
                  BiddingNode(call: '1\$M', desc: '3 card support', rule: 'p#3 11-16hcp 3\$M'),
                ],
              ),
            ],
          ),
          BiddingNode(
            call: '~>No Support',
            rule: 'p#5 2-\$M',
            bids: [
              BiddingNode(call: '1nt', desc: 'Weak NT no support', rule: 'p#5 \$weakbal'),
              BiddingNode(call: '2c', desc: 'Clubs without support', rule: 'p#4 15-hcp 5+c'),
            ],
          ),
        ],
      );

      final rawCandidates = node1h.getEffectiveChildren({'M': 's', 'OM': 'h'});
      final playable = resolver.resolvePlayableCandidates(
        openerHand,
        rawCandidates,
        activeVariables: {'M': 's', 'OM': 'h'},
      );

      expect(playable.any((c) => c.call == '1nt'), isTrue, reason: '1nt must be unwrapped as a playable candidate');

      final bestBid = resolver.resolveBestBid(
        openerHand,
        rawCandidates,
        activeVariables: {'M': 's', 'OM': 'h'},
      );

      expect(bestBid, isNotNull);
      expect(bestBid!.call, '1nt', reason: 'Opener with 2 spades and balanced hand must bid 1NT');
    });
  });

  group('Base 5-Card Majors, Strong NT & 2/1 System Loading', () {
    test('Loads us_standard_2over1.yaml and resolves 2/1 GF and Jacoby 2NT', () async {
      final file = File('assets/core/systems/us_standard_2over1.yaml');
      expect(file.existsSync(), isTrue);

      final system = await SystemLibraryResolver.loadSystemWithLibraries(
        file.readAsStringSync(),
        fileLoader: (path) async => File(path).readAsString(),
      );

      expect(system.openingBids.length, greaterThanOrEqualTo(5));

      final node1h = system.openingBids.firstWhere((b) => b.call == '1h');
      expect(node1h.ref, 'fHeartResponses2Over1');
      expect(system.fragments.containsKey('fHeartResponses2Over1'), isTrue);

      final heartResponses = system.fragments['fHeartResponses2Over1']!.bids;
      expect(heartResponses.any((b) => b.call == '2c'), isTrue);
      expect(heartResponses.any((b) => b.call == '2nt'), isTrue);

      // Verify responder with 13 HCP and 4+ Clubs bids 2C (2/1 GF) over 1H
      final responderGFClubs = Hand.fromString('43:K4:A32:AK432');
      final resolver = SpecificityResolver();
      final bestBid = resolver.resolveBestBid(responderGFClubs, heartResponses);
      expect(bestBid, isNotNull);
      expect(bestBid!.call, '2c', reason: 'Responder with 13 HCP and 5 clubs bids 2C (2/1 GF) over 1H');

      // Verify responder with 14 HCP and 4 Hearts bids 2NT (Jacoby 2NT) over 1H
      final responderJacoby = Hand.fromString('A3:KJ43:A32:Q432');
      final jacobyBid = resolver.resolveBestBid(responderJacoby, heartResponses);
      expect(jacobyBid, isNotNull);
      expect(jacobyBid!.call, '2nt', reason: 'Responder with 14 HCP and 4 hearts bids 2NT over 1H');
    });
  });
}
