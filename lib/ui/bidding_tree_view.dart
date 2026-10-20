import 'package:flutter/material.dart';
import '../models/bidding_system.dart';
import '../engine/compiled_auction_graph.dart';
import '../engine/bidding_graph_compiler.dart';
import 'bid_badge.dart';

/// An interactive, hierarchical tree-like explorer for bridge bidding systems.
/// Supports in-place expansion via '>' chevrons and switches between
/// Partnership (friendly NS bids only) and Competitive (including opponent interference) perspectives.
class BiddingTreeView extends StatefulWidget {
  final BridgeSystem system;
  final Function(String fragmentName)? onNavigateToFragment;
  final Function(List<BiddingNode> path)? onPracticeFromNode;

  const BiddingTreeView({
    super.key,
    required this.system,
    this.onNavigateToFragment,
    this.onPracticeFromNode,
  });

  @override
  State<BiddingTreeView> createState() => _BiddingTreeViewState();
}

class _BiddingTreeViewState extends State<BiddingTreeView> {
  // Bidding Mode: Partnership (NS bids only) vs Competitive (All calls including opposition)
  bool _isCompetitiveMode = false;

  // Opening category: Opening Bids (our side) vs Opposition Opening Bids
  bool _isOppositionOpening = false;

  // Set of sequence keys that are currently expanded, e.g. "1c", "1c:1h"
  final Set<String> _expandedKeys = {};

  // Selected node and full auction path to that node for the side inspector
  BiddingNode? _selectedNode;
  List<BiddingNode> _selectedPath = [];

  // Live search query
  String _searchQuery = '';

  // Cached compiled bidding graph for fast, accurate continuation resolution
  CompiledBiddingGraph? _compiledGraph;

  @override
  void initState() {
    super.initState();
    _recompileGraph();
  }

  @override
  void didUpdateWidget(BiddingTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.system != widget.system) {
      _recompileGraph();
      _expandedKeys.clear();
      _selectedNode = null;
      _selectedPath = [];
    }
  }

  void _recompileGraph() {
    try {
      final compiler = BiddingGraphCompiler(system: widget.system);
      _compiledGraph = compiler.compile();
    } catch (_) {
      _compiledGraph = null;
    }
  }

  /// Returns the root opening bids resolved with fragment metadata (avoiding 'No description').
  List<BiddingNode> get _rootNodes {
    final rawList = _isOppositionOpening
        ? widget.system.oppositionOpeningBids
        : widget.system.openingBids;

    final resolved = rawList.map((b) => b.withResolvedFragmentMetadata(widget.system.fragments)).toList();

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      return _filterNodesRecursively(resolved, q);
    }

    if (!_isCompetitiveMode) {
      // In Partnership mode: only show our friendly openings (exclude opposition opening bids if any)
      return resolved.where((n) => !n.isOpponent && !n.call.startsWith('(')).toList();
    }

    return resolved;
  }

  /// Searches and filters nodes matching [query], including matching descendants.
  List<BiddingNode> _filterNodesRecursively(List<BiddingNode> nodes, String query) {
    final List<BiddingNode> results = [];
    for (final node in nodes) {
      final matchesSelf = node.call.toLowerCase().contains(query) ||
          node.desc.toLowerCase().contains(query) ||
          (node.rule?.toLowerCase().contains(query) ?? false) ||
          (node.ref?.toLowerCase().contains(query) ?? false);

      final children = _getChildrenForSequence([node]);
      final matchingChildren = _filterNodesRecursively(children, query);

      if (matchesSelf || matchingChildren.isNotEmpty) {
        results.add(node);
        // Automatically expand node if a child matched
        if (matchingChildren.isNotEmpty) {
          final key = _getSequenceKey([node]);
          _expandedKeys.add(key);
        }
      }
    }
    return results;
  }

  /// Normalizes a list of nodes into a colon-separated sequence key for state tracking.
  String _getSequenceKey(List<BiddingNode> path) {
    return path.map((n) => CompiledAuctionState.normalizeCallKey(n.displayCall)).join(':');
  }

  /// Fetches legal continuation children for [path] using the compiled graph,
  /// filtering according to Partnership or Competitive mode.
  List<BiddingNode> _getChildrenForSequence(List<BiddingNode> path) {
    if (path.isEmpty) return [];

    final calls = path.map((n) => n.displayCall).toList();
    List<BiddingNode> candidates = [];

    // 1. Try compiled bidding graph lookup
    final state = _compiledGraph?.getState(calls);
    if (state != null && state.candidateNodes.isNotEmpty) {
      candidates = state.candidateNodes;
    } else {
      // 2. Fallback to direct AST children if not in compiled graph
      final last = path.last;
      final raw = last.getEffectiveChildren(last.variables, fragments: widget.system.fragments);
      candidates = raw.map((c) => c.withResolvedFragmentMetadata(widget.system.fragments)).toList();
    }

    // Filter by perspective mode:
    if (!_isCompetitiveMode) {
      // In Partnership mode: only North-South friendly bids are shown.
      // Opposition bids are skipped throughout the tree as if opponents pass throughout.
      return candidates.where((c) => !c.isOpponent && !c.call.startsWith('(')).toList();
    } else {
      // In Competitive mode: all calls (friendly bids and opponent interference) are shown.
      return candidates;
    }
  }

  /// Returns true if [path] has any continuations to expand.
  bool _hasContinuations(List<BiddingNode> path) {
    return _getChildrenForSequence(path).isNotEmpty;
  }

  void _toggleExpansion(String sequenceKey) {
    setState(() {
      if (_expandedKeys.contains(sequenceKey)) {
        _expandedKeys.remove(sequenceKey);
      } else {
        _expandedKeys.add(sequenceKey);
      }
    });
  }

  void _expandAllRoots() {
    setState(() {
      for (final n in _rootNodes) {
        _expandedKeys.add(_getSequenceKey([n]));
      }
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedKeys.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rootNodes = _rootNodes;

    return Column(
      children: [
        // Top Toolbar: Mode Selector, Scope, Search & Expand/Collapse actions
        _buildTopToolbar(theme),

        // Main Tree View and Detail Inspector Split View
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tree View List
              Expanded(
                flex: 3,
                child: rootNodes.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No bids match "$_searchQuery"'
                              : 'No bids available.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: rootNodes.length,
                        itemBuilder: (context, index) {
                          final node = rootNodes[index];
                          return _buildTreeNode(node, [node], 0);
                        },
                      ),
              ),

              // Detail Inspector Side Panel
              if (_selectedNode != null)
                Container(
                  width: 380,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: Border(left: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: _buildInspectorPanel(context, _selectedNode!, _selectedPath),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Partnership vs Competitive Mode Toggle
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Partnership (NS Only)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  icon: Icon(Icons.people_outline, size: 18),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Competitive (All Calls)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  icon: Icon(Icons.flash_on_outlined, size: 18),
                ),
              ],
              selected: {_isCompetitiveMode},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _isCompetitiveMode = newSelection.first;
                });
              },
            ),

            const SizedBox(width: 14),

            // Category scope toggle (Opening Bids vs Opposition Openings)
            FilterChip(
              label: Text(
                _isOppositionOpening ? 'Opposition Openings' : 'Our Openings',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              selected: _isOppositionOpening,
              avatar: Icon(_isOppositionOpening ? Icons.shield_outlined : Icons.play_circle_outline, size: 16),
              onSelected: (selected) {
                setState(() {
                  _isOppositionOpening = selected;
                  _expandedKeys.clear();
                  _selectedNode = null;
                  _selectedPath = [];
                });
              },
            ),

            const SizedBox(width: 20),

            // Quick Tree Actions: Expand All / Collapse All
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.unfold_more, size: 16),
              label: const Text('Expand All', style: TextStyle(fontSize: 12)),
              onPressed: _expandAllRoots,
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.unfold_less, size: 16),
              label: const Text('Collapse All', style: TextStyle(fontSize: 12)),
              onPressed: _collapseAll,
            ),

            const SizedBox(width: 14),

            // Search Box
            SizedBox(
              width: 220,
              height: 38,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search bids, rules...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds an interactive tree node with in-place '>' expansion chevron.
  Widget _buildTreeNode(BiddingNode node, List<BiddingNode> path, int depth) {
    final theme = Theme.of(context);
    final sequenceKey = _getSequenceKey(path);
    final isExpanded = _expandedKeys.contains(sequenceKey);
    final hasContinuations = _hasContinuations(path);
    final isSelected = _selectedNode == node && _selectedPath.length == path.length;
    final isOpponentCall = node.isOpponent || node.call.startsWith('(');

    // Fetch children if expanded
    final children = isExpanded ? _getChildrenForSequence(path) : <BiddingNode>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Indentation wrapper with tree guidelines
        Padding(
          padding: EdgeInsets.only(left: depth * 22.0, bottom: 6),
          child: Card(
            elevation: isSelected ? 3 : 0.5,
            color: isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : (isOpponentCall ? Colors.amber.shade50.withValues(alpha: 0.5) : Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isSelected
                    ? theme.colorScheme.primary
                    : (isOpponentCall ? Colors.amber.shade400 : Colors.grey.shade300),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  _selectedNode = node;
                  _selectedPath = List.from(path);
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    // Expansion Symbol: '>' chevron button if node has continuations
                    if (hasContinuations)
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _toggleExpansion(sequenceKey),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: AnimatedRotation(
                            turns: isExpanded ? 0.25 : 0.0, // Rotates > downwards when expanded
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: isExpanded ? theme.colorScheme.primary : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      )
                    else
                      // Leaf node placeholder to align badges cleanly
                      const SizedBox(
                        width: 28,
                        child: Center(
                          child: Icon(Icons.circle, size: 5, color: Colors.black26),
                        ),
                      ),

                    const SizedBox(width: 6),

                    // Bid Badge
                    BidBadge(node: node, isSelected: isSelected, fontSize: 14),

                    const SizedBox(width: 12),

                    // Bid Description & Rule
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                node.desc.isNotEmpty ? node.desc : '(No description)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w600,
                                  color: isOpponentCall ? Colors.brown.shade900 : Colors.black87,
                                ),
                              ),
                              if (node.priority != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber.shade600),
                                  ),
                                  child: Text(
                                    '?${node.priority}',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                  ),
                                ),
                              if (node.ref != null && node.ref!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.purple.shade200),
                                  ),
                                  child: Text(
                                    node.ref!,
                                    style: TextStyle(fontSize: 11, color: Colors.purple.shade800),
                                  ),
                                ),
                            ],
                          ),
                          if (node.rule != null && node.rule!.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              node.rule!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: Colors.blueGrey.shade800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Continuations indicator pill
                    if (hasContinuations)
                      InkWell(
                        onTap: () => _toggleExpansion(sequenceKey),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isExpanded ? theme.colorScheme.primaryContainer : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isExpanded ? theme.colorScheme.primary : Colors.grey.shade300),
                          ),
                          child: Text(
                            isExpanded ? 'Hide' : 'Continuations',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isExpanded ? theme.colorScheme.onPrimaryContainer : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Expanded Nested Children
        if (isExpanded)
          Container(
            margin: EdgeInsets.only(left: depth * 22.0 + 14.0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children.map((child) {
                return _buildTreeNode(child, [...path, child], depth + 1);
              }).toList(),
            ),
          ),
      ],
    );
  }

  /// Builds the detail inspector for the currently selected node.
  Widget _buildInspectorPanel(BuildContext context, BiddingNode node, List<BiddingNode> path) {
    final theme = Theme.of(context);
    final hasContinuations = _hasContinuations(path);
    final sequenceStr = path.map((n) => n.displayCall).join(' ➔ ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bid Inspector',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedNode = null;
                  _selectedPath = [];
                }),
              ),
            ],
          ),
          const Divider(),

          // Auction sequence path
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              sequenceStr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
            ),
          ),

          const SizedBox(height: 12),
          Center(child: BidBadge(node: node, fontSize: 22)),
          const SizedBox(height: 10),
          Center(
            child: Text(
              node.desc.isNotEmpty ? node.desc : '(No description)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Raw Call', node.call),
          _buildInfoRow('Type', node.isOpponent ? 'Opposition Intervention' : 'Partnership Agreement'),
          if (node.suit != null) _buildInfoRow('Suit', node.suit!),
          if (node.level != null) _buildInfoRow('Level', '${node.level}'),
          if (node.priority != null) _buildInfoRow('Priority / Alert', '?${node.priority}'),
          if (node.inlineCondition != null) _buildInfoRow('Condition', node.inlineCondition!),
          if (node.ref != null && node.ref!.isNotEmpty) ...[
            _buildInfoRow('Subroutine Fragment', node.ref!),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.alt_route),
                label: Text('Open Fragment "${node.ref}"'),
                onPressed: () {
                  if (widget.onNavigateToFragment != null) {
                    widget.onNavigateToFragment!(node.ref!);
                  }
                },
              ),
            ),
          ],
          if (node.rule != null && node.rule!.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Hand Criteria Rule:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                node.rule!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.lightGreenAccent,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Action Buttons: Toggle Expansion & Practice from this bid
          if (hasContinuations) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: Icon(
                  _expandedKeys.contains(_getSequenceKey(path)) ? Icons.unfold_less : Icons.unfold_more,
                  size: 18,
                ),
                label: Text(_expandedKeys.contains(_getSequenceKey(path))
                    ? 'Collapse Continuations'
                    : 'Expand Continuations in Tree'),
                onPressed: () => _toggleExpansion(_getSequenceKey(path)),
              ),
            ),
            const SizedBox(height: 8),
          ],

          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.psychology),
              label: const Text('Practice Auction from Here 🎯'),
              onPressed: () {
                if (widget.onPracticeFromNode != null) {
                  widget.onPracticeFromNode!(path);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
