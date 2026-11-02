import 'dart:io';
import 'package:yaml/yaml.dart';

class BidSummary {
  final String call;
  final String? desc;
  final String? rule;
  final String? ref;
  final Map<String, dynamic>? vars;
  final List<String> childCalls;
  final int totalDescendantNodes;

  BidSummary({
    required this.call,
    this.desc,
    this.rule,
    this.ref,
    this.vars,
    required this.childCalls,
    required this.totalDescendantNodes,
  });
}

int countNodes(dynamic bidsNode) {
  if (bidsNode is! Map) return 0;
  int count = 0;
  for (final entry in bidsNode.entries) {
    count++;
    final val = entry.value;
    if (val is Map && val.containsKey('bids')) {
      count += countNodes(val['bids']);
    }
  }
  return count;
}

List<String> getChildCalls(dynamic bidsNode) {
  if (bidsNode is! Map) return [];
  return bidsNode.keys.map((k) => k.toString()).toList()..sort();
}

void main() {
  final dir = Directory('assets');
  final yamlFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
      .toList();

  print('Scanning ${yamlFiles.length} YAML files...\n');

  final fragmentDefinitions = <String, List<String>>{};
  final sameRefSiblings = <String>[];
  final identicalChildTrees = <String>[];
  final interferenceBids = <String, List<String>>{};
  final texasTransfersFound = <String>[];
  final gerberFound = <String>[];
  final jacobyTransfersFound = <String>[];

  for (final file in yamlFiles) {
    final content = file.readAsStringSync();
    dynamic doc;
    try {
      doc = loadYaml(content);
    } catch (e) {
      print('Error parsing ${file.path}: $e');
      continue;
    }
    if (doc is! Map) continue;

    final frags = doc['fragments'];
    if (frags is Map) {
      for (final fragEntry in frags.entries) {
        final fragName = fragEntry.key.toString();
        fragmentDefinitions.putIfAbsent(fragName, () => []).add(file.path);

        final fragVal = fragEntry.value;
        if (fragVal is Map && fragVal.containsKey('bids') && fragVal['bids'] is Map) {
          final bidsMap = fragVal['bids'] as Map;

          // 1. Check for Texas Transfers (4d/4h) in this fragment
          final has4d = bidsMap.containsKey('4d');
          final has4h = bidsMap.containsKey('4h');
          if (has4d && has4h) {
            texasTransfersFound.add('${file.path} -> $fragName (bids: 4d and 4h)');
          }

          // 2. Check for Gerber (4c)
          if (bidsMap.containsKey('4c')) {
            final c4 = bidsMap['4c'];
            if (c4 is Map && (c4['desc']?.toString().toLowerCase().contains('gerber') == true ||
                c4['rule']?.toString().toLowerCase().contains('ace') == true)) {
              gerberFound.add('${file.path} -> $fragName (4c Gerber)');
            }
          }

          // 3. Check for Jacoby Transfers (2d/2h)
          final has2d = bidsMap.containsKey('2d');
          final has2h = bidsMap.containsKey('2h');
          if (has2d && has2h) {
            final d2Desc = bidsMap['2d'] is Map ? (bidsMap['2d']['desc']?.toString().toLowerCase() ?? '') : '';
            final h2Desc = bidsMap['2h'] is Map ? (bidsMap['2h']['desc']?.toString().toLowerCase() ?? '') : '';
            if (d2Desc.contains('transfer') || h2Desc.contains('transfer')) {
              jacobyTransfersFound.add('${file.path} -> $fragName (2d and 2h Jacoby Transfers)');
            }
          }

          // Check sibling bids sharing same ref
          final byRef = <String, List<String>>{};
          final byChildren = <String, List<String>>{};

          for (final bEntry in bidsMap.entries) {
            final bidCall = bEntry.key.toString();
            final bVal = bEntry.value;

            // Interference
            if (bidCall.startsWith('(') && bidCall.endsWith(')')) {
              interferenceBids.putIfAbsent(bidCall, () => []).add('${file.path}::$fragName');
            }

            if (bVal is Map) {
              final ref = bVal['ref']?.toString();
              if (ref != null) {
                byRef.putIfAbsent(ref, () => []).add(bidCall);
              }

              final childBids = bVal['bids'];
              if (childBids is Map && childBids.isNotEmpty) {
                final childKeys = getChildCalls(childBids).join(',');
                final totalNodes = countNodes(childBids);
                if (totalNodes >= 2) {
                  byChildren.putIfAbsent(childKeys, () => []).add('$bidCall ($totalNodes child nodes)');
                }
              }
            }
          }

          for (final refEntry in byRef.entries) {
            if (refEntry.value.length > 1) {
              sameRefSiblings.add('${file.path} -> $fragName: bids ${refEntry.value} both call ref "${refEntry.key}"');
            }
          }

          for (final childEntry in byChildren.entries) {
            if (childEntry.value.length > 1) {
              identicalChildTrees.add('${file.path} -> $fragName: bids ${childEntry.value} share child pattern [${childEntry.key}]');
            }
          }
        }
      }
    }
  }

  print('=== 1. FRAGMENTS DEFINED IN MULTIPLE FILES ===');
  for (final entry in fragmentDefinitions.entries) {
    if (entry.value.length > 1) {
      print('• ${entry.key} (${entry.value.length} files):');
      for (final p in entry.value) {
        print('    - $p');
      }
    }
  }

  print('\n=== 2. TEXAS TRANSFERS (4D / 4H) LOCATIONS ===');
  for (final loc in texasTransfersFound) {
    print('• $loc');
  }

  print('\n=== 3. GERBER (4C) LOCATIONS ===');
  for (final loc in gerberFound) {
    print('• $loc');
  }

  print('\n=== 4. JACOBY TRANSFERS (2D / 2H) LOCATIONS ===');
  for (final loc in jacobyTransfersFound) {
    print('• $loc');
  }

  print('\n=== 5. SIBLINGS SHARING IDENTICAL REF (Parallel Variable Invocations) ===');
  for (final s in sameRefSiblings) {
    print('• $s');
  }

  print('\n=== 6. SIBLINGS WITH UN-FACTORED INLINE CHILD TREES ===');
  for (final s in identicalChildTrees) {
    print('• $s');
  }

  print('\n=== 7. INLINE INTERFERENCE CALLS REPEATED ACROSS FRAGMENTS ===');
  final sortedInterf = interferenceBids.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final entry in sortedInterf) {
    if (entry.value.length > 1) {
      print('• ${entry.key}: ${entry.value.length} occurrences:');
      for (final loc in entry.value.take(4)) {
        print('    - $loc');
      }
      if (entry.value.length > 4) {
        print('    ... and ${entry.value.length - 4} more');
      }
    }
  }
}
