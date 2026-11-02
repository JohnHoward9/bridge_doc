import 'package:flutter/foundation.dart';

/// Represents an entire Bridge Bidding System definition.
class BridgeSystem {
  final String name;
  final String? player;
  final String? partner;
  final Map<String, String> definitions;
  final List<BiddingNode> openingBids;
  final List<BiddingNode> oppositionOpeningBids;
  final Map<String, Fragment> fragments;

  BridgeSystem({
    required this.name,
    this.player,
    this.partner,
    Map<String, String>? definitions,
    List<BiddingNode>? openingBids,
    List<BiddingNode>? oppositionOpeningBids,
    Map<String, Fragment>? fragments,
  })  : definitions = definitions ?? {},
        openingBids = openingBids ?? [],
        oppositionOpeningBids = oppositionOpeningBids ?? [],
        fragments = fragments ?? {};

  /// Total count of bidding nodes defined across opening and opposition trees.
  int get totalNodesCount {
    int count(List<BiddingNode> nodes) {
      int total = 0;
      for (final n in nodes) {
        total += 1 + count(n.bids);
      }
      return total;
    }
    return count(openingBids) + count(oppositionOpeningBids);
  }
}

/// The partnership forcing commitment level established by bids during an auction.
enum ForcingLevel {
  partScore(0, 'partScore'),
  game(1, 'game'),
  slam(2, 'slam'),
  grandSlam(3, 'grandSlam');

  final int rank;
  final String label;
  const ForcingLevel(this.rank, this.label);

  static ForcingLevel fromString(String? str) {
    if (str == null) return ForcingLevel.partScore;
    final clean = str.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
    switch (clean) {
      case 'game':
      case 'gf':
        return ForcingLevel.game;
      case 'slam':
      case 'sf':
        return ForcingLevel.slam;
      case 'grandslam':
      case 'grand':
      case 'gsf':
        return ForcingLevel.grandSlam;
      case 'partscore':
      default:
        return ForcingLevel.partScore;
    }
  }

  bool get isForced => this != ForcingLevel.partScore;

  /// Checks if [rawCall] satisfies this [forcingLevel].
  static bool isContractSatisfied(String rawCall, ForcingLevel forcingLevel) {
    if (forcingLevel == ForcingLevel.partScore) return true;
    final clean = rawCall.toLowerCase().replaceAll('(', '').replaceAll(')', '').trim();
    if (clean.length < 2) return false;
    final level = int.tryParse(clean.substring(0, 1));
    if (level == null || level < 1 || level > 7) return false;
    final strain = clean.substring(1).trim();

    if (forcingLevel == ForcingLevel.grandSlam) {
      return level >= 7;
    }
    if (forcingLevel == ForcingLevel.slam) {
      return level >= 6;
    }
    if (forcingLevel == ForcingLevel.game) {
      if (level >= 6) return true;
      if (strain == 'nt') return level >= 3;
      if (strain == 'h' || strain == 's') return level >= 4;
      if (strain == 'c' || strain == 'd') return level >= 5;
    }
    return false;
  }
}

/// A reusable bidding convention or subroutine fragment (e.g. `fMultiLandy`, `WalshClubOpening`).
class Fragment {
  final String name;
  final String? desc;
  final String? rule;
  final int? priority;
  final String? ref;
  final List<String> includes;
  final List<String> aliases;
  final String? agreedSuit;
  final Map<String, String> variables;
  final ForcingLevel forceTo;
  final List<BiddingNode> bids;

  Fragment({
    required this.name,
    this.desc,
    this.rule,
    this.priority,
    this.ref,
    this.includes = const [],
    this.aliases = const [],
    this.agreedSuit,
    Map<String, String>? variables,
    ForcingLevel? forceTo,
    List<BiddingNode>? bids,
  })  : forceTo = forceTo ?? ForcingLevel.partScore,
        variables = BiddingNode.enrichSuitVariables(
          BiddingNode._extractVariablesFromRule(rule, variables),
          agreedSuit: agreedSuit,
        ),
        bids = bids ?? [];
}

/// A node in the bidding tree.
class BiddingNode {
  /// The call text as defined, e.g. "pass", "1c", "(1s)", "[1h-1s]", "<$M=h>1s", "~>MultiLandy", "step#1".
  final String call;

  /// Meaning or description, e.g. "Drury 3-4", "Takeout", "No opening available".
  final String desc;

  /// Hand evaluation / shape / hcp constraints, e.g. "10-hcp", "p#3 5-10hcp 4s 2-h".
  final String? rule;

  /// Optional priority (e.g. from ?1, ?2 or p#1..p#10). Lower number = higher priority.
  final int? priority;

  /// Fragment reference if this bid redirects/branches to a fragment (e.g. "fMultiLandy").
  final String? ref;

  /// Additional fragment mixins whose child bids are merged with this node's [bids].
  final List<String> includes;

  /// Explicit condition if parsed (e.g. "$M=h").
  final String? condition;

  /// Explicit agreed trump suit established by this bid (e.g. "h", "s", "$M").
  final String? agreedSuit;

  /// Context variables bound at this node, e.g. { 'M': 'h', 'OM': 's', 'os': 'h' }.
  final Map<String, String> variables;

  /// Forcing level established by this bid (defaults to [ForcingLevel.partScore]).
  final ForcingLevel forceTo;

  /// Child responses / follow-up bids.
  final List<BiddingNode> bids;

  BiddingNode({
    required this.call,
    this.desc = '',
    this.rule,
    this.priority,
    this.ref,
    this.includes = const [],
    this.condition,
    this.agreedSuit,
    Map<String, String>? variables,
    ForcingLevel? forceTo,
    List<BiddingNode>? bids,
  })  : forceTo = forceTo ?? ForcingLevel.partScore,
        variables = enrichSuitVariables(_extractVariablesFromRule(rule, variables), agreedSuit: agreedSuit),
        bids = bids ?? [];

  static const List<String> _bridgeBidLadder = [
    '1c', '1d', '1h', '1s', '1nt',
    '2c', '2d', '2h', '2s', '2nt',
    '3c', '3d', '3h', '3s', '3nt',
    '4c', '4d', '4h', '4s', '4nt',
    '5c', '5d', '5h', '5s', '5nt',
    '6c', '6d', '6h', '6s', '6nt',
    '7c', '7d', '7h', '7s', '7nt',
  ];

  /// Resolves a relative step call (e.g. `step#1`, `step#2`) relative to [parentCall].
  /// Preserves any inline `<condition>` prefix if present.
  static String resolveStepCall(String childCall, String parentCall) {
    var trimmed = childCall.trim();
    String? prefix;
    if (trimmed.startsWith('<') && trimmed.contains('>')) {
      final end = trimmed.indexOf('>');
      prefix = trimmed.substring(0, end + 1);
      trimmed = trimmed.substring(end + 1).trim();
    }
    final stepMatch = RegExp(r'^step#(\d+)$', caseSensitive: false).firstMatch(trimmed);
    if (stepMatch == null) return childCall;

    final stepOffset = int.tryParse(stepMatch.group(1)!);
    if (stepOffset == null || stepOffset <= 0) return childCall;

    var cleanParent = parentCall.trim().toLowerCase();
    if (cleanParent.startsWith('<') && cleanParent.contains('>')) {
      cleanParent = cleanParent.substring(cleanParent.indexOf('>') + 1).trim();
    }
    cleanParent = cleanParent.replaceAll('(', '').replaceAll(')', '').trim();

    final parentIdx = _bridgeBidLadder.indexOf(cleanParent);
    if (parentIdx == -1 || parentIdx + stepOffset >= _bridgeBidLadder.length) {
      return childCall;
    }

    final resolved = _bridgeBidLadder[parentIdx + stepOffset];
    return prefix != null ? '$prefix $resolved' : resolved;
  }

  /// Returns the other major suit character ('h' -> 's', 's' -> 'h').
  static String otherMajor(String major) {
    final m = major.toLowerCase().replaceAll(r'$', '').trim();
    if (m == 'h') return 's';
    if (m == 's') return 'h';
    return '';
  }

  /// Returns the other minor suit character ('c' -> 'd', 'd' -> 'c').
  static String otherMinor(String minor) {
    final m = minor.toLowerCase().replaceAll(r'$', '').trim();
    if (m == 'c') return 'd';
    if (m == 'd') return 'c';
    return '';
  }

  static String suitName(String s) => _suitName(s);
  static String suitSym(String s) => _suitSym(s);

  static String _suitName(String s) =>
      s == 'h' ? 'Hearts' : (s == 's' ? 'Spades' : (s == 'd' ? 'Diamonds' : (s == 'c' ? 'Clubs' : s)));

  static String _suitSym(String s) =>
      s == 'h' ? '♥' : (s == 's' ? '♠' : (s == 'd' ? '♦' : (s == 'c' ? '♣' : s)));

  /// Enriches suit variables ($M, $OM, $m, $om, $suit, $trump, $os, $agreedSuit) with their _name and _sym counterparts.
  static Map<String, String> enrichSuitVariables(
    Map<String, String> input, {
    String? agreedSuit,
  }) {
    if (input.isEmpty && (agreedSuit == null || agreedSuit.isEmpty)) return input;
    final map = Map<String, String>.from(input);

    if (agreedSuit != null && agreedSuit.isNotEmpty) {
      map['agreedSuit'] = agreedSuit;
      map['agreed_suit'] = agreedSuit;
      map['trump'] = agreedSuit;
    } else if (map.containsKey('agreedSuit') && map['agreedSuit']!.isNotEmpty) {
      final s = map['agreedSuit']!;
      map['agreed_suit'] = s;
      map['trump'] = s;
    }

    if (map.containsKey('agreedSuit')) {
      final s = map['agreedSuit']!;
      if (s == 'h' || s == 's') {
        map['M'] = s;
        map['OM'] = otherMajor(s);
      }
    }

    if (map.containsKey('M') && !map.containsKey('OM')) {
      final om = otherMajor(map['M']!);
      if (om.isNotEmpty) map['OM'] = om;
    }
    if (map.containsKey('m') && !map.containsKey('om')) {
      final om = otherMinor(map['m']!);
      if (om.isNotEmpty) map['om'] = om;
    }
    if (map.containsKey('oppos') && !map.containsKey('os')) {
      map['os'] = map['oppos']!;
    } else if (map.containsKey('os') && !map.containsKey('oppos')) {
      map['oppos'] = map['os']!;
    }
    if (map.containsKey('os') && !map.containsKey('OM')) {
      final om = otherMajor(map['os']!);
      if (om.isNotEmpty) map['OM'] = om;
    }

    for (final k in ['M', 'OM', 'm', 'om', 'os', 'oppos', 'suit', 'trump', 'agreedSuit', 'agreed_suit']) {
      if (map.containsKey(k) && map[k]!.isNotEmpty) {
        final v = map[k]!;
        map['${k}_name'] = _suitName(v);
        map['${k}_sym'] = _suitSym(v);
      }
    }
    return map;
  }

  static Map<String, String> _extractVariablesFromRule(String? ruleText, [Map<String, String>? existingVars]) {
    if (ruleText == null && (existingVars == null || existingVars.isEmpty)) return {};
    final map = <String, String>{};
    if (existingVars != null) {
      map.addAll(existingVars);
    }
    // Match [$M=h, $OM=s, $os=h] or [$OM=otherMajor($M)]
    final match = ruleText != null ? RegExp(r'\[([^\]]+)\]').firstMatch(ruleText) : null;
    if (match != null) {
      final inner = match.group(1)!;
      final pairs = inner.split(',');
      for (final p in pairs) {
        final kv = p.split('=');
        if (kv.length == 2) {
          final key = kv[0].replaceAll(r'$', '').trim();
          var val = kv[1].trim();

          // Resolve function expressions: otherMajor($M), otherMinor($m)
          if (val.startsWith('otherMajor(') && val.endsWith(')')) {
            final arg = val.substring('otherMajor('.length, val.length - 1).replaceAll(r'$', '').trim();
            final resolvedArg = map[arg] ?? (arg == 'h' || arg == 's' ? arg : '');
            if (resolvedArg.isNotEmpty) {
              val = otherMajor(resolvedArg);
            } else {
              continue;
            }
          } else if (val.startsWith('otherMinor(') && val.endsWith(')')) {
            final arg = val.substring('otherMinor('.length, val.length - 1).replaceAll(r'$', '').trim();
            final resolvedArg = map[arg] ?? (arg == 'c' || arg == 'd' ? arg : '');
            if (resolvedArg.isNotEmpty) {
              val = otherMinor(resolvedArg);
            } else {
              continue;
            }
          }

          if (val.startsWith(r'$')) {
            final varName = val.substring(1).trim();
            if (map.containsKey(varName)) {
              val = map[varName]!;
            } else {
              continue;
            }
          }

          if (val.isNotEmpty) {
            map[key] = val;
          }
        }
      }
    }

    return enrichSuitVariables(map);
  }

  /// Priority defined either via explicit field or p# rule tag from Bridge.g grammar.
  int? get effectivePriority {
    if (priority != null) return priority;
    if (rule != null) {
      final pMatch = RegExp(r'p#(\d+)').firstMatch(rule!);
      if (pMatch != null) {
        return int.tryParse(pMatch.group(1)!);
      }
    }
    return null;
  }

  /// Returns true if this call represents an opponent bid (typically wrapped in parentheses).
  bool get isOpponent {
    final trimmed = call.trim();
    return (trimmed.startsWith('(') && trimmed.endsWith(')')) ||
        trimmed.contains('50%') ||
        trimmed.contains('25%');
  }

  /// Clean display text for chip / badge.
  String get displayCall {
    var c = call.trim();
    // Strip leading condition like <$M=h>
    if (c.startsWith('<') && c.contains('>')) {
      final end = c.indexOf('>');
      c = c.substring(end + 1).trim();
    }
    // If it's an opponent bid like (1s) or (50%SAYC.1c), strip outer parens for cleaner badge if needed
    if (c.startsWith('(') && c.endsWith(')')) {
      c = c.substring(1, c.length - 1).trim();
    }
    if (c.contains('.')) {
      final parts = c.split('.');
      if (parts.length == 2) {
        c = parts[1];
      }
    }
    return c;
  }

  /// Returns the call key for auction sequence tracking and graph state lookups.
  /// Opposition bids retain parentheses, e.g. "(2d)", while friendly bids are "2d".
  String get auctionCall {
    if (isOpponent || call.trim().startsWith('(')) {
      return '($displayCall)';
    }
    return displayCall;
  }

  /// Suit character: 'C', 'D', 'H', 'S', 'NT' or null.
  String? get suit {
    final c = displayCall.toLowerCase();
    if (c.contains('nt')) return 'NT';
    if (c.contains('c') && !c.contains('pass') && !c.contains('dbl')) return 'C';
    if (c.contains('d') && !c.contains('pass') && !c.contains('dbl')) return 'D';
    if (c.contains('h')) return 'H';
    if (c.contains('s')) return 'S';
    return null;
  }

  bool get isPass => displayCall.toLowerCase().contains('pass');
  bool get isDbl => displayCall.toLowerCase() == 'dbl' || displayCall.toLowerCase().contains('double');
  bool get isRdbl => displayCall.toLowerCase() == 'rdbl' || displayCall.toLowerCase().contains('redouble');
  bool get isJumpConvention => call.trim().startsWith('~>') || (ref != null && ref!.isNotEmpty);

  /// Returns true if this node is an inline conditional continuation router (~>) rather than a physical call.
  bool get isConditionalBranch => call.trim().startsWith('~>');

  /// Level if natural bid (1-7), null otherwise.
  int? get level {
    final c = displayCall;
    if (c.isNotEmpty && c[0].compareTo('1') >= 0 && c[0].compareTo('7') <= 0) {
      return int.tryParse(c[0]);
    }
    return null;
  }

  /// Extracted condition if any, e.g. `<$M=h>` -> `$M=h`.
  String? get inlineCondition {
    if (condition != null) return condition;
    final trimmed = call.trim();
    if (trimmed.startsWith('<') && trimmed.contains('>')) {
      return trimmed.substring(1, trimmed.indexOf('>'));
    }
    return null;
  }

  /// Checks if this node's condition (e.g. `<$M=h>`, `<$suit=c,d>`, `<$M>`, `<!$m>`) is satisfied in [activeVariables].
  bool isConditionSatisfied(Map<String, String> activeVariables) {
    final cond = inlineCondition;
    if (cond == null || cond.isEmpty) return true;

    final isNot = cond.startsWith('!') || cond.contains('!=');
    final cleanCond = cond.startsWith('!') ? cond.substring(1) : cond;
    final sep = cleanCond.contains('!=') ? '!=' : (cleanCond.contains('=') ? '=' : null);

    if (sep != null) {
      final parts = cleanCond.split(sep);
      final key = parts[0].replaceAll(r'$', '').trim();
      final expectedVals = parts[1].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final actualVal = activeVariables[key];
      final matches = actualVal != null && expectedVals.contains(actualVal);
      return isNot ? !matches : matches;
    } else {
      // Variable presence check, e.g. <$M> or <$m>
      final key = cleanCond.replaceAll(r'$', '').trim();
      final actualVal = activeVariables[key];
      final hasVar = actualVal != null && actualVal.isNotEmpty;
      return isNot ? !hasVar : hasVar;
    }
  }

  /// Returns a clone of this node with variable values ($M, $OM, $m, $om, etc.)
  /// substituted into call, rule, and desc.
  BiddingNode substituted(Map<String, String> activeVariables) {
    if (activeVariables.isEmpty) return this;

    String subText(String text) {
      var result = text;
      final sortedKeys = activeVariables.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (final k in sortedKeys) {
        final v = activeVariables[k]!;
        if (k == 'M' || k == 'OM' || k == 'os' || k == 'oppos' || k == 'om' || k == 'm' || k == 'suit' || k == 'trump') {
          final sym = v == 'h' ? '♥' : (v == 's' ? '♠' : (v == 'd' ? '♦' : (v == 'c' ? '♣' : v)));
          result = result.replaceAll('\$${k}_sym', sym);
          final name = v == 'h' ? 'Hearts' : (v == 's' ? 'Spades' : (v == 'd' ? 'Diamonds' : 'Clubs'));
          result = result.replaceAll('\$${k}_name', name);
        }
        result = result.replaceAll('\$$k', v);
      }
      return result;
    }

    final newCall = subText(call);
    final newDesc = subText(desc);
    final newRule = rule != null ? subText(rule!) : null;

    return BiddingNode(
      call: newCall,
      desc: newDesc,
      rule: newRule,
      priority: priority,
      ref: ref,
      includes: includes,
      condition: condition,
      variables: variables,
      forceTo: forceTo,
      bids: bids,
    );
  }

  /// Expands compound bids like `[1d-1h]`, `[1h-1s]`, `[2c-2d]`, `[2h,2s]`, `[3c,3d]` into individual
  /// candidate bids, binding their respective variables.
  List<BiddingNode> expandCompoundBid() {
    var trimmedCall = call.trim();
    String? prefixCond = condition;
    if (trimmedCall.startsWith('<') && trimmedCall.contains('>')) {
      final end = trimmedCall.indexOf('>');
      prefixCond ??= trimmedCall.substring(1, end).trim();
      trimmedCall = trimmedCall.substring(end + 1).trim();
    }
    if (!trimmedCall.startsWith('[') || !trimmedCall.endsWith(']')) {
      return [this];
    }

    final inner = trimmedCall.substring(1, trimmedCall.length - 1).trim();

    // Check if inner is step indices like [1], [2], [3]
    if (RegExp(r'^\d+$').hasMatch(inner)) {
      return [this];
    }

    // Determine candidate calls from dash [1d-1h] or comma [2h,2s]
    List<String> subCalls = [];
    if (inner.contains('-')) {
      subCalls = inner.split('-').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (inner.contains(',')) {
      subCalls = inner.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else {
      subCalls = [inner];
    }

    if (subCalls.isEmpty) return [this];

    // If rule is split with ^ (e.g. "1d:p#4 4+h [$M=h] ^ 1h:p#5 4+s [$M=s]")
    if (rule != null && rule!.contains('^')) {
      final rParts = rule!.split('^').map((s) => s.trim()).toList();
      final List<BiddingNode> expanded = [];

      for (int i = 0; i < subCalls.length; i++) {
        final subCall = subCalls[i];
        String partRule = i < rParts.length ? rParts[i] : rule!;
        Map<String, String> partVars = {};

        // If partRule has explicit call prefix like "1d:..."
        if (partRule.contains(':')) {
          final colonIdx = partRule.indexOf(':');
          final prefix = partRule.substring(0, colonIdx).trim();
          if (prefix.toLowerCase() == subCall.toLowerCase() || prefix.startsWith(subCall)) {
            partRule = partRule.substring(colonIdx + 1).trim();
          }
        }

        // Extract variables from this specific part
        partVars = _extractVariablesFromRule(partRule);

        // Fallback default major bindings for common compound forms
        if (!partVars.containsKey('M')) {
          if (subCall.endsWith('h')) {
            partVars['M'] = 'h';
            partVars['OM'] = otherMajor('h');
          } else if (subCall.endsWith('s')) {
            partVars['M'] = 's';
            partVars['OM'] = otherMajor('s');
          }
        }

        expanded.add(BiddingNode(
          call: prefixCond != null ? '<$prefixCond> $subCall' : subCall,
          condition: prefixCond,
          desc: desc.isNotEmpty ? '$desc ($subCall)' : subCall,
          rule: partRule,
          priority: priority,
          ref: ref,
          variables: partVars,
          forceTo: forceTo,
          bids: bids,
        ));
      }

      return expanded;
    }

    // Otherwise compound list with unified rule (e.g. "[3c,3d]" with rule "5$M 4+%")
    final List<BiddingNode> expanded = [];
    for (final subCall in subCalls) {
      var subRule = rule;
      final partVars = <String, String>{};

      // Substitute % with suit character of subCall if present
      String suitChar = '';
      if (subCall.endsWith('c')) suitChar = 'c';
      if (subCall.endsWith('d')) suitChar = 'd';
      if (subCall.endsWith('h')) suitChar = 'h';
      if (subCall.endsWith('s')) suitChar = 's';
      if (suitChar.isNotEmpty) {
        if (subRule != null && subRule.contains('%')) {
          subRule = subRule.replaceAll('%', suitChar);
        }
        partVars['%'] = suitChar;
        partVars['suit'] = suitChar;
        final name = suitChar == 'h' ? 'Hearts' : (suitChar == 's' ? 'Spades' : (suitChar == 'd' ? 'Diamonds' : 'Clubs'));
        final sym = suitChar == 'h' ? '♥' : (suitChar == 's' ? '♠' : (suitChar == 'd' ? '♦' : '♣'));
        partVars['suit_name'] = name;
        partVars['suit_sym'] = sym;
      }

      final isMajorTransfer = (inner.contains('4d') && inner.contains('4h')) ||
          (inner.contains('2d') && inner.contains('2h')) ||
          (desc.toLowerCase().contains('transfer') && (subCall.endsWith('d') || subCall.endsWith('h')));

      if (isMajorTransfer) {
        if (subCall.endsWith('d')) {
          partVars['M'] = 'h';
          partVars['OM'] = otherMajor('h');
          partVars['M_name'] = 'Hearts';
          partVars['M_sym'] = '♥';
          partVars['OM_name'] = 'Spades';
          partVars['OM_sym'] = '♠';
          partVars['transfer_suit'] = 'h';
        } else if (subCall.endsWith('h')) {
          partVars['M'] = 's';
          partVars['OM'] = otherMajor('s');
          partVars['M_name'] = 'Spades';
          partVars['M_sym'] = '♠';
          partVars['OM_name'] = 'Hearts';
          partVars['OM_sym'] = '♥';
          partVars['transfer_suit'] = 's';
        }
      } else {
        if (subCall.endsWith('h')) {
          partVars.putIfAbsent('M', () => 'h');
          partVars.putIfAbsent('OM', () => otherMajor('h'));
          partVars.putIfAbsent('M_name', () => 'Hearts');
          partVars.putIfAbsent('M_sym', () => '♥');
          partVars.putIfAbsent('OM_name', () => 'Spades');
          partVars.putIfAbsent('OM_sym', () => '♠');
        } else if (subCall.endsWith('s')) {
          partVars.putIfAbsent('M', () => 's');
          partVars.putIfAbsent('OM', () => otherMajor('s'));
          partVars.putIfAbsent('M_name', () => 'Spades');
          partVars.putIfAbsent('M_sym', () => '♠');
          partVars.putIfAbsent('OM_name', () => 'Hearts');
          partVars.putIfAbsent('OM_sym', () => '♥');
        } else if (subCall.endsWith('c')) {
          partVars.putIfAbsent('m', () => 'c');
          partVars.putIfAbsent('om', () => otherMinor('c'));
          partVars.putIfAbsent('m_name', () => 'Clubs');
          partVars.putIfAbsent('m_sym', () => '♣');
          partVars.putIfAbsent('om_name', () => 'Diamonds');
          partVars.putIfAbsent('om_sym', () => '♦');
        } else if (subCall.endsWith('d')) {
          partVars.putIfAbsent('m', () => 'd');
          partVars.putIfAbsent('om', () => otherMinor('d'));
          partVars.putIfAbsent('m_name', () => 'Diamonds');
          partVars.putIfAbsent('m_sym', () => '♦');
          partVars.putIfAbsent('om_name', () => 'Clubs');
          partVars.putIfAbsent('om_sym', () => '♣');
        }
      }

      // Merge variables extracted from subRule (e.g. [$OM=otherMajor($M)])
      if (subRule != null) {
        final extracted = _extractVariablesFromRule(subRule, partVars);
        partVars.addAll(extracted);

        // Substitute variable tokens $M, $OM, etc. into subRule
        final sortedKeys = partVars.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
        for (final k in sortedKeys) {
          final v = partVars[k]!;
          if (v.isNotEmpty) {
            subRule = subRule!.replaceAll('\$$k', v);
          }
        }
      }

      var subDesc = desc;
      if (subDesc.isNotEmpty) {
        final sortedKeys = partVars.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
        for (final k in sortedKeys) {
          final v = partVars[k]!;
          if (k == 'M' || k == 'OM' || k == 'os' || k == 'oppos' || k == 'om' || k == 'm' || k == 'suit') {
            final sym = v == 'h' ? '♥' : (v == 's' ? '♠' : (v == 'd' ? '♦' : (v == 'c' ? '♣' : v)));
            subDesc = subDesc.replaceAll('\$${k}_sym', sym);
          }
          if (v.isNotEmpty) {
            subDesc = subDesc.replaceAll('\$$k', v);
          }
        }
        if (!desc.contains(r'$')) {
          subDesc = '$desc ($subCall)';
        }
      }

      expanded.add(BiddingNode(
        call: prefixCond != null ? '<$prefixCond> $subCall' : subCall,
        condition: prefixCond,
        desc: subDesc.isNotEmpty ? subDesc : subCall,
        rule: subRule,
        priority: priority,
        ref: ref,
        includes: includes,
        variables: partVars,
        forceTo: forceTo,
        bids: bids,
      ));
    }

    return expanded;
  }

  /// Returns valid child bids for the given [activeVariables], expanding compound bids
  /// and resolving fragment references from [fragments] if [bids] is empty.
  List<BiddingNode> getEffectiveChildren(
    Map<String, String> activeVariables, {
    Map<String, Fragment>? fragments,
  }) {
    final List<BiddingNode> result = [];
    final mergedVars = Map<String, String>.from(activeVariables);
    if (ref != null && fragments != null && fragments.containsKey(ref)) {
      mergedVars.addAll(fragments[ref]!.variables);
    }
    if (isOpponent && activeVariables.containsKey('M')) {
      final filteredVars = Map<String, String>.from(variables);
      filteredVars.remove('M');
      filteredVars.remove('OM');
      filteredVars.remove('M_name');
      filteredVars.remove('M_sym');
      if (activeVariables.containsKey('m')) {
        filteredVars.remove('m');
        filteredVars.remove('om');
        filteredVars.remove('m_name');
        filteredVars.remove('m_sym');
      }
      mergedVars.addAll(filteredVars);
    } else {
      mergedVars.addAll(variables);
    }
    if (!mergedVars.containsKey('trump')) {
      final fallbackTrump = mergedVars['M'] ?? mergedVars['m'] ?? mergedVars['suit'];
      if (fallbackTrump != null && fallbackTrump.isNotEmpty) {
        mergedVars['trump'] = fallbackTrump;
      }
    }
    final enrichedVars = enrichSuitVariables(mergedVars);

    final selfSub = substituted(enrichedVars);
    final parentEffectiveCall = (!isConditionalBranch && selfSub.displayCall.isNotEmpty)
        ? selfSub.displayCall
        : (enrichedVars['_last_call'] ?? '');
    if (parentEffectiveCall.isNotEmpty) {
      enrichedVars['_last_call'] = parentEffectiveCall;
    }

    final List<BiddingNode> sourceList = [];
    if (bids.isNotEmpty) {
      sourceList.addAll(bids);
    } else if (ref != null && fragments != null && fragments.containsKey(ref)) {
      final resolvedFrag = _resolveFragmentChain(fragments[ref!]!, fragments, <String>{});
      sourceList.addAll(resolvedFrag.bids);
    }
    for (final inc in includes) {
      if (fragments != null && fragments.containsKey(inc)) {
        final incFrag = _resolveFragmentChain(fragments[inc]!, fragments, <String>{});
        sourceList.addAll(incFrag.bids);
      }
    }

    final Set<String> seenKeys = {};
    for (final child in sourceList) {
      final resolvedChild = fragments != null ? child.withResolvedFragmentMetadata(fragments) : child;
      if (!resolvedChild.isConditionSatisfied(enrichedVars)) {
        continue;
      }
      final expandedList = resolvedChild.expandCompoundBid();
      for (final exp in expandedList) {
        var sub = exp.substituted(enrichedVars);
        if (parentEffectiveCall.isNotEmpty && sub.call.toLowerCase().contains('step#')) {
          final stepCall = resolveStepCall(sub.call, parentEffectiveCall);
          sub = BiddingNode(
            call: stepCall,
            desc: sub.desc,
            rule: sub.rule,
            priority: sub.priority,
            ref: sub.ref,
            includes: sub.includes,
            condition: sub.condition,
            variables: sub.variables,
            forceTo: sub.forceTo,
            bids: sub.bids,
          );
        }
        final key = '${sub.call}|${sub.rule}|${sub.condition}';
        if (seenKeys.add(key)) {
          result.add(sub);
        }
      }
    }

    return result;
  }

  /// Deduce contextual suit variables ($M, $OM, $m, $om, $os) from a call string.
  static Map<String, String> deduceVariablesFromCall(String call) {
    final clean = call.toLowerCase().replaceAll('(', '').replaceAll(')', '').trim();
    final vars = <String, String>{};
    String? suit;
    if (clean.endsWith('c')) {
      suit = 'c';
    } else if (clean.endsWith('d')) {
      suit = 'd';
    } else if (clean.endsWith('h')) {
      suit = 'h';
    } else if (clean.endsWith('s')) {
      suit = 's';
    }

    final isOpp = call.contains('(');
    if (suit != null) {
      final suitName = suit == 'h' ? 'Hearts' : (suit == 's' ? 'Spades' : (suit == 'd' ? 'Diamonds' : 'Clubs'));
      final suitSym = suit == 'h' ? '♥' : (suit == 's' ? '♠' : (suit == 'd' ? '♦' : '♣'));

      vars['suit'] = suit;
      vars['suit_name'] = suitName;
      vars['suit_sym'] = suitSym;

      if (suit == 'h' || suit == 's') {
        vars['M'] = suit;
        vars['OM'] = otherMajor(suit);
        vars['M_name'] = suit == 'h' ? 'Hearts' : 'Spades';
        vars['M_sym'] = suit == 'h' ? '♥' : '♠';
        vars['OM_name'] = suit == 'h' ? 'Spades' : 'Hearts';
        vars['OM_sym'] = suit == 'h' ? '♠' : '♥';
      } else {
        vars['m'] = suit;
        vars['om'] = otherMinor(suit);
        vars['m_name'] = suit == 'c' ? 'Clubs' : 'Diamonds';
        vars['m_sym'] = suit == 'c' ? '♣' : '♦';
      }

      if (isOpp) {
        vars['os'] = suit;
        vars['oppos'] = suit;
        vars['os_name'] = suitName;
        vars['os_sym'] = suitSym;
        vars['om'] = suit;
        vars['om_name'] = suitName;
        vars['om_sym'] = suitSym;
      }
    }
    return vars;
  }

  static Fragment _resolveFragmentChain(
    Fragment frag,
    Map<String, Fragment> fragments,
    Set<String> visited,
  ) {
    if (!visited.add(frag.name)) return frag;
    String? desc = frag.desc;
    String? rule = frag.rule;
    int? priority = frag.priority;
    ForcingLevel forcing = frag.forceTo;
    final vars = Map<String, String>.from(frag.variables);
    final mergedBids = List<BiddingNode>.from(frag.bids);

    if (frag.ref != null && fragments.containsKey(frag.ref)) {
      final base = _resolveFragmentChain(fragments[frag.ref!]!, fragments, Set.from(visited));
      desc ??= base.desc;
      rule ??= base.rule;
      priority ??= base.priority;
      if (base.forceTo.rank > forcing.rank) {
        forcing = base.forceTo;
      }
      final combinedVars = Map<String, String>.from(base.variables)..addAll(vars);
      vars
        ..clear()
        ..addAll(combinedVars);
      mergedBids.addAll(base.bids);
    }

    for (final inc in frag.includes) {
      if (fragments.containsKey(inc)) {
        final incFrag = _resolveFragmentChain(fragments[inc]!, fragments, Set.from(visited));
        if (incFrag.forceTo.rank > forcing.rank) {
          forcing = incFrag.forceTo;
        }
        mergedBids.addAll(incFrag.bids);
      }
    }

    return Fragment(
      name: frag.name,
      desc: desc,
      rule: rule,
      priority: priority,
      aliases: frag.aliases,
      variables: enrichSuitVariables(vars),
      forceTo: forcing,
      bids: mergedBids,
    );
  }

  /// Returns a copy of this node with `desc`, `rule`, `priority`, and `bids` inherited from
  /// the referenced [Fragment] if not explicitly specified on this node.
  BiddingNode withResolvedFragmentMetadata(
    Map<String, Fragment> fragments, [
    Set<String>? visited,
  ]) {
    final activeVisited = visited ?? <String>{};
    Fragment? resolvedFrag;
    if (ref != null && fragments.containsKey(ref) && !activeVisited.contains(ref)) {
      resolvedFrag = _resolveFragmentChain(fragments[ref!]!, fragments, Set.from(activeVisited));
    }

    final List<BiddingNode> incBids = [];
    final Map<String, String> incVars = {};
    ForcingLevel maxIncForcing = ForcingLevel.partScore;
    for (final inc in includes) {
      if (fragments.containsKey(inc) && !activeVisited.contains(inc)) {
        final incFrag = _resolveFragmentChain(fragments[inc]!, fragments, Set.from(activeVisited));
        incBids.addAll(incFrag.bids);
        incVars.addAll(incFrag.variables);
        if (incFrag.forceTo.rank > maxIncForcing.rank) {
          maxIncForcing = incFrag.forceTo;
        }
      }
    }

    if (resolvedFrag == null && incBids.isEmpty) {
      if (bids.isEmpty) return this;
      final nextVisited = Set<String>.from(activeVisited);
      return BiddingNode(
        call: call,
        desc: desc,
        rule: rule,
        priority: priority,
        ref: ref,
        includes: includes,
        condition: condition,
        agreedSuit: agreedSuit,
        variables: variables,
        forceTo: forceTo,
        bids: bids.map((b) => b.withResolvedFragmentMetadata(fragments, nextVisited)).toList(),
      );
    }

    final deducedVars = deduceVariablesFromCall(call);
    final mergedVars = <String, String>{};
    if (resolvedFrag != null) {
      for (final e in resolvedFrag.variables.entries) {
        if (!e.value.startsWith(r'$') && !e.value.contains('(')) {
          mergedVars[e.key] = e.value;
        }
      }
    }
    mergedVars.addAll(incVars);
    final activeAgreed = agreedSuit ?? resolvedFrag?.agreedSuit;
    if (activeAgreed != null && activeAgreed.isNotEmpty) {
      mergedVars['agreedSuit'] = activeAgreed;
    }
    for (final e in deducedVars.entries) {
      if (!mergedVars.containsKey(e.key) && !variables.containsKey(e.key)) {
        if (activeAgreed != null && (e.key == 'M' || e.key == 'OM' || e.key == 'trump')) {
          continue; // do not clobber agreed suit
        }
        mergedVars[e.key] = e.value;
      }
    }
    mergedVars.addAll(variables);
    final enrichedVars = enrichSuitVariables(mergedVars, agreedSuit: activeAgreed);

    String resolveString(String text) {
      var s = text;
      final sortedKeys = enrichedVars.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (final k in sortedKeys) {
        final v = enrichedVars[k]!;
        if (k == 'M' || k == 'OM' || k == 'os' || k == 'oppos' || k == 'om' || k == 'm' || k == 'suit' || k == 'trump') {
          final sym = v == 'h' ? '♥' : (v == 's' ? '♠' : (v == 'd' ? '♦' : (v == 'c' ? '♣' : v)));
          s = s.replaceAll('\$${k}_sym', sym);
          final name = v == 'h' ? 'Hearts' : (v == 's' ? 'Spades' : (v == 'd' ? 'Diamonds' : 'Clubs'));
          s = s.replaceAll('\$${k}_name', name);
        }
        s = s.replaceAll('\$$k', v);
      }
      return s;
    }

    final resolvedDesc = desc.isNotEmpty
        ? desc
        : (resolvedFrag?.desc != null ? resolveString(resolvedFrag!.desc!) : '');
    final resolvedRule = (rule != null && rule!.isNotEmpty)
        ? rule
        : (resolvedFrag?.rule != null ? resolveString(resolvedFrag!.rule!) : null);
    final resolvedPriority = priority ?? resolvedFrag?.priority;
    final ruleVars = resolvedRule != null ? _extractVariablesFromRule(resolvedRule, enrichedVars) : enrichedVars;

    var resolvedForcing = forceTo;
    if (resolvedFrag != null && resolvedFrag.forceTo.rank > resolvedForcing.rank) {
      resolvedForcing = resolvedFrag.forceTo;
    }
    if (maxIncForcing.rank > resolvedForcing.rank) {
      resolvedForcing = maxIncForcing;
    }

    final nextVisited = Set<String>.from(activeVisited);
    if (ref != null) nextVisited.add(ref!);
    nextVisited.addAll(includes);

    final combinedBids = <BiddingNode>[
      ...bids,
      if (resolvedFrag != null) ...resolvedFrag.bids,
      ...incBids,
    ].map((b) => b.withResolvedFragmentMetadata(fragments, nextVisited)).toList();

    return BiddingNode(
      call: call,
      desc: resolvedDesc,
      rule: resolvedRule,
      priority: resolvedPriority,
      ref: ref,
      includes: const [],
      condition: condition,
      agreedSuit: activeAgreed,
      variables: ruleVars.isNotEmpty ? ruleVars : null,
      forceTo: resolvedForcing,
      bids: combinedBids,
    );
  }
}

