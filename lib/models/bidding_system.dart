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

/// A reusable bidding convention or subroutine fragment (e.g. `fMultiLandy`, `WalshClubOpening`).
class Fragment {
  final String name;
  final String? desc;
  final String? rule;
  final int? priority;
  final List<String> aliases;
  final List<BiddingNode> bids;

  Fragment({
    required this.name,
    this.desc,
    this.rule,
    this.priority,
    this.aliases = const [],
    List<BiddingNode>? bids,
  }) : bids = bids ?? [];
}

/// A node in the bidding tree.
class BiddingNode {
  /// The call text as defined, e.g. "pass", "1c", "(1s)", "[1h-1s]", "<$M=h>1s", "~>MultiLandy".
  final String call;

  /// Meaning or description, e.g. "Drury 3-4", "Takeout", "No opening available".
  final String desc;

  /// Hand evaluation / shape / hcp constraints, e.g. "10-hcp", "p#3 5-10hcp 4s 2-h".
  final String? rule;

  /// Optional priority (e.g. from ?1, ?2 or p#1..p#10). Lower number = higher priority.
  final int? priority;

  /// Fragment reference if this bid redirects/branches to a fragment (e.g. "fMultiLandy").
  final String? ref;

  /// Explicit condition if parsed (e.g. "$M=h").
  final String? condition;

  /// Context variables bound at this node, e.g. { 'M': 'h', 'OM': 's', 'os': 'h' }.
  final Map<String, String> variables;

  /// Child responses / follow-up bids.
  final List<BiddingNode> bids;

  BiddingNode({
    required this.call,
    this.desc = '',
    this.rule,
    this.priority,
    this.ref,
    this.condition,
    Map<String, String>? variables,
    List<BiddingNode>? bids,
  })  : variables = variables ?? _extractVariablesFromRule(rule),
        bids = bids ?? [];

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

  static Map<String, String> _extractVariablesFromRule(String? ruleText, [Map<String, String>? existingVars]) {
    if (ruleText == null) return {};
    final map = <String, String>{};
    if (existingVars != null) {
      map.addAll(existingVars);
    }
    // Match [$M=h, $OM=s, $os=h] or [$OM=otherMajor($M)]
    final match = RegExp(r'\[([^\]]+)\]').firstMatch(ruleText);
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
            }
          } else if (val.startsWith('otherMinor(') && val.endsWith(')')) {
            final arg = val.substring('otherMinor('.length, val.length - 1).replaceAll(r'$', '').trim();
            final resolvedArg = map[arg] ?? (arg == 'c' || arg == 'd' ? arg : '');
            if (resolvedArg.isNotEmpty) {
              val = otherMinor(resolvedArg);
            }
          }

          if (val.isNotEmpty) {
            map[key] = val;
          }
        }
      }
    }

    // Automatic fallback: if $M is defined and $OM is not, automatically derive otherMajor($M)
    if (map.containsKey('M') && !map.containsKey('OM')) {
      final om = otherMajor(map['M']!);
      if (om.isNotEmpty) {
        map['OM'] = om;
      }
    }

    // Automatic fallback: alias $oppos and $os
    if (map.containsKey('oppos') && !map.containsKey('os')) {
      map['os'] = map['oppos']!;
    } else if (map.containsKey('os') && !map.containsKey('oppos')) {
      map['oppos'] = map['os']!;
    }

    // If $os is a major and $OM is not set, automatically derive otherMajor($os)
    if (map.containsKey('os') && !map.containsKey('OM')) {
      final om = otherMajor(map['os']!);
      if (om.isNotEmpty) {
        map['OM'] = om;
      }
    }

    return map;
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

  /// Checks if this node's condition (e.g. `<$M=h>`) is satisfied in [activeVariables].
  bool isConditionSatisfied(Map<String, String> activeVariables) {
    final cond = inlineCondition;
    if (cond == null || cond.isEmpty) return true;

    // Pattern: $M=h or M=h or !$M=h or $M!=h
    final isNot = cond.startsWith('!') || cond.contains('!=');
    final cleanCond = cond.startsWith('!') ? cond.substring(1) : cond;
    final sep = cleanCond.contains('!=') ? '!=' : '=';
    final parts = cleanCond.split(sep);
    if (parts.length == 2) {
      final key = parts[0].replaceAll(r'$', '').trim();
      final expectedVal = parts[1].trim();
      final actualVal = activeVariables[key];
      final matches = actualVal == expectedVal;
      return isNot ? !matches : matches;
    }
    return true;
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
        if (k == 'M' || k == 'OM' || k == 'os' || k == 'oppos' || k == 'om' || k == 'm') {
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
      condition: condition,
      variables: variables,
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
      if (subRule != null && subRule.contains('%')) {
        String suitChar = '';
        if (subCall.endsWith('c')) suitChar = 'c';
        if (subCall.endsWith('d')) suitChar = 'd';
        if (subCall.endsWith('h')) suitChar = 'h';
        if (subCall.endsWith('s')) suitChar = 's';
        if (suitChar.isNotEmpty) {
          subRule = subRule.replaceAll('%', suitChar);
          partVars['%'] = suitChar;
        }
      }

      if (subCall.endsWith('h')) {
        partVars.putIfAbsent('M', () => 'h');
        partVars.putIfAbsent('OM', () => otherMajor('h'));
      } else if (subCall.endsWith('s')) {
        partVars.putIfAbsent('M', () => 's');
        partVars.putIfAbsent('OM', () => otherMajor('s'));
      }

      // Merge variables extracted from subRule (e.g. [$OM=otherMajor($M)])
      if (subRule != null) {
        final extracted = _extractVariablesFromRule(subRule, partVars);
        partVars.addAll(extracted);

        // Substitute variable tokens $M, $OM, etc. into subRule
        partVars.forEach((k, v) {
          if (v.isNotEmpty) {
            subRule = subRule!.replaceAll('\$$k', v);
          }
        });
      }

      var subDesc = desc;
      if (subDesc.isNotEmpty) {
        partVars.forEach((k, v) {
          subDesc = subDesc.replaceAll('\$$k', v);
          if (k == 'M' || k == 'OM' || k == 'os' || k == 'oppos') {
            final sym = v == 'h' ? '♥' : (v == 's' ? '♠' : (v == 'd' ? '♦' : (v == 'c' ? '♣' : v)));
            subDesc = subDesc.replaceAll('\$${k}_sym', sym);
          }
        });
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
        variables: partVars,
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
    final mergedVars = Map<String, String>.from(activeVariables)..addAll(variables);

    final List<BiddingNode> sourceList = [];
    if (bids.isNotEmpty) {
      sourceList.addAll(bids);
    } else if (ref != null && fragments != null && fragments.containsKey(ref)) {
      sourceList.addAll(fragments[ref]!.bids);
    }

    final Set<String> seenKeys = {};
    for (final child in sourceList) {
      final resolvedChild = fragments != null ? child.withResolvedFragmentMetadata(fragments) : child;
      if (!resolvedChild.isConditionSatisfied(mergedVars)) {
        continue;
      }
      final expandedList = resolvedChild.expandCompoundBid();
      for (final exp in expandedList) {
        final sub = exp.substituted(mergedVars);
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
      } else {
        vars['m'] = suit;
        vars['om'] = isOpp ? suit : otherMinor(suit);
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

  /// Returns a copy of this node with `desc`, `rule`, `priority`, and `bids` inherited from
  /// the referenced [Fragment] if not explicitly specified on this node.
  BiddingNode withResolvedFragmentMetadata(Map<String, Fragment> fragments) {
    if (ref == null) return this;
    final frag = fragments[ref];
    if (frag == null) return this;

    final deducedVars = deduceVariablesFromCall(call);
    final mergedVars = Map<String, String>.from(deducedVars)..addAll(variables);

    String resolveString(String text) {
      var s = text;
      mergedVars.forEach((k, v) {
        if (k == 'M' || k == 'OM' || k == 'os' || k == 'oppos' || k == 'om' || k == 'm' || k == 'suit') {
          final sym = v == 'h' ? '♥' : (v == 's' ? '♠' : (v == 'd' ? '♦' : (v == 'c' ? '♣' : v)));
          s = s.replaceAll('\$${k}_sym', sym);
          final name = v == 'h' ? 'Hearts' : (v == 's' ? 'Spades' : (v == 'd' ? 'Diamonds' : 'Clubs'));
          s = s.replaceAll('\$${k}_name', name);
        }
        s = s.replaceAll('\$$k', v);
      });
      return s;
    }

    final resolvedDesc = desc.isNotEmpty ? desc : (frag.desc != null ? resolveString(frag.desc!) : '');
    final resolvedRule = (rule != null && rule!.isNotEmpty) ? rule : (frag.rule != null ? resolveString(frag.rule!) : null);
    final resolvedPriority = priority ?? frag.priority;
    final ruleVars = resolvedRule != null ? _extractVariablesFromRule(resolvedRule, mergedVars) : mergedVars;

    return BiddingNode(
      call: call,
      desc: resolvedDesc,
      rule: resolvedRule,
      priority: resolvedPriority,
      ref: ref,
      condition: condition,
      variables: ruleVars.isNotEmpty ? ruleVars : null,
      bids: bids.isNotEmpty ? bids : frag.bids,
    );
  }
}

