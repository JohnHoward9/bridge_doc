import '../models/bidding_system.dart';

/// Parser for legacy Bridge Bidding System (.bbs) files.
class BbsParser {
  /// Parse the entire contents of a .bbs file into a [BridgeSystem].
  static BridgeSystem parse(String content) {
    // Strip multi-line comments /* ... */
    var cleaned = content.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    // Strip single-line comments // ...
    cleaned = cleaned.replaceAll(RegExp(r'//[^\n]*'), '');

    // Extract System, Player, Partner
    final systemMatch = RegExp(r'System\s*:\s*"([^"]*)"').firstMatch(cleaned);
    final playerMatch = RegExp(r'Player\s*:\s*"([^"]*)"').firstMatch(cleaned);
    final partnerMatch = RegExp(r'Partner\s*:\s*"([^"]*)"').firstMatch(cleaned);

    final systemName = systemMatch?.group(1) ?? 'Bridge Bidding System';
    final player = playerMatch?.group(1);
    final partner = partnerMatch?.group(1);

    // Extract BidDefinitions [ ... ]
    final definitions = <String, String>{};
    final defsMatch = RegExp(r'BidDefinitions\s*\[([\s\S]*?)\]').firstMatch(cleaned);
    if (defsMatch != null) {
      final defsBody = defsMatch.group(1)!;
      final defEntries = RegExp(r'\(\s*\$([a-zA-Z0-9_]+)\s*,\s*([^)]+)\)').allMatches(defsBody);
      for (final m in defEntries) {
        definitions[m.group(1)!] = m.group(2)!.trim();
      }
    }

    // Extract OppositionOpeningBids [ ... ]
    List<BiddingNode> oppositionOpeningBids = [];
    final oppoSection = _extractTopLevelSection(cleaned, 'OppositionOpeningBids');
    if (oppoSection != null) {
      oppositionOpeningBids = _parseBiddingBlock(oppoSection);
    }

    // Extract OpeningBids [ ... ]
    List<BiddingNode> openingBids = [];
    final openingSection = _extractTopLevelSection(cleaned, 'OpeningBids');
    if (openingSection != null) {
      openingBids = _parseBiddingBlock(openingSection);
    }

    // Extract Fragments
    final fragments = <String, Fragment>{};
    final fragMatches = RegExp(r'Fragment\s+([a-zA-Z0-9_]+)\s*\[').allMatches(cleaned);
    for (final fm in fragMatches) {
      final fragName = fm.group(1)!;
      final fragSection = _extractSectionFromIndex(cleaned, fm.end - 1);
      if (fragSection != null) {
        final fragBids = _parseBiddingBlock(fragSection);
        fragments[fragName] = Fragment(name: fragName, bids: fragBids);
      }
    }

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

  /// Extracts the content between matching '[' and ']' for a given section name.
  static String? _extractTopLevelSection(String text, String sectionName) {
    final pattern = RegExp(sectionName + r'\s*\[');
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    return _extractSectionFromIndex(text, match.end - 1);
  }

  /// Extracts matching bracket [ ... ] content starting at bracketIndex.
  static String? _extractSectionFromIndex(String text, int bracketIndex) {
    if (bracketIndex < 0 || bracketIndex >= text.length || text[bracketIndex] != '[') {
      return null;
    }
    int depth = 0;
    int start = bracketIndex + 1;
    for (int i = bracketIndex; i < text.length; i++) {
      if (text[i] == '[') {
        depth++;
      } else if (text[i] == ']') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i);
        }
      }
    }
    return null;
  }

  /// Parses a block of bidding declarations and nested `{ ... }` blocks.
  static List<BiddingNode> _parseBiddingBlock(String block) {
    final List<BiddingNode> nodes = [];
    int i = 0;
    final len = block.length;

    while (i < len) {
      // Skip whitespace
      while (i < len && (block[i] == ' ' || block[i] == '\t' || block[i] == '\r' || block[i] == '\n')) {
        i++;
      }
      if (i >= len) break;

      // Check if closing brace (should be handled by caller, but guard)
      if (block[i] == '}') {
        i++;
        break;
      }

      // Read a single bid declaration up to either '{' or newline/next bid
      int lineStart = i;
      int braceIndex = -1;
      bool inQuotes = false;
      bool inParen = false;

      while (i < len) {
        final char = block[i];
        if (char == '"') {
          inQuotes = !inQuotes;
        } else if (!inQuotes) {
          if (char == '(') {
            inParen = true;
          } else if (char == ')') {
            inParen = false;
          } else if (char == '{' && !inParen) {
            braceIndex = i;
            break;
          } else if (char == '\n' && !inParen) {
            // Check if next non-whitespace is '{'
            int nextNonWs = i + 1;
            while (nextNonWs < len &&
                (block[nextNonWs] == ' ' || block[nextNonWs] == '\t' || block[nextNonWs] == '\r' || block[nextNonWs] == '\n')) {
              nextNonWs++;
            }
            if (nextNonWs < len && block[nextNonWs] == '{') {
              // The brace belongs to this declaration
              i = nextNonWs;
              braceIndex = nextNonWs;
              break;
            } else {
              // End of single-line bid without children
              break;
            }
          }
        }
        i++;
      }

      final declStr = braceIndex != -1
          ? block.substring(lineStart, braceIndex).trim()
          : block.substring(lineStart, i).trim();

      if (declStr.isNotEmpty) {
        final parsedNode = _parseSingleBidDeclaration(declStr);
        if (parsedNode != null) {
          if (braceIndex != -1) {
            // Find matching '}'
            int depth = 1;
            int childStart = braceIndex + 1;
            int j = childStart;
            bool childInQuotes = false;
            while (j < len && depth > 0) {
              final c = block[j];
              if (c == '"') {
                childInQuotes = !childInQuotes;
              } else if (!childInQuotes) {
                if (c == '{') depth++;
                if (c == '}') depth--;
              }
              j++;
            }
            final childBlock = block.substring(childStart, j - 1);
            i = j;

            // Strip optional "{ name responderBids" prefix inside child block
            var cleanChildBlock = childBlock.trim();
            if (cleanChildBlock.startsWith('name ')) {
              final firstNl = cleanChildBlock.indexOf('\n');
              if (firstNl != -1) {
                cleanChildBlock = cleanChildBlock.substring(firstNl + 1);
              }
            }

            final children = _parseBiddingBlock(cleanChildBlock);
            nodes.add(BiddingNode(
              call: parsedNode.call,
              desc: parsedNode.desc,
              rule: parsedNode.rule,
              priority: parsedNode.priority,
              ref: parsedNode.ref,
              condition: parsedNode.condition,
              bids: children,
            ));
          } else {
            nodes.add(parsedNode);
          }
        }
      }
    }

    return nodes;
  }

  /// Parses a declaration string like:
  /// `pass:"No opening available" (10-hcp)`
  /// `[1h-1s]: "5 card major opening" (1h:p#5 ...)`
  /// `3d:"splinter 18+" (p#3 1-d 18-21hcp 4$M) ?1`
  /// `~>"MultiLandy" (p#4) ->fMultiLandy`
  /// `1nt:"Strong bal" (p#3 15-17hcp $bal) ->f1NTResponsesInComp`
  static BiddingNode? _parseSingleBidDeclaration(String text) {
    var s = text.trim();
    if (s.isEmpty) return null;

    // Check for priority at end: ?1, ?2, ?3, ?4
    int? priority;
    final prioMatch = RegExp(r'\?\s*([0-9]+)\s*$').firstMatch(s);
    if (prioMatch != null) {
      priority = int.tryParse(prioMatch.group(1)!);
      s = s.substring(0, prioMatch.start).trim();
    }

    // Check for fragment reference: ->fSomeName
    String? ref;
    final refMatch = RegExp(r'->\s*([a-zA-Z0-9_]+)\s*$').firstMatch(s);
    if (refMatch != null) {
      ref = refMatch.group(1);
      s = s.substring(0, refMatch.start).trim();
    }

    // Check for rule in parentheses at the end: ( ... )
    String? rule;
    if (s.endsWith(')')) {
      int openIdx = -1;
      int depth = 0;
      for (int i = s.length - 1; i >= 0; i--) {
        if (s[i] == ')') depth++;
        if (s[i] == '(') {
          depth--;
          if (depth == 0) {
            openIdx = i;
            break;
          }
        }
      }
      if (openIdx != -1) {
        rule = s.substring(openIdx + 1, s.length - 1).trim();
        s = s.substring(0, openIdx).trim();
      }
    }

    // Check for description in quotes: "desc"
    String desc = '';
    String call = '';
    final quoteMatch = RegExp(r':\s*"([^"]*)"').firstMatch(s);
    if (quoteMatch != null) {
      desc = quoteMatch.group(1)!;
      call = s.substring(0, quoteMatch.start).trim();
    } else {
      // Could be ~>"MultiLandy"
      final tildeMatch = RegExp(r'~>\s*"([^"]*)"').firstMatch(s);
      if (tildeMatch != null) {
        desc = tildeMatch.group(1)!;
        call = '~>${tildeMatch.group(1)!}';
      } else {
        // Fallback: just call
        call = s;
      }
    }

    // Extract condition if present like <$M=h>
    String? condition;
    if (call.startsWith('<') && call.contains('>')) {
      final endCond = call.indexOf('>');
      condition = call.substring(1, endCond);
      // We keep the call intact or clean
    }

    return BiddingNode(
      call: call,
      desc: desc,
      rule: rule,
      priority: priority,
      ref: ref,
      condition: condition,
    );
  }
}
