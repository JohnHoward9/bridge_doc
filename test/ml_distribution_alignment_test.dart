import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/ml_hand_valuation_model.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';

void main() {
  group('ML Model Milton Work Distribution Alignment Tests', () {
    test('Continuous ML Effective HCP matches empirical Milton Work distribution on BBO deals', () {
      final datasetFile = File('res/bbo_championships_2025_dataset.json');
      expect(datasetFile.existsSync(), isTrue);

      final jsonList = jsonDecode(datasetFile.readAsStringSync()) as List;
      final valuation = MLHandValuation();

      final List<double> mlPredictions = [];
      final List<int> miltonHcpList = [];

      // Sample first 5,000 hands from the championship dataset for fast test verification
      int sampleCount = 0;
      for (final item in jsonList) {
        final dealStr = item['deal'] as String?;
        if (dealStr == null || !dealStr.startsWith('md|')) continue;
        final inner = dealStr.substring(3).replaceAll('|', '');
        final handsStr = inner.substring(1).split(',');
        if (handsStr.length != 4) continue;

        for (final hStr in handsStr) {
          // Parse hand cards into dot notation
          String s = '', h = '', d = '', c = '';
          String curr = '';
          for (int i = 0; i < hStr.length; i++) {
            final char = hStr[i];
            if ('SHDC'.contains(char)) {
              curr = char;
            } else {
              if (curr == 'S') s += char;
              if (curr == 'H') h += char;
              if (curr == 'D') d += char;
              if (curr == 'C') c += char;
            }
          }
          final hand = Hand.fromString('$s.$h.$d.$c');
          final eff = valuation.evaluatePoints(hand);
          mlPredictions.add(eff);
          miltonHcpList.add(hand.hcp);
          sampleCount++;
          if (sampleCount >= 5000) break;
        }
        if (sampleCount >= 5000) break;
      }

      final n = mlPredictions.length;
      expect(n, equals(5000));

      final mlMean = mlPredictions.reduce((a, b) => a + b) / n;
      final mlVar = mlPredictions.map((x) => (x - mlMean) * (x - mlMean)).reduce((a, b) => a + b) / n;
      final mlStd = sqrt(mlVar);

      // Verify Mean matches Milton Work (10.00 ± 0.25)
      expect(mlMean, closeTo(10.0, 0.25), reason: 'Calibrated ML Mean must match Milton Work 10.00');

      // Verify Standard Deviation matches Milton Work (4.13 ± 0.35)
      expect(mlStd, closeTo(4.13, 0.35), reason: 'Calibrated ML Std must match Milton Work 4.13');

      // Verify 15-17 range frequency:
      // Milton Work discrete 15-17
      final milton15to17Count = miltonHcpList.where((x) => x >= 15 && x <= 17).length;
      final milton15to17Freq = (milton15to17Count / n) * 100.0;

      // Continuous ML in [14.5, 17.5) (the rounding bucket for 15, 16, 17)
      final ml15to17Count = mlPredictions.where((x) => x >= 14.5 && x < 17.5).length;
      final ml15to17Freq = (ml15to17Count / n) * 100.0;

      expect(ml15to17Freq, closeTo(milton15to17Freq, 1.0),
          reason: '15-17 ML probability ($ml15to17Freq%) must align with Milton Work ($milton15to17Freq%)');

      // Verify 12+ opening frequency:
      final milton12PlusCount = miltonHcpList.where((x) => x >= 12).length;
      final milton12PlusFreq = (milton12PlusCount / n) * 100.0;

      final ml12PlusCount = mlPredictions.where((x) => x >= 11.5).length;
      final ml12PlusFreq = (ml12PlusCount / n) * 100.0;

      expect(ml12PlusFreq, closeTo(milton12PlusFreq, 1.5),
          reason: '12+ ML probability ($ml12PlusFreq%) must align with Milton Work ($milton12PlusFreq%)');
    });
  });
}
