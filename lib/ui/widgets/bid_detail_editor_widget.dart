import 'package:flutter/material.dart';
import '../../models/bidding_system.dart';
import '../../models/card.dart';
import '../../services/visual_rule_translator.dart';
import '../../services/system_editor_service.dart';
import '../bid_badge.dart';

/// Tier 2: Bid & Constraint Detail Editor.
/// Provides a zero-YAML visual form for configuring a single bid's parameters,
/// HCP thresholds, suit lengths, shape constraints, stoppers, and continuations.
class BidDetailEditorWidget extends StatefulWidget {
  final BridgeSystem system;
  final List<String> callPath; // e.g. ['1nt', '2d', '2h', '3c']
  final ValueChanged<BridgeSystem> onSystemSaved;
  final ValueChanged<List<String>> onNavigatePath;

  const BidDetailEditorWidget({
    super.key,
    required this.system,
    required this.callPath,
    required this.onSystemSaved,
    required this.onNavigatePath,
  });

  @override
  State<BidDetailEditorWidget> createState() => _BidDetailEditorWidgetState();
}

class _BidDetailEditorWidgetState extends State<BidDetailEditorWidget> {
  late VisualBidFormData _formData;
  late TextEditingController _descController;
  BiddingNode? _originalNode;
  List<BiddingNode> _children = [];

  // Call Picker State
  int? _selectedLevel;
  String? _selectedStrain;
  bool _isSpecialCall = false;

  @override
  void initState() {
    super.initState();
    _loadNode();
  }

  @override
  void didUpdateWidget(covariant BidDetailEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.system != widget.system ||
        oldWidget.callPath.join(':') != widget.callPath.join(':')) {
      _loadNode();
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  void _loadNode() {
    final nodes = SystemEditorService.resolvePath(widget.system, widget.callPath);
    if (nodes.isNotEmpty) {
      _originalNode = nodes.last;
      _formData = VisualBidFormData.fromNode(_originalNode!);
      _children = List.from(SystemEditorService.getContinuationsForPath(widget.system, widget.callPath));
    } else {
      // Default fallback if path is empty
      final fallbackCall = widget.callPath.isNotEmpty ? widget.callPath.last : '1nt';
      _formData = VisualBidFormData(call: fallbackCall);
      _children = [];
    }

    _descController = TextEditingController(text: _formData.desc);
    _parseCallIntoPicker(_formData.call);
  }

  void _parseCallIntoPicker(String call) {
    final clean = call.trim().toLowerCase();
    if (clean == 'pass' || clean == 'p') {
      _isSpecialCall = true;
      _selectedLevel = null;
      _selectedStrain = 'Pass';
      return;
    }
    if (clean == 'dbl' || clean == 'x') {
      _isSpecialCall = true;
      _selectedLevel = null;
      _selectedStrain = 'Dbl';
      return;
    }
    if (clean == 'rdbl' || clean == 'xx') {
      _isSpecialCall = true;
      _selectedLevel = null;
      _selectedStrain = 'Rdbl';
      return;
    }

    _isSpecialCall = false;
    final m = RegExp(r'^([1-7])([cdhs]|nt)$').firstMatch(clean);
    if (m != null) {
      _selectedLevel = int.tryParse(m.group(1)!);
      final strainChar = m.group(2)!;
      switch (strainChar) {
        case 'c':
          _selectedStrain = '♣';
          break;
        case 'd':
          _selectedStrain = '♦';
          break;
        case 'h':
          _selectedStrain = '♥';
          break;
        case 's':
          _selectedStrain = '♠';
          break;
        case 'nt':
          _selectedStrain = 'NT';
          break;
      }
    } else {
      _selectedLevel = 1;
      _selectedStrain = 'NT';
    }
  }

  void _updateCallFromPicker() {
    if (_isSpecialCall) {
      _formData.call = _selectedStrain ?? 'Pass';
    } else if (_selectedLevel != null && _selectedStrain != null) {
      _formData.call = '$_selectedLevel$_selectedStrain';
    }
    setState(() {});
  }

  void _saveBid() {
    _formData.desc = _descController.text.trim();
    final updatedNode = _formData.toNode(existingChildren: _children);

    final updatedSystem = SystemEditorService.updateNodeAtPath(
      widget.system,
      widget.callPath,
      updatedNode,
    );

    widget.onSystemSaved(updatedSystem);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "${_formData.call}" (${_formData.desc}) successfully!'),
        backgroundColor: const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _addNewResponse() {
    final newChild = BiddingNode(
      call: 'pass',
      desc: 'Pass',
      rule: '',
      priority: 2,
    );
    final updatedSystem = SystemEditorService.addChildNodeAtPath(
      widget.system,
      widget.callPath,
      newChild,
    );
    widget.onSystemSaved(updatedSystem);
    setState(() {
      _children.add(newChild);
    });
  }

  void _deleteResponse(int index) {
    final childCall = _children[index].call;
    final childPath = [...widget.callPath, childCall];
    final updatedSystem = SystemEditorService.deleteNodeAtPath(widget.system, childPath);
    widget.onSystemSaved(updatedSystem);
    setState(() {
      _children.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb Navigation Header
          _buildAuctionBreadcrumbs(),
          const SizedBox(height: 16),

          // Main Bid Identity & Call Picker Card
          _buildIdentityCard(theme),
          const SizedBox(height: 20),

          // Hand Criteria: HCP & Forcing
          _buildHcpAndForcingCard(theme),
          const SizedBox(height: 20),

          // Hand Criteria: Suit Lengths
          _buildSuitLengthsCard(theme),
          const SizedBox(height: 20),

          // Hand Criteria: Shape & Stoppers
          _buildShapeAndStoppersCard(theme),
          const SizedBox(height: 20),

          // Continuations / Child Bids Manager
          _buildContinuationsCard(theme),
          const SizedBox(height: 24),

          // Bottom Action Bar: Save & Discard
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  elevation: 2,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text(
                  'Apply & Save Bid 💾',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                onPressed: _saveBid,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset Changes'),
                onPressed: () => setState(() => _loadNode()),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAuctionBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.alt_route, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 8),
          const Text(
            'Auction Sequence: ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (int i = 0; i < widget.callPath.length; i++) ...[
                  if (i > 0)
                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  InkWell(
                    onTap: () {
                      final subPath = widget.callPath.sublist(0, i + 1);
                      widget.onNavigatePath(subPath);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: i == widget.callPath.length - 1
                            ? const Color(0xFF1B5E20).withValues(alpha: 0.15)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: i == widget.callPath.length - 1
                              ? const Color(0xFF1B5E20)
                              : Colors.grey.shade400,
                        ),
                      ),
                      child: Text(
                        widget.callPath[i].toUpperCase(),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: i == widget.callPath.length - 1
                              ? const Color(0xFF1B5E20)
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Live Bid Preview Badge
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: BidBadge(
                    node: BiddingNode(call: _formData.call, desc: _descController.text),
                    fontSize: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Call & Meaning',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select the bid level, suit or special call, and specify its human meaning.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Call Selector
            const Text('Select Call:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),

            // Level Buttons (1 to 7)
            Wrap(
              spacing: 8,
              children: [
                for (int level = 1; level <= 7; level++)
                  ChoiceChip(
                    label: Text('$level', style: const TextStyle(fontWeight: FontWeight.bold)),
                    selected: !_isSpecialCall && _selectedLevel == level,
                    selectedColor: theme.colorScheme.primaryContainer,
                    onSelected: (sel) {
                      if (sel) {
                        _isSpecialCall = false;
                        _selectedLevel = level;
                        _selectedStrain ??= 'NT';
                        _updateCallFromPicker();
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Strain Buttons (♣, ♦, ♥, ♠, NT) + Special (Pass, Dbl, Rdbl)
            Wrap(
              spacing: 8,
              children: [
                for (final strain in ['♣', '♦', '♥', '♠', 'NT'])
                  ChoiceChip(
                    label: Text(
                      strain,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: strain == '♥' || strain == '♦' ? Colors.red.shade700 : Colors.black87,
                      ),
                    ),
                    selected: !_isSpecialCall && _selectedStrain == strain,
                    selectedColor: theme.colorScheme.primaryContainer,
                    onSelected: (sel) {
                      if (sel) {
                        _isSpecialCall = false;
                        _selectedStrain = strain;
                        _selectedLevel ??= 1;
                        _updateCallFromPicker();
                      }
                    },
                  ),
                const SizedBox(width: 8),
                for (final spec in ['Pass', 'Dbl', 'Rdbl'])
                  ChoiceChip(
                    label: Text(spec, style: const TextStyle(fontWeight: FontWeight.bold)),
                    selected: _isSpecialCall && _selectedStrain == spec,
                    selectedColor: Colors.amber.shade200,
                    onSelected: (sel) {
                      if (sel) {
                        _isSpecialCall = true;
                        _selectedStrain = spec;
                        _selectedLevel = null;
                        _updateCallFromPicker();
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Description Input
            TextField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: 'Plain Meaning / Description',
                hintText: 'e.g. Natural second suit Clubs, Game Forcing',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.description_outlined),
              ),
              onChanged: (val) => setState(() => _formData.desc = val),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHcpAndForcingCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Strength & Forcing Requirements',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              'Specify High Card Point (HCP) thresholds and bidding commitment.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
            const SizedBox(height: 16),

            // HCP Range Spinners
            Row(
              children: [
                Expanded(
                  child: _buildNumberInput(
                    label: 'Min HCP',
                    value: _formData.minHcp,
                    onChanged: (val) => setState(() => _formData.minHcp = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildNumberInput(
                    label: 'Max HCP',
                    value: _formData.maxHcp,
                    onChanged: (val) => setState(() => _formData.maxHcp = val),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildNumberInput(
                    label: 'Priority (1=High, 5=Low)',
                    value: _formData.priority,
                    onChanged: (val) {
                      if (val != null) setState(() => _formData.priority = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Forcing Category Chips
            const Text('Forcing Status:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final f in ForcingCategory.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _formData.forcing == f,
                    selectedColor: theme.colorScheme.primaryContainer,
                    onSelected: (sel) {
                      if (sel) setState(() => _formData.forcing = f);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuitLengthsCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suit Length Requirements',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              'Specify minimum or maximum card counts in each suit.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
            const SizedBox(height: 16),

            for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs]) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 50,
                      child: Text(
                        suit.symbol,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: suit.isMajor && suit == Suit.hearts || suit == Suit.diamonds
                              ? Colors.red.shade700
                              : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text('Any Length'),
                            selected: _formData.minSuitLength[suit] == null &&
                                _formData.maxSuitLength[suit] == null,
                            onSelected: (sel) {
                              if (sel) {
                                setState(() {
                                  _formData.minSuitLength[suit] = null;
                                  _formData.maxSuitLength[suit] = null;
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('4+ cards'),
                            selected: _formData.minSuitLength[suit] == 4,
                            selectedColor: theme.colorScheme.primaryContainer,
                            onSelected: (sel) {
                              setState(() {
                                _formData.minSuitLength[suit] = sel ? 4 : null;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('5+ cards'),
                            selected: _formData.minSuitLength[suit] == 5,
                            selectedColor: theme.colorScheme.primaryContainer,
                            onSelected: (sel) {
                              setState(() {
                                _formData.minSuitLength[suit] = sel ? 5 : null;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('6+ cards'),
                            selected: _formData.minSuitLength[suit] == 6,
                            selectedColor: theme.colorScheme.primaryContainer,
                            onSelected: (sel) {
                              setState(() {
                                _formData.minSuitLength[suit] = sel ? 6 : null;
                              });
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Max 2 cards'),
                            selected: _formData.maxSuitLength[suit] == 2,
                            selectedColor: Colors.amber.shade100,
                            onSelected: (sel) {
                              setState(() {
                                _formData.maxSuitLength[suit] = sel ? 2 : null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (suit != Suit.clubs) const Divider(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShapeAndStoppersCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hand Distribution & Short-Suit Honors (Stoppers)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              'Specify hand shapes and whether short suits must hold honors or be unstopped.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
            const SizedBox(height: 16),

            // Shape Choices
            const Text('Distribution Shape:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final s in ShapeCategory.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _formData.shape == s,
                    selectedColor: theme.colorScheme.primaryContainer,
                    onSelected: (sel) {
                      if (sel) setState(() => _formData.shape = s);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Short-Suit Honors
            const Text('Short-Suit Honors / Stoppers:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Any / No Requirement'),
                  selected: _formData.requireShortHonors == null,
                  onSelected: (sel) {
                    if (sel) setState(() => _formData.requireShortHonors = null);
                  },
                ),
                ChoiceChip(
                  label: const Text('Honors in Short Suits Required (Stopped)'),
                  selected: _formData.requireShortHonors == true,
                  selectedColor: Colors.green.shade100,
                  onSelected: (sel) {
                    if (sel) setState(() => _formData.requireShortHonors = true);
                  },
                ),
                ChoiceChip(
                  label: const Text('Short Suits Unstopped Allowed (!short_honors)'),
                  selected: _formData.requireShortHonors == false,
                  selectedColor: Colors.amber.shade100,
                  onSelected: (sel) {
                    if (sel) setState(() => _formData.requireShortHonors = false);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinuationsCard(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Follow-Up Responses (Continuations)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Direct bids available to partner following this call (${_children.length} responses).',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Response Bid', style: TextStyle(fontSize: 12.5)),
                  onPressed: _addNewResponse,
                ),
              ],
            ),
            const Divider(height: 24),

            if (_children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'No direct continuations defined for this bid. Click "+ Add Response Bid" to add one.',
                    style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _children.length,
                separatorBuilder: (ctx, i) => const Divider(height: 8),
                itemBuilder: (ctx, i) {
                  final child = _children[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: BidBadge(node: child, fontSize: 13),
                    title: Text(
                      child.desc.isNotEmpty ? child.desc : '(No description)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    subtitle: child.rule != null && child.rule!.isNotEmpty
                        ? Text(child.rule!, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                          tooltip: 'Edit this response',
                          onPressed: () {
                            final nextPath = [...widget.callPath, child.call];
                            widget.onNavigatePath(nextPath);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          tooltip: 'Delete response',
                          onPressed: () => _deleteResponse(i),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'None',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: (val) {
        final parsed = int.tryParse(val.trim());
        onChanged(parsed);
      },
    );
  }
}
