import 'ml_hand_valuation_model.dart';
import 'ml_preempt_model.dart';
import '../evaluators/ml_bid_evaluator.dart';
import '../evaluators/ml_strain_model.dart';

/// Central registry managing multiple Machine Learning models across all bidding domains.
/// Supports registering, selecting, inspecting, and hot-swapping models without code changes.
class MLModelRegistry {
  MLModelRegistry._() {
    _initDefaults();
  }

  static final MLModelRegistry instance = MLModelRegistry._();

  // Registered Model Dictionaries
  final Map<String, MLHandValuationModel> _valuationModels = {};
  final Map<String, MLPreemptModel> _preemptModels = {};
  final Map<String, MLStrainBiddingModel> _strainModels = {};
  final Map<String, MLEdgeCaseEvaluator> _edgeCaseModels = {};

  // Active Model Keys
  String _activeValuationId = 'bbo_empirical';
  String _activePreemptId = 'bbo_preempt';
  String _activeStrainId = 'bbo_strain';
  String _activeEdgeCaseId = 'gavin_edge_tree';

  void _initDefaults() {
    // 1. Hand Valuation Models
    _valuationModels['bbo_empirical'] = MLHandValuationModel.current;
    _valuationModels['milton_work_baseline'] = MLHandValuationModel(
      version: '1.0.0-milton-baseline',
      dataset: 'Milton Work Standard',
      trainingSamples: 0,
      featureNames: MLHandValuationModel.current.featureNames,
      weights: [1.0, ...List.filled(MLHandValuationModel.current.weights.length - 1, 0.0)],
      bias: 0.0,
      explanationLabels: const {},
    );

    // 2. Preempt Models
    _preemptModels['bbo_preempt'] = MLPreemptModel.defaultModel();

    // 3. Strain Models
    _strainModels['bbo_strain'] = MLStrainBiddingModel();

    // 4. Edge Case Models
    _edgeCaseModels['gavin_edge_tree'] = MLEdgeCaseEvaluator();
  }

  // --- Hand Valuation Model Management ---
  void registerValuationModel(String id, MLHandValuationModel model) {
    _valuationModels[id] = model;
  }

  MLHandValuationModel? getValuationModel(String id) => _valuationModels[id];

  MLHandValuationModel get activeValuationModel =>
      _valuationModels[_activeValuationId] ?? MLHandValuationModel.current;

  void setActiveValuationModel(String id) {
    if (_valuationModels.containsKey(id)) {
      _activeValuationId = id;
      MLHandValuationModel.setModel(_valuationModels[id]!);
    } else {
      throw ArgumentError('Valuation model "$id" is not registered.');
    }
  }

  List<String> get availableValuationModels => _valuationModels.keys.toList();

  // --- Preempt Model Management ---
  void registerPreemptModel(String id, MLPreemptModel model) {
    _preemptModels[id] = model;
  }

  MLPreemptModel? getPreemptModel(String id) => _preemptModels[id];

  MLPreemptModel get activePreemptModel =>
      _preemptModels[_activePreemptId] ?? MLPreemptModel.defaultModel();

  void setActivePreemptModel(String id) {
    if (_preemptModels.containsKey(id)) {
      _activePreemptId = id;
    } else {
      throw ArgumentError('Preempt model "$id" is not registered.');
    }
  }

  List<String> get availablePreemptModels => _preemptModels.keys.toList();

  // --- Strain Model Management ---
  void registerStrainModel(String id, MLStrainBiddingModel model) {
    _strainModels[id] = model;
  }

  MLStrainBiddingModel? getStrainModel(String id) => _strainModels[id];

  MLStrainBiddingModel get activeStrainModel =>
      _strainModels[_activeStrainId] ?? MLStrainBiddingModel();

  void setActiveStrainModel(String id) {
    if (_strainModels.containsKey(id)) {
      _activeStrainId = id;
    } else {
      throw ArgumentError('Strain model "$id" is not registered.');
    }
  }

  List<String> get availableStrainModels => _strainModels.keys.toList();

  // --- Edge Case Model Management ---
  void registerEdgeCaseModel(String id, MLEdgeCaseEvaluator model) {
    _edgeCaseModels[id] = model;
  }

  MLEdgeCaseEvaluator? getEdgeCaseModel(String id) => _edgeCaseModels[id];

  MLEdgeCaseEvaluator get activeEdgeCaseModel =>
      _edgeCaseModels[_activeEdgeCaseId] ?? MLEdgeCaseEvaluator();

  void setActiveEdgeCaseModel(String id) {
    if (_edgeCaseModels.containsKey(id)) {
      _activeEdgeCaseId = id;
    } else {
      throw ArgumentError('Edge-case model "$id" is not registered.');
    }
  }

  List<String> get availableEdgeCaseModels => _edgeCaseModels.keys.toList();

  // --- Global Profile Management ---
  void setProfile(String profileName) {
    switch (profileName.toLowerCase()) {
      case 'bbo_empirical':
      case 'default':
        _activeValuationId = 'bbo_empirical';
        _activePreemptId = 'bbo_preempt';
        _activeStrainId = 'bbo_strain';
        _activeEdgeCaseId = 'gavin_edge_tree';
        MLHandValuationModel.setModel(_valuationModels['bbo_empirical']!);
        break;
      case 'milton_work':
        _activeValuationId = 'milton_work_baseline';
        _activePreemptId = 'bbo_preempt';
        _activeStrainId = 'bbo_strain';
        _activeEdgeCaseId = 'gavin_edge_tree';
        MLHandValuationModel.setModel(_valuationModels['milton_work_baseline']!);
        break;
      default:
        throw ArgumentError('Unknown profile "$profileName".');
    }
  }

  void resetToDefaults() {
    _initDefaults();
    _activeValuationId = 'bbo_empirical';
    _activePreemptId = 'bbo_preempt';
    _activeStrainId = 'bbo_strain';
    _activeEdgeCaseId = 'gavin_edge_tree';
    MLHandValuationModel.resetToDefault();
  }
}
