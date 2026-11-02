import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final dir = Directory('assets');
  final yamlFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
      .toList();

  print('Analyzing ${yamlFiles.length} files for duplication...\n');

  // 1. Files by line count
  final fileLines = <String, int>{};
  for (final f in yamlFiles) {
    fileLines[f.path] = f.readAsLinesSync().length;
  }
  final sortedFiles = fileLines.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  print('Top 15 Largest YAML Files:');
  for (final entry in sortedFiles.take(15)) {
    print('  ${entry.value.toString().padLeft(5)} lines: ${entry.key}');
  }

  // 2. Scan for duplicate subtrees across all files
  final subtrees = <String, List<String>>{};
  for (final f in yamlFiles) {
    final content = f.readAsStringSync();
    dynamic doc;
    try {
      doc = loadYaml(content);
    } catch (_) {
      continue;
    }
    if (doc is! Map) continue;

    void traverse(dynamic node, String currentPath) {
      if (node is Map) {
        if (node.containsKey('bids') && node['bids'] is Map) {
          final bids = node['bids'] as Map;
          final keys = (bids.keys.map((k) => k.toString()).toList()..sort()).join(',');
          if (keys.length > 5 && bids.length >= 3) {
            subtrees.putIfAbsent(keys, () => []).add('$currentPath (keys: [$keys])');
          }
          for (final e in bids.entries) {
            traverse(e.value, '$currentPath -> ${e.key}');
          }
        }
        if (node.containsKey('fragments') && node['fragments'] is Map) {
          for (final e in (node['fragments'] as Map).entries) {
            traverse(e.value, '${f.path}::${e.key}');
          }
        }
      }
    }

    traverse(doc, f.path);
  }

  print('\n=== SUBTREES WITH IDENTICAL SIBLING BIDS (>= 3 bids) APPEARING IN >= 2 PLACES ===');
  final repeatedSubtrees = subtrees.entries.where((e) => e.value.length > 1).toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final entry in repeatedSubtrees.take(20)) {
    print('\nPattern: [${entry.key}] (${entry.value.length} occurrences)');
    for (final loc in entry.value.take(5)) {
      print('  * $loc');
    }
    if (entry.value.length > 5) {
      print('  ... and ${entry.value.length - 5} more');
    }
  }
}
