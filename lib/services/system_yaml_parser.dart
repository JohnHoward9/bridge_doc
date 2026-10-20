import 'package:yaml/yaml.dart';
import '../models/bidding_system.dart';

class SystemYamlParser {
  /// Parse a YAML string into a [BridgeSystem].
  static BridgeSystem fromYaml(String yamlContent) {
    final doc = loadYaml(yamlContent);
    if (doc is! Map) {
      throw FormatException('YAML document root must be a mapping');
    }

    final systemName = doc['system']?.toString() ??
        doc['System']?.toString() ??
        doc['name']?.toString() ??
        'Bridge Bidding System';

    final player = doc['player']?.toString() ?? doc['Player']?.toString();
    final partner = doc['partner']?.toString() ?? doc['Partner']?.toString();

    // Definitions
    final defsRaw = doc['definitions'] ?? doc['Definitions'] ?? doc['BidDefinitions'];
    final Map<String, String> definitions = {};
    if (defsRaw is Map) {
      defsRaw.forEach((k, v) {
        definitions[k.toString()] = v.toString();
      });
    } else if (defsRaw is List) {
      for (final item in defsRaw) {
        if (item is Map) {
          item.forEach((k, v) => definitions[k.toString()] = v.toString());
        }
      }
    }

    // Fragments
    final fragmentsRaw = doc['fragments'] ?? doc['Fragments'] ?? doc['conventions'] ?? doc['Conventions'];
    final Map<String, Fragment> fragments = {};
    if (fragmentsRaw is Map) {
      fragmentsRaw.forEach((key, val) {
        final name = key.toString();
        if (val is Map) {
          final desc = val['desc']?.toString() ?? val['description']?.toString();
          final rule = val['rule']?.toString() ?? val['criteria']?.toString();
          final priority = val['priority'] is int
              ? val['priority'] as int
              : int.tryParse(val['priority']?.toString() ?? '');
          final aliasesRaw = val['aliases'] ?? val['alias'];
          final List<String> aliases = [];
          if (aliasesRaw is List) {
            aliases.addAll(aliasesRaw.map((e) => e.toString()));
          } else if (aliasesRaw is String) {
            aliases.add(aliasesRaw);
          }
          final bids = _parseBids(val['bids'] ?? val['responses'] ?? val['continuations'] ?? val);
          final frag = Fragment(
            name: name,
            desc: desc,
            rule: rule,
            priority: priority,
            aliases: aliases,
            bids: bids,
          );
          fragments[name] = frag;
          for (final alias in aliases) {
            fragments[alias] = frag;
          }
        } else if (val is List) {
          fragments[name] = Fragment(name: name, bids: _parseBids(val));
        }
      });
    }

    // If document itself is a standalone convention library file with 'responses' or 'bids'
    if (doc.containsKey('responses') || (doc.containsKey('bids') && !doc.containsKey('OpeningBids') && !doc.containsKey('openings'))) {
      final libDesc = doc['desc']?.toString() ?? doc['description']?.toString();
      final libRule = doc['rule']?.toString() ?? doc['criteria']?.toString();
      final libBids = _parseBids(doc['responses'] ?? doc['bids']);
      fragments[systemName] = Fragment(name: systemName, desc: libDesc, rule: libRule, bids: libBids);
    }

    // Opening Bids
    final openingRaw = doc['OpeningBids'] ??
        doc['opening_bids'] ??
        doc['openingBids'] ??
        doc['openings'] ??
        doc['Openings'];
    final openingBids = _parseBids(openingRaw);

    // Opposition Opening Bids
    final oppositionRaw = doc['OppositionOpeningBids'] ??
        doc['opposition_opening_bids'] ??
        doc['oppositionOpeningBids'] ??
        doc['defensive'] ??
        doc['DefensiveBids'];
    final oppositionOpeningBids = _parseBids(oppositionRaw);

    return BridgeSystem(
      name: systemName,
      player: player,
      partner: partner,
      definitions: definitions,
      openingBids: openingBids,
      oppositionOpeningBids: oppositionOpeningBids,
      fragments: fragments,
    );
  }

  static List<BiddingNode> _parseBids(dynamic raw) {
    if (raw == null) return [];
    final List<BiddingNode> nodes = [];

    if (raw is Map) {
      raw.forEach((keyStr, val) {
        final key = keyStr.toString();
        // Skip metadata keys if inside map
        if (key == 'desc' || key == 'rule' || key == 'bids' || key == 'priority' || key == 'ref' || key == 'name') {
          return;
        }

        if (val is String) {
          // Shorthand format: 'pass': 'No opening (10-hcp)'
          nodes.add(_parseShorthandBid(key, val));
        } else if (val is Map) {
          final desc = val['desc']?.toString() ?? val['description']?.toString() ?? '';
          final rule = val['rule']?.toString() ?? val['criteria']?.toString();
          final priority = val['priority'] is int
              ? val['priority'] as int
              : int.tryParse(val['priority']?.toString() ?? '');
          final ref = val['ref']?.toString() ??
              val['fragment']?.toString() ??
              val['library']?.toString() ??
              val['convention']?.toString();
          final condition = val['condition']?.toString();
          final childBids = _parseBids(
            val['bids'] ??
            val['responses'] ??
            val['continuations'] ??
            val['partnership'] ??
            val['then'],
          );

          nodes.add(BiddingNode(
            call: key,
            desc: desc,
            rule: rule,
            priority: priority,
            ref: ref,
            condition: condition,
            bids: childBids,
          ));
        }
      });
    } else if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final call = item['call']?.toString();
          if (call != null) {
            final desc = item['desc']?.toString() ?? item['description']?.toString() ?? '';
            final rule = item['rule']?.toString();
            final priority = item['priority'] is int
                ? item['priority'] as int
                : int.tryParse(item['priority']?.toString() ?? '');
            final ref = item['ref']?.toString() ?? item['fragment']?.toString();
            final childBids = _parseBids(item['bids'] ?? item['responses']);

            nodes.add(BiddingNode(
              call: call,
              desc: desc,
              rule: rule,
              priority: priority,
              ref: ref,
              bids: childBids,
            ));
          } else {
            // Nested map entries in list
            nodes.addAll(_parseBids(item));
          }
        }
      }
    }

    return nodes;
  }

  static BiddingNode _parseShorthandBid(String call, String value) {
    // E.g. "No opening available (10-hcp)"
    var desc = value.trim();
    String? rule;
    if (desc.endsWith(')') && desc.contains('(')) {
      final parenIdx = desc.lastIndexOf('(');
      rule = desc.substring(parenIdx + 1, desc.length - 1).trim();
      desc = desc.substring(0, parenIdx).trim();
    }
    return BiddingNode(call: call, desc: desc, rule: rule);
  }

  /// Serialize a [BridgeSystem] into readable, clean YAML.
  static String toYaml(BridgeSystem system) {
    final buffer = StringBuffer();
    buffer.writeln('system: "${_escape(system.name)}"');
    if (system.player != null && system.player!.isNotEmpty) {
      buffer.writeln('player: "${_escape(system.player!)}"');
    }
    if (system.partner != null && system.partner!.isNotEmpty) {
      buffer.writeln('partner: "${_escape(system.partner!)}"');
    }
    buffer.writeln();

    if (system.definitions.isNotEmpty) {
      buffer.writeln('definitions:');
      system.definitions.forEach((k, v) {
        buffer.writeln('  $k: "${_escape(v)}"');
      });
      buffer.writeln();
    }

    buffer.writeln('OpeningBids:');
    _serializeNodes(buffer, system.openingBids, indentLevel: 1);
    buffer.writeln();

    buffer.writeln('OppositionOpeningBids:');
    _serializeNodes(buffer, system.oppositionOpeningBids, indentLevel: 1);
    buffer.writeln();

    if (system.fragments.isNotEmpty) {
      buffer.writeln('Fragments:');
      system.fragments.forEach((name, fragment) {
        buffer.writeln('  $name:');
        if (fragment.desc != null && fragment.desc!.isNotEmpty) {
          buffer.writeln('    desc: "${_escape(fragment.desc!)}"');
        }
        buffer.writeln('    bids:');
        _serializeNodes(buffer, fragment.bids, indentLevel: 3);
      });
    }

    return buffer.toString();
  }

  static void _serializeNodes(StringBuffer buffer, List<BiddingNode> nodes, {required int indentLevel}) {
    final indent = '  ' * indentLevel;
    for (final node in nodes) {
      // Use quotes around call if it contains special characters
      final safeCall = _quoteKeyIfNeeded(node.call);
      buffer.writeln('$indent$safeCall:');
      final childIndent = '  ' * (indentLevel + 1);

      if (node.desc.isNotEmpty) {
        buffer.writeln('$childIndent desc: "${_escape(node.desc)}"');
      }
      if (node.rule != null && node.rule!.isNotEmpty) {
        buffer.writeln('$childIndent rule: "${_escape(node.rule!)}"');
      }
      if (node.priority != null) {
        buffer.writeln('$childIndent priority: ${node.priority}');
      }
      if (node.ref != null && node.ref!.isNotEmpty) {
        buffer.writeln('$childIndent ref: "${_escape(node.ref!)}"');
      }
      if (node.condition != null && node.condition!.isNotEmpty) {
        buffer.writeln('$childIndent condition: "${_escape(node.condition!)}"');
      }
      if (node.bids.isNotEmpty) {
        buffer.writeln('$childIndent bids:');
        _serializeNodes(buffer, node.bids, indentLevel: indentLevel + 2);
      }
    }
  }

  static String _quoteKeyIfNeeded(String key) {
    if (key.contains('[') ||
        key.contains(']') ||
        key.contains('(') ||
        key.contains(')') ||
        key.contains('%') ||
        key.contains('<') ||
        key.contains('>') ||
        key.contains(':') ||
        key.contains('~') ||
        key.contains(' ') ||
        key.startsWith('#')) {
      return '"${_escape(key)}"';
    }
    return key;
  }

  static String _escape(String text) {
    return text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }
}
