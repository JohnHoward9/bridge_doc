import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final file = File('assets/libraries/conventions/gavin_majors_2over1.yaml');
  final doc = loadYaml(file.readAsStringSync()) as Map;
  final frags = doc['fragments'] as Map;

  final heart = frags['GavinHeartOpening']['bids'] as Map;
  final spade = frags['GavinSpadeOpening']['bids'] as Map;

  print('Heart opening bids: ${heart.keys.toList()}');
  print('Spade opening bids: ${spade.keys.toList()}');

  final common = heart.keys.where((k) => spade.containsKey(k)).toList();
  print('Common bids directly in both: $common');

  // Compare 1NT response tree under 1H vs 1S
  final ntUnderH = heart['1nt'];
  final ntUnderS = spade['1nt'];
  print('\n1NT under 1H bids: ${ntUnderH is Map ? (ntUnderH['bids'] as Map).keys.toList() : 'none'}');
  print('1NT under 1S bids: ${ntUnderS is Map ? (ntUnderS['bids'] as Map).keys.toList() : 'none'}');

  // Compare 2NT (Jacoby 2NT) under 1H vs 1S
  print('\n2NT under 1H: ${heart['2nt']}');
  print('2NT under 1S: ${spade['2nt']}');

  // Compare splinters under 1H vs 1S
  print('\nSplinters under 1H: 3s, 4c, 4d');
  print('Splinters under 1S: 4c, 4d, 4h');

  // Compare interference under 1H vs 1S
  final interfH = heart.keys.where((k) => k.toString().startsWith('(')).toList();
  final interfS = spade.keys.where((k) => k.toString().startsWith('(')).toList();
  print('\nInterference under 1H: $interfH');
  print('Interference under 1S: $interfS');
}
