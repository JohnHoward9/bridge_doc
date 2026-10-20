import 'dart:convert';
import 'dart:io';
import '../models/hand.dart';
import '../models/card.dart';

/// Prediction result from the Gavin Wolpert ML Edge-Case Model.
class MLEdgeCasePrediction {
  /// Expected Result = Tricks Taken - Target Tricks (e.g. +0.37 or -0.69).
  final double expectedResult;

  /// Probability of making the contract (Result >= 0).
  final double probMaking;

  /// Number of championship training samples supporting this node.
  final int samples;

  const MLEdgeCasePrediction({
    required this.expectedResult,
    required this.probMaking,
    required this.samples,
  });

  /// True if expected tricks >= target or probability of making >= 50%.
  bool get shouldAcceptInvite => probMaking >= 0.50 || expectedResult >= 0.0;

  @override
  String toString() =>
      'MLEdgeCasePrediction(expectedResult: ${expectedResult.toStringAsFixed(2)}, '
      'probMaking: ${(probMaking * 100).toStringAsFixed(1)}%, samples: $samples)';
}

typedef MLBidEvaluator = MLEdgeCaseEvaluator;

/// Evaluates borderline edge cases (e.g. 22-25 HCP game invitations, 29-32 HCP marginal slams)
/// using the Machine Learning decision tree trained on 2025 BBO Championship deals.
class MLEdgeCaseEvaluator {
  final Map<String, dynamic> modelData;

  MLEdgeCaseEvaluator({Map<String, dynamic>? model})
      : modelData = model ?? _defaultModel;

  factory MLEdgeCaseEvaluator.fromJsonString(String jsonStr) {
    return MLEdgeCaseEvaluator(model: jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  /// Evaluates an edge-case contract using partnership features.
  MLEdgeCasePrediction evaluateEdgeCase({
    required double combHcp,
    required double hcpDiff,
    required double maxMajorFit,
    required int contractLevel,
    required int strainCode, // 0=NT, 1=S, 2=H, 3=D, 4=C
    required bool isGameTarget,
    double combControls = 4.0,
    double combLtc = 14.0,
    bool isVulnerable = false,
  }) {
    final features = <String, double>{
      'comb_hcp': combHcp,
      'hcp_diff': hcpDiff,
      'max_major_fit': maxMajorFit,
      'comb_controls': combControls,
      'comb_ltc': combLtc,
      'contract_level': contractLevel.toDouble(),
      'strain_code': strainCode.toDouble(),
      'is_game_target': isGameTarget ? 1.0 : 0.0,
      'is_vulnerable': isVulnerable ? 1.0 : 0.0,
    };

    final tree = modelData['tree'] as Map<String, dynamic>;
    return _traverse(tree, features);
  }

  /// Convenience evaluation directly from North and South hands.
  MLEdgeCasePrediction evaluateHands({
    required Hand north,
    required Hand south,
    required int contractLevel,
    required String strain, // 'nt', 's', 'h', 'd', 'c'
    bool isVulnerable = false,
  }) {
    final s = strain.toLowerCase();
    int code = 0;
    if (s.contains('s')) {
      code = 1;
    } else if (s.contains('h')) {
      code = 2;
    } else if (s.contains('d')) {
      code = 3;
    } else if (s.contains('c')) {
      code = 4;
    }

    final combHcp = (north.hcp + south.hcp).toDouble();
    final hcpDiff = (north.hcp - south.hcp).abs().toDouble();
    final spadeFit = (north.length(Suit.spades) + south.length(Suit.spades)).toDouble();
    final heartFit = (north.length(Suit.hearts) + south.length(Suit.hearts)).toDouble();
    final double maxFit;
    if (code == 1) {
      maxFit = spadeFit;
    } else if (code == 2) {
      maxFit = heartFit;
    } else {
      maxFit = spadeFit > heartFit ? spadeFit : heartFit;
    }

    final isGame = (contractLevel >= 4 && (code == 1 || code == 2)) ||
        (contractLevel >= 3 && code == 0) ||
        (contractLevel >= 5 && (code == 3 || code == 4));

    final combControls = (north.controls + south.controls).toDouble();
    final combLtc = (north.losingTrickCount + south.losingTrickCount).toDouble();

    return evaluateEdgeCase(
      combHcp: combHcp,
      hcpDiff: hcpDiff,
      maxMajorFit: maxFit,
      contractLevel: contractLevel,
      strainCode: code,
      isGameTarget: isGame,
      combControls: combControls,
      combLtc: combLtc,
      isVulnerable: isVulnerable,
    );
  }

  MLEdgeCasePrediction _traverse(
      Map<String, dynamic> node, Map<String, double> features) {
    if (!node.containsKey('feature') || node['feature'] == null) {
      return MLEdgeCasePrediction(
        expectedResult: (node['value'] as num).toDouble(),
        probMaking: (node['prob_making'] as num).toDouble(),
        samples: (node['samples'] as num).toInt(),
      );
    }

    final featureName = node['feature'] as String;
    final threshold = (node['threshold'] as num).toDouble();
    final val = features[featureName] ?? 0.0;

    if (val <= threshold) {
      return _traverse(node['left'] as Map<String, dynamic>, features);
    } else {
      return _traverse(node['right'] as Map<String, dynamic>, features);
    }
  }

  static Map<String, dynamic> _loadDefaultModel() {
    try {
      final file = File('assets/models/gavin_ml_edge_model.json');
      if (file.existsSync()) {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return _embeddedModel;
  }

  static final Map<String, dynamic> _defaultModel = _loadDefaultModel();

  static final Map<String, dynamic> _embeddedModel = {
    "model_name": "GavinWolpertEdgeCaseDecisionTree",
    "version": "1.0.0",
    "target_metric": "Tricks Taken - Target Tricks",
    "tree": {
      "feature": "contract_level",
      "threshold": 2.5,
      "samples": 116,
      "left": {
        "feature": "hcp_diff",
        "threshold": 1.5,
        "samples": 44,
        "left": {
          "value": -0.25,
          "prob_making": 0.75,
          "samples": 4
        },
        "right": {
          "feature": "strain_code",
          "threshold": 1.5,
          "samples": 40,
          "left": {
            "value": 1.0625,
            "prob_making": 0.9062,
            "samples": 32
          },
          "right": {
            "value": 2.5,
            "prob_making": 1.0,
            "samples": 8
          }
        }
      },
      "right": {
        "feature": "comb_hcp",
        "threshold": 27.0,
        "samples": 72,
        "left": {
          "feature": "max_major_fit",
          "threshold": 7.5,
          "samples": 62,
          "left": {
            "value": -0.6857,
            "prob_making": 0.3429,
            "samples": 35
          },
          "right": {
            "value": 0.3704,
            "prob_making": 0.8148,
            "samples": 27
          }
        },
        "right": {
          "feature": "contract_level",
          "threshold": 3.5,
          "samples": 10,
          "left": {
            "value": 3.3333,
            "prob_making": 1.0,
            "samples": 3
          },
          "right": {
            "value": 0.2857,
            "prob_making": 0.8571,
            "samples": 7
          }
        }
      }
    }
  };
}
