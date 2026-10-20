import '../models/card.dart';
import 'hand_constraint.dart';

/// Parses raw constraint expressions (structured YAML or shorthand DSL)
/// into a strongly-typed [HandConstraint] tree.
class ConstraintParser {
  final Map<String, String> definitions;

  ConstraintParser({this.definitions = const {}});

  /// Parse a constraint from either a Map or a String.
  HandConstraint parse(dynamic raw) {
    if (raw == null) {
      return const CompositeConstraint(children: []);
    }
    if (raw is Map) {
      return _parseMapConstraint(raw);
    }
    if (raw is String) {
      return parseStringDsl(raw);
    }
    return const CompositeConstraint(children: []);
  }

  /// Parses a structured YAML mapping, e.g.:
  /// ```yaml
  /// hcp: [15, 17] # or "10+"
  /// shape: balanced
  /// suits:
  ///   hearts: ">=5"
  ///   clubs: ">=2"
  /// any_of: [...]
  /// ```
  HandConstraint _parseMapConstraint(Map map) {
    final List<HandConstraint> constraints = [];

    // any_of (OR)
    if (map.containsKey('any_of') && map['any_of'] is List) {
      final orList = (map['any_of'] as List).map((item) => parse(item)).toList();
      return CompositeConstraint(children: orList, isAnd: false);
    }

    // HCP
    if (map.containsKey('hcp') || map.containsKey('points')) {
      final hcpVal = map['hcp'] ?? map['points'];
      if (hcpVal is List && hcpVal.length == 2) {
        constraints.add(HcpConstraint(
          min: hcpVal[0] is int ? hcpVal[0] as int : int.tryParse(hcpVal[0].toString()),
          max: hcpVal[1] is int ? hcpVal[1] as int : int.tryParse(hcpVal[1].toString()),
        ));
      } else if (hcpVal is String) {
        final parsedHcp = _parseSingleHcpString(hcpVal);
        if (parsedHcp != null) constraints.add(parsedHcp);
      }
    }

    // Shape
    if (map.containsKey('shape')) {
      final shapeVal = map['shape'];
      if (shapeVal == 'balanced') {
        constraints.add(const ShapeConstraint(requiresBalanced: true));
      } else if (shapeVal is List) {
        constraints.add(ShapeConstraint(patterns: shapeVal.map((e) => e.toString()).toList()));
      } else if (shapeVal is String) {
        constraints.add(ShapeConstraint(patterns: shapeVal.split('|').map((e) => e.trim()).toList()));
      }
    }

    // Suits
    if (map.containsKey('suits') && map['suits'] is Map) {
      final suitsMap = map['suits'] as Map;
      suitsMap.forEach((suitKey, lenVal) {
        final suit = Suit.fromString(suitKey.toString());
        if (suit != null) {
          final lenConstraint = _parseLengthString(suit, lenVal.toString());
          if (lenConstraint != null) constraints.add(lenConstraint);
        }
      });
    }

    // Suit order
    if (map.containsKey('suit_order')) {
      final orderConstraint = _parseSuitOrderString(map['suit_order'].toString());
      if (orderConstraint != null) constraints.add(orderConstraint);
    }

    return CompositeConstraint(children: constraints, isAnd: true);
  }

  /// Parses human-friendly DSL strings such as:
  /// - "10+hcp, 5+h"
  /// - "15-17 hcp, balanced, 4-h, 4-s"
  /// - "p#6 2+c $weakbal, 4+c 12+hcp c>=*"
  HandConstraint parseStringDsl(String text) {
    // Strip variable binding annotations like [$M=h, $OM=s] before tokenizing
    var s = text.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    if (s.isEmpty) return const CompositeConstraint(children: []);

    // If there are comma-separated alternatives (OR in BBS format, e.g. "p#6 2+c $weakbal, 4+c 12+hcp")
    // Check if the comma separates independent alternatives
    final alternatives = _splitTopLevelOr(s);
    if (alternatives.length > 1) {
      return CompositeConstraint(
        children: alternatives.map((alt) => _parseSingleClause(alt)).toList(),
        isAnd: false,
      );
    }

    return _parseSingleClause(s);
  }

  List<String> _splitTopLevelOr(String text) {
    if (text.contains(' | ')) {
      return text.split(' | ').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    if (text.contains('|') && !text.contains('s#') && !text.contains('d#') && !text.contains('kc=') && !text.contains('n#')) {
      return text.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    if (text.contains(',')) {
      final parts = text.split(',');
      // If at least two parts contain point criteria ('hcp', 'knr', or macro '$'),
      // or if they represent distinct bidding alternatives as defined in Bridge.g
      final hcpCount = parts.where((p) => p.contains('hcp') || p.contains('knr') || p.contains('ltc') || p.contains('gf') || p.contains(r'$')).length;
      if (hcpCount >= 2) {
        return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
    return [text];
  }

  HandConstraint _parseSingleClause(String clause) {
    // Expand macro references like $bal, $weakbal
    var expanded = clause;
    definitions.forEach((macroKey, macroVal) {
      if (expanded.contains('\$$macroKey')) {
        expanded = expanded.replaceAll('\$$macroKey', macroVal);
      }
    });

    final List<HandConstraint> constraints = [];
    final tokens = expanded.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final t = token.toLowerCase();

      // Priority tags like p#6, ?1 - skip in constraint matching
      if (t.startsWith('p#') || t.startsWith('?')) continue;
      // Variable bindings like [$M=h] - skip
      if (t.startsWith('[') && t.endsWith(']')) continue;

      // Key Card patterns: kc=0|3, kc=1|4, kc=2-q, kc=2+q, kc>=2, kc<=1, etc.
      if (t.startsWith('kc=') || t.startsWith('kc>=') || t.startsWith('kc<=') || t.startsWith('kc>') || t.startsWith('kc<')) {
        Suit? trump;
        final suitMatch = RegExp(r'[:]?([cdhs])$').firstMatch(t);
        String cleanKcToken = t;
        if (suitMatch != null) {
          trump = Suit.fromString(suitMatch.group(1)!);
          cleanKcToken = t.substring(0, suitMatch.start);
        } else if (i + 1 < tokens.length) {
          final nextT = tokens[i + 1].toLowerCase();
          final nextSuit = Suit.fromString(nextT);
          if (nextSuit != null) {
            trump = nextSuit;
            i++; // consume next suit token
          }
        }
        trump ??= Suit.hearts;

        final kcConstraint = _parseKeyCardToken(cleanKcToken, trump);
        if (kcConstraint != null) {
          constraints.add(kcConstraint);
          continue;
        }
      }

      // Honor patterns: qh, qs, +qh, !qh, -qh, kh, ah, etc.
      final honorMatch = RegExp(r'^(!|\+|\-)?([akqj])([cdhs])$').firstMatch(t);
      if (honorMatch != null) {
        final prefix = honorMatch.group(1);
        final rankChar = honorMatch.group(2)!;
        final suitChar = honorMatch.group(3)!;
        final suit = Suit.fromString(suitChar);
        Rank? rank;
        switch (rankChar) {
          case 'a': rank = Rank.ace; break;
          case 'k': rank = Rank.king; break;
          case 'q': rank = Rank.queen; break;
          case 'j': rank = Rank.jack; break;
        }
        if (suit != null && rank != null) {
          final isPresent = prefix != '!' && prefix != '-';
          constraints.add(HonorConstraint(suit: suit, rank: rank, isPresent: isPresent));
          continue;
        }
      }

      // HCP patterns: 10+hcp, 15-17hcp, 10-hcp, 12hcp
      if (t.contains('hcp')) {
        final parsedHcp = _parseSingleHcpString(t.replaceAll('hcp', ''));
        if (parsedHcp != null) {
          constraints.add(parsedHcp);
          continue;
        }
      }

      // LTC patterns: 4-ltc, 3-ltc, 4ltc, 4+ltc, <=4ltc
      if (t.contains('ltc')) {
        final parsedLtc = _parseSingleLtcString(t);
        if (parsedLtc != null) {
          constraints.add(parsedLtc);
          continue;
        }
      }

      // Solid suit patterns: solid_minor, solid:c, solid:d, solid:h, solid:s
      if (t == 'solid_minor' || t == 'solid_m') {
        constraints.add(const SolidSuitConstraint());
        continue;
      }
      if (t.startsWith('solid:') || t.startsWith('solid_')) {
        final suitPart = t.replaceFirst(RegExp(r'^solid[:_]'), '');
        final s = Suit.fromString(suitPart);
        if (s != null) {
          constraints.add(SolidSuitConstraint(suit: s));
          continue;
        }
      }

      // Outside controls: outside_ctrl<=1, outside_ctrl=0, outside_controls<=1, outside_ctrl>=1
      if (t.contains('outside_ctrl') || t.contains('outside_controls')) {
        final parsedOutsideCtrl = _parseOutsideControlsToken(t);
        if (parsedOutsideCtrl != null) {
          constraints.add(parsedOutsideCtrl);
          continue;
        }
      }

      // Hand controls: controls<=2, controls>=3, ctrl<=2, ctrl>=3, controls=2
      if (t.startsWith('controls') || t.startsWith('ctrl')) {
        final parsedCtrl = _parseControlsToken(t);
        if (parsedCtrl != null) {
          constraints.add(parsedCtrl);
          continue;
        }
      }

      // GF pattern: Game Force (22+ HCP or 20+ HCP unbalanced or <=4 LTC with 16+ HCP)
      if (t == 'gf') {
        constraints.add(const CompositeConstraint(
          children: [
            HcpConstraint(min: 22),
            CompositeConstraint(
              children: [
                HcpConstraint(min: 20),
                ShapeConstraint(requiresBalanced: true, isNegated: true),
              ],
              isAnd: true,
            ),
            CompositeConstraint(
              children: [
                HcpConstraint(min: 16),
                LosingTrickCountConstraint(max: 4),
              ],
              isAnd: true,
            ),
          ],
          isAnd: false,
        ));
        continue;
      }

      // Negated Shape patterns: !s#4333
      if (t.startsWith('!s#')) {
        final patternStr = t.substring(3);
        final patterns = patternStr.split('|');
        final isBal = patternStr == '5332|4432|4333';
        constraints.add(ShapeConstraint(patterns: patterns, requiresBalanced: isBal, isNegated: true));
        continue;
      }

      // Shape patterns: s#5332|4432|4333
      if (t.startsWith('s#')) {
        final patternStr = t.substring(2);
        final patterns = patternStr.split('|');
        final isBal = patternStr == '5332|4432|4333';
        constraints.add(ShapeConstraint(patterns: patterns, requiresBalanced: isBal));
        continue;
      }

      if (t == '!balanced' || t == r'!$bal') {
        constraints.add(const ShapeConstraint(requiresBalanced: true, isNegated: true));
        continue;
      }

      if (t == 'balanced' || t == r'$bal') {
        constraints.add(const ShapeConstraint(requiresBalanced: true));
        continue;
      }

      // Suit comparison: c>=*, d>=s, h>=s
      if (t.contains('>=') || t.contains('>') || t.contains('<=') || t.contains('<')) {
        final order = _parseSuitOrderString(t);
        if (order != null) {
          constraints.add(order);
          continue;
        }
      }

      // Suit length patterns: 5+h, 4+c, 3-d, 4-s, 6h, 5s
      final suitLen = _parseSuitLengthToken(t);
      if (suitLen != null) {
        constraints.add(suitLen);
        continue;
      }
    }

    return CompositeConstraint(children: constraints, isAnd: true);
  }

  KeyCardConstraint? _parseKeyCardToken(String token, Suit trumpSuit) {
    if (token.startsWith('kc>=')) {
      final min = int.tryParse(token.substring(4));
      if (min != null) {
        return KeyCardConstraint(trumpSuit: trumpSuit, minCount: min);
      }
    } else if (token.startsWith('kc<=')) {
      final max = int.tryParse(token.substring(4));
      if (max != null) {
        return KeyCardConstraint(trumpSuit: trumpSuit, maxCount: max);
      }
    } else if (token.startsWith('kc>')) {
      final min = int.tryParse(token.substring(3));
      if (min != null) {
        return KeyCardConstraint(trumpSuit: trumpSuit, minCount: min + 1);
      }
    } else if (token.startsWith('kc<')) {
      final max = int.tryParse(token.substring(3));
      if (max != null) {
        return KeyCardConstraint(trumpSuit: trumpSuit, maxCount: max - 1);
      }
    } else if (token.startsWith('kc=')) {
      var val = token.substring(3);
      bool? requiresQueen;
      if (val.endsWith('-q')) {
        requiresQueen = false;
        val = val.substring(0, val.length - 2);
      } else if (val.endsWith('+q')) {
        requiresQueen = true;
        val = val.substring(0, val.length - 2);
      }

      if (val.contains('|')) {
        final parts = val.split('|').map((e) => int.tryParse(e.trim())).whereType<int>().toList();
        if (parts.isNotEmpty) {
          return KeyCardConstraint(
            trumpSuit: trumpSuit,
            allowedCounts: parts,
            requiresQueen: requiresQueen,
          );
        }
      } else {
        final single = int.tryParse(val);
        if (single != null) {
          return KeyCardConstraint(
            trumpSuit: trumpSuit,
            allowedCounts: [single],
            requiresQueen: requiresQueen,
          );
        }
      }
    }
    return null;
  }

  OutsideControlsConstraint? _parseOutsideControlsToken(String token) {
    final s = token.replaceAll('outside_controls', '').replaceAll('outside_ctrl', '').trim();
    if (s.startsWith('<=')) {
      final val = int.tryParse(s.substring(2));
      if (val != null) return OutsideControlsConstraint(max: val);
    } else if (s.startsWith('>=')) {
      final val = int.tryParse(s.substring(2));
      if (val != null) return OutsideControlsConstraint(min: val);
    } else if (s.startsWith('=')) {
      final val = int.tryParse(s.substring(1));
      if (val != null) return OutsideControlsConstraint(min: val, max: val);
    } else if (s.startsWith('<')) {
      final val = int.tryParse(s.substring(1));
      if (val != null) return OutsideControlsConstraint(max: val - 1);
    } else if (s.startsWith('>')) {
      final val = int.tryParse(s.substring(1));
      if (val != null) return OutsideControlsConstraint(min: val + 1);
    } else if (s.endsWith('-')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return OutsideControlsConstraint(max: val);
    } else if (s.endsWith('+')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return OutsideControlsConstraint(min: val);
    } else {
      final val = int.tryParse(s);
      if (val != null) return OutsideControlsConstraint(min: val, max: val);
    }
    return null;
  }

  ControlsConstraint? _parseControlsToken(String token) {
    var s = token.replaceAll('controls', '').replaceAll('ctrl', '').trim();
    if (s.startsWith('<=')) {
      final val = int.tryParse(s.substring(2));
      if (val != null) return ControlsConstraint(max: val);
    } else if (s.startsWith('>=')) {
      final val = int.tryParse(s.substring(2));
      if (val != null) return ControlsConstraint(min: val);
    } else if (s.startsWith('=')) {
      final val = int.tryParse(s.substring(1));
      if (val != null) return ControlsConstraint(min: val, max: val);
    } else if (s.startsWith('<')) {
      final val = int.tryParse(s.substring(1));
      if (val != null) return ControlsConstraint(max: val - 1);
    } else if (s.startsWith('>')) {
      final val = int.tryParse(s.substring(1));
      if (val != null) return ControlsConstraint(min: val + 1);
    } else if (s.endsWith('-')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return ControlsConstraint(max: val);
    } else if (s.endsWith('+')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return ControlsConstraint(min: val);
    } else if (s.contains('-')) {
      final parts = s.split('-');
      if (parts.length == 2) {
        final min = int.tryParse(parts[0]);
        final max = int.tryParse(parts[1]);
        if (min != null && max != null) return ControlsConstraint(min: min, max: max);
      }
    } else {
      final val = int.tryParse(s);
      if (val != null) return ControlsConstraint(min: val, max: val);
    }
    return null;
  }

  HcpConstraint? _parseSingleHcpString(String raw) {
    final s = raw.replaceAll('hcp', '').trim();
    if (s.endsWith('+')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return HcpConstraint(min: val);
    } else if (s.endsWith('-')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return HcpConstraint(max: val);
    } else if (s.contains('-')) {
      final parts = s.split('-');
      if (parts.length == 2) {
        final min = int.tryParse(parts[0]);
        final max = int.tryParse(parts[1]);
        if (min != null && max != null) return HcpConstraint(min: min, max: max);
      }
    } else {
      final val = int.tryParse(s);
      if (val != null) return HcpConstraint(min: val, max: val);
    }
    return null;
  }

  LosingTrickCountConstraint? _parseSingleLtcString(String raw) {
    final s = raw.replaceAll('ltc', '').trim();
    if (s.startsWith('<=')) {
      final val = int.tryParse(s.substring(2));
      if (val != null) return LosingTrickCountConstraint(max: val);
    } else if (s.startsWith('>=')) {
      final val = int.tryParse(s.substring(2));
      if (val != null) return LosingTrickCountConstraint(min: val);
    } else if (s.endsWith('+')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return LosingTrickCountConstraint(min: val);
    } else if (s.endsWith('-')) {
      final val = int.tryParse(s.substring(0, s.length - 1));
      if (val != null) return LosingTrickCountConstraint(max: val);
    } else if (s.contains('-')) {
      final parts = s.split('-');
      if (parts.length == 2) {
        final min = int.tryParse(parts[0]);
        final max = int.tryParse(parts[1]);
        if (min != null && max != null) return LosingTrickCountConstraint(min: min, max: max);
      }
    } else {
      final val = int.tryParse(s);
      if (val != null) return LosingTrickCountConstraint(min: val, max: val);
    }
    return null;
  }


  SuitLengthConstraint? _parseLengthString(Suit suit, String s) {
    var str = s.trim();
    if (str.startsWith('>=')) {
      final val = int.tryParse(str.substring(2));
      if (val != null) return SuitLengthConstraint(suit: suit, min: val);
    } else if (str.startsWith('<=')) {
      final val = int.tryParse(str.substring(2));
      if (val != null) return SuitLengthConstraint(suit: suit, max: val);
    } else if (str.endsWith('+')) {
      final val = int.tryParse(str.substring(0, str.length - 1));
      if (val != null) return SuitLengthConstraint(suit: suit, min: val);
    } else if (str.endsWith('-')) {
      final val = int.tryParse(str.substring(0, str.length - 1));
      if (val != null) return SuitLengthConstraint(suit: suit, max: val);
    } else {
      final val = int.tryParse(str);
      if (val != null) return SuitLengthConstraint(suit: suit, min: val, max: val);
    }
    return null;
  }

  SuitLengthConstraint? _parseSuitLengthToken(String token) {
    // Patterns like: "5+h", "2+c", "4-s", "3-d", "4=h", "4=s", "6h", "5s"
    final regex = RegExp(r'^(\d+)(\+|\-|=)?([cdhs])$');
    final match = regex.firstMatch(token);
    if (match != null) {
      final numVal = int.parse(match.group(1)!);
      final modifier = match.group(2);
      final suitChar = match.group(3)!;
      final suit = Suit.fromString(suitChar);
      if (suit != null) {
        if (modifier == '+') {
          return SuitLengthConstraint(suit: suit, min: numVal);
        } else if (modifier == '-') {
          return SuitLengthConstraint(suit: suit, max: numVal);
        } else if (modifier == '=') {
          return SuitLengthConstraint(suit: suit, min: numVal, max: numVal);
        } else {
          // Exact length like "5h" or minimum? In bridge BBS, "5h" usually means 5+ hearts or exact 5
          return SuitLengthConstraint(suit: suit, min: numVal);
        }
      }
    }
    return null;
  }

  SuitComparisonConstraint? _parseSuitOrderString(String token) {
    final regex = RegExp(r'^([cdhs])(>=|>|<=|<|=)(\*|[cdhs])$');
    final match = regex.firstMatch(token);
    if (match != null) {
      final s1 = Suit.fromString(match.group(1)!);
      final op = match.group(2)!;
      final target = match.group(3)!;
      final s2 = target == '*' ? null : Suit.fromString(target);
      if (s1 != null) {
        return SuitComparisonConstraint(suit1: s1, op: op, suit2: s2);
      }
    }
    return null;
  }
}
