import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bidding_system.dart';
import '../services/system_yaml_parser.dart';
import '../services/system_library_resolver.dart';

class YamlEditorTab extends StatefulWidget {
  final BridgeSystem system;
  final ValueChanged<BridgeSystem> onSystemUpdated;

  const YamlEditorTab({
    super.key,
    required this.system,
    required this.onSystemUpdated,
  });

  @override
  State<YamlEditorTab> createState() => _YamlEditorTabState();
}

class _YamlEditorTabState extends State<YamlEditorTab> {
  late TextEditingController _controller;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: SystemYamlParser.toYaml(widget.system));
  }

  @override
  void didUpdateWidget(covariant YamlEditorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.system != widget.system) {
      _controller.text = SystemYamlParser.toYaml(widget.system);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _applyYaml() async {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final updated = await SystemLibraryResolver.loadSystemWithLibraries(_controller.text);
      widget.onSystemUpdated(updated);
      setState(() {
        _successMessage = 'System applied successfully! (${updated.totalNodesCount} bidding rules loaded)';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Parsing Error: $e';
      });
    }
  }

  Future<void> _loadTemplate(String assetPath) async {
    try {
      String content = '';
      try {
        content = await rootBundle.loadString(assetPath);
      } catch (_) {
        final f = File(assetPath);
        if (f.existsSync()) {
          content = f.readAsStringSync();
        }
      }
      if (content.isNotEmpty) {
        setState(() {
          _controller.text = content;
          _successMessage = 'Template loaded! Review or customize your rules, then click "Validate & Apply".';
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load template: $e';
      });
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _controller.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('YAML copied to clipboard!')),
    );
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
                'YAML System Definition',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy YAML'),
                onPressed: _copyToClipboard,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Validate & Apply'),
                onPressed: _applyYaml,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Starter Templates: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                ActionChip(
                  avatar: const Icon(Icons.favorite, size: 15, color: Colors.red),
                  label: const Text('5-Card Majors & 2/1 GF', style: TextStyle(fontSize: 12)),
                  onPressed: () => _loadTemplate('assets/core/systems/us_standard_2over1.yaml'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.filter_3, size: 15, color: Colors.green),
                  label: const Text('3-Way Club (5CM)', style: TextStyle(fontSize: 12)),
                  onPressed: () => _loadTemplate('assets/core/systems/three_way_club_5cm.yaml'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.shield, size: 15, color: Colors.blue),
                  label: const Text('UK Acol (4CM)', style: TextStyle(fontSize: 12)),
                  onPressed: () => _loadTemplate('assets/core/systems/uk_acol_4cm.yaml'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          if (_successMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_successMessage!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade700),
              ),
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
