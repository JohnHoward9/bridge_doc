import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/services/bbs_parser.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';

void main() {
  test('BbsParser parses system20120910.bbs and converts to YAML', () {
    const bbsPath = r'C:\Users\johnh\Documents\josulasa\bridge_doc\res\system20120910.bbs';
    final file = File(bbsPath);
    expect(file.existsSync(), isTrue);

    final content = file.readAsStringSync();
    final system = BbsParser.parse(content);

    expect(system.name, '3-Way club 5 card Majors');
    expect(system.player, 'John');
    expect(system.partner, 'Andy');
    expect(system.definitions.isNotEmpty, isTrue);
    expect(system.definitions['bal'], 's#5332|4432|4333');
    expect(system.definitions['weakbal'], r'11-14hcp $bal 4-h 4-s');

    print('Parsed definitions: ${system.definitions.length}');
    print('Parsed Opening Bids: ${system.openingBids.length}');
    print('Parsed Opposition Opening Bids: ${system.oppositionOpeningBids.length}');
    print('Parsed Fragments: ${system.fragments.length}');
    print('Total bidding nodes count: ${system.totalNodesCount}');

    expect(system.openingBids.isNotEmpty, isTrue);
    final firstNode = system.openingBids.first;
    expect(firstNode.call.isNotEmpty, isTrue);

    // Test conversion to YAML
    final yamlStr = SystemYamlParser.toYaml(system);
    expect(yamlStr.contains('system: "3-Way club 5 card Majors"'), isTrue);
    expect(yamlStr.contains('pass:'), isTrue);
    expect(yamlStr.contains('OppositionOpeningBids:'), isTrue);

    // Test parsing the generated YAML back into BridgeSystem
    final roundTripped = SystemYamlParser.fromYaml(yamlStr);
    expect(roundTripped.name, system.name);
    expect(roundTripped.player, system.player);
    expect(roundTripped.partner, system.partner);
    expect(roundTripped.definitions.length, system.definitions.length);
    expect(roundTripped.openingBids.length, system.openingBids.length);
    expect(roundTripped.oppositionOpeningBids.length, system.oppositionOpeningBids.length);
    expect(roundTripped.fragments.length, system.fragments.length);
    print('Round-trip successful! Total nodes in round trip: ${roundTripped.totalNodesCount}');
  });
}
