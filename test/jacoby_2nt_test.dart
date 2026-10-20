import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadSystem(String relativePath) async {
    final file = File(relativePath);
    final yamlStr = await file.readAsString();
    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
  }

  group('Jacoby 2NT Convention Tests (M -> 2NT from system20120910.bbs using variables)', () {
    test('jacoby_2nt.yaml loads and compiles standalone with single fragment fJacoby2NT', () async {
      final yamlContent = await File('assets/libraries/conventions/jacoby_2nt.yaml').readAsString();
      final lib = SystemYamlParser.fromYaml(yamlContent);

      expect(lib.fragments.keys.length, equals(1));
      expect(lib.fragments.containsKey('fJacoby2NT'), isTrue);

      final fJacoby = lib.fragments['fJacoby2NT']!;
      final topCalls = fJacoby.bids.map((b) => b.displayCall.toLowerCase()).toSet();
      expect(topCalls, containsAll(['3c', '3d', '3h', '3s', '3nt', '[4c-4d]', '4h']));
    });

    test(r'Heart Opening (1H -> 2NT): $M=h and $OM=s substitution and BBS continuations', () async {
      final system = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final state1H2NT = engine.graph.getState(['1h', '2nt']);
      expect(state1H2NT, isNotNull);
      final openerCalls = state1H2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      // Opener rebids over 1H - 2NT according to BBS:
      // 3c (any min), 3d (non min no shortage), 3h (short clubs), 3s (short diamonds), 3nt (short OM=s), 4c/4d (55 non min)
      expect(openerCalls, contains('3c'), reason: 'Any minimum');
      expect(openerCalls, contains('3d'), reason: 'Non minimum no shortage');
      expect(openerCalls, contains('3h'), reason: 'Short clubs');
      expect(openerCalls, contains('3s'), reason: 'Short diamonds');
      expect(openerCalls, contains('3nt'), reason: 'Short OM (Spades)');
      expect(openerCalls, contains('4c'), reason: '5-5 non minimum clubs');
      expect(openerCalls, contains('4d'), reason: '5-5 non minimum diamonds');
      expect(openerCalls, isNot(contains('4h')), reason: '4H is not opener rebid directly over 2NT in BBS');

      // 1H - 2NT - 3C (Any minimum) continuations:
      final state3C = engine.graph.getState(['1h', '2nt', '3c']);
      expect(state3C, isNotNull);
      final respCalls3C = state3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3C, contains('3d'), reason: 'Enquiry');
      expect(respCalls3C, contains('3h'), reason: r'3$M: Inv 10-11 HCP');
      expect(respCalls3C, contains('3s'), reason: r'<$M=h> Splinter in Spades');
      expect(respCalls3C, contains('4c'), reason: r'<$M=h> Splinter in Clubs');
      expect(respCalls3C, contains('4d'), reason: r'<$M=h> Splinter in Diamonds');
      expect(respCalls3C, contains('4h'), reason: r'4$M: Inv 12-15 HCP');

      // 1H - 2NT - 3C - 3D (Enquiry) responses:
      final stateEnquiry = engine.graph.getState(['1h', '2nt', '3c', '3d']);
      expect(stateEnquiry, isNotNull);
      final enquiryResponses = stateEnquiry!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(enquiryResponses, contains('3h'), reason: 'Balanced');
      expect(enquiryResponses, contains('3s'), reason: 'Short clubs');
      expect(enquiryResponses, contains('3nt'), reason: 'Short diamonds');
      expect(enquiryResponses, contains('4c'), reason: 'Short OM (Spades)');

      // 1H - 2NT - 3D (Non minimum no shortage) responses:
      final state3D = engine.graph.getState(['1h', '2nt', '3d']);
      expect(state3D, isNotNull);
      final respCalls3D = state3D!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3D, contains('3h'), reason: r'3$M: FG 16+ HCP');
      expect(respCalls3D, contains('3nt'), reason: 'FG 13-15 HCP');
      expect(respCalls3D, contains('4h'), reason: r'4$M: Original inv 10-12 HCP');
      expect(respCalls3D, contains('3s'), reason: r'<$M=h> Splinter in Spades');
      expect(respCalls3D, contains('4c'), reason: r'<$M=h> Splinter in Clubs');
      expect(respCalls3D, contains('4d'), reason: r'<$M=h> Splinter in Diamonds');

      // 1H - 2NT - 3H (Short clubs) responses:
      final state3H = engine.graph.getState(['1h', '2nt', '3h']);
      expect(state3H, isNotNull);
      final respCalls3H = state3H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3H, contains('3s'), reason: r'<$M=h> 3s naturalish 16+ HCP');
      expect(respCalls3H, contains('3nt'), reason: 'FG 13-15 HCP');
      expect(respCalls3H, contains('4c'), reason: '16+ HCP naturalish Clubs');
      expect(respCalls3H, contains('4d'), reason: '16+ HCP naturalish Diamonds');
      expect(respCalls3H, contains('4h'), reason: r'4$M: Original inv 10-12 HCP');

      // 1H - 2NT - 3S (Short diamonds) responses:
      final state3S = engine.graph.getState(['1h', '2nt', '3s']);
      expect(state3S, isNotNull);
      final respCalls3S = state3S!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3S, contains('3nt'), reason: 'FG 13-15 HCP');
      expect(respCalls3S, contains('4c'), reason: '16+ HCP naturalish');
      expect(respCalls3S, contains('4d'), reason: '16+ HCP naturalish');
      expect(respCalls3S, contains('4h'), reason: r'4$M: Original inv 10-12 HCP');

      // 1H - 2NT - 3NT (Short OM = Spades) responses:
      final state3NT = engine.graph.getState(['1h', '2nt', '3nt']);
      expect(state3NT, isNotNull);
      final respCalls3NT = state3NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3NT, contains('4h'), reason: r'4$M: Original inv 10-12 HCP');
      expect(respCalls3NT, contains('4c'), reason: '13+ HCP cue');
      expect(respCalls3NT, contains('4d'), reason: '13+ HCP cue');
    });

    test(r'Spade Opening (1S -> 2NT): $M=s and $OM=h substitution and BBS continuations', () async {
      final system = await loadSystem('assets/core/systems/us_standard_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      final state1S2NT = engine.graph.getState(['1s', '2nt']);
      expect(state1S2NT, isNotNull);
      final openerCalls = state1S2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();

      // Opener rebids over 1S - 2NT according to BBS:
      // 3c, 3d, 3h (short clubs), 3s (short diamonds), 3nt (short OM=h), 4c/4d (55 non min), 4h (<$M=s> 55 non min Hearts)
      expect(openerCalls, contains('3c'), reason: 'Any minimum');
      expect(openerCalls, contains('3d'), reason: 'Non minimum no shortage');
      expect(openerCalls, contains('3h'), reason: 'Short clubs');
      expect(openerCalls, contains('3s'), reason: 'Short diamonds');
      expect(openerCalls, contains('3nt'), reason: 'Short OM (Hearts)');
      expect(openerCalls, contains('4c'), reason: '5-5 non minimum clubs');
      expect(openerCalls, contains('4d'), reason: '5-5 non minimum diamonds');
      expect(openerCalls, contains('4h'), reason: r'5-5 non minimum hearts (<$M=s> 4h)');
      expect(openerCalls, isNot(contains('4s')), reason: '4S is not opener rebid directly over 2NT in BBS');

      // 1S - 2NT - 3C (Any minimum) continuations:
      final state3C = engine.graph.getState(['1s', '2nt', '3c']);
      expect(state3C, isNotNull);
      final respCalls3C = state3C!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3C, contains('3d'), reason: 'Enquiry');
      expect(respCalls3C, contains('3s'), reason: r'3$M: Inv 10-11 HCP');
      expect(respCalls3C, contains('4c'), reason: r'<$M=s> Splinter in Clubs');
      expect(respCalls3C, contains('4d'), reason: r'<$M=s> Splinter in Diamonds');
      expect(respCalls3C, contains('4h'), reason: r'<$M=s> Splinter in Hearts');
      expect(respCalls3C, contains('4s'), reason: r'4$M: Inv 12-15 HCP');

      // 1S - 2NT - 3C - 3D (Enquiry) responses:
      final stateEnquiry = engine.graph.getState(['1s', '2nt', '3c', '3d']);
      expect(stateEnquiry, isNotNull);
      final enquiryResponses = stateEnquiry!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(enquiryResponses, contains('3h'), reason: 'Balanced');
      expect(enquiryResponses, contains('3s'), reason: 'Short clubs');
      expect(enquiryResponses, contains('3nt'), reason: 'Short diamonds');
      expect(enquiryResponses, contains('4c'), reason: 'Short OM (Hearts)');

      // 1S - 2NT - 3H (Short clubs) responses:
      final state3H = engine.graph.getState(['1s', '2nt', '3h']);
      expect(state3H, isNotNull);
      final respCalls3H = state3H!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3H, contains('3s'), reason: r'<$M=s> 3s FG 16+ HCP');
      expect(respCalls3H, contains('3nt'), reason: 'FG 13-15 HCP');
      expect(respCalls3H, contains('4c'), reason: '16+ naturalish');
      expect(respCalls3H, contains('4d'), reason: '16+ naturalish');
      expect(respCalls3H, contains('4s'), reason: r'4$M: Original inv 10-12 HCP');

      // 1S - 2NT - 3NT (Short OM = Hearts) responses:
      final state3NT = engine.graph.getState(['1s', '2nt', '3nt']);
      expect(state3NT, isNotNull);
      final respCalls3NT = state3NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(respCalls3NT, contains('4s'), reason: r'4$M: Original inv 10-12 HCP');
      expect(respCalls3NT, contains('4c'), reason: '13+ cue');
      expect(respCalls3NT, contains('4d'), reason: '13+ cue');
      expect(respCalls3NT, contains('4h'), reason: r'<$M=s> 4h: 13+ cue in Hearts');
    });

    test('Gavin Wolpert System: verifies deduplicated fJacoby2NT works seamlessly over 1H and 1S', () async {
      final system = await loadSystem('assets/core/systems/gavin_wolpert_2over1.yaml');
      final engine = AuctionEngine.fromSystem(system);

      // Over 1H -> 2NT
      final state1H2NT = engine.graph.getState(['1h', '2nt']);
      expect(state1H2NT, isNotNull);
      final calls1H2NT = state1H2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls1H2NT, containsAll(['3c', '3d', '3h', '3s', '3nt', '4c', '4d']));

      // Over 1S -> 2NT
      final state1S2NT = engine.graph.getState(['1s', '2nt']);
      expect(state1S2NT, isNotNull);
      final calls1S2NT = state1S2NT!.candidateNodes.map((n) => n.displayCall.toLowerCase()).toSet();
      expect(calls1S2NT, containsAll(['3c', '3d', '3h', '3s', '3nt', '4c', '4d', '4h']));
    });
  });
}
