import 'package:flutter/material.dart';
import '../models/bidding_system.dart';
import '../services/system_editor_service.dart';
import 'widgets/system_blueprint_editor_widget.dart';
import 'widgets/bid_detail_editor_widget.dart';

enum SystemEditorViewMode {
  blueprint,
  bidDetail,
}

/// A comprehensive, visual System Editor replacing the raw YAML Editor.
/// Features a 2-Tier architecture:
/// - Tier 1: System Blueprint & Convention Wiring (Macro level)
/// - Tier 2: Bid & Constraint Detail Editor (Micro level, zero YAML)
class SystemEditorTab extends StatefulWidget {
  final BridgeSystem system;
  final ValueChanged<BridgeSystem> onSystemUpdated;
  final List<String>? initialFocusedPath;

  const SystemEditorTab({
    super.key,
    required this.system,
    required this.onSystemUpdated,
    this.initialFocusedPath,
  });

  @override
  State<SystemEditorTab> createState() => _SystemEditorTabState();
}

class _SystemEditorTabState extends State<SystemEditorTab> {
  late SystemEditorViewMode _viewMode;
  late List<String> _currentPath;
  late BridgeSystem _currentSystem;

  @override
  void initState() {
    super.initState();
    _currentSystem = widget.system;

    if (widget.initialFocusedPath != null && widget.initialFocusedPath!.isNotEmpty) {
      _viewMode = SystemEditorViewMode.bidDetail;
      _currentPath = List.from(widget.initialFocusedPath!);
    } else {
      _viewMode = SystemEditorViewMode.blueprint;
      _currentPath = ['1nt'];
    }
  }

  @override
  void didUpdateWidget(covariant SystemEditorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.system != widget.system) {
      _currentSystem = widget.system;
    }
    if (widget.initialFocusedPath != null &&
        widget.initialFocusedPath!.isNotEmpty &&
        widget.initialFocusedPath != oldWidget.initialFocusedPath) {
      setState(() {
        _viewMode = SystemEditorViewMode.bidDetail;
        _currentPath = List.from(widget.initialFocusedPath!);
      });
    }
  }

  void _onSystemSaved(BridgeSystem updatedSystem) {
    setState(() {
      _currentSystem = updatedSystem;
    });
    widget.onSystemUpdated(updatedSystem);
  }

  void _onInspectBids(List<String> path) {
    setState(() {
      _currentPath = path;
      _viewMode = SystemEditorViewMode.bidDetail;
    });
  }

  void _onNavigatePath(List<String> newPath) {
    setState(() {
      _currentPath = newPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                // 2-Tier Mode Switcher
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModeButton(
                        mode: SystemEditorViewMode.blueprint,
                        label: '🏛️ Blueprint Wiring',
                        icon: Icons.architecture,
                        isSelected: _viewMode == SystemEditorViewMode.blueprint,
                      ),
                      _buildModeButton(
                        mode: SystemEditorViewMode.bidDetail,
                        label: '🎯 Bid Editor',
                        icon: Icons.tune,
                        isSelected: _viewMode == SystemEditorViewMode.bidDetail,
                      ),
                    ],
                  ),
                ),

                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    // Quick Tree Selector when in Bid Detail mode
                    if (_viewMode == SystemEditorViewMode.bidDetail) ...[
                      const Text(
                        'Jump: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                      _buildQuickJumpDropdown(),
                    ],

                    // System Name & Status Indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1B5E20).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified, size: 15, color: Color(0xFF1B5E20)),
                          const SizedBox(width: 5),
                          Text(
                            _currentSystem.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _viewMode == SystemEditorViewMode.blueprint
                ? SystemBlueprintEditorWidget(
                    system: _currentSystem,
                    onSystemChanged: _onSystemSaved,
                    onInspectBids: _onInspectBids,
                  )
                : BidDetailEditorWidget(
                    system: _currentSystem,
                    callPath: _currentPath,
                    onSystemSaved: _onSystemSaved,
                    onNavigatePath: _onNavigatePath,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required SystemEditorViewMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF1B5E20) : Colors.grey.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFF1B5E20) : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickJumpDropdown() {
    // Collect root opening bids
    final openings = _currentSystem.openingBids.map((b) => b.call).toList();
    if (!openings.contains('1nt')) openings.insert(0, '1nt');

    final currentRoot = _currentPath.isNotEmpty ? SystemEditorService.normalizeCall(_currentPath.first) : '1nt';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: openings.contains(currentRoot) ? currentRoot : openings.first,
          items: openings.map((call) {
            return DropdownMenuItem<String>(
              value: call,
              child: Text(
                'Opening ${call.toUpperCase()}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            );
          }).toList(),
          onChanged: (newCall) {
            if (newCall != null) {
              setState(() {
                _currentPath = [newCall];
              });
            }
          },
        ),
      ),
    );
  }
}
