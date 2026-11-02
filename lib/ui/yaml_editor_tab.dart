import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import '../models/bidding_system.dart';
import '../services/system_yaml_parser.dart';
import '../services/system_library_resolver.dart';
import '../services/system_yaml_validator.dart';

/// Represents a distinct editable document (either the system blueprint or a convention library).
class EditableDocument {
  final String key;
  final String title;
  final String? subtitle;
  final bool isSystem;

  const EditableDocument({
    required this.key,
    required this.title,
    this.subtitle,
    this.isSystem = false,
  });
}

class YamlEditorTab extends StatefulWidget {
  final BridgeSystem system;
  final ValueChanged<BridgeSystem> onSystemUpdated;
  final String? systemAssetPath;
  final String? initialFocusedCall;
  final String? initialFocusedRef;

  const YamlEditorTab({
    super.key,
    required this.system,
    required this.onSystemUpdated,
    this.systemAssetPath,
    this.initialFocusedCall,
    this.initialFocusedRef,
  });

  @override
  State<YamlEditorTab> createState() => _YamlEditorTabState();
}

class _YamlEditorTabState extends State<YamlEditorTab> {
  late TextEditingController _controller;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _gutterController = ScrollController();

  // Map of file key / path -> raw YAML content
  final Map<String, String> _fileContents = {};

  // Map of fragment name -> file key defining it
  final Map<String, String> _fragmentToFile = {};

  // List of available documents to edit (System + imported conventions)
  final List<EditableDocument> _documents = [];
  String _selectedDocumentKey = 'system';
  String _systemBlueprintKey = 'system';

  SystemValidationResult? _validationResult;
  bool _isLoading = true;
  String? _successMessage;
  bool _showDiagnosticsPanel = false;
  String _diagnosticFilter = 'all'; // 'all', 'errors', 'warnings'

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();

    _scrollController.addListener(() {
      if (_gutterController.hasClients && _gutterController.offset != _scrollController.offset) {
        _gutterController.jumpTo(_scrollController.offset);
      }
    });

    _loadModularDocuments();
  }

  @override
  void didUpdateWidget(covariant YamlEditorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.systemAssetPath != widget.systemAssetPath ||
        oldWidget.system.name != widget.system.name) {
      _loadModularDocuments();
    } else if (widget.initialFocusedRef != null &&
        widget.initialFocusedRef != oldWidget.initialFocusedRef) {
      _focusOnRefAndCall(widget.initialFocusedRef!, widget.initialFocusedCall);
    } else if (widget.initialFocusedCall != null &&
        widget.initialFocusedCall != oldWidget.initialFocusedCall) {
      _jumpToCall(widget.initialFocusedCall!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _gutterController.dispose();
    super.dispose();
  }

  Future<void> _loadModularDocuments() async {
    setState(() => _isLoading = true);

    _documents.clear();
    _fileContents.clear();
    _fragmentToFile.clear();

    String systemYaml = '';
    final sysPath = widget.systemAssetPath;

    // 1. Load System Blueprint file
    if (sysPath != null) {
      systemYaml = await _loadFileContent(sysPath);
      _systemBlueprintKey = sysPath;
    }

    if (systemYaml.isEmpty) {
      systemYaml = SystemYamlParser.systemBlueprintToYaml(widget.system);
      _systemBlueprintKey = 'system';
    }

    _fileContents[_systemBlueprintKey] = systemYaml;
    _documents.add(EditableDocument(
      key: _systemBlueprintKey,
      title: '🏛️ System Blueprint: ${widget.system.name}',
      subtitle: sysPath != null ? sysPath.split('/').last : 'Main System File',
      isSystem: true,
    ));

    // 2. Extract and load all imported convention files
    final List<String> importPaths = [];
    try {
      final doc = loadYaml(systemYaml);
      if (doc is Map && doc.containsKey('imports') && doc['imports'] is List) {
        for (final imp in doc['imports']) {
          importPaths.add(imp.toString());
        }
      }
    } catch (_) {}

    for (final impPath in importPaths) {
      final content = await _loadFileContent(impPath);
      if (content.isNotEmpty) {
        _fileContents[impPath] = content;

        // Parse title and fragments defined in this convention file
        String title = impPath.split('/').last.replaceAll('.yaml', '').replaceAll('_', ' ');
        // Capitalize title
        title = title.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');

        try {
          final libDoc = loadYaml(content);
          if (libDoc is Map) {
            if (libDoc.containsKey('library') || libDoc.containsKey('name')) {
              title = (libDoc['library'] ?? libDoc['name']).toString();
            }
            final frags = libDoc['fragments'] ?? libDoc['conventions'];
            if (frags is Map) {
              for (final k in frags.keys) {
                _fragmentToFile[k.toString()] = impPath;
              }
            }
          }
        } catch (_) {}

        _documents.add(EditableDocument(
          key: impPath,
          title: '📑 $title',
          subtitle: impPath.split('/').last,
        ));
      }
    }

    // 3. Fallback: if there are standalone fragments in system not covered by files
    for (final fragEntry in widget.system.fragments.entries) {
      if (!_fragmentToFile.containsKey(fragEntry.key)) {
        final fragKey = 'frag:${fragEntry.key}';
        _fileContents[fragKey] = SystemYamlParser.fragmentToYaml(fragEntry.value);
        _fragmentToFile[fragEntry.key] = fragKey;
        _documents.add(EditableDocument(
          key: fragKey,
          title: '🧩 Fragment: ${fragEntry.key}',
          subtitle: fragEntry.value.desc ?? 'Inline Fragment',
        ));
      }
    }

    // Determine initial document selection
    String targetKey = _systemBlueprintKey;
    if (widget.initialFocusedRef != null && _fragmentToFile.containsKey(widget.initialFocusedRef)) {
      targetKey = _fragmentToFile[widget.initialFocusedRef!]!;
    }

    _selectedDocumentKey = targetKey;
    _controller.text = _fileContents[_selectedDocumentKey] ?? systemYaml;

    setState(() => _isLoading = false);

    // Initial validation and jump
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runValidation(autoShowPanel: false);
      if (widget.initialFocusedCall != null) {
        _jumpToCall(widget.initialFocusedCall!);
      }
    });
  }

  Future<String> _loadFileContent(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (_) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          return await f.readAsString();
        }
      } catch (_) {}
    }
    return '';
  }

  void _switchDocument(String newKey) {
    if (newKey == _selectedDocumentKey) return;

    // Cache current unsaved edits in memory
    _fileContents[_selectedDocumentKey] = _controller.text;

    setState(() {
      _selectedDocumentKey = newKey;
      _controller.text = _fileContents[newKey] ?? '';
      _successMessage = null;
    });

    _runValidation(autoShowPanel: false);
  }

  void _focusOnRefAndCall(String ref, String? call) {
    final targetDoc = _fragmentToFile[ref];
    if (targetDoc != null) {
      _switchDocument(targetDoc);
    }
    if (call != null) {
      _jumpToCall(call);
    }
  }

  void _runValidation({bool autoShowPanel = true}) {
    final res = SystemYamlValidator.validate(_controller.text);

    setState(() {
      _validationResult = res;
      if (autoShowPanel) {
        _showDiagnosticsPanel = true;
      }
    });
  }

  Future<void> _applyYaml() async {
    setState(() {
      _successMessage = null;
    });

    // 1. Validate the current document
    _runValidation(autoShowPanel: true);
    final res = _validationResult;

    if (res == null || !res.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot apply: ${res?.errors.length ?? 1} syntax or constraint errors found in this document.',
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _showDiagnosticsPanel = true);
      return;
    }

    // 2. Cache updated text
    _fileContents[_selectedDocumentKey] = _controller.text;

    // 3. Persist to disk if running locally on desktop
    try {
      final f = File(_selectedDocumentKey);
      if (f.existsSync()) {
        f.writeAsStringSync(_controller.text);
      }
    } catch (_) {}

    // 4. Recompile the full system using the updated modular file
    try {
      final baseSystemYaml = _fileContents[_systemBlueprintKey] ?? _fileContents['system']!;
      final updatedSystem = await SystemLibraryResolver.loadSystemWithLibraries(
        baseSystemYaml,
        fileLoader: (path) async {
          return _fileContents[path] ?? await _loadFileContent(path);
        },
      );

      widget.onSystemUpdated(updatedSystem);

      final docTitle = _documents.firstWhere((d) => d.key == _selectedDocumentKey).title;
      setState(() {
        _successMessage = '$docTitle updated and applied successfully! (${updatedSystem.totalNodesCount} rules active)';
        _showDiagnosticsPanel = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_successMessage!),
          backgroundColor: const Color(0xFF1B5E20),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        _showDiagnosticsPanel = true;
        _validationResult = SystemValidationResult(
          isValid: false,
          diagnostics: [
            SystemDiagnostic(
              severity: DiagnosticSeverity.error,
              message: 'Failed to recompile system with this document: $e',
              category: 'YAML Syntax',
            ),
          ],
        );
      });
    }
  }

  void _jumpToLine(int line) {
    final text = _controller.text;
    final lines = text.split('\n');
    if (line < 1 || line > lines.length) return;

    int charOffset = 0;
    for (int i = 0; i < line - 1; i++) {
      charOffset += lines[i].length + 1; // +1 for \n
    }
    final lineLength = lines[line - 1].length;

    _controller.selection = TextSelection(
      baseOffset: charOffset,
      extentOffset: charOffset + lineLength,
    );

    if (_scrollController.hasClients) {
      final targetOffset = (line - 1) * 18.2;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToCall(String call) {
    final text = _controller.text;
    final clean = call.trim().toLowerCase();
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase();
      if (l.contains('call: $clean') ||
          l.contains('call: "$clean"') ||
          l.contains('call: \'$clean\'') ||
          l.contains(' $clean:') ||
          l.startsWith('$clean:')) {
        _jumpToLine(i + 1);
        return;
      }
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _controller.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Document YAML copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final valRes = _validationResult;
    final hasErrors = valRes?.hasErrors ?? false;
    final hasWarnings = valRes?.hasWarnings ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Control & Document Selector Bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              // Modular Document Dropdown Selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_open, size: 18, color: Color(0xFF1B5E20)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _documents.any((d) => d.key == _selectedDocumentKey)
                                ? _selectedDocumentKey
                                : _documents.first.key,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            items: _documents.map((doc) {
                              return DropdownMenuItem<String>(
                                value: doc.key,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(child: Text(doc.title, overflow: TextOverflow.ellipsis)),
                                    if (doc.subtitle != null) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '(${doc.subtitle})',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (newKey) {
                              if (newKey != null) _switchDocument(newKey);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons & Validation Pill
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Validation Status Pill
                  if (valRes != null)
                    InkWell(
                      onTap: () => setState(() => _showDiagnosticsPanel = !_showDiagnosticsPanel),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: hasErrors
                              ? Colors.red.shade100
                              : (hasWarnings ? Colors.amber.shade100 : Colors.green.shade100),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasErrors
                                ? Colors.red.shade400
                                : (hasWarnings ? Colors.amber.shade600 : Colors.green.shade400),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasErrors
                                  ? Icons.error
                                  : (hasWarnings ? Icons.warning_amber : Icons.check_circle),
                              size: 14,
                              color: hasErrors
                                  ? Colors.red.shade900
                                  : (hasWarnings ? Colors.amber.shade900 : Colors.green.shade900),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              hasErrors
                                  ? '${valRes.errors.length} Error${valRes.errors.length > 1 ? 's' : ''}'
                                  : (hasWarnings
                                      ? '${valRes.warnings.length} Warning${valRes.warnings.length > 1 ? 's' : ''}'
                                      : 'Valid (${valRes.totalRulesChecked} rules)'),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: hasErrors
                                    ? Colors.red.shade900
                                    : (hasWarnings ? Colors.amber.shade900 : Colors.green.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  OutlinedButton.icon(
                    icon: const Icon(Icons.rule_folder_outlined, size: 16),
                    label: const Text('Validate 🔍'),
                    onPressed: () => _runValidation(autoShowPanel: true),
                  ),

                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                    onPressed: _copyToClipboard,
                  ),

                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: hasErrors ? Colors.grey : const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text(
                      'Validate & Apply 🚀',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _applyYaml,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Success Message Banner (if any)
          if (_successMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.green),
                    onPressed: () => setState(() => _successMessage = null),
                  ),
                ],
              ),
            ),

          // Main Editor View with Line Numbers Gutter
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasErrors ? Colors.red.shade400 : Colors.grey.shade700,
                  width: hasErrors ? 1.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Line Numbers Gutter
                    _buildLineNumbersGutter(),

                    // Divider between gutter and code
                    Container(width: 1, color: const Color(0xFF333333)),

                    // Monospace Code Editor
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: TextField(
                          controller: _controller,
                          scrollController: _scrollController,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: Color(0xFFD4D4D4),
                            height: 1.4,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) {
                            if (_validationResult != null) {
                              _runValidation(autoShowPanel: false);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Collapsible Diagnostics & Syntax Check Panel
          if (_showDiagnosticsPanel && valRes != null) ...[
            const SizedBox(height: 10),
            _buildDiagnosticsPanel(valRes),
          ],
        ],
      ),
    );
  }

  Widget _buildLineNumbersGutter() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (ctx, _) {
        final lineCount = '\n'.allMatches(_controller.text).length + 1;
        final errorLines = _validationResult?.errors.map((e) => e.line).toSet() ?? {};
        final warningLines = _validationResult?.warnings.map((w) => w.line).toSet() ?? {};

        return Container(
          width: 52,
          color: const Color(0xFF252526),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: ListView.builder(
            controller: _gutterController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lineCount,
            itemBuilder: (ctx, i) {
              final lineNum = i + 1;
              final isError = errorLines.contains(lineNum);
              final isWarning = warningLines.contains(lineNum);

              return Container(
                height: 18.2, // matches fontSize 13 * height 1.4
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 8),
                color: isError
                    ? Colors.red.withValues(alpha: 0.3)
                    : (isWarning ? Colors.amber.withValues(alpha: 0.2) : Colors.transparent),
                child: Text(
                  '$lineNum',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: isError
                        ? Colors.redAccent
                        : (isWarning ? Colors.amberAccent : const Color(0xFF858585)),
                    fontWeight: isError || isWarning ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDiagnosticsPanel(SystemValidationResult result) {
    final filtered = _diagnosticFilter == 'errors'
        ? result.errors
        : (_diagnosticFilter == 'warnings' ? result.warnings : result.diagnostics);

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3E3E42)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Diagnostics Header with Filter Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D30),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                const Text(
                  'Document Diagnostics & Rule Checker',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.white),
                ),
                const SizedBox(width: 12),

                // Filter Chips
                _buildFilterChip('All (${result.diagnostics.length})', 'all'),
                const SizedBox(width: 6),
                _buildFilterChip('Errors (${result.errors.length})', 'errors', isError: true),
                const SizedBox(width: 6),
                _buildFilterChip('Warnings (${result.warnings.length})', 'warnings', isWarning: true),

                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showDiagnosticsPanel = false),
                ),
              ],
            ),
          ),

          // Diagnostics List
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'No ${_diagnosticFilter == 'all' ? '' : _diagnosticFilter} issues found! This document is valid.',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filtered.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1, color: Color(0xFF333333)),
                itemBuilder: (ctx, i) {
                  final diag = filtered[i];
                  final isErr = diag.severity == DiagnosticSeverity.error;

                  return InkWell(
                    onTap: () {
                      if (diag.line != null) {
                        _jumpToLine(diag.line!);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            isErr ? Icons.error : Icons.warning_amber,
                            size: 15,
                            color: isErr ? Colors.redAccent : Colors.amberAccent,
                          ),
                          const SizedBox(width: 8),

                          // Category pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              diag.category,
                              style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Line jump pill
                          if (diag.line != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isErr ? Colors.red.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Line ${diag.line}',
                                style: TextStyle(
                                  color: isErr ? Colors.redAccent : Colors.amberAccent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),

                          // Message text
                          Expanded(
                            child: Text(
                              diag.message,
                              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.white38),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, {bool isError = false, bool isWarning = false}) {
    final isSelected = _diagnosticFilter == key;

    return InkWell(
      onTap: () => setState(() => _diagnosticFilter = key),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? (isError ? Colors.redAccent : (isWarning ? Colors.amberAccent : Colors.white60))
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isError
                ? Colors.redAccent
                : (isWarning ? Colors.amberAccent : Colors.white70),
          ),
        ),
      ),
    );
  }
}
