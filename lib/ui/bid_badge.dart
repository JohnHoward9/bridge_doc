import 'package:flutter/material.dart';
import '../models/bidding_system.dart';

class BidBadge extends StatelessWidget {
  final BiddingNode node;
  final bool isSelected;
  final double fontSize;

  const BidBadge({
    super.key,
    required this.node,
    this.isSelected = false,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final isOpp = node.isOpponent;
    final isPass = node.isPass;
    final isDbl = node.isDbl;
    final isRdbl = node.isRdbl;
    final suit = node.suit;

    Color bg;
    Color fg;
    Color border;

    if (isPass) {
      bg = isOpp ? Colors.grey.shade200 : const Color(0xFFE8F5E9);
      fg = isOpp ? Colors.grey.shade800 : const Color(0xFF2E7D32);
      border = isOpp ? Colors.grey.shade400 : const Color(0xFF81C784);
    } else if (isDbl) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
      border = const Color(0xFFEF9A9A);
    } else if (isRdbl) {
      bg = const Color(0xFFE3F2FD);
      fg = const Color(0xFF1565C0);
      border = const Color(0xFF90CAF9);
    } else {
      switch (suit) {
        case 'C':
          bg = const Color(0xFFE8F5E9);
          fg = const Color(0xFF1B5E20);
          border = const Color(0xFFA5D6A7);
          break;
        case 'D':
          bg = const Color(0xFFFFF3E0);
          fg = const Color(0xFFE65100);
          border = const Color(0xFFFFCC80);
          break;
        case 'H':
          bg = const Color(0xFFFFEBEE);
          fg = const Color(0xFFB71C1C);
          border = const Color(0xFFEF9A9A);
          break;
        case 'S':
          bg = const Color(0xFFEDE7F6);
          fg = const Color(0xFF311B92);
          border = const Color(0xFFB39DDB);
          break;
        case 'NT':
          bg = const Color(0xFFE0F7FA);
          fg = const Color(0xFF006064);
          border = const Color(0xFF80DEEA);
          break;
        default:
          bg = Colors.grey.shade100;
          fg = Colors.blueGrey.shade800;
          border = Colors.blueGrey.shade200;
      }
    }

    if (isSelected) {
      border = Theme.of(context).colorScheme.primary;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.7, vertical: fontSize * 0.35),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: border,
          width: isSelected ? 2.0 : (isOpp ? 1.5 : 1.0),
          style: isOpp ? BorderStyle.solid : BorderStyle.solid,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: border.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOpp) ...[
            Icon(Icons.shield_outlined, size: fontSize * 0.85, color: fg),
            const SizedBox(width: 4),
          ],
          _buildSuitIcon(suit, fg, fontSize),
          Text(
            node.displayCall,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
              letterSpacing: 0.3,
            ),
          ),
          if (node.inlineCondition != null) ...[
            const SizedBox(width: 4),
            Text(
              '[${node.inlineCondition}]',
              style: TextStyle(
                color: fg.withValues(alpha: 0.75),
                fontSize: fontSize * 0.75,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuitIcon(String? suit, Color color, double size) {
    if (suit == null) return const SizedBox.shrink();
    String symbol = '';
    switch (suit) {
      case 'C':
        symbol = '♣ ';
        break;
      case 'D':
        symbol = '♦ ';
        break;
      case 'H':
        symbol = '♥ ';
        break;
      case 'S':
        symbol = '♠ ';
        break;
      case 'NT':
        return const SizedBox.shrink();
    }
    return Text(
      symbol,
      style: TextStyle(color: color, fontSize: size * 1.05, fontWeight: FontWeight.bold),
    );
  }
}
