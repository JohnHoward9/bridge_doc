import 'package:flutter/material.dart';
import '../../models/card.dart';
import '../../models/hand.dart';
import '../../evaluators/valuation_engine.dart';

class CardHandWidget extends StatefulWidget {
  final Hand hand;
  final VoidCallback? onRedeal;
  final String? filterBadge;
  final String title;
  final IconData icon;
  final Color headerColor;
  final bool isCollapsible;
  final bool initiallyCollapsed;
  final MLHandBreakdown? mlBreakdown;

  const CardHandWidget({
    super.key,
    required this.hand,
    this.onRedeal,
    this.filterBadge,
    this.title = 'Your Hand (South)',
    this.icon = Icons.style,
    this.headerColor = const Color(0xFF1B5E20),
    this.isCollapsible = false,
    this.initiallyCollapsed = false,
    this.mlBreakdown,
  });

  @override
  State<CardHandWidget> createState() => _CardHandWidgetState();
}

class _CardHandWidgetState extends State<CardHandWidget> {
  late bool _isCollapsed;

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.initiallyCollapsed;
  }

  @override
  void didUpdateWidget(covariant CardHandWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyCollapsed != widget.initiallyCollapsed) {
      _isCollapsed = widget.initiallyCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 20, color: widget.headerColor),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: widget.headerColor,
                      ),
                    ),
                    if (widget.filterBadge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purple.shade300),
                        ),
                        child: Text(
                          widget.filterBadge!,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.purple.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade600),
                      ),
                      child: Text(
                        '${widget.hand.hcp} HCP',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                    if (widget.mlBreakdown != null) ...[
                      const SizedBox(width: 6),
                      _buildEffHcpBadge(widget.mlBreakdown!),
                    ],
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.hand.exactDistribution,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (widget.isCollapsible) ...[
                      const SizedBox(width: 4),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        icon: Icon(_isCollapsed ? Icons.visibility : Icons.visibility_off, size: 16),
                        label: Text(_isCollapsed ? 'Show' : 'Hide'),
                        onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                      ),
                    ],
                    if (widget.onRedeal != null) ...[
                      const SizedBox(width: 2),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'Deal new hand',
                        onPressed: widget.onRedeal,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (!widget.isCollapsible || !_isCollapsed) ...[
              const Divider(height: 20),
              _buildSuitRow(Suit.spades, const Color(0xFF1A237E)),
              const SizedBox(height: 6),
              _buildSuitRow(Suit.hearts, const Color(0xFFB71C1C)),
              const SizedBox(height: 6),
              _buildSuitRow(Suit.diamonds, const Color(0xFFE65100)),
              const SizedBox(height: 6),
              _buildSuitRow(Suit.clubs, const Color(0xFF1B5E20)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuitRow(Suit suit, Color suitColor) {
    final cards = widget.hand.cardsInSuit(suit);

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: suitColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            suit.symbol,
            style: TextStyle(
              fontSize: 20,
              color: suitColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (cards.isEmpty)
          Text(
            '— (void)',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
          )
        else
          Wrap(
            spacing: 6,
            children: cards.map((c) => _buildCardTile(c, suitColor)).toList(),
          ),
      ],
    );
  }

  Widget _buildCardTile(BridgeCard card, Color suitColor) {
    final isHonor = card.rank.hcp > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHonor ? Colors.white : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHonor ? suitColor.withValues(alpha: 0.5) : Colors.grey.shade300,
          width: isHonor ? 1.5 : 1.0,
        ),
        boxShadow: isHonor
            ? [BoxShadow(color: suitColor.withValues(alpha: 0.15), blurRadius: 2, offset: const Offset(0, 1))]
            : null,
      ),
      child: Text(
        card.rank.symbol,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isHonor ? FontWeight.bold : FontWeight.w500,
          color: isHonor ? suitColor : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildEffHcpBadge(MLHandBreakdown b) {
    final isUp = b.effectiveHcp > b.rawHcp;
    final isDown = b.effectiveHcp < b.rawHcp;
    return Tooltip(
      message: b.reasons.isNotEmpty
          ? b.reasons.join('\n')
          : 'Evaluated at ${b.effectiveHcp.toStringAsFixed(1)} Eff HCP',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isUp
              ? const Color(0xFFEDE9FE)
              : isDown
                  ? const Color(0xFFFEF3C7)
                  : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUp
                ? const Color(0xFF8B5CF6)
                : isDown
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF94A3B8),
            width: 1.2,
          ),
        ),
        child: Text(
          isUp
              ? '🚀 ${b.effectiveHcp.toStringAsFixed(1)} Eff HCP'
              : isDown
                  ? '⚠️ ${b.effectiveHcp.toStringAsFixed(1)} Eff HCP'
                  : '✨ ${b.effectiveHcp.toStringAsFixed(1)} Eff HCP',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
            color: isUp
                ? const Color(0xFF6D28D9)
                : isDown
                    ? const Color(0xFFB45309)
                    : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
