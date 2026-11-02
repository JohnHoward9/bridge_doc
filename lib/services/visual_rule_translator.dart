import '../models/card.dart';
import '../models/bidding_system.dart';

/// Enum representing common bridge distribution shapes.
enum ShapeCategory {
  any('Any Shape'),
  balanced('Balanced (4333, 4432, 5332)'),
  unbalanced('Unbalanced (Singletons or Voids)'),
  twoSuited55('Two-Suiter (5-5)'),
  twoSuited54('Two-Suiter (5-4)'),
  flat4333('Flat (4333)');

  final String label;
  const ShapeCategory(this.label);
}

/// Forcing status of a call.
enum ForcingCategory {
  none('Natural / Non-Forcing'),
  invitational('Invitational'),
  gameForcing('Game Forcing (GF)'),
  signoff('Signoff / To Play');

  final String label;
  const ForcingCategory(this.label);
}

/// Strongly-typed visual representation of a bid's constraints and parameters,
/// allowing form-based editing without touching YAML or constraint DSL syntax.
class VisualBidFormData {
  String call;
  String desc;
  int? minHcp;
  int? maxHcp;
  Map<Suit, int?> minSuitLength;
  Map<Suit, int?> maxSuitLength;
  ShapeCategory shape;
  bool? requireShortHonors; // true = short_honors, false = !short_honors, null = any
  ForcingCategory forcing;
  int priority;
  String? conventionRef; // e.g. "fJacobyTransferAcceptance"

  VisualBidFormData({
    required this.call,
    this.desc = '',
    this.minHcp,
    this.maxHcp,
    Map<Suit, int?>? minSuitLength,
    Map<Suit, int?>? maxSuitLength,
    this.shape = ShapeCategory.any,
    this.requireShortHonors,
    this.forcing = ForcingCategory.none,
    this.priority = 2,
    this.conventionRef,
  })  : minSuitLength = minSuitLength ?? {for (var s in Suit.values) s: null},
        maxSuitLength = maxSuitLength ?? {for (var s in Suit.values) s: null};

  /// Decodes any [BiddingNode] into user-friendly form fields.
  factory VisualBidFormData.fromNode(BiddingNode node, {Map<String, String>? definitions}) {
    final rawRule = node.rule ?? '';
    final rawDesc = node.desc ?? '';
    final combined = '$rawRule $rawDesc'.toLowerCase();

    // 1. Call & Ref
    final call = node.displayCall.isNotEmpty ? node.displayCall : node.call;
    final conventionRef = node.ref;

    // 2. Priority
    int priority = node.priority ?? 2;
    final pMatch = RegExp(r'p#(\d+)').firstMatch(rawRule);
    if (pMatch != null) {
      priority = int.tryParse(pMatch.group(1)!) ?? priority;
    }

    // 3. HCP range
    int? minHcp;
    int? maxHcp;
    final rangeRegex = RegExp(r'(\d+)\s*[-–]\s*(\d+)\s*(?:hcp|points)?');
    final plusRegex = RegExp(r'(\d+)\s*\+\s*(?:hcp|points)?');
    final minusRegex = RegExp(r'(\d+)\s*-\s*(?:hcp|points)?');

    final rangeMatch = rangeRegex.firstMatch(rawRule);
    if (rangeMatch != null) {
      minHcp = int.tryParse(rangeMatch.group(1)!);
      maxHcp = int.tryParse(rangeMatch.group(2)!);
    } else {
      final plusMatch = plusRegex.firstMatch(rawRule);
      if (plusMatch != null) {
        minHcp = int.tryParse(plusMatch.group(1)!);
      }
      final minusMatch = minusRegex.firstMatch(rawRule);
      if (minusMatch != null) {
        maxHcp = int.tryParse(minusMatch.group(1)!);
      }
    }

    // 4. Suit lengths
    final minLens = <Suit, int?>{for (var s in Suit.values) s: null};
    final maxLens = <Suit, int?>{for (var s in Suit.values) s: null};

    for (final s in Suit.values) {
      final sChar = s.name[0];
      final sPattern = sChar == 'h' ? r'h(?!cp)' : sChar;

      // Min: e.g. 5+h, 4+c
      final minMatch = RegExp('(\\d+)\\s*\\+\\s*(?:$sPattern|${s.name})').firstMatch(rawRule);
      if (minMatch != null) {
        minLens[s] = int.tryParse(minMatch.group(1)!);
      }

      // Max: e.g. 3-s, 2-h
      final maxMatch = RegExp('(\\d+)\\s*-\\s*(?:$sPattern|${s.name})').firstMatch(rawRule);
      if (maxMatch != null) {
        maxLens[s] = int.tryParse(maxMatch.group(1)!);
      }
    }

    // 5. Shape
    ShapeCategory shape = ShapeCategory.any;
    if (rawRule.contains('s#5332') || combined.contains('balanced') || rawRule.contains(r'$bal')) {
      shape = ShapeCategory.balanced;
    } else if (rawRule.contains('!s#4333') || rawRule.contains('!balanced') || rawRule.contains('unbalanced')) {
      shape = ShapeCategory.unbalanced;
    } else if (rawRule.contains('s#4333')) {
      shape = ShapeCategory.flat4333;
    }

    // 6. Short-suit honors / stoppers
    bool? requireShortHonors;
    if (rawRule.contains('!short_honors')) {
      requireShortHonors = false;
    } else if (rawRule.contains('short_honors')) {
      requireShortHonors = true;
    }

    // 7. Forcing category
    ForcingCategory forcing = ForcingCategory.none;
    if (combined.contains('game force') || combined.contains('game_force') || combined.contains(' gf') || combined.startsWith('gf')) {
      forcing = ForcingCategory.gameForcing;
    } else if (combined.contains('invite') || combined.contains('invitational')) {
      forcing = ForcingCategory.invitational;
    } else if (combined.contains('signoff') || combined.contains('to play')) {
      forcing = ForcingCategory.signoff;
    }

    return VisualBidFormData(
      call: call,
      desc: rawDesc,
      minHcp: minHcp,
      maxHcp: maxHcp,
      minSuitLength: minLens,
      maxSuitLength: maxLens,
      shape: shape,
      requireShortHonors: requireShortHonors,
      forcing: forcing,
      priority: priority,
      conventionRef: conventionRef,
    );
  }

  /// Generates a clean constraint rule string from the visual form values.
  String generateRuleString() {
    final tokens = <String>[];

    // Priority
    tokens.add('p#$priority');

    // HCP Range
    if (minHcp != null && maxHcp != null) {
      tokens.add('$minHcp-${maxHcp}hcp');
    } else if (minHcp != null) {
      tokens.add('$minHcp+hcp');
    } else if (maxHcp != null) {
      tokens.add('$maxHcp-hcp');
    }

    // Suit Lengths
    for (final s in Suit.values) {
      final sChar = s.name[0];
      final min = minSuitLength[s];
      final max = maxSuitLength[s];
      if (min != null) tokens.add('$min+$sChar');
      if (max != null) tokens.add('$max-$sChar');
    }

    // Shape
    switch (shape) {
      case ShapeCategory.balanced:
        tokens.add('s#5332|4432|4333');
        break;
      case ShapeCategory.unbalanced:
        tokens.add('!s#4333');
        break;
      case ShapeCategory.flat4333:
        tokens.add('s#4333');
        break;
      case ShapeCategory.twoSuited55:
        tokens.add('!s#5332 !s#5422 !s#4333');
        break;
      case ShapeCategory.twoSuited54:
        tokens.add('!s#5332');
        break;
      case ShapeCategory.any:
        break;
    }

    // Short-suit honors
    if (requireShortHonors == true) {
      tokens.add('short_honors');
    } else if (requireShortHonors == false) {
      tokens.add('!short_honors');
    }

    // Forcing
    if (forcing == ForcingCategory.gameForcing) {
      tokens.add('gf');
    }

    return tokens.join(' ');
  }

  /// Converts form data back into a valid [BiddingNode].
  BiddingNode toNode({List<BiddingNode>? existingChildren}) {
    String cleanCall = call.trim().toLowerCase();
    cleanCall = cleanCall
        .replaceAll('♣', 'c')
        .replaceAll('♦', 'd')
        .replaceAll('♥', 'h')
        .replaceAll('♠', 's');

    final ruleStr = generateRuleString();

    return BiddingNode(
      call: cleanCall,
      desc: desc,
      rule: ruleStr,
      priority: priority,
      ref: conventionRef,
      bids: conventionRef != null ? [] : (existingChildren ?? []),
    );
  }
}
