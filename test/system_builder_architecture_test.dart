import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';

void main() {
  group('Convention-Defined Rules & UI Builder Modularization Tests', () {
    test('Fragment defines rule, desc, priority, and aliases which are inherited by ref-only node', () {
      const yaml = '''
system: "Modular Builder Test"
fragments:
  WalshClubOpening:
    aliases: ["fWalshClubResponses"]
    desc: "Better minor opening (3+ Clubs, 12-21 HCP)"
    rule: "12-21hcp, 3+c, c>=d"
    priority: 1
    bids:
      1d:
        desc: "Natural 4+ Diamonds"
        rule: "6+hcp 4+d"

OpeningBids:
  1c:
    ref: "WalshClubOpening"
''';

      final system = SystemYamlParser.fromYaml(yaml);
      expect(system.fragments.containsKey('WalshClubOpening'), isTrue);
      expect(system.fragments.containsKey('fWalshClubResponses'), isTrue);

      final frag = system.fragments['WalshClubOpening']!;
      expect(frag.desc, equals('Better minor opening (3+ Clubs, 12-21 HCP)'));
      expect(frag.rule, equals('12-21hcp, 3+c, c>=d'));
      expect(frag.priority, equals(1));
      expect(frag.aliases, contains('fWalshClubResponses'));

      // Compile graph and inspect resolved node
      final graph = BiddingGraphCompiler(system: system).compile();
      final rootCandidates = graph.sequenceIndex['']!.candidateNodes;
      final node1c = rootCandidates.firstWhere((n) => n.call == '1c');
      expect(node1c.desc, equals('Better minor opening (3+ Clubs, 12-21 HCP)'));
      expect(node1c.rule, equals('12-21hcp, 3+c, c>=d'));
      expect(node1c.priority, equals(1));

      final state1c = graph.getState(['1c']);
      expect(state1c, isNotNull);
      expect(state1c!.candidateNodes.any((n) => n.call == '1d'), isTrue);
    });

    test('System-level rule and desc override fragment defaults', () {
      const yaml = '''
system: "Override Test"
fragments:
  WalshClubOpening:
    desc: "Default Fragment Description"
    rule: "12-21hcp"
    priority: 2
    bids:
      1d:
        desc: "Natural 4+ Diamonds"

OpeningBids:
  1c:
    desc: "Custom System Override (11-21 HCP)"
    rule: "11-21hcp"
    ref: "WalshClubOpening"
''';

      final system = SystemYamlParser.fromYaml(yaml);
      final graph = BiddingGraphCompiler(system: system).compile();
      final rootCandidates = graph.sequenceIndex['']!.candidateNodes;
      final node1c = rootCandidates.firstWhere((n) => n.call == '1c');
      expect(node1c.desc, equals('Custom System Override (11-21 HCP)'));
      expect(node1c.rule, equals('11-21hcp'));
      expect(node1c.priority, equals(2)); // priority falls back if not set on node
    });

    test('Legacy references using alias work seamlessly without modification', () {
      const yaml = '''
system: "Legacy Alias Test"
fragments:
  GavinHeartOpening:
    aliases: ["fGavinHeartResponses", "fGavinMajors1HResponses"]
    desc: "Gavin 5+ Hearts opening (12-21 HCP)"
    rule: "12-21hcp, 5+h"
    bids:
      1s:
        desc: "1S Response"

OpeningBids:
  1h:
    ref: "fGavinHeartResponses"
''';

      final system = SystemYamlParser.fromYaml(yaml);
      final graph = BiddingGraphCompiler(system: system).compile();
      final rootCandidates = graph.sequenceIndex['']!.candidateNodes;
      final node1h = rootCandidates.firstWhere((n) => n.call == '1h');
      expect(node1h.desc, equals('Gavin 5+ Hearts opening (12-21 HCP)'));
      expect(node1h.rule, equals('12-21hcp, 5+h'));

      final state1h = graph.getState(['1h']);
      expect(state1h, isNotNull);
      expect(state1h!.candidateNodes.any((n) => n.call == '1s'), isTrue);
    });
  });
}
