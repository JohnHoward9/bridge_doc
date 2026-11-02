import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
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

  group('Gavin Wolpert Webinar 25: Exclusion RKCB (0314 Steps)', () {
    test('fExclusionRKCB_Spades defines 0314 steps over 5C, 5D, 5H void jumps', () {
      expect(system.fragments.containsKey('fExclusionRKCB_Spades'), isTrue);
      final frag = system.fragments['fExclusionRKCB_Spades']!;

      final bid5C = frag.bids.firstWhere((b) => b.call.toLowerCase() == '5c');
      expect(bid5C.desc, contains('Club void'));
      expect(bid5C.forceTo, equals(ForcingLevel.slam));

      // Steps over 5C: 5D (0/3), 5H (1/4), 5S (2-Q), 5NT (2+Q)
      final steps5C = bid5C.bids.map((b) => b.call.toLowerCase()).toList();
      expect(steps5C, containsAll(['5d', '5h', '5s', '5nt']));

      final step1 = bid5C.bids.firstWhere((b) => b.call.toLowerCase() == '5d');
      expect(step1.desc, contains('0 or 3 Key Cards'));
      expect(step1.rule, contains('kc=0|3:s'));

      final step2 = bid5C.bids.firstWhere((b) => b.call.toLowerCase() == '5h');
      expect(step2.desc, contains('1 or 4 Key Cards'));
      expect(step2.rule, contains('kc=1|4:s'));

      final step3 = bid5C.bids.firstWhere((b) => b.call.toLowerCase() == '5s');
      expect(step3.desc, contains('2 Key Cards without Queen'));
      expect(step3.rule, contains('kc=2-q:s'));

      final step4 = bid5C.bids.firstWhere((b) => b.call.toLowerCase() == '5nt');
      expect(step4.desc, contains('2 Key Cards with Queen'));
      expect(step4.rule, contains('kc=2+q:s'));
    });

    test('fExclusionRKCB_Hearts defines 0314 steps over 5C, 5D, 5S void jumps', () {
      expect(system.fragments.containsKey('fExclusionRKCB_Hearts'), isTrue);
      final frag = system.fragments['fExclusionRKCB_Hearts']!;

      final bid5D = frag.bids.firstWhere((b) => b.call.toLowerCase() == '5d');
      expect(bid5D.desc, contains('Diamond void'));

      // Steps over 5D: 5H (0/3), 5S (1/4), 5NT (2-Q), 6C (2+Q)
      final steps5D = bid5D.bids.map((b) => b.call.toLowerCase()).toList();
      expect(steps5D, containsAll(['5h', '5s', '5nt', '6c']));

      final step1 = bid5D.bids.firstWhere((b) => b.call.toLowerCase() == '5h');
      expect(step1.desc, contains('0 or 3 Key Cards'));
      expect(step1.rule, contains('kc=0|3:h'));

      final step2 = bid5D.bids.firstWhere((b) => b.call.toLowerCase() == '5s');
      expect(step2.desc, contains('1 or 4 Key Cards'));
      expect(step2.rule, contains('kc=1|4:h'));
    });
  });
}
