import 'package:flutter/material.dart';
import '../models/bidding_system.dart';
import 'bid_badge.dart';

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
  bool _isOppositionOpening = false;
  final List<BiddingNode> _breadcrumbPath = [];
  BiddingNode? _selectedNode;
  String _searchQuery = '';

  List<BiddingNode> get _currentNodes {
    if (_searchQuery.trim().isNotEmpty) {
      return _filterNodesByQuery(_searchQuery.trim().toLowerCase());
    }
    if (_breadcrumbPath.isEmpty) {
      return _isOppositionOpening
          ? widget.system.oppositionOpeningBids
          : widget.system.openingBids;
    }
    return _getChildrenOf(_breadcrumbPath.last);
  }

  List<BiddingNode> _getChildrenOf(BiddingNode node) {
    if (node.bids.isNotEmpty) return node.bids;
    if (node.ref != null && widget.system.fragments.containsKey(node.ref)) {
      return widget.system.fragments[node.ref]!.bids;
    }
    return [];
  }

  List<BiddingNode> _filterNodesByQuery(String query) {
    final List<BiddingNode> results = [];
    void searchIn(List<BiddingNode> nodes) {
      for (final n in nodes) {
        if (n.call.toLowerCase().contains(query) ||
            n.desc.toLowerCase().contains(query) ||
            (n.rule?.toLowerCase().contains(query) ?? false) ||
            (n.ref?.toLowerCase().contains(query) ?? false)) {
          results.add(n);
        }
        searchIn(_getChildrenOf(n));
      }
    }

    final rootList = _isOppositionOpening
        ? widget.system.oppositionOpeningBids
        : widget.system.openingBids;
    searchIn(rootList);
    return results;
  }

  void _drillInto(BiddingNode node) {
    final children = _getChildrenOf(node);
    if (children.isNotEmpty) {
      setState(() {
        _breadcrumbPath.add(node);
        _selectedNode = null;
        _searchQuery = '';
      });
    } else if (node.ref != null && widget.onNavigateToFragment != null) {
      widget.onNavigateToFragment!(node.ref!);
    }
  }

  void _popToBreadcrumbIndex(int index) {
    setState(() {
      if (index < 0) {
        _breadcrumbPath.clear();
      } else {
        while (_breadcrumbPath.length > index + 1) {
          _breadcrumbPath.removeLast();
        }
      }
      _selectedNode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = _currentNodes;

    return Column(
      children: [
        // Mode Selector and Search Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Opening Bids (Our Side)'),
                        icon: Icon(Icons.play_circle_outline),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Opposition Opening Bids'),
                        icon: Icon(Icons.shield_outlined),
                      ),
                    ],
                    selected: {_isOppositionOpening},
                    onSelectionChanged: (Set<bool> newSelection) {
                      setState(() {
                        _isOppositionOpening = newSelection.first;
                        _breadcrumbPath.clear();
                        _selectedNode = null;
                      });
                    },
                  ),
                  const Spacer(),
                  // Search box
                  SizedBox(
                    width: 280,
                    height: 40,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search bids, rules, Drury...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Breadcrumb trail
              _buildBreadcrumbBar(theme),
            ],
          ),
        ),

        // Main List and Inspector Split View
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bids List
              Expanded(
                flex: 3,
                child: nodes.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No bids match "$_searchQuery"'
                              : 'No child bids found at this sequence.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: nodes.length,
                        itemBuilder: (context, index) {
                          final node = nodes[index];
                          final isSelected = _selectedNode == node;
                          return _buildBidCard(context, node, isSelected);
                        },
                      ),
              ),

              // Detail Inspector Panel
              if (_selectedNode != null)
                Container(
                  width: 360,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: Border(left: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: _buildInspectorPanel(context, _selectedNode!),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () => _popToBreadcrumbIndex(-1),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.home_outlined, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      _isOppositionOpening ? 'Opposition Openings' : 'Opening Bids',
                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            for (int i = 0; i < _breadcrumbPath.length; i++) ...[
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              InkWell(
                onTap: () => _popToBreadcrumbIndex(i),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      BidBadge(node: _breadcrumbPath[i], fontSize: 12),
                      const SizedBox(width: 4),
                      Text(
                        _breadcrumbPath[i].desc.isNotEmpty
                            ? _breadcrumbPath[i].desc
                            : _breadcrumbPath[i].displayCall,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: i == _breadcrumbPath.length - 1 ? FontWeight.bold : FontWeight.normal,
                          color: i == _breadcrumbPath.length - 1 ? Colors.black87 : Colors.blueGrey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBidCard(BuildContext context, BiddingNode node, bool isSelected) {
    final theme = Theme.of(context);
    final hasChildren = node.bids.isNotEmpty;
    final hasRef = node.ref != null && node.ref!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isSelected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? theme.colorScheme.primary : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedNode = node;
          });
        },
        onDoubleTap: () => _drillInto(node),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BidBadge(node: node, isSelected: isSelected, fontSize: 15),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            node.desc.isNotEmpty ? node.desc : '(No description)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (node.priority != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.shade600),
                            ),
                            child: Text(
                              '?${node.priority}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (hasRef) ...[
                          ActionChip(
                            avatar: const Icon(Icons.alt_route, size: 14),
                            label: Text(node.ref!, style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.purple.shade50,
                            side: BorderSide(color: Colors.purple.shade200),
                            onPressed: () {
                              if (widget.onNavigateToFragment != null) {
                                widget.onNavigateToFragment!(node.ref!);
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    if (node.rule != null && node.rule!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          node.rule!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            color: Colors.blueGrey.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (hasChildren) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text('${node.bids.length} ${node.bids.length == 1 ? "bid" : "bids"}'),
                  onPressed: () => _drillInto(node),
                ),
              ] else if (hasRef) ...[
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: 'Jump to fragment: ${node.ref}',
                  onPressed: () {
                    if (widget.onNavigateToFragment != null) {
                      widget.onNavigateToFragment!(node.ref!);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorPanel(BuildContext context, BiddingNode node) {
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
                onPressed: () => setState(() => _selectedNode = null),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          Center(child: BidBadge(node: node, fontSize: 20)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              node.desc.isNotEmpty ? node.desc : '(No description)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Raw Call', node.call),
          _buildInfoRow('Type', node.isOpponent ? 'Opponent Bid' : 'System Bid'),
          if (node.suit != null) _buildInfoRow('Suit', node.suit!),
          if (node.level != null) _buildInfoRow('Level', '${node.level}'),
          if (node.priority != null) _buildInfoRow('Priority / Alert', '?${node.priority}'),
          if (node.inlineCondition != null) _buildInfoRow('Condition', node.inlineCondition!),
          if (node.ref != null) ...[
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
          if (node.bids.isNotEmpty) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.subdirectory_arrow_right),
                label: Text('Explore ${node.bids.length} Follow-ups'),
                onPressed: () => _drillInto(node),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.psychology),
                label: const Text('Practice Auction from Here 🎯'),
                onPressed: () {
                  if (widget.onPracticeFromNode != null) {
                    final fullPath = [..._breadcrumbPath, node];
                    widget.onPracticeFromNode!(fullPath);
                  }
                },
              ),
            ),
          ],
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
