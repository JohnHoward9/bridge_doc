import '../models/card.dart';
import '../models/hand.dart';
import '../evaluators/valuation_engine.dart';

/// The result of evaluating a hand against a constraint.
class MatchResult {
  final bool isMatch;
  final List<String> satisfiedCriteria;
  final List<String> failedCriteria;
  final double specificityScore;

  const MatchResult({
    required this.isMatch,
    this.satisfiedCriteria = const [],
    this.failedCriteria = const [],
    this.specificityScore = 0.0,
  });

  MatchResult combine(MatchResult other, {bool isAnd = true}) {
    final match = isAnd ? (isMatch && other.isMatch) : (isMatch || other.isMatch);
    return MatchResult(
      isMatch: match,
      satisfiedCriteria: [...satisfiedCriteria, ...other.satisfiedCriteria],
      failedCriteria: [...failedCriteria, ...other.failedCriteria],
      specificityScore: specificityScore + other.specificityScore,
    );
  }
}

/// Abstract base class for all bidding constraints.
abstract class HandConstraint {
  const HandConstraint();

  /// Evaluates whether the [hand] satisfies this constraint.
  MatchResult evaluate(Hand hand, HandValuationEngine valuation);

  /// Approximate metric of how restrictive / informative this constraint is.
  double get baseSpecificity;
}

/// High Card Points constraint, e.g. "10+ hcp", "15-17 hcp", "10- hcp".
class HcpConstraint extends HandConstraint {
  final int? min;
  final int? max;

  const HcpConstraint({this.min, this.max});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final rawHcp = hand.hcp;
    final effectivePts = valuation.evaluatePoints(hand);
    final pts = effectivePts.round();
    bool passed = true;
    final List<String> satisfied = [];
    final List<String> failed = [];

    // Check minimum:
    // If downgraded, effective points must still meet min.
    // If upgraded, effective points can promote into min.
    // Otherwise, raw Milton Work HCP must satisfy min.
    if (min != null) {
      if (valuation is MLHandValuation) {
        final breakdown = valuation.evaluateBreakdown(hand);
        if (breakdown.isDowngraded) {
          if (pts < min!) {
            passed = false;
            failed.add('ML Downgraded HCP $pts is below minimum $min');
          }
        } else if (breakdown.isUpgraded) {
          if (pts < min!) {
            passed = false;
            failed.add('HCP $rawHcp ($pts effective) is below minimum $min');
          }
        } else {
          if (rawHcp < min!) {
            passed = false;
            failed.add('HCP $rawHcp is below minimum $min');
          }
        }
      } else {
        if (pts < min!) {
          passed = false;
          failed.add('HCP $pts is below minimum $min');
        }
      }
    }

    // Check maximum:
    // Hands are not disqualified from their natural range by an upgrade bonus,
    // but if raw HCP exceeds max and is not downgraded, it fails.
    if (max != null) {
      if (valuation is MLHandValuation) {
        final breakdown = valuation.evaluateBreakdown(hand);
        if (breakdown.isDowngraded) {
          if (pts > max!) {
            passed = false;
            failed.add('HCP $pts is above maximum $max');
          }
        } else {
          if (rawHcp > max!) {
            passed = false;
            failed.add('HCP $rawHcp is above maximum $max');
          }
        }
      } else {
        if (pts > max!) {
          passed = false;
          failed.add('HCP $pts is above maximum $max');
        }
      }
    }

    final rangeStr = min != null && max != null
        ? '$min-$max HCP'
        : (min != null ? '$min+ HCP' : '$max- HCP');

    if (passed) {
      satisfied.add('HCP $pts matches $rangeStr');
      if (valuation is MLHandValuation) {
        final breakdown = valuation.evaluateBreakdown(hand);
        if (breakdown.isUpgraded || breakdown.isDowngraded) {
          satisfied.add('ML ${breakdown.summaryText}');
        }
      }
    }

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: satisfied,
      failedCriteria: failed,
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity {
    if (min != null && max != null) {
      final width = (max! - min!).clamp(0, 30);
      return (35.0 - width).clamp(5.0, 35.0);
    }
    if (min != null) {
      // 10+ is broad, 16+ is more specific
      return (min! * 1.5).clamp(5.0, 30.0);
    }
    return 10.0;
  }
}

/// Suit length constraint, e.g. "5+h", "2+c", "<=3s", "4d".
class SuitLengthConstraint extends HandConstraint {
  final Suit suit;
  final int? min;
  final int? max;

  const SuitLengthConstraint({required this.suit, this.min, this.max});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final len = hand.length(suit);
    bool passed = true;
    final List<String> satisfied = [];
    final List<String> failed = [];

    if (min != null && len < min!) {
      passed = false;
      failed.add('${suit.symbol} length $len is less than required $min+');
    }
    if (max != null && len > max!) {
      passed = false;
      failed.add('${suit.symbol} length $len exceeds maximum $max');
    }

    final reqStr = min != null && max != null
        ? (min == max ? '$min ${suit.symbol}' : '$min-$max ${suit.symbol}')
        : (min != null ? '$min+ ${suit.symbol}' : '<=$max ${suit.symbol}');

    if (passed) {
      satisfied.add('${suit.symbol} length $len matches $reqStr');
    }

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: satisfied,
      failedCriteria: failed,
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity {
    // Suit length specificity:
    // 5+ Major is far more descriptive than 2+ Minor!
    double score = 0.0;
    if (min != null) {
      if (min! >= 6) {
        score = 25.0;
      } else if (min! == 5) {
        score = 18.0;
      } else if (min! == 4) {
        score = 12.0;
      } else {
        score = (min! * 2.5); // e.g. 2+ -> 5.0
      }
    }
    // Major suit priority bonus: in natural bidding, showing a 5-card major takes priority
    if (suit.isMajor && (min ?? 0) >= 4) {
      score += 15.0;
    }
    return score;
  }
}

/// Distribution shape constraint, e.g. balanced (5332, 4432, 4333) or specific patterns.
class ShapeConstraint extends HandConstraint {
  final List<String> patterns;
  final bool requiresBalanced;
  final bool isNegated;

  const ShapeConstraint({
    this.patterns = const [],
    this.requiresBalanced = false,
    this.isNegated = false,
  });

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    bool passed = false;
    final shape = hand.sortedShapePattern;

    if (requiresBalanced) {
      passed = hand.isBalanced;
    } else if (patterns.isNotEmpty) {
      passed = patterns.any((p) {
        if (p.contains('x')) {
          // Pattern with wildcards like 54xx
          final regex = RegExp('^' + p.replaceAll('x', r'\d') + r'$');
          return regex.hasMatch(shape);
        }
        return p == shape;
      });
    } else {
      passed = true;
    }

    if (isNegated) {
      passed = !passed;
    }

    final patternDesc = requiresBalanced ? 'balanced' : patterns.join('/');
    final prefix = isNegated ? 'not ' : '';

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: passed ? ['Hand shape $shape matches $prefix$patternDesc'] : [],
      failedCriteria: !passed ? ['Hand shape $shape does not match required ${prefix}pattern'] : [],
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity {
    if (isNegated) return 5.0;
    return requiresBalanced ? 15.0 : 25.0;
  }
}

/// Losing Trick Count (LTC) constraint, e.g. "4-ltc", "<=4 ltc", "3-4 ltc".
class LosingTrickCountConstraint extends HandConstraint {
  final int? min;
  final int? max;

  const LosingTrickCountConstraint({this.min, this.max});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final ltc = hand.losingTrickCount;
    bool passed = true;
    final List<String> satisfied = [];
    final List<String> failed = [];

    if (min != null && ltc < min!) {
      passed = false;
      failed.add('LTC $ltc is below required minimum $min');
    }
    if (max != null && ltc > max!) {
      passed = false;
      failed.add('LTC $ltc exceeds required maximum $max');
    }

    final reqStr = min != null && max != null
        ? (min == max ? '$min LTC' : '$min-$max LTC')
        : (max != null ? '<=$max LTC' : '$min+ LTC');

    if (passed) {
      satisfied.add('LTC $ltc matches $reqStr');
    }

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: satisfied,
      failedCriteria: failed,
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity {
    if (max != null && max! <= 4) return 25.0;
    return 15.0;
  }
}


/// Suit comparison constraint, e.g. "h >= s" or "c >= *" (clubs longest or equal to all).
class SuitComparisonConstraint extends HandConstraint {
  final Suit suit1;
  final String op; // '>=', '>', '<=', '<', '='
  final Suit? suit2; // null if comparing against all other suits (*)

  const SuitComparisonConstraint({required this.suit1, required this.op, this.suit2});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final len1 = hand.length(suit1);
    bool passed = true;

    if (suit2 != null) {
      final len2 = hand.length(suit2!);
      passed = _compare(len1, len2, op);
    } else {
      // Compare against all other suits
      for (final s in Suit.values) {
        if (s == suit1) continue;
        if (!_compare(len1, hand.length(s), op)) {
          passed = false;
          break;
        }
      }
    }

    final targetName = suit2 != null ? suit2!.symbol : 'all other suits';
    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: passed ? ['${suit1.symbol} ($len1) $op $targetName'] : [],
      failedCriteria: !passed ? ['${suit1.symbol} ($len1) is not $op $targetName'] : [],
      specificityScore: baseSpecificity,
    );
  }

  bool _compare(int a, int b, String op) {
    switch (op) {
      case '>=':
        return a >= b;
      case '>':
        return a > b;
      case '<=':
        return a <= b;
      case '<':
        return a < b;
      case '=':
      case '==':
        return a == b;
      default:
        return false;
    }
  }

  @override
  double get baseSpecificity => 8.0;
}

/// Composite constraint combining multiple rules with AND or OR.
class CompositeConstraint extends HandConstraint {
  final bool isAnd;
  final List<HandConstraint> children;

  const CompositeConstraint({required this.children, this.isAnd = true});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    if (children.isEmpty) {
      return const MatchResult(isMatch: true);
    }

    MatchResult combined = children.first.evaluate(hand, valuation);
    for (int i = 1; i < children.length; i++) {
      final res = children[i].evaluate(hand, valuation);
      combined = combined.combine(res, isAnd: isAnd);
    }

    return combined;
  }

  @override
  double get baseSpecificity => children.fold(0.0, (sum, c) => sum + c.baseSpecificity);
}

/// Key Card constraint for RKCB evaluation (4 Aces + Trump King, optional Queen).
class KeyCardConstraint extends HandConstraint {
  final Suit trumpSuit;
  final List<int>? allowedCounts;
  final int? minCount;
  final int? maxCount;
  final bool? requiresQueen;

  const KeyCardConstraint({
    required this.trumpSuit,
    this.allowedCounts,
    this.minCount,
    this.maxCount,
    this.requiresQueen,
  });

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final count = hand.keyCardCount(trumpSuit);
    final hasQ = hand.hasQueen(trumpSuit);

    bool countPassed = true;
    if (allowedCounts != null && !allowedCounts!.contains(count)) {
      countPassed = false;
    }
    if (minCount != null && count < minCount!) {
      countPassed = false;
    }
    if (maxCount != null && count > maxCount!) {
      countPassed = false;
    }

    bool queenPassed = true;
    if (requiresQueen != null && hasQ != requiresQueen!) {
      queenPassed = false;
    }

    final isMatch = countPassed && queenPassed;
    final List<String> satisfied = [];
    final List<String> failed = [];

    if (isMatch) {
      satisfied.add('Key cards ($count) in ${trumpSuit.symbol} match requirement');
    } else {
      if (!countPassed) {
        failed.add('Key cards ($count) in ${trumpSuit.symbol} outside requirement');
      }
      if (!queenPassed) {
        failed.add('Trump Queen ${requiresQueen! ? "missing" : "unexpected"} in ${trumpSuit.symbol}');
      }
    }

    return MatchResult(
      isMatch: isMatch,
      satisfiedCriteria: satisfied,
      failedCriteria: failed,
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity {
    double score = 40.0;
    if (requiresQueen != null) score += 5.0;
    return score;
  }
}

/// Honor holding constraint, e.g. holding or lacking specific honor like Queen of trump.
class HonorConstraint extends HandConstraint {
  final Suit suit;
  final Rank rank;
  final bool isPresent;

  const HonorConstraint({
    required this.suit,
    required this.rank,
    this.isPresent = true,
  });

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final hasCard = hand.cards.any((c) => c.suit == suit && c.rank == rank);
    final passed = isPresent ? hasCard : !hasCard;

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: passed ? ['${isPresent ? "Holds" : "Lacks"} ${rank.symbol}${suit.symbol}'] : [],
      failedCriteria: !passed ? ['Failed ${isPresent ? "holding" : "lacking"} ${rank.symbol}${suit.symbol}'] : [],
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity => 20.0;
}

/// Hand controls constraint (A=2, K=1), e.g. "controls<=2", "ctrl>=3", "controls=1".
class ControlsConstraint extends HandConstraint {
  final int? min;
  final int? max;

  const ControlsConstraint({this.min, this.max});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final ctrl = hand.controls;
    bool passed = true;
    final List<String> satisfied = [];
    final List<String> failed = [];

    if (min != null && ctrl < min!) {
      passed = false;
      failed.add('Controls ($ctrl) is less than required min $min');
    }
    if (max != null && ctrl > max!) {
      passed = false;
      failed.add('Controls ($ctrl) exceeds maximum $max');
    }

    final reqStr = min != null && max != null
        ? (min == max ? '$min controls' : '$min-$max controls')
        : (min != null ? '$min+ controls' : '<=$max controls');

    if (passed) {
      satisfied.add('Controls ($ctrl) matches $reqStr');
    }

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: satisfied,
      failedCriteria: failed,
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity => 15.0;
}

/// Outside controls constraint (A=2, K=1 in suits outside the trump/solid suit),
/// e.g. "outside_ctrl=0", "outside_ctrl<=1".
class OutsideControlsConstraint extends HandConstraint {
  final Suit? trumpSuit;
  final int? min;
  final int? max;

  const OutsideControlsConstraint({this.trumpSuit, this.min, this.max});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    final Suit suit = trumpSuit ?? (hand.solidMinorSuit ?? hand.longestSuit);
    final ctrl = hand.outsideControls(suit);
    bool passed = true;
    final List<String> satisfied = [];
    final List<String> failed = [];

    if (min != null && ctrl < min!) {
      passed = false;
      failed.add('Outside controls ($ctrl) outside ${suit.symbol} is less than min $min');
    }
    if (max != null && ctrl > max!) {
      passed = false;
      failed.add('Outside controls ($ctrl) outside ${suit.symbol} exceeds max $max');
    }

    final reqStr = min != null && max != null
        ? (min == max ? '$min outside controls' : '$min-$max outside controls')
        : (min != null ? '$min+ outside controls' : '<=$max outside controls');

    if (passed) {
      satisfied.add('Outside controls ($ctrl) matches $reqStr');
    }

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: satisfied,
      failedCriteria: failed,
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity => 18.0;
}

/// Solid suit constraint, e.g. "solid_minor" or "solid:c", "solid:h".
/// Checks for at least [minLength] cards (default 7) headed by Ace, King, and Queen.
class SolidSuitConstraint extends HandConstraint {
  final Suit? suit; // null if checking solid minor (clubs or diamonds)
  final int minLength;

  const SolidSuitConstraint({this.suit, this.minLength = 7});

  @override
  MatchResult evaluate(Hand hand, HandValuationEngine valuation) {
    bool passed = false;
    String desc = '';

    if (suit != null) {
      passed = hand.isSolidSuit(suit!, minLength: minLength);
      desc = 'solid ${suit!.symbol} ($minLength+ AKQ)';
    } else {
      passed = hand.isSolidMinor(minLength: minLength);
      desc = 'solid minor ($minLength+ AKQ)';
    }

    return MatchResult(
      isMatch: passed,
      satisfiedCriteria: passed ? ['Hand contains $desc'] : [],
      failedCriteria: !passed ? ['Hand lacks required $desc'] : [],
      specificityScore: baseSpecificity,
    );
  }

  @override
  double get baseSpecificity => 35.0;
}

