import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pure ML Zero-Hardcoding Static Guardrail Tests', () {
    test('No manual heuristic point bonuses exist in core models, constraints, and evaluators', () {
      final directories = [
        Directory('lib/models'),
        Directory('lib/constraints'),
        Directory('lib/evaluators'),
      ];

      final prohibitedPatterns = [
        RegExp(r'bonus\s*\+=\s*\d'), // e.g. bonus += 1.5
        RegExp(r'pts\s*\+=\s*3\.5'),  // e.g. pts += 3.5
        RegExp(r'bonus\s*=\s*\d+\.\d+'), // e.g. bonus = 3.5
        RegExp(r'expectationBonus\s*>\s*0'), // old ad-hoc branches
      ];

      final violations = <String>[];

      for (final dir in directories) {
        if (!dir.existsSync()) continue;
        for (final file in dir.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          final lines = file.readAsLinesSync();
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            // Allow comments, explanations, tests, or deprecation notices
            final trimmed = line.trim();
            if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
              continue;
            }
            for (final pattern in prohibitedPatterns) {
              if (pattern.hasMatch(line)) {
                violations.add('${file.path}:${i + 1}: $trimmed');
              }
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Hardcoded heuristics violated the Zero Hardcoded Heuristics Policy:\n${violations.join('\n')}',
      );
    });
  });
}
