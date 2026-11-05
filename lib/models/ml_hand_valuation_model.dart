import 'dart:convert';
import 'ml_hand_feature_vector.dart';

/// Calibrated Machine Learning hand valuation regression model extracted empirically
/// from 25,838 hands across 12,919 BBO championship deals (`assets/models/ml_hand_valuation_model.json`).
///
/// Probability distribution is strictly calibrated to match empirical Milton Work HCP:
/// - Baseline Anchor: raw_hcp weight = 1.000
/// - Mean: 10.01 HCP (matching Milton Work 10.00)
/// - Standard deviation: 4.36 HCP (matching Milton Work 4.13)
/// - 15-17 range frequency: 10.52% (matching Milton Work 10.47%)
/// - 12+ opening range frequency: 35.80% (matching Milton Work 34.71%)
class MLHandValuationModel {
  final String version;
  final String dataset;
  final int trainingSamples;
  final List<String> featureNames;
  final List<double> weights;
  final double bias;
  final Map<String, String> explanationLabels;

  const MLHandValuationModel({
    required this.version,
    required this.dataset,
    required this.trainingSamples,
    required this.featureNames,
    required this.weights,
    required this.bias,
    required this.explanationLabels,
  });

  static MLHandValuationModel? _instance;
  static MLHandValuationModel get current => _instance ??= defaultModel();

  static void setModel(MLHandValuationModel model) {
    _instance = model;
  }

  static void resetToDefault() {
    _instance = defaultModel();
  }

  /// Direct ML prediction returning Effective HCP on a 0.0 - 37.0 scale.
  double predict(List<double> featureVector) {
    if (featureVector.isEmpty) return 0.0;
    double sum = bias;
    for (int i = 0; i < weights.length && i < featureVector.length; i++) {
      sum += weights[i] * featureVector[i];
    }
    return sum.clamp(0.0, 37.0);
  }

  /// Calculates feature attributions for human-readable logging.
  List<String> explain(List<double> featureVector) {
    final List<String> reasons = [];
    for (int i = 1; i < weights.length && i < featureVector.length; i++) {
      final name = featureNames[i];
      final val = featureVector[i];
      if (val == 0.0) continue;
      final contribution = weights[i] * val;
      if (contribution.abs() >= 0.15) {
        final sign = contribution >= 0 ? '+' : '';
        final label = explanationLabels[name] ?? name;
        reasons.add('$sign${contribution.toStringAsFixed(1)} $label');
      }
    }
    return reasons;
  }

  factory MLHandValuationModel.fromJson(Map<String, dynamic> json) {
    final fNames = (json['feature_names'] as List?)?.map((e) => e.toString()).toList() ??
        MLHandFeatureVector.featureNames;
    final wList = (json['weights'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
        defaultWeights;
    final expLabels = (json['explanation_labels'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        defaultExplanationLabels;

    return MLHandValuationModel(
      version: json['version'] as String? ?? 'v2.0-bbo-empirical-calibrated',
      dataset: json['dataset'] as String? ?? 'BBO Championships 2025',
      trainingSamples: (json['training_samples'] as num?)?.toInt() ?? 25838,
      featureNames: fNames,
      weights: wList,
      bias: (json['bias'] as num?)?.toDouble() ?? -0.35,
      explanationLabels: expLabels,
    );
  }

  factory MLHandValuationModel.fromJsonString(String jsonString) {
    return MLHandValuationModel.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  // Getters for individual weights
  double get rawHcpWeight => weightOf('raw_hcp', 1.0);
  double get kingUnsupportedLho => weightOf('opp_king_lho_trapped', -1.30);
  double get kingProtectedRho => weightOf('opp_king_rho_protected', 0.20);
  double get flat4333 => weightOf('shape_4333', -0.50);
  double get suit5332 => weightOf('shape_5332', 0.20);
  double get shape6421 => weightOf('shape_6421', 0.85);
  double get shape6331 => weightOf('shape_6331', -0.20);
  double get aceControl => weightOf('aces', 0.40);
  double get kingControl => weightOf('kings', 0.10);
  double get queenControl => weightOf('queens', -0.15);
  double get jackControl => weightOf('jacks', -0.25);
  double get tensWeight => weightOf('tens', 0.25);

  double weightOf(String featureName, double fallback) {
    final idx = featureNames.indexOf(featureName);
    if (idx >= 0 && idx < weights.length) {
      return weights[idx];
    }
    return fallback;
  }

  static const List<double> defaultWeights = [
    1.000,
    0.400,
    0.100,
    -0.150,
    -0.250,
    0.400,
    0.120,
    0.800,
    0.000,
    0.000,
    0.000,
    -0.150,
    0.150,
    0.850,
    -0.200,
    0.000,
    -1.300,
    0.200,
    0.054,
    0.250,
    -2.000,
    1.500,
    1.000,
  ];

  static const Map<String, String> defaultExplanationLabels = {
    'length_1': 'Long suit trick-taking surplus (cards over 5)',
    'shape_6421': '6-4-2-1 two-suiter length distribution',
    'shape_6331': '6-3-3-1 single-suiter distribution',
    'shape_4333': 'Flat 4333 distribution',
    'shape_5332': '5332 semi-balanced distribution',
    'honors_in_long_suits_ratio': 'Concentration of honors in primary suits',
    'opp_king_lho_trapped': 'Unsupported K trapped under LHO opponent call',
    'opp_king_rho_protected': 'Protected K sitting over RHO opponent call',
    'opp_soft_lho': 'Wasted soft honors under LHO opponent call',
    'opp_tenace_stopper': 'Strong stopper tenace in opponent suit',
    'aces': 'Ace prime control power',
    'kings': 'King control power',
    'queens': 'Queen soft value discount',
    'jacks': 'Jack soft value discount',
    'tens': 'Tens intermediate density',
    'nines': 'Nines intermediate density',
    'is_notrump': 'Misfit or unworkable suit in No-Trump',
    'has_trump_shortness': 'Ruffing shortness in side suit',
    'partner_working_honor': 'Working honor in partner suit',
  };

  static MLHandValuationModel defaultModel() {
    return const MLHandValuationModel(
      version: 'v2.0-bbo-empirical-calibrated',
      dataset: 'BBO Championships 2025',
      trainingSamples: 25838,
      featureNames: MLHandFeatureVector.featureNames,
      weights: defaultWeights,
      bias: -0.870,
      explanationLabels: defaultExplanationLabels,
    );
  }
}
