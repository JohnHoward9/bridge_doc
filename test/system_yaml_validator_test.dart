import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/services/system_yaml_validator.dart';

void main() {
  group('SystemYamlValidator Tests', () {
    test('validates clean system YAML with 0 errors', () {
      const validYaml = '''
system: "Standard American 5CM"
definitions:
  strong_nt: "15-17"
openings:
  - call: 1nt
    desc: "15-17 Balanced"
    rule: "15-17hcp s#5332|4432|4333"
    bids:
      - call: 2c
        desc: "Stayman"
        rule: "8+hcp 4+M"
      - call: 2d
        desc: "Jacoby Transfer to Hearts"
        rule: "5+h"
  - call: 1s
    desc: "1S Opening"
    rule: "12-21hcp 5+s"
''';

      final result = SystemYamlValidator.validate(validYaml);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
      expect(result.totalRulesChecked, 4);
    });

    test('detects YAML syntax errors with line number', () {
      const badSyntaxYaml = '''
system: "Bad Syntax System"
openings:
  - call: 1nt
    desc: "Unclosed quote string
    rule: 15-17hcp
''';

      final result = SystemYamlValidator.validate(badSyntaxYaml);
      expect(result.isValid, isFalse);
      expect(result.hasErrors, isTrue);
      expect(result.errors.first.category, 'YAML Syntax');
      expect(result.errors.first.line, isNotNull);
    });

    test('detects invalid bridge calls', () {
      const badCallYaml = '''
system: "Bad Call System"
openings:
  - call: 8nt
    desc: "Impossible level 8"
    rule: "15-17hcp"
  - call: invalid_call
    desc: "Non-bridge call"
''';

      final result = SystemYamlValidator.validate(badCallYaml);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.category == 'Call Syntax' && e.call == '8nt'), isTrue);
      expect(result.errors.any((e) => e.category == 'Call Syntax' && e.call == 'invalid_call'), isTrue);
    });

    test('detects constraint DSL errors (inverted range, typos, invalid shapes)', () {
      const badRuleYaml = '''
system: "Bad Rule System"
openings:
  - call: 1nt
    desc: "Inverted HCP range"
    rule: "17-15hcp"
  - call: 1h
    desc: "Typo hpc"
    rule: "12-14hpc 5+h"
  - call: 1s
    desc: "Bad suit length"
    rule: "15+s"
  - call: 2c
    desc: "Bad shape pattern"
    rule: "s#123"
''';

      final result = SystemYamlValidator.validate(badRuleYaml);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.message.contains('Inverted HCP range')), isTrue);
      expect(result.errors.any((e) => e.message.contains('typo')), isTrue);
      expect(result.errors.any((e) => e.message.contains('exceeds 13 cards')), isTrue);
      expect(result.errors.any((e) => e.message.contains('Invalid shape pattern')), isTrue);
    });

    test('detects unresolved variables and macros', () {
      const unknownVarYaml = '''
system: "Unknown Variable System"
openings:
  - call: 1nt
    desc: "References undefined variable"
    rule: "\$my_unknown_variable 15-17hcp"
''';

      final result = SystemYamlValidator.validate(unknownVarYaml);
      expect(result.warnings.any((w) => w.message.contains(r'$my_unknown_variable')), isTrue);
    });
  });
}
