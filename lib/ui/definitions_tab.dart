import 'package:flutter/material.dart';
import '../models/bidding_system.dart';
import 'bid_badge.dart';

class DefinitionsTab extends StatefulWidget {
  final BridgeSystem system;
  final String? selectedFragment;

  const DefinitionsTab({
    super.key,
    required this.system,
    this.selectedFragment,
  });

  @override
  State<DefinitionsTab> createState() => _DefinitionsTabState();
}

class _DefinitionsTabState extends State<DefinitionsTab> {
  String? _currentFragmentName;

  @override
  void initState() {
    super.initState();
    _currentFragmentName = widget.selectedFragment ??
        (widget.system.fragments.isNotEmpty ? widget.system.fragments.keys.first : null);
  }

  @override
  void didUpdateWidget(covariant DefinitionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedFragment != null && widget.selectedFragment != _currentFragmentName) {
      setState(() {
        _currentFragmentName = widget.selectedFragment;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definitions = widget.system.definitions;
    final fragments = widget.system.fragments;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.code),
                text: 'Macro Definitions (${definitions.length})',
              ),
              Tab(
                icon: const Icon(Icons.alt_route),
                text: 'Convention Fragments (${fragments.length})',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Macro Definitions View
                _buildDefinitionsList(definitions, theme),

                // Fragments View
                _buildFragmentsView(fragments, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefinitionsList(Map<String, String> defs, ThemeData theme) {
    if (defs.isEmpty) {
      return const Center(child: Text('No macro definitions found.'));
    }

    final keys = defs.keys.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final key = keys[index];
        final val = defs[key]!;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '\$$key',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SelectableText(
                    val,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFragmentsView(Map<String, Fragment> fragments, ThemeData theme) {
    if (fragments.isEmpty) {
      return const Center(child: Text('No convention fragments defined.'));
    }

    final fragNames = fragments.keys.toList();
    final activeFrag = _currentFragmentName != null && fragments.containsKey(_currentFragmentName)
        ? fragments[_currentFragmentName]!
        : fragments.values.first;

    return Row(
      children: [
        // Sidebar list of fragments
        Container(
          width: 250,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: Colors.grey.shade300)),
          ),
          child: ListView.builder(
            itemCount: fragNames.length,
            itemBuilder: (context, index) {
              final name = fragNames[index];
              final isSelected = name == activeFrag.name;
              final frag = fragments[name]!;

              return ListTile(
                selected: isSelected,
                selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                title: Text(
                  name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontFamily: 'monospace',
                  ),
                ),
                subtitle: Text('${frag.bids.length} bids'),
                onTap: () {
                  setState(() {
                    _currentFragmentName = name;
                  });
                },
              );
            },
          ),
        ),

        // Fragment detail / bid tree
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      activeFrag.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 12),
                    Chip(label: Text('${activeFrag.bids.length} entry bids')),
                  ],
                ),
                if (activeFrag.desc != null) ...[
                  const SizedBox(height: 6),
                  Text(activeFrag.desc!, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                ],
                const Divider(height: 24),
                Expanded(
                  child: ListView.builder(
                    itemCount: activeFrag.bids.length,
                    itemBuilder: (context, index) {
                      final bid = activeFrag.bids[index];
                      return _buildFragmentBidTile(bid);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFragmentBidTile(BiddingNode bid) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: bid.bids.isNotEmpty,
        leading: BidBadge(node: bid, fontSize: 13),
        title: Text(
          bid.desc.isNotEmpty ? bid.desc : bid.call,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: bid.rule != null
            ? Text(
                bid.rule!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              )
            : null,
        children: bid.bids.map((child) => _buildFragmentBidTile(child)).toList(),
      ),
    );
  }
}
