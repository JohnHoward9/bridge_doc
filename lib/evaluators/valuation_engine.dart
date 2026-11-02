import '../models/card.dart';

import '../models/hand.dart';

import '../models/bidding_state_context.dart';

import '../models/ml_hand_valuation_model.dart';

import '../models/ml_hand_feature_vector.dart';

/// Pluggable engine for evaluating bridge hands.

abstract class HandValuationEngine {

  /// Name of this valuation methodology.

  String get name;

  /// Evaluate the primary point count (e.g. HCP or ML strength).

  double evaluatePoints(Hand hand, {Suit? trumpSuit, Suit? partnerSuit, Suit? oppSuit});

  /// Feature extraction vector for ML training/inference (e.g. 52-card one-hot or suit distribution).

  List<double> extractFeatureVector(Hand hand);

}

/// Standard Milton Work High Card Point count (A=4, K=3, Q=2, J=1).

class MiltonWorkValuation extends HandValuationEngine {

  @override

  String get name => 'Milton Work HCP (A=4, K=3, Q=2, J=1)';

  @override

  double evaluatePoints(Hand hand, {Suit? trumpSuit, Suit? partnerSuit, Suit? oppSuit}) {

    return hand.hcp.toDouble();

  }

  @override

  List<double> extractFeatureVector(Hand hand) {

    return [

      hand.hcp.toDouble(),

      hand.spadesLength.toDouble(),

      hand.heartsLength.toDouble(),

      hand.diamondsLength.toDouble(),

      hand.clubsLength.toDouble(),

      hand.suitHcp(Suit.spades).toDouble(),

      hand.suitHcp(Suit.hearts).toDouble(),

      hand.suitHcp(Suit.diamonds).toDouble(),

      hand.suitHcp(Suit.clubs).toDouble(),

      hand.isBalanced ? 1.0 : 0.0,

    ];

  }

}

/// Structured diagnosis of an ML hand upgrade or downgrade.

/// Valuation result from Machine Learning hand strength estimation.
class MLHandBreakdown {
  final double rawHcp;
  final double effectiveHcp;
  final double intermediateAdjustment;
  final double suitQualityAdjustment;
  final double controlAdjustment;
  final double shapeAdjustment;
  final double partnerMeshAdjustment;
  final double opponentWasteAdjustment;
  final List<String> reasons;

  const MLHandBreakdown({
    required this.rawHcp,
    required this.effectiveHcp,
    this.intermediateAdjustment = 0.0,
    this.suitQualityAdjustment = 0.0,
    this.controlAdjustment = 0.0,
    this.shapeAdjustment = 0.0,
    this.partnerMeshAdjustment = 0.0,
    this.opponentWasteAdjustment = 0.0,
    this.reasons = const [],
  });

  factory MLHandBreakdown.raw(double hcp) {
    return MLHandBreakdown(
      rawHcp: hcp,
      effectiveHcp: hcp,
    );
  }

  bool get isUpgraded => effectiveHcp >= rawHcp + 0.75;
  bool get isDowngraded => effectiveHcp <= rawHcp - 0.75;
  double get netDelta => effectiveHcp - rawHcp;

  /// The Machine Learning Power Index mapped on a 0-37 scale.
  double get mpi => double.parse(effectiveHcp.clamp(0.0, 37.0).toStringAsFixed(1));

  String get summaryText {
    final prefix = isUpgraded ? '🚀 Upgraded' : (isDowngraded ? '⚠️ Downgraded' : '⚖️ Neutral');
    final sign = netDelta >= 0 ? '+' : '';
    return ' ( →  HCP, )';
  }
}

/// Machine Learning hand valuation engine incorporating intermediate honor density (10s and 9s),

/// prime control ratios, 5-card suit quality, fit shortness, and partner/opponent mesh.

class MLHandValuation extends HandValuationEngine {

  final MLHandValuationModel model;

  final String modelVersion;

  final bool strictEffectiveHcp;

  MLHandValuation({

    MLHandValuationModel? model,

    String? modelVersion,

    this.strictEffectiveHcp = false,

  })  : model = model ?? MLHandValuationModel.current,

        modelVersion = modelVersion ?? (model?.version ?? 'v2.0-bbo-empirical');

  @override

  String get name => 'ML Hand Valuation ($modelVersion)';

  @override

  double evaluatePoints(Hand hand, {Suit? trumpSuit, Suit? partnerSuit, Suit? oppSuit}) {

    final opponentActions = oppSuit != null

        ? [OpponentSuitAction(suit: oppSuit, position: RelativeOpponentPosition.lho, call: 'bid', seat: 'LHO')]

        : const <OpponentSuitAction>[];

    final vector = MLHandFeatureVector.extract(

      hand,

      trumpSuit: trumpSuit,

      partnerSuit: partnerSuit,

      opponentActions: opponentActions,

    );

    return model.predict(vector);

  }

  /// Evaluates hand with full auction context including opponent positional actions.

  MLHandBreakdown evaluateWithAuctionContext(

    Hand hand, {

    Suit? trumpSuit,

    Suit? partnerSuit,

    Suit? oppSuit,

    List<OpponentSuitAction> opponentActions = const [],

  }) {

    return evaluateBreakdown(

      hand,

      trumpSuit: trumpSuit,

      partnerSuit: partnerSuit,

      oppSuit: oppSuit,

      opponentActions: opponentActions,

    );

  }

  /// Evaluates hand on the 0-37 ML Power Index scale.

  double evaluateMpi(Hand hand, {Suit? trumpSuit, Suit? partnerSuit, Suit? oppSuit}) {

    return evaluateBreakdown(

      hand,

      trumpSuit: trumpSuit,

      partnerSuit: partnerSuit,

      oppSuit: oppSuit,

    ).mpi;

  }

  MLHandBreakdown evaluateBreakdown(

    Hand hand, {

    Suit? trumpSuit,

    Suit? partnerSuit,

    Suit? oppSuit,

    List<OpponentSuitAction> opponentActions = const [],

  }) {

    var actions = opponentActions;

    if (actions.isEmpty && oppSuit != null) {

      actions = [OpponentSuitAction(suit: oppSuit, position: RelativeOpponentPosition.lho, call: 'bid', seat: 'LHO')];

    }

    final vector = MLHandFeatureVector.extract(

      hand,

      trumpSuit: trumpSuit,

      partnerSuit: partnerSuit,

      opponentActions: actions,

    );

    // Direct ML prediction returning a single continuous score on the 0.0 - 37.0 scale
    final effectiveHcp = model.predict(vector);
    final rawHcp = hand.hcp.toDouble();

    return MLHandBreakdown(
      rawHcp: rawHcp,
      effectiveHcp: effectiveHcp,
    );

  }

  @override

  List<double> extractFeatureVector(Hand hand) {

    return [

      hand.hcp.toDouble(),

      hand.spadesLength.toDouble(),

      hand.heartsLength.toDouble(),

      hand.diamondsLength.toDouble(),

      hand.clubsLength.toDouble(),

      hand.controls.toDouble(),

      hand.losingTrickCount.toDouble(),

      hand.isBalanced ? 1.0 : 0.0,

    ];

  }

}

typedef MachineLearningValuation = MLHandValuation;

