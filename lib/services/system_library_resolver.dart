import 'dart:io';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import '../models/bidding_system.dart';
import 'system_yaml_parser.dart';

/// Loads a system YAML profile and resolves any imported convention libraries.
class SystemLibraryResolver {
  /// Loads a system YAML string and stitches together all imported libraries.
  static Future<BridgeSystem> loadSystemWithLibraries(
    String systemYamlContent, {
    Future<String> Function(String path)? fileLoader,
  }) async {
    final baseSystem = SystemYamlParser.fromYaml(systemYamlContent);
    final doc = loadYaml(systemYamlContent);
    if (doc is! Map || !doc.containsKey('imports')) {
      return baseSystem;
    }

    final Map<String, Fragment> mergedFragments = Map.of(baseSystem.fragments);
    final Map<String, String> mergedDefs = Map.of(baseSystem.definitions);

    final List<String> toLoad = [];
    if (doc.containsKey('imports') && doc['imports'] is List) {
      for (final imp in doc['imports']) {
        toLoad.add(imp.toString());
      }
    }

    final Set<String> visited = {};

    while (toLoad.isNotEmpty) {
      final importPath = toLoad.removeAt(0);
      if (!visited.add(importPath)) continue;

      try {
        String libContent = '';
        if (fileLoader != null) {
          libContent = await fileLoader(importPath);
        } else {
          // Try loading from Flutter assets or local File
          try {
            libContent = await rootBundle.loadString(importPath);
          } catch (_) {
            final f = File(importPath);
            if (f.existsSync()) {
              libContent = await f.readAsString();
            }
          }
        }

        if (libContent.isNotEmpty) {
          final libSystem = SystemYamlParser.fromYaml(libContent);
          mergedFragments.addAll(libSystem.fragments);
          mergedDefs.addAll(libSystem.definitions);

          // Also register under file basename and full path for library/ref linking
          final baseName = importPath.split('/').last.replaceAll('.yaml', '').replaceAll('.yml', '');
          if (libSystem.openingBids.isNotEmpty) {
            mergedFragments.putIfAbsent(baseName, () => Fragment(name: baseName, bids: libSystem.openingBids));
            mergedFragments.putIfAbsent(importPath, () => Fragment(name: importPath, bids: libSystem.openingBids));
          } else if (libSystem.fragments.isNotEmpty) {
            mergedFragments.putIfAbsent(baseName, () => libSystem.fragments.values.first);
            mergedFragments.putIfAbsent(importPath, () => libSystem.fragments.values.first);
          }

          // Recursively resolve any imports declared by this library
          final libDoc = loadYaml(libContent);
          if (libDoc is Map && libDoc.containsKey('imports') && libDoc['imports'] is List) {
            for (final subImp in libDoc['imports']) {
              final subPath = subImp.toString();
              if (!visited.contains(subPath)) {
                toLoad.add(subPath);
              }
            }
          }
        }
      } catch (e) {
        // Silently skip or log missing library
      }
    }

    return BridgeSystem(
      name: baseSystem.name,
      player: baseSystem.player,
      partner: baseSystem.partner,
      definitions: mergedDefs,
      openingBids: baseSystem.openingBids,
      oppositionOpeningBids: baseSystem.oppositionOpeningBids,
      fragments: mergedFragments,
    );
  }
}
