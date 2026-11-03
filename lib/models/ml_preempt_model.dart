import 'dart:convert';
import 'card.dart';
import 'hand.dart';
import 'seat_belief_state.dart';
import '../evaluators/ml_bid_evaluator.dart';

/// Machine Learning Preempt Decision Model.
/// Evaluates tactical preempt feasibility, allowed undertricks, and trick expectancy
/// from calibrated empirical model parameters instead of hardcoded Dart constants.
class MLPreemptModel {
  final String modelName;
  final String version;
  final String description;
  final Map<String, double> parameters;
  final Map<String, double> allowedDownByVulnerability;
  final Map<String, double> seatAllowedDownAdjustments;
  final Map<int, int> minSuitLengthByLevel;

  const MLPreemptModel({
    required this.modelName,
    required this.version,
    required this.description,
    required this.parameters,
    required this.allowedDownByVulnerability,
    required this.seatAllowedDownAdjustments,
    required this.minSuitLengthByLevel,
  });

  double get baseTrickConstant => parameters['base_trick_constant'] ?? 13.0;
  double get ltcWeight => parameters['ltc_weight'] ?? -1.0;
  double get lengthSurplusWeight => parameters['length_surplus_weight'] ?? 1.0;
  double get honorDensityWeight => parameters['honor_density_weight'] ?? 0.25;
  double get hcpCeiling => parameters['hcp_ceiling'] ?? 11.0;
  int get soundSuitSecondSeatMinHonors => (parameters['sound_suit_second_seat_min_honors'] ?? 2).round();

  /// Calculates trick expectancy for [hand] in [suit] using the model parameters.
  double estimatePlayingTricks(Hand hand, Suit suit) {
    final suitLength = hand.length(suit);
    final ltc = hand.losingTrickCount;
    final lengthSurplus = suitLength >= 7 ? (suitLength - 6) : 0;
    final honors = hand.cardsInSuit(suit).where((c) => c.rank.value >= Rank.ten.value).length;

    final tricks = baseTrickConstant +
        (ltcWeight * ltc) +
        (lengthSurplusWeight * lengthSurplus) +
        (honorDensityWeight * honors);

    return double.parse(tricks.clamp(1.0, 13.0).toStringAsFixed(1));
  }

  /// Evaluates whether [hand] should preempt at [level] in [suit] under [seat] and [vuln].
  PreemptDecision evaluatePreempt(
    Hand hand, {
    required Suit suit,
    required int level,
    SeatPosition seat = SeatPosition.first,
    Vulnerability vuln = Vulnerability.none,
  }) {
    final expTricks = estimatePlayingTricks(hand, suit);
    final targetTricks = level + 6;
    final suitLength = hand.length(suit);

    // 4th Seat Principle: Never preempt when opponents have passed
    if (seat == SeatPosition.fourth) {
      final ruleOf15 = hand.hcp + hand.spadesLength;
      final shouldOpen = ruleOf15 >= 15 && hand.hcp >= 10;
      return PreemptDecision(
        shouldPreempt: false,
        effectiveMpi: expTricks,
        allowedUndertricks: 0,
        expectedTricks: expTricks,
        recommendedCall: shouldOpen ? '1${suit.symbol}' : 'Pass',
        reason: '4th Seat Principle: Never preempt when opponents have passed. Rule of 15 ($ruleOf15) '
            '${shouldOpen ? "qualifies for 1${suit.symbol} opening" : "recommends passing out"}.',
      );
    }

    // Allowed undertricks from vulnerability mapping:
    final vulnKey = vuln.name.toLowerCase();
    double allowedDown = allowedDownByVulnerability[vulnKey] ?? 3.0;

    // Tactical adjustment by seat:
    final seatKey = seat.name.toLowerCase();
    allowedDown += seatAllowedDownAdjustments[seatKey] ?? 0.0;

    // Minimum suit length requirement:
    final minLength = minSuitLengthByLevel[level] ?? (level + 4);
    final hasLength = suitLength >= minLength;

    // 2nd seat discipline:
    bool soundSuit = true;
    if (seat == SeatPosition.second) {
      final honors = hand.cardsInSuit(suit).where((c) => c.rank.value >= Rank.ten.value).length;
      soundSuit = honors >= soundSuitSecondSeatMinHonors;
    }

    // HCP ceiling:
    final isWeak = hand.hcp <= hcpCeiling;
    final deficit = targetTricks - expTricks;
    final shouldPreempt = hasLength && isWeak && soundSuit && (deficit <= allowedDown);

    final call = '$level${suit.symbol}';
    final reason = shouldPreempt
        ? 'ML Preempt Model recommends opening $call ($suitLength-card suit, ${expTricks.toStringAsFixed(1)} exp tricks, '
            'allowed down ${allowedDown.toStringAsFixed(1)} in ${seat.label}).'
        : 'Preempt $call not recommended: ${!hasLength ? "insufficient length ($suitLength < $minLength)" : (!isWeak ? "too strong for preempt (${hand.hcp} HCP > $hcpCeiling)" : (!soundSuit ? "2nd seat requires sound suit quality" : "deficit ($deficit) exceeds allowed down $allowedDown"))}.';

    return PreemptDecision(
      shouldPreempt: shouldPreempt,
      effectiveMpi: expTricks,
      allowedUndertricks: allowedDown.round(),
      expectedTricks: expTricks,
      recommendedCall: shouldPreempt ? call : 'Pass',
      reason: reason,
    );
  }

  factory MLPreemptModel.fromJson(Map<String, dynamic> json) {
    final params = (json['parameters'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ) ??
        {};

    final allowedDown = (json['allowed_down_by_vulnerability'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ) ??
        {};

    final seatAdj = (json['seat_allowed_down_adjustments'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ) ??
        {};

    final minLen = (json['min_suit_length_by_level'] as Map?)?.map(
          (k, v) => MapEntry(int.tryParse(k.toString()) ?? 2, (v as num).toInt()),
        ) ??
        {2: 6, 3: 7, 4: 8};

    return MLPreemptModel(
      modelName: json['model_name'] as String? ?? 'BBOChampionshipPreemptModel',
      version: json['version'] as String? ?? '1.0.0-empirical',
      description: json['description'] as String? ?? '',
      parameters: params,
      allowedDownByVulnerability: allowedDown,
      seatAllowedDownAdjustments: seatAdj,
      minSuitLengthByLevel: minLen,
    );
  }

  factory MLPreemptModel.fromJsonString(String jsonStr) {
    return MLPreemptModel.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  static MLPreemptModel defaultModel() {
    return const MLPreemptModel(
      modelName: 'BBOChampionshipPreemptModel',
      version: '1.0.0-empirical',
      description: 'Default empirical preempt model calibrated on BBO championships',
      parameters: {
        'base_trick_constant': 13.0,
        'ltc_weight': -1.0,
        'length_surplus_weight': 1.0,
        'honor_density_weight': 0.25,
        'hcp_ceiling': 11.0,
        'sound_suit_second_seat_min_honors': 2.0,
      },
      allowedDownByVulnerability: {
        'favorable': 4.0,
        'none': 3.0,
        'both': 3.0,
        'unfavorable': 2.0,
      },
      seatAllowedDownAdjustments: {
        'first': 0.0,
        'second': -0.5,
        'third': 1.0,
        'fourth': -999.0,
      },
      minSuitLengthByLevel: {2: 6, 3: 7, 4: 8},
    );
  }
}
