import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bidding_system.dart';
import '../services/bbs_parser.dart';
import '../services/system_yaml_parser.dart';

class BbsConverterTab extends StatefulWidget {
  final ValueChanged<BridgeSystem> onSystemImported;

  const BbsConverterTab({
    super.key,
    required this.onSystemImported,
  });

  @override
  State<BbsConverterTab> createState() => _BbsConverterTabState();
}

class _BbsConverterTabState extends State<BbsConverterTab> {
  final TextEditingController _bbsInputController = TextEditingController();
  final TextEditingController _yamlOutputController = TextEditingController();
  String? _statusMessage;
  bool _isSuccess = false;

  static const String defaultBbsFilePath =
      r'C:\Users\johnh\Documents\josulasa\bridge_doc\res\system20120910.bbs';

  void _loadDefaultBbsFile() {
    try {
      final file = File(defaultBbsFilePath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        setState(() {
          _bbsInputController.text = content;
          _statusMessage = 'Loaded ${file.path} (${content.length} characters)';
          _isSuccess = true;
        });
      } else {
        setState(() {
          _statusMessage = 'File not found at $defaultBbsFilePath';
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading file: $e';
        _isSuccess = false;
      });
    }
  }

  void _convertBbsToYaml() {
    final bbsText = _bbsInputController.text;
    if (bbsText.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Please enter or load BBS content first.';
        _isSuccess = false;
      });
      return;
    }

    try {
      final system = BbsParser.parse(bbsText);
      final yaml = SystemYamlParser.toYaml(system);
      setState(() {
        _yamlOutputController.text = yaml;
        _statusMessage =
            'Successfully converted BBS to YAML!\n'
            '• System: "${system.name}"\n'
            '• Definitions: ${system.definitions.length}\n'
            '• Opening bids: ${system.openingBids.length}\n'
            '• Opposition opening bids: ${system.oppositionOpeningBids.length}\n'
            '• Fragments: ${system.fragments.length}\n'
            '• Total bidding rules in tree: ${system.totalNodesCount}';
        _isSuccess = true;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error during BBS parsing: $e';
        _isSuccess = false;
      });
    }
  }

  void _applyToActiveSystem() {
    if (_yamlOutputController.text.trim().isEmpty) return;
    try {
      final system = SystemYamlParser.fromYaml(_yamlOutputController.text);
      widget.onSystemImported(system);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Activated system: "${system.name}" with ${system.totalNodesCount} rules!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to activate: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Legacy BBS to YAML Converter',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_open),
                label: const Text('Load system20120910.bbs'),
                onPressed: _loadDefaultBbsFile,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.transform),
                label: const Text('Convert BBS to YAML'),
                onPressed: _convertBbsToYaml,
              ),
              const SizedBox(width: 8),
              if (_yamlOutputController.text.isNotEmpty)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.check),
                  label: const Text('Use in Bidding Explorer'),
                  onPressed: _applyToActiveSystem,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isSuccess ? Colors.green.shade300 : Colors.red.shade300),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _isSuccess ? Colors.green.shade900 : Colors.red.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                // BBS Input
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Input BBS (.bbs file format)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: TextField(
                            controller: _bbsInputController,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                            decoration: const InputDecoration(
                              hintText: 'Paste .bbs content here or click "Load system20120910.bbs"...',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // YAML Output
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Output YAML (.yaml)', style: TextStyle(fontWeight: FontWeight.bold)),
                          if (_yamlOutputController.text.isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy Output'),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _yamlOutputController.text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Copied YAML output!')),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            border: Border.all(color: Colors.grey.shade700),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: TextField(
                            controller: _yamlOutputController,
                            maxLines: null,
                            expands: true,
                            readOnly: true,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              color: Color(0xFFD4D4D4),
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Converted YAML will appear here...',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
