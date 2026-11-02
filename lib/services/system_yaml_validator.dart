import 'package:yaml/yaml.dart';
import '../models/bidding_system.dart';
import '../models/card.dart';
import '../services/system_yaml_parser.dart';
import '../constraints/constraint_parser.dart';

/// Severity of a validation diagnostic.
enum DiagnosticSeverity {
  error,
  warning,
  info,
}

/// A diagnostic message pointing to an issue in the YAML system definition.
class SystemDiagnostic {
  final DiagnosticSeverity severity;
  final String message;
  final int? line; // 1-indexed
  final int? column; // 1-indexed
  final String? call;
  final String category; // 'YAML Syntax', 'Call Syntax', 'Constraint DSL', 'Variables & Macros', 'Fragment Reference'

  const SystemDiagnostic({
    required this.severity,
    required this.message,
    this.line,
    this.column,
    this.call,
    required this.category,
  });

  @override
  String toString() {
    final prefix = severity == DiagnosticSeverity.error ? '🔴 [ERROR]' : '🟡 [WARNING]';
    final lineStr = line != null ? ' (Line $line${column != null ? ':$column' : ''})' : '';
    return '$prefix $category$lineStr: $message';
  }
}

/// Result of validating a YAML bridge bidding system.
class SystemValidationResult {
  final bool isValid;
  final List<SystemDiagnostic> diagnostics;
  final BridgeSystem? parsedSystem;
  final int totalRulesChecked;
  final int totalFragmentsChecked;

  const SystemValidationResult({
    required this.isValid,
    required this.diagnostics,
    this.parsedSystem,
    this.totalRulesChecked = 0,
    this.totalFragmentsChecked = 0,
  });

  List<SystemDiagnostic> get errors =>
      diagnostics.where((d) => d.severity == DiagnosticSeverity.error).toList();

  List<SystemDiagnostic> get warnings =>
      diagnostics.where((d) => d.severity == DiagnosticSeverity.warning).toList();

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Comprehensive validator for Bridge Bidding System YAML definitions.
/// Validates YAML syntax, call syntax, hand constraint DSL rules,
/// variable bindings, and fragment references.
class SystemYamlValidator {
  static const Set<String> _builtInMacros = {
    'bal',
    'balanced',
    'unbal',
    'unbalanced',
    'weakbal',
    'strongnt',
    'wknt',
    'rule19',
    'rule20',
  };

  static const Set<String> _contextVariables = {
    'M',
    'OM',
    'm',
    'om',
    'os',
    'suit',
  };

  /// Validates [yamlContent] completely and returns a [SystemValidationResult].
  static SystemValidationResult validate(String yamlContent) {
    final diagnostics = <SystemDiagnostic>[];
    final lines = yamlContent.split('\n');

    if (yamlContent.trim().isEmpty) {
      return const SystemValidationResult(
        isValid: false,
        diagnostics: [
          SystemDiagnostic(
            severity: DiagnosticSeverity.error,
            message: 'YAML document is empty',
            line: 1,
            category: 'YAML Syntax',
          ),
        ],
      );
    }

    // Phase 1: YAML Syntax Check
    dynamic rootYaml;
    try {
      rootYaml = loadYamlNode(yamlContent);
    } on YamlException catch (e) {
      final line = e.span?.start.line != null ? e.span!.start.line + 1 : null;
      final col = e.span?.start.column != null ? e.span!.start.column + 1 : null;
      diagnostics.add(SystemDiagnostic(
        severity: DiagnosticSeverity.error,
        message: e.message,
        line: line,
        column: col,
        category: 'YAML Syntax',
      ));
      return SystemValidationResult(
        isValid: false,
        diagnostics: diagnostics,
      );
    } catch (e) {
      diagnostics.add(SystemDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'Could not parse YAML: $e',
        line: 1,
        category: 'YAML Syntax',
      ));
      return SystemValidationResult(
        isValid: false,
        diagnostics: diagnostics,
      );
    }

    if (rootYaml is! YamlMap) {
      diagnostics.add(const SystemDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'Root of YAML document must be a key-value mapping (e.g. system: "...", definitions: ..., openings: ...)',
        line: 1,
        category: 'YAML Syntax',
      ));
      return SystemValidationResult(isValid: false, diagnostics: diagnostics);
    }

    // Phase 2: System Parsing
    BridgeSystem? system;
    try {
      system = SystemYamlParser.fromYaml(yamlContent);
    } catch (e) {
      diagnostics.add(SystemDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'Failed to construct BridgeSystem: $e',
        line: 1,
        category: 'YAML Syntax',
      ));
      return SystemValidationResult(isValid: false, diagnostics: diagnostics);
    }

    // Collect definitions
    final definitions = Map<String, String>.from(system.definitions);

    // Validate forceTo declarations across the document
    void validateForcingLevels(dynamic node) {
      if (node is YamlMap) {
        final val = node['forceTo'] ?? node['force'] ?? node['forcing'];
        if (val != null) {
          const valid = {'partscore', 'game', 'slam', 'grandslam', 'gf', 'sf', 'gsf', 'grand'};
          final clean = val.toString().trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
          if (!valid.contains(clean)) {
            final line = _findLineForPattern(lines, RegExp(r'force(?:To)?\s*:\s*.*' + RegExp.escape(val.toString())));
            diagnostics.add(SystemDiagnostic(
              severity: DiagnosticSeverity.warning,
              message: 'Invalid forceTo value "$val". Expected partScore, game, slam, or grandSlam.',
              line: line,
              category: 'Forcing Level',
            ));
          }
        }
        for (final entry in node.entries) {
          validateForcingLevels(entry.value);
        }
      } else if (node is YamlList) {
        for (final item in node) {
          validateForcingLevels(item);
        }
      }
    }
    validateForcingLevels(rootYaml);

    // Phase 3 & 4: Deep Inspection of Nodes, Constraints, and Variables
    int rulesCount = 0;
    int fragmentsCount = system.fragments.length;

    // Check Definitions block for validity
    for (final defEntry in definitions.entries) {
      final defKey = defEntry.key;
      final defVal = defEntry.value;
      final defLine = _findLineForPattern(lines, RegExp(defKey + r'\s*:'));

      if (defKey.contains(' ') || defKey.contains('\t')) {
        diagnostics.add(SystemDiagnostic(
          severity: DiagnosticSeverity.warning,
          message: 'Definition key "$defKey" contains whitespace. Macro keys should be single words without spaces.',
          line: defLine,
          category: 'Variables & Macros',
        ));
      }

      // Check if definition value is an HCP range or rule
      _validateConstraintTokens(
        ruleStr: defVal,
        definitions: definitions,
        line: defLine,
        callContext: 'def:$defKey',
        diagnostics: diagnostics,
      );
    }

    // Helper to recursively validate a list of bidding nodes
    void validateNodes(List<BiddingNode> nodes, Map<String, String> activeVariables, List<String> callPath) {
      for (final node in nodes) {
        rulesCount++;
        final currentPath = [...callPath, node.call];
        final nodeLine = _findLineForNode(lines, node.call, currentPath);

        // 1. Validate Call Syntax
        _validateCallSyntax(node.call, nodeLine, diagnostics);

        // 2. Validate Context Variable Bindings on this node
        final updatedVariables = Map<String, String>.from(activeVariables);
        if (node.condition != null) {
          _validateCondition(node.condition!, nodeLine, node.call, diagnostics);
        }
        for (final v in node.variables.entries) {
          updatedVariables[v.key] = v.value;
        }

        // 3. Validate Constraint Rule (if present)
        if (node.rule != null && node.rule!.trim().isNotEmpty) {
          final ruleLine = _findLineForRule(lines, node.rule!, nodeLine);
          _validateConstraintTokens(
            ruleStr: node.rule!,
            definitions: definitions,
            activeVariables: updatedVariables,
            line: ruleLine ?? nodeLine,
            callContext: node.call,
            diagnostics: diagnostics,
          );
        }

        // 4. Validate Fragment Reference
        if (node.ref != null && node.ref!.isNotEmpty) {
          final refName = node.ref!;
          if (!system!.fragments.containsKey(refName)) {
            // Check if it is a standard library convention fragment
            final knownConventions = {
              'fJacobyTransfer', 'fJacobyTransfers', 'fStayman', 'fPuppetStayman1NT',
              'fMultiLandy', 'fDrury', 'fReverseDrury', 'fTwoWayCheckback', 'fXYZ',
              'fSupportDoubles', 'fUnusual2NT', 'fMichaelsCuebid', 'fWalshClub',
              'fInvertedMinors', 'fLebensohl', 'fTransferLebensohl', 'f1430', 'fSmolen',
              'f1NTResponses', 'f2NTResponses', 'fWeakTwoResponses',
            };
            if (!knownConventions.contains(refName)) {
              diagnostics.add(SystemDiagnostic(
                severity: DiagnosticSeverity.warning,
                message: 'Referenced fragment "$refName" is not defined in local fragments or standard libraries.',
                line: nodeLine,
                call: node.call,
                category: 'Fragment Reference',
              ));
            }
          }
        }

        // Recurse children
        validateNodes(node.bids, updatedVariables, currentPath);
      }
    }

    // Validate Opening Bids
    validateNodes(system.openingBids, {}, []);

    // Validate Opposition Opening Bids
    validateNodes(system.oppositionOpeningBids, {}, []);

    // Validate Fragments
    for (final fragEntry in system.fragments.entries) {
      final frag = fragEntry.value;
      final fragLine = _findLineForPattern(lines, RegExp(frag.name + r'\s*:'));

      if (frag.rule != null && frag.rule!.trim().isNotEmpty) {
        _validateConstraintTokens(
          ruleStr: frag.rule!,
          definitions: definitions,
          line: fragLine,
          callContext: 'frag:${frag.name}',
          diagnostics: diagnostics,
        );
      }

      validateNodes(frag.bids, {}, [frag.name]);
    }

    final hasErrors = diagnostics.any((d) => d.severity == DiagnosticSeverity.error);

    return SystemValidationResult(
      isValid: !hasErrors,
      diagnostics: diagnostics,
      parsedSystem: hasErrors ? null : system,
      totalRulesChecked: rulesCount,
      totalFragmentsChecked: fragmentsCount,
    );
  }

  // --- Syntax, Constraint & Variable Checks ---

  static void _validateCallSyntax(String call, int? line, List<SystemDiagnostic> diagnostics) {
    final clean = call
        .trim()
        .toLowerCase()
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('[', '')
        .replaceAll(']', '');

    // Allow special calls
    if (clean == 'pass' || clean == 'p' || clean == 'dbl' || clean == 'x' || clean == 'rdbl' || clean == 'xx') {
      return;
    }

    // Allow relative step calls e.g. "step#1", "step#2"
    if (RegExp(r'^step#\d+$').hasMatch(clean)) {
      return;
    }

    // Allow variable-parameterized calls e.g. "3$suit", "4$M", "5$trump"
    if (RegExp(r'^([1-7])\$[a-z]+$').hasMatch(clean)) {
      return;
    }

    // Allow fragment redirection calls e.g. "~>MultiLandy"
    if (call.startsWith('~>') || call.startsWith('-->')) {
      return;
    }

    // Regular contract call: [1-7][cdhs|nt]
    final callRegex = RegExp(r'^([1-7])(c|d|h|s|nt|♣|♦|♥|♠)$');
    if (!callRegex.hasMatch(clean)) {
      diagnostics.add(SystemDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'Invalid bridge call "$call". Call must be 1-7 (C, D, H, S, NT), Pass, Dbl, or Rdbl (e.g. "1nt", "2h", "pass", "(1s)").',
        line: line,
        call: call,
        category: 'Call Syntax',
      ));
    }
  }

  static void _validateCondition(String condition, int? line, String? call, List<SystemDiagnostic> diagnostics) {
    // Condition e.g. "$M=h", "$suit=s", "$suit!=d", "$suit=d,h", "$M", "!$m", "$fourth_suit=true"
    final clean = condition.trim();
    final m = RegExp(r'^!?\$?([a-zA-Z0-9_]+)(?:(!=|=)([a-zA-Z0-9,\s]+))?$').firstMatch(clean);
    if (m == null) {
      diagnostics.add(SystemDiagnostic(
        severity: DiagnosticSeverity.warning,
        message: 'Malformed condition "$condition". Expected syntax like "\$M=h", "\$suit!=d", or "\$suit=d,h".',
        line: line,
        call: call,
        category: 'Variables & Macros',
      ));
    }
  }

  static void _validateConstraintTokens({
    required String ruleStr,
    required Map<String, String> definitions,
    Map<String, String> activeVariables = const {},
    int? line,
    String? callContext,
    required List<SystemDiagnostic> diagnostics,
  }) {
    // 1. First test full parse through ConstraintParser
    try {
      final parser = ConstraintParser(definitions: definitions);
      parser.parse(ruleStr);
    } catch (e) {
      diagnostics.add(SystemDiagnostic(
        severity: DiagnosticSeverity.error,
        message: 'Constraint syntax error in rule "$ruleStr": $e',
        line: line,
        call: callContext,
        category: 'Constraint DSL',
      ));
      return;
    }

    // 2. Tokenize and validate individual tokens
    // Remove binding annotations: [ ... ]
    final cleanStr = ruleStr.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    if (cleanStr.isEmpty) return;

    // Split on whitespace or commas or pipes
    final tokens = cleanStr.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();

    for (final token in tokens) {
      // Check priority token: p#1, ?1
      if (token.startsWith('p#') || token.startsWith('?')) {
        final pNum = int.tryParse(token.replaceAll(RegExp(r'[^0-9]'), ''));
        if (pNum == null || pNum < 0 || pNum > 99) {
          diagnostics.add(SystemDiagnostic(
            severity: DiagnosticSeverity.error,
            message: 'Invalid priority token "$token". Expected syntax like "p#1" or "?2".',
            line: line,
            call: callContext,
            category: 'Constraint DSL',
          ));
        }
        continue;
      }

      // Check variable/macro token: starts with $
      if (token.startsWith(r'$')) {
        final varName = token.substring(1).replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
        final isBuiltIn = _builtInMacros.contains(varName.toLowerCase());
        final isContext = _contextVariables.contains(varName) || activeVariables.containsKey(varName);
        final isDefined = definitions.containsKey(varName) || definitions.containsKey(token);

        if (!isBuiltIn && !isContext && !isDefined) {
          diagnostics.add(SystemDiagnostic(
            severity: DiagnosticSeverity.warning,
            message: 'Unresolved variable or macro "\$$varName". It is not defined in the "definitions:" section or context.',
            line: line,
            call: callContext,
            category: 'Variables & Macros',
          ));
        }
        continue;
      }

      // Check condition token: e.g. <$M=h> or $M=h
      if (token.contains('=')) {
        continue;
      }

      // Check HCP range: e.g. "15-17hcp", "10+hcp", "10+", "15-17", "12-hcp"
      final rangeMatch = RegExp(r'^(\d+)\s*[-–]\s*(\d+)(?:hcp|points)?$').firstMatch(token);
      if (rangeMatch != null) {
        final min = int.parse(rangeMatch.group(1)!);
        final max = int.parse(rangeMatch.group(2)!);
        if (min > max) {
          diagnostics.add(SystemDiagnostic(
            severity: DiagnosticSeverity.error,
            message: 'Inverted HCP range "$token" (min $min > max $max).',
            line: line,
            call: callContext,
            category: 'Constraint DSL',
          ));
        }
        if (min > 37 || max > 37) {
          diagnostics.add(SystemDiagnostic(
            severity: DiagnosticSeverity.error,
            message: 'HCP value out of bridge bounds in "$token" (maximum 37 HCP in deck).',
            line: line,
            call: callContext,
            category: 'Constraint DSL',
          ));
        }
        continue;
      }

      // Check plus/minus HCP: e.g. 10+hcp, 15-hcp
      final plusMatch = RegExp(r'^(\d+)\s*(\+|-)(?:hcp|points)?$').firstMatch(token);
      if (plusMatch != null) {
        final val = int.parse(plusMatch.group(1)!);
        if (val > 37) {
          diagnostics.add(SystemDiagnostic(
            severity: DiagnosticSeverity.error,
            message: 'HCP threshold "$token" exceeds maximum possible 37 HCP.',
            line: line,
            call: callContext,
            category: 'Constraint DSL',
          ));
        }
        continue;
      }

      // Check suit length: e.g. 5+s, 4+h, 2-c, 5+M, 4+m, 3-s, 4s, 5h
      final suitLenMatch = RegExp(r'^(\d+)\s*(\+|-)?([cdhs]|nt|m|om|M|OM|os)$').firstMatch(token);
      if (suitLenMatch != null) {
        final len = int.parse(suitLenMatch.group(1)!);
        if (len > 13) {
          diagnostics.add(SystemDiagnostic(
            severity: DiagnosticSeverity.error,
            message: 'Suit length "$token" exceeds 13 cards in a bridge hand.',
            line: line,
            call: callContext,
            category: 'Constraint DSL',
          ));
        }
        continue;
      }

      // Check shape patterns: e.g. s#5332, !s#4333, s#5422|5332
      if (token.startsWith('s#') || token.startsWith('!s#')) {
        final shapes = token.replaceAll('!s#', '').replaceAll('s#', '').split('|');
        for (final sh in shapes) {
          if (sh.length != 4 || int.tryParse(sh) == null) {
            diagnostics.add(SystemDiagnostic(
              severity: DiagnosticSeverity.error,
              message: 'Invalid shape pattern "$sh" in "$token". Bridge shapes must be 4 digits summing to 13 (e.g. "s#5332").',
              line: line,
              call: callContext,
              category: 'Constraint DSL',
            ));
          } else {
            final sum = sh.split('').map(int.parse).reduce((a, b) => a + b);
            if (sum != 13) {
              diagnostics.add(SystemDiagnostic(
                severity: DiagnosticSeverity.warning,
                message: 'Shape pattern "$sh" digits sum to $sum instead of 13 cards.',
                line: line,
                call: callContext,
                category: 'Constraint DSL',
              ));
            }
          }
        }
        continue;
      }

      // Check recognized keywords
      final lower = token.toLowerCase();
      if (lower == 'balanced' ||
          lower == '!balanced' ||
          lower == 'unbalanced' ||
          lower == 'semi-balanced' ||
          lower == 'short_honors' ||
          lower == '!short_honors' ||
          lower == 'gf' ||
          lower == 'game_force' ||
          lower == 'inv' ||
          lower == 'invitational' ||
          lower == 'signoff' ||
          lower == 'to_play') {
        continue;
      }

      // Check suit comparisons e.g. c>=*, h>=s, s>h
      if (RegExp(r'^[cdhsM]\s*(>=|<=|>|<|=)\s*([cdhsM]|\*)$').hasMatch(token)) {
        continue;
      }

      // If token ends with "hpc" (common typo for "hcp")
      if (lower.contains('hpc')) {
        diagnostics.add(SystemDiagnostic(
          severity: DiagnosticSeverity.error,
          message: 'Possible typo "$token". Did you mean "hcp" instead of "hpc"?',
          line: line,
          call: callContext,
          category: 'Constraint DSL',
        ));
        continue;
      }

      // If token is an unrecognized alphanumeric sequence
      if (RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(token) && int.tryParse(token) == null) {
        diagnostics.add(SystemDiagnostic(
          severity: DiagnosticSeverity.warning,
          message: 'Unrecognized constraint keyword or parameter "$token".',
          line: line,
          call: callContext,
          category: 'Constraint DSL',
        ));
      }
    }
  }

  // --- Line Locator Helpers ---

  static int? _findLineForPattern(List<String> lines, RegExp pattern) {
    for (int i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) {
        return i + 1;
      }
    }
    return null;
  }

  static int? _findLineForNode(List<String> lines, String call, List<String> path) {
    final cleanCall = call.toLowerCase().replaceAll('(', r'\(').replaceAll(')', r'\)');
    final pattern = RegExp(r'(?:call:\s*|["'']?)' + cleanCall + r'(?:["'']?|\s*:)');

    for (int i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i].toLowerCase())) {
        return i + 1;
      }
    }
    return null;
  }

  static int? _findLineForRule(List<String> lines, String rule, int? startLine) {
    final searchLines = lines;
    final startIndex = (startLine != null && startLine <= lines.length) ? startLine - 1 : 0;

    // Search downwards from the node's line
    for (int i = startIndex; i < lines.length && i < startIndex + 15; i++) {
      if (lines[i].contains('rule:') || lines[i].contains('criteria:')) {
        return i + 1;
      }
    }

    // Fallback: search anywhere in file
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains(rule.trim())) {
        return i + 1;
      }
    }
    return null;
  }
}
