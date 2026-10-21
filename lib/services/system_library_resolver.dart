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
    final Map<String, String> libraryDefs = {};

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
          libraryDefs.addAll(libSystem.definitions);

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

    // Base system definitions take ultimate precedence over library default definitions
    final Map<String, String> mergedDefs = Map.of(libraryDefs)..addAll(baseSystem.definitions);

    // Calculate / derive 1NT globals from 1NTOpening if provided
    final ntOpening = baseSystem.definitions['1NTOpening'] ??
        baseSystem.definitions['1ntOpening'] ??
        mergedDefs['1NTOpening'] ??
        mergedDefs['1ntOpening'] ??
        mergedDefs['1NTRange'];
    if (ntOpening != null) {
      final clean = ntOpening.replaceAll('hcp', '').trim();
      final isStrong = clean.startsWith('15') || clean.startsWith('14') || clean.startsWith('16');
      void setIfBaseAbsent(String key, String val) {
        if (!baseSystem.definitions.containsKey(key)) {
          mergedDefs[key] = val;
        }
      }

      setIfBaseAbsent('1NTOpening', '$clean' 'hcp');
      setIfBaseAbsent('1ntOpeningRange', '$clean' 'hcp');
      setIfBaseAbsent('1ntOpeningInvite', isStrong ? '8-9hcp' : '11-12hcp');
      setIfBaseAbsent('1ntOpeningGf', isStrong ? '10+hcp' : '13+hcp');
      setIfBaseAbsent('1ntOpeningPassRange', '7-hcp');

      // Canonical 1NT Rebid variable names
      final rebidRange = isStrong ? '12-14hcp' : '15-17hcp';
      final rebidInvite = isStrong ? '10-11hcp' : '8-10hcp';
      final rebidGf = isStrong ? '12+hcp' : '11+hcp';
      final rebidMin = isStrong ? '12-13hcp' : '15-16hcp';
      final rebidMax = isStrong ? '14hcp' : '17hcp';
      const rebidPass = '7-hcp';

      setIfBaseAbsent('1ntRebidRange', rebidRange);
      setIfBaseAbsent('1ntRebidInviteRange', rebidInvite);
      setIfBaseAbsent('1ntRebidGfRange', rebidGf);
      setIfBaseAbsent('1ntRebidMinRange', rebidMin);
      setIfBaseAbsent('1ntRebidMaxRange', rebidMax);
      setIfBaseAbsent('1ntRebidPassRange', rebidPass);

      // Aliases for compatibility
      setIfBaseAbsent('1ntInviteRange', rebidInvite);
      setIfBaseAbsent('1ntGfRange', rebidGf);
      setIfBaseAbsent('1ntMinRange', rebidMin);
      setIfBaseAbsent('1ntMaxRange', rebidMax);
      setIfBaseAbsent('1ntPassRange', rebidPass);
    }

    // Support 1ntRange alias: if 1ntOpeningRange is set, 1ntRange defaults to opening; otherwise alias 1ntRebidRange
    if (!mergedDefs.containsKey('1ntRange')) {
      if (mergedDefs.containsKey('1ntOpeningRange')) {
        mergedDefs['1ntRange'] = mergedDefs['1ntOpeningRange']!;
      } else if (mergedDefs.containsKey('1ntRebidRange')) {
        mergedDefs['1ntRange'] = mergedDefs['1ntRebidRange']!;
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
