import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/constraints/specificity_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BridgeSystem system;
  final resolver = SpecificityResolver();

  setUpAll(() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    final yamlStr = await file.readAsString();
    system = await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async => File(path).existsSync() ? await File(path).readAsString() : '',
    );
  });

  group('Exclusion RKCB (0314) and Captain Follow-ups', () {
    test('1. 5C Exclusion jump over Spades and step responses', () {
      final frag = system.fragments['fExclusionRKCB_Spades'];
      expect(frag, isNotNull);
      final bid5C = frag!.bids.firstWhere((b) => b.call.toLowerCase() == '5c');
      final calls = bid5C.bids.map((n) => n.call.toLowerCase()).toSet();

      // Step responses: 5D (0/3), 5H (1/4), 5S (2-Q), 5NT (2+Q)
      expect(calls, containsAll(['5d', '5h', '5s', '5nt']));

      // Hand with 1 Keycard outside Clubs: bids 5H (Step 2)
      // ♠ T74, ♥ A86, ♦ K862, ♣ 9542 (1 KC = HA; Trump King is not held)
      final hand1KC = Hand.fromString('T74.A86.K862.9542');
      final match1KC = resolver.evaluateCandidates(hand1KC, bid5C.bids);
      expect(match1KC.first.node.call.toLowerCase(), equals('5h'),
          reason: '1 Keycard outside void bids 5H (Step 2)');
    });

    test('2. Captain follow-ups over Step 2 (1 or 4 KC outside void)', () {
      final frag = system.fragments['fExclusionRKCB_Spades']!;
      final bid5C = frag.bids.firstWhere((b) => b.call.toLowerCase() == '5c');
      final step2 = bid5C.bids.firstWhere((b) => b.call.toLowerCase() == '5h');
      final step2FollowUps = step2.getEffectiveChildren(const {}, fragments: system.fragments);
      final calls = step2FollowUps.map((n) => n.call.toLowerCase()).toSet();

      // Over Step 2: 5S (signoff missing 2 KC), 6S (small slam), 5NT (King ask)
      expect(calls, containsAll(['5s', '6s', '5nt']));

      // Captain with 2 Keycards outside Clubs (♠ K8642, ♥ A74, ♦ K82, ♣ -):
      // Partner has 1 KC -> Total = 3 KC (missing 1 KC + missing Ace) -> Signoff in 5S!
      final hand2KC = Hand.fromString('K8642.A74.K82.');
      final match2KC = resolver.evaluateCandidates(hand2KC, step2FollowUps);
      expect(match2KC.first.node.call.toLowerCase(), equals('5s'),
          reason: 'Captain holding <=2 KC signs off in 5S when partner has 1 KC (missing 2 KC)');

      // Captain with 3 Keycards + Queen outside Clubs (♠ AKQ42, ♥ A74, ♦ K82, ♣ -):
      // Partner has 1 KC -> Total = ALL 4 KC + Queen -> 5NT King ask / 7S!
      final hand3KCWithQ = Hand.fromString('AKQ42.A74.K82.');
      final match3KC = resolver.evaluateCandidates(hand3KCWithQ, step2FollowUps);
      expect(match3KC.first.node.call.toLowerCase(), equals('5nt'),
          reason: 'Captain holding 3 KC + Queen bids 5NT King ask when partner has 1 KC (all controls held)');
    });
  });
}
