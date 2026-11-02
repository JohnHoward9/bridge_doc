import 'package:flutter/material.dart';
import '../../models/bidding_system.dart';
import '../../services/system_editor_service.dart';

/// Tier 1: System Blueprint & Convention Wiring Editor.
/// Allows users to visually configure their system's architecture (openings, 1NT responses,
/// defense modules, and partnership gadgets) without touching any code or YAML.
class SystemBlueprintEditorWidget extends StatefulWidget {
  final BridgeSystem system;
  final ValueChanged<BridgeSystem> onSystemChanged;
  final ValueChanged<List<String>> onInspectBids;

  const SystemBlueprintEditorWidget({
    super.key,
    required this.system,
    required this.onSystemChanged,
    required this.onInspectBids,
  });

  @override
  State<SystemBlueprintEditorWidget> createState() => _SystemBlueprintEditorWidgetState();
}

class _SystemBlueprintEditorWidgetState extends State<SystemBlueprintEditorWidget> {
  late int _ntMin;
  late int _ntMax;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void didUpdateWidget(covariant SystemBlueprintEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.system != widget.system) {
      _loadState();
    }
  }

  void _loadState() {
    final range = SystemEditorService.get1NTRange(widget.system);
    _ntMin = range.$1;
    _ntMax = range.$2;
  }

  void _applyNtRange(int min, int max) {
    setState(() {
      _ntMin = min;
      _ntMax = max;
    });
    final updated = SystemEditorService.set1NTRange(widget.system, min, max);
    widget.onSystemChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.shade700),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.architecture, color: Colors.amberAccent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Blueprint & Convention Wiring',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Configure your partnership conventions and opening framework at the macro level.',
                        style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 1: Opening Framework
          _buildSectionHeader('🏛️ Opening Framework', 'Base suit lengths and point thresholds'),
          const SizedBox(height: 12),
          _buildOpeningFrameworkCard(),
          const SizedBox(height: 24),

          // Section 2: 1NT & 2NT Response Suite
          _buildSectionHeader('🎯 1NT Response Suite', 'Conventions wired directly into opening 1NT'),
          const SizedBox(height: 12),
          _build1NTResponsesCard(),
          const SizedBox(height: 24),

          // Section 3: Competitive & Defensive Modules
          _buildSectionHeader('🛡️ Competitive & Defense', 'Actions over opponent openings and overcalls'),
          const SizedBox(height: 12),
          _buildCompetitiveCard(),
          const SizedBox(height: 24),

          // Section 4: Partnership Gadgets
          _buildSectionHeader('🤝 Partnership Gadgets', 'Specialized agreements and passed-hand bids'),
          const SizedBox(height: 12),
          _buildPartnershipGadgetsCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildOpeningFrameworkCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 1NT Range Control
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '1NT Opening Range',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Current standard: $_ntMin - $_ntMax High Card Points (HCP)',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('Inspect 1NT', style: TextStyle(fontSize: 12)),
                      onPressed: () => widget.onInspectBids(['1nt']),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('15-17 Strong NT'),
                      selected: _ntMin == 15 && _ntMax == 17,
                      selectedColor: const Color(0xFF1B5E20).withValues(alpha: 0.2),
                      onSelected: (sel) {
                        if (sel) _applyNtRange(15, 17);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('14.5-17 (Wolpert)'),
                      selected: _ntMin == 14 && _ntMax == 17,
                      selectedColor: const Color(0xFF1B5E20).withValues(alpha: 0.2),
                      onSelected: (sel) {
                        if (sel) _applyNtRange(14, 17);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('12-14 Weak NT'),
                      selected: _ntMin == 12 && _ntMax == 14,
                      selectedColor: const Color(0xFF1B5E20).withValues(alpha: 0.2),
                      onSelected: (sel) {
                        if (sel) _applyNtRange(12, 14);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 28),

            // Major Opening Length
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Major Openings (1♥ / 1♠)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '5-card majors standard with 2/1 Game Force',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Text(
                        '5-Card Majors',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('Inspect 1♥/1♠', style: TextStyle(fontSize: 12)),
                      onPressed: () => widget.onInspectBids(['1h']),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 28),

            // 2-Level Openings
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '2-Level Openings',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Strong 2♣ artificial (22+ HCP); Weak Twos in 2♦, 2♥, 2♠',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Text(
                        'Weak Twos + Strong 2♣',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('Inspect 2♣', style: TextStyle(fontSize: 12)),
                      onPressed: () => widget.onInspectBids(['2c']),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _build1NTResponsesCard() {
    final hasJacoby = SystemEditorService.isConventionActive(widget.system, 'jacoby_transfers');
    final hasStayman = SystemEditorService.isConventionActive(widget.system, 'stayman');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildConventionRow(
              title: 'Jacoby Transfers (2♦ → ♥, 2♥ → ♠)',
              desc: 'Responder transfers declarership to opener with 5+ major cards, followed by invitational, GF, or two-suited continuations (3♣/3♦).',
              isActive: hasJacoby,
              inspectPath: ['1nt', '2d'],
            ),
            const Divider(height: 24),
            _buildConventionRow(
              title: 'Stayman Convention (2♣)',
              desc: 'Asks opener for a 4-card major (2♦ = no major, 2♥ = 4+ hearts, 2♠ = 4+ spades).',
              isActive: hasStayman,
              inspectPath: ['1nt', '2c'],
            ),
            const Divider(height: 24),
            _buildConventionRow(
              title: 'Puppet Stayman (3♣)',
              desc: 'Asks opener for a 5-card major (3♦ = one or two 4-card majors, 3♥/3♠ = 5-card major, 3NT = no 4/5-card major).',
              isActive: widget.system.fragments.containsKey('fPuppetStayman1NT'),
              inspectPath: ['1nt', '3c'],
            ),
            const Divider(height: 24),
            _buildConventionRow(
              title: 'Texas Transfers (4♦ → ♥, 4♥ → ♠)',
              desc: 'Direct signoff transfers into 4-level major game with 6+ cards.',
              isActive: widget.system.openingBids.any((n) =>
                  SystemEditorService.normalizeCall(n.call) == '1nt' &&
                  n.bids.any((c) => SystemEditorService.normalizeCall(c.call) == '4d')),
              inspectPath: ['1nt', '4d'],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompetitiveCard() {
    final hasMultiLandy = SystemEditorService.isConventionActive(widget.system, 'multi_landy');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildConventionRow(
              title: 'Defense vs Opponent 1NT: Multi-Landy',
              desc: '2♣ = Both majors (5-4+), 2♦ = Single 6+ major, 2♥ = 5+♥ & 4+ minor, 2♠ = 5+♠ & 4+ minor.',
              isActive: hasMultiLandy,
              badgeText: 'Multi-Landy Active',
              inspectPath: ['(1nt)', '2c'],
            ),
            const Divider(height: 24),
            _buildConventionRow(
              title: 'Two-Suited Overcalls: Unusual 2NT & Michaels',
              desc: '2NT over opponent 1-level opening shows lowest two unbid suits (5-5+). Michaels cuebid shows other major and a minor.',
              isActive: widget.system.fragments.containsKey('fUnusual2NT') ||
                  widget.system.fragments.containsKey('fMichaelsCuebid') ||
                  widget.system.oppositionOpeningBids.any((n) => n.bids.any((c) => c.desc.toLowerCase().contains('unusual'))),
              inspectPath: ['(1h)', '2nt'],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnershipGadgetsCard() {
    final hasDrury = SystemEditorService.isConventionActive(widget.system, 'drury');
    final hasSupportDbl = SystemEditorService.isConventionActive(widget.system, 'support_doubles');
    final hasTwoWayCB = SystemEditorService.isConventionActive(widget.system, 'two_way_checkback');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildConventionRow(
              title: 'Reverse Drury (Passed Hand 2♣ over 1♥ / 1♠)',
              desc: 'Passed hand bids artificial 2♣ with limit raise strength (10-11 HCP) and 3+ trumps to verify partner has a genuine full opening.',
              isActive: hasDrury,
              inspectPath: ['1s', '2c'],
            ),
            const Divider(height: 24),
            _buildConventionRow(
              title: 'Support Doubles',
              desc: 'Opener doubles after opponent interference to show exactly 3-card support for responder\'s major suit.',
              isActive: hasSupportDbl,
              inspectPath: ['1c', '(pass)', '1h', '(1s)', 'dbl'],
            ),
            const Divider(height: 24),
            _buildConventionRow(
              title: 'Two-Way Checkback / XYZ',
              desc: '2♣ is invitational relay to 2♦; 2♦ is game forcing checkback asking opener to clarify shape.',
              isActive: hasTwoWayCB,
              inspectPath: ['1c', '1h', '1nt', '2c'],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConventionRow({
    required String title,
    required String desc,
    required bool isActive,
    String? badgeText,
    required List<String> inspectPath,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isActive ? Colors.green.shade400 : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      badgeText ?? (isActive ? 'Active' : 'Not Wired'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.green.shade800 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B5E20).withValues(alpha: 0.1),
            foregroundColor: const Color(0xFF1B5E20),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: const Color(0xFF1B5E20).withValues(alpha: 0.3)),
            ),
          ),
          icon: const Icon(Icons.edit_note, size: 16),
          label: const Text(
            'Inspect / Edit Bids',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          onPressed: () => widget.onInspectBids(inspectPath),
        ),
      ],
    );
  }
}
