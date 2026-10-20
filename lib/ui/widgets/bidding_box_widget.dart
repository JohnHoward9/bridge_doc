import 'package:flutter/material.dart';
import '../../engine/auction_engine.dart';

/// Helper representation of auction legality for the bidding box.
class _AuctionLegality {
  final int minLegalLevel;
  final bool Function(int level) isLevelLegal;
  final bool Function(int level, String suitChar) isSuitLegal;
  final bool canDouble;
  final bool canRedouble;

  const _AuctionLegality({
    required this.minLegalLevel,
    required this.isLevelLegal,
    required this.isSuitLegal,
    required this.canDouble,
    required this.canRedouble,
  });
}

/// Represents description and rule details of a bid to show in preview/confirm cards.
class BidDescription {
  final String call;
  final String displayCall;
  final String description;
  final String? rule;

  const BidDescription({
    required this.call,
    required this.displayCall,
    required this.description,
    this.rule,
  });
}

/// Compact BBO-style Bridge Bidding Box widget with Bridge Law legality filtering.
///
/// Features:
/// - Row 1: Segmented Level selector [ 1 | 2 | 3 | 4 | 5 | 6 | 7 ]
/// - Row 2: Segmented Suit selector [ ♣ | ♦ | ♥ | ♠ | NT ] + Alert [ A ]
/// - Row 3: Action buttons [ Pass ]  [ X ]  [ XX ]
/// - Optional Confirm button with Direct / Confirm radio selection.
///
/// Bids lower than or equal to the current contract are grayed out and disabled.
/// Double (X) is only enabled when the last contract was bid by an opponent and undoubled.
/// Redouble (XX) is only enabled when our contract was doubled by an opponent and unredoubled.
class BiddingBoxWidget extends StatefulWidget {
  final ValueChanged<String> onBidSelected;
  final bool isEnabled;
  final List<AuctionEntry> history;
  final String activeSeat;
  final bool validateLegality;
  final bool requireConfirmation;
  final ValueChanged<bool>? onRequireConfirmationChanged;
  final bool showConfirmationRadio;
  final BidDescription? Function(String call)? descriptionResolver;

  const BiddingBoxWidget({
    super.key,
    required this.onBidSelected,
    this.isEnabled = true,
    this.history = const [],
    this.activeSeat = 'S',
    this.validateLegality = true,
    this.requireConfirmation = false,
    this.onRequireConfirmationChanged,
    this.showConfirmationRadio = true,
    this.descriptionResolver,
  });

  @override
  State<BiddingBoxWidget> createState() => _BiddingBoxWidgetState();
}

class _BiddingBoxWidgetState extends State<BiddingBoxWidget> {
  int _selectedLevel = 1;
  bool _isAlerted = false;
  late bool _requireConfirmation;
  String? _stagedCall;
  BidDescription? _stagedDescription;

  static const List<String> _suits = ['♣', '♦', '♥', '♠', 'NT'];
  static const List<String> _suitChars = ['c', 'd', 'h', 's', 'nt'];
  static const Map<String, int> _suitRank = {
    'c': 0,
    'd': 1,
    'h': 2,
    's': 3,
    'nt': 4,
  };

  static const Color _primaryBorderColor = Color(0xFF2979FF); // Crisp bridge blue
  static const Color _selectedBgColor = Color(0xFF1976D2);
  static const Color _containerBgColor = Color(0xFFF1F3F5);

  @override
  void initState() {
    super.initState();
    _requireConfirmation = widget.requireConfirmation;
    _syncSelectedLevel();
  }

  @override
  void didUpdateWidget(BiddingBoxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requireConfirmation != oldWidget.requireConfirmation) {
      _requireConfirmation = widget.requireConfirmation;
      _stagedCall = null;
      _stagedDescription = null;
    }
    if (widget.history.length != oldWidget.history.length || !widget.isEnabled) {
      _stagedCall = null;
      _stagedDescription = null;
    }
    _syncSelectedLevel();
  }

  void _syncSelectedLevel() {
    if (!widget.validateLegality) return;
    final legality = _computeLegality();
    if (_selectedLevel < legality.minLegalLevel) {
      _selectedLevel = legality.minLegalLevel <= 7 ? legality.minLegalLevel : 7;
    }
  }

  static String _normalizeCall(String raw) {
    final clean = raw.trim().toLowerCase()
        .replaceAll('♣', 'c')
        .replaceAll('♦', 'd')
        .replaceAll('♥', 'h')
        .replaceAll('♠', 's');
    if (clean == 'x') return 'dbl';
    if (clean == 'xx') return 'rdbl';
    if (clean == 'p') return 'pass';
    return clean;
  }

  static bool _isOpponent(String seat1, String seat2) {
    final s1 = seat1.toUpperCase();
    final s2 = seat2.toUpperCase();
    final isNS1 = s1 == 'N' || s1 == 'S';
    final isNS2 = s2 == 'N' || s2 == 'S';
    return isNS1 != isNS2;
  }

  _AuctionLegality _computeLegality() {
    if (!widget.validateLegality) {
      return _AuctionLegality(
        minLegalLevel: 1,
        isLevelLegal: (l) => l >= 1 && l <= 7,
        isSuitLegal: (l, s) => true,
        canDouble: true,
        canRedouble: true,
      );
    }

    AuctionEntry? lastContract;
    int lastContractIdx = -1;
    int lastLevel = 0;
    String lastSuit = '';
    int lastSuitRank = -1;

    for (int i = widget.history.length - 1; i >= 0; i--) {
      final entry = widget.history[i];
      final norm = _normalizeCall(entry.call);
      final match = RegExp(r'^([1-7])(c|d|h|s|nt)$').firstMatch(norm);
      if (match != null) {
        lastContract = entry;
        lastContractIdx = i;
        lastLevel = int.parse(match.group(1)!);
        lastSuit = match.group(2)!;
        lastSuitRank = _suitRank[lastSuit] ?? -1;
        break;
      }
    }

    int minLegalLevel = 1;
    if (lastContract != null) {
      if (lastSuitRank < 4) {
        minLegalLevel = lastLevel;
      } else {
        minLegalLevel = lastLevel + 1;
      }
    }

    bool isLevelLegal(int l) {
      if (l < minLegalLevel || l > 7) return false;
      return true;
    }

    bool isSuitLegal(int l, String suitChar) {
      if (!isLevelLegal(l)) return false;
      if (lastContract == null) return true;
      if (l > lastLevel) return true;
      if (l < lastLevel) return false;
      final rank = _suitRank[suitChar] ?? -1;
      return rank > lastSuitRank;
    }

    bool canDouble = false;
    bool canRedouble = false;

    if (lastContract != null) {
      final isContractByOpponent = _isOpponent(widget.activeSeat, lastContract.seat);
      final callsAfterContract = widget.history
          .sublist(lastContractIdx + 1)
          .map((e) => _normalizeCall(e.call))
          .toList();

      final dblIndex = callsAfterContract.lastIndexOf('dbl');
      final rdblIndex = callsAfterContract.lastIndexOf('rdbl');

      if (isContractByOpponent) {
        if (dblIndex == -1 && rdblIndex == -1) {
          canDouble = true;
        }
      } else {
        if (dblIndex != -1 && rdblIndex == -1) {
          canRedouble = true;
        }
      }
    }

    return _AuctionLegality(
      minLegalLevel: minLegalLevel,
      isLevelLegal: isLevelLegal,
      isSuitLegal: isSuitLegal,
      canDouble: canDouble,
      canRedouble: canRedouble,
    );
  }

  void _onLevelTapped(int level) {
    if (!widget.isEnabled) return;
    if (widget.validateLegality) {
      final legality = _computeLegality();
      if (!legality.isLevelLegal(level)) return;
    }
    setState(() {
      _selectedLevel = level;
      if (_requireConfirmation && _stagedCall != null) {
        final match = RegExp(r'^[1-7]([a-z]+)$').firstMatch(_stagedCall!);
        if (match != null) {
          final suitChar = match.group(1)!;
          final legality = _computeLegality();
          if (legality.isSuitLegal(level, suitChar)) {
            final newCall = '$level$suitChar';
            _stagedCall = newCall;
            _stagedDescription = widget.descriptionResolver?.call(newCall) ?? _defaultDescription(newCall);
          } else {
            _stagedCall = null;
            _stagedDescription = null;
          }
        }
      }
    });
  }

  void _onSuitTapped(String suitChar) {
    if (!widget.isEnabled) return;
    if (widget.validateLegality) {
      final legality = _computeLegality();
      if (!legality.isSuitLegal(_selectedLevel, suitChar)) return;
    }
    final call = '$_selectedLevel$suitChar';
    if (!_requireConfirmation) {
      widget.onBidSelected(call);
      if (_isAlerted) {
        setState(() => _isAlerted = false);
      }
    } else {
      setState(() {
        _stagedCall = call;
        _stagedDescription = widget.descriptionResolver?.call(call) ?? _defaultDescription(call);
      });
    }
  }

  void _onActionTapped(String action) {
    if (!widget.isEnabled) return;
    if (widget.validateLegality) {
      final legality = _computeLegality();
      if (action == 'dbl' && !legality.canDouble) return;
      if (action == 'rdbl' && !legality.canRedouble) return;
    }
    if (!_requireConfirmation) {
      widget.onBidSelected(action);
    } else {
      setState(() {
        _stagedCall = action;
        _stagedDescription = widget.descriptionResolver?.call(action) ?? _defaultDescription(action);
      });
    }
  }

  void _confirmStagedBid() {
    if (_stagedCall == null || !widget.isEnabled) return;
    final call = _stagedCall!;
    setState(() {
      _stagedCall = null;
      _stagedDescription = null;
      if (_isAlerted) _isAlerted = false;
    });
    widget.onBidSelected(call);
  }

  void _cancelStagedBid() {
    setState(() {
      _stagedCall = null;
      _stagedDescription = null;
    });
  }

  BidDescription _defaultDescription(String call) {
    final lower = call.trim().toLowerCase();
    String display = call.toUpperCase();
    String desc = 'Bid $display';

    if (lower == 'pass') {
      display = 'Pass';
      desc = 'Pass (no bid / no system action)';
    } else if (lower == 'dbl' || lower == 'x') {
      display = 'Dbl';
      desc = 'Double';
    } else if (lower == 'rdbl' || lower == 'xx') {
      display = 'Rdbl';
      desc = 'Redouble';
    } else if (lower.length >= 2) {
      final l = lower[0];
      final s = lower.substring(1);
      final suitMap = {'c': '♣', 'd': '♦', 'h': '♥', 's': '♠', 'nt': 'NT'};
      display = '$l${suitMap[s] ?? s.toUpperCase()}';
      desc = 'Natural bid $display';
    }

    return BidDescription(
      call: call,
      displayCall: display,
      description: desc,
    );
  }

  Widget _buildConfirmationRadioRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Bid Mode: ',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                if (_requireConfirmation) {
                  setState(() {
                    _requireConfirmation = false;
                    _stagedCall = null;
                    _stagedDescription = null;
                  });
                  widget.onRequireConfirmationChanged?.call(false);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<bool>(
                    value: false,
                    groupValue: _requireConfirmation,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) {
                      setState(() {
                        _requireConfirmation = false;
                        _stagedCall = null;
                        _stagedDescription = null;
                      });
                      widget.onRequireConfirmationChanged?.call(false);
                    },
                  ),
                  const Text('Direct', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            InkWell(
              onTap: () {
                if (!_requireConfirmation) {
                  setState(() {
                    _requireConfirmation = true;
                    _stagedCall = null;
                    _stagedDescription = null;
                  });
                  widget.onRequireConfirmationChanged?.call(true);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<bool>(
                    value: true,
                    groupValue: _requireConfirmation,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) {
                      setState(() {
                        _requireConfirmation = true;
                        _stagedCall = null;
                        _stagedDescription = null;
                      });
                      widget.onRequireConfirmationChanged?.call(true);
                    },
                  ),
                  const Text('Confirm', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStagedBidCard() {
    final desc = _stagedDescription ?? _defaultDescription(_stagedCall!);
    final displayCall = desc.displayCall;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1976D2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF90CAF9)),
                ),
                child: Text(
                  'Selected: $displayCall',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Review bid description before confirming:',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                tooltip: 'Cancel',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _cancelStagedBid,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc.description,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                ),
                if (desc.rule != null && desc.rule!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Rule: ${desc.rule}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF475569)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    'Confirm Bid: $displayCall',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  onPressed: _confirmStagedBid,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onPressed: _cancelStagedBid,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final legality = _computeLegality();
    if (widget.validateLegality && !legality.isLevelLegal(_selectedLevel)) {
      _selectedLevel = legality.minLegalLevel <= 7 ? legality.minLegalLevel : 7;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Opacity(
          opacity: widget.isEnabled ? 1.0 : 0.45,
          child: IgnorePointer(
            ignoring: !widget.isEnabled,
            child: Container(
              decoration: BoxDecoration(
                color: _containerBgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _primaryBorderColor.withValues(alpha: 0.6), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showConfirmationRadio) ...[
                    _buildConfirmationRadioRow(),
                    const SizedBox(height: 6),
                  ],

                  // Row 1: Levels [ 1 | 2 | 3 | 4 | 5 | 6 | 7 ]
                  _buildLevelRow(legality),
                  const SizedBox(height: 6),

                  // Row 2: Suits [ ♣ | ♦ | ♥ | ♠ | NT ] + Alert [ A ]
                  _buildSuitAndAlertRow(legality),
                  const SizedBox(height: 6),

                  // Row 3: Actions [ Pass ]  [ X ]  [ XX ]
                  _buildActionRow(legality),

                  if (_requireConfirmation && _stagedCall != null) ...[
                    const SizedBox(height: 8),
                    _buildStagedBidCard(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelRow(_AuctionLegality legality) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _primaryBorderColor, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2.5),
        child: Row(
          children: List.generate(7, (index) {
            final level = index + 1;
            final isLegal = legality.isLevelLegal(level);
            final canTap = widget.isEnabled && isLegal;
            final isSelected = _selectedLevel == level && isLegal;
            final isLast = index == 6;

            Color bgColor;
            Color textColor;
            if (!isLegal) {
              bgColor = const Color(0xFFF3F4F6); // Soft gray
              textColor = const Color(0xFFBDBDBD); // Muted gray
            } else if (isSelected) {
              bgColor = _selectedBgColor;
              textColor = Colors.white;
            } else {
              bgColor = Colors.white;
              textColor = const Color(0xFF1F2937);
            }

            return Expanded(
              child: InkWell(
                onTap: canTap ? () => _onLevelTapped(level) : null,
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: isLast
                        ? null
                        : const Border(
                            right: BorderSide(color: _primaryBorderColor, width: 1.0),
                          ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$level',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSuitAndAlertRow(_AuctionLegality legality) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          // 5 Suit buttons aligned with columns 1..5
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _primaryBorderColor, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2.5),
                child: Row(
                  children: List.generate(5, (index) {
                    final symbol = _suits[index];
                    final suitChar = _suitChars[index];
                    final isLast = index == 4;
                    final isRedSuit = index == 1 || index == 2;
                    final isLegal = legality.isSuitLegal(_selectedLevel, suitChar);
                    final canTap = widget.isEnabled && isLegal;

                    final isStaged = _requireConfirmation && _stagedCall == '$_selectedLevel$suitChar';
                    final Color textColor = isStaged
                        ? const Color(0xFF0D47A1)
                        : (!isLegal
                            ? const Color(0xFFBDBDBD)
                            : (isRedSuit ? const Color(0xFFD32F2F) : Colors.black87));
                    final Color bgColor = isStaged
                        ? const Color(0xFFBBDEFB)
                        : (isLegal ? Colors.white : const Color(0xFFF3F4F6));

                    return Expanded(
                      child: InkWell(
                        onTap: canTap ? () => _onSuitTapped(suitChar) : null,
                        child: Container(
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: bgColor,
                            border: isStaged
                                ? Border.all(color: const Color(0xFF1976D2), width: 2.0)
                                : (isLast
                                    ? null
                                    : const Border(
                                        right: BorderSide(color: _primaryBorderColor, width: 1.0),
                                      )),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            symbol,
                            style: TextStyle(
                              fontSize: index == 4 ? 14 : 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Alert "A" button taking flex 2 (aligned with columns 6..7)
          Expanded(
            flex: 2,
            child: Tooltip(
              message: _isAlerted ? 'Alert active' : 'Alert bid',
              child: Material(
                color: _isAlerted ? const Color(0xFFF59E0B) : const Color(0xFFA5C4EB),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: () {
                    if (!widget.isEnabled) return;
                    setState(() => _isAlerted = !_isAlerted);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: double.infinity,
                    alignment: Alignment.center,
                    child: Text(
                      'A',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isAlerted ? Colors.white : const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(_AuctionLegality legality) {
    final canDouble = widget.isEnabled && legality.canDouble;
    final canRedouble = widget.isEnabled && legality.canRedouble;

    final isPassStaged = _requireConfirmation && _stagedCall == 'pass';
    final isDblStaged = _requireConfirmation && _stagedCall == 'dbl';
    final isRdblStaged = _requireConfirmation && _stagedCall == 'rdbl';

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          // Pass Button (Green) - always legal on your turn
          SizedBox(
            width: 78,
            child: Material(
              color: widget.isEnabled ? const Color(0xFF2E7D32) : const Color(0xFFBDBDBD),
              shape: isPassStaged
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: const BorderSide(color: Color(0xFF1976D2), width: 2.5),
                    )
                  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: InkWell(
                onTap: widget.isEnabled ? () => _onActionTapped('pass') : null,
                borderRadius: BorderRadius.circular(4),
                child: const Center(
                  child: Text(
                    'Pass',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Double "X" Button (Pastel Red when enabled, Gray when disabled)
          SizedBox(
            width: 52,
            child: Material(
              color: canDouble ? const Color(0xFFEF9A9A) : const Color(0xFFE0E0E0),
              shape: isDblStaged
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: const BorderSide(color: Color(0xFF1976D2), width: 2.5),
                    )
                  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: InkWell(
                onTap: canDouble ? () => _onActionTapped('dbl') : null,
                borderRadius: BorderRadius.circular(4),
                child: Center(
                  child: Text(
                    'X',
                    style: TextStyle(
                      color: canDouble ? Colors.white : const Color(0xFF9E9E9E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Redouble "XX" Button (Pastel Blue when enabled, Gray when disabled)
          SizedBox(
            width: 52,
            child: Material(
              color: canRedouble ? const Color(0xFF90CAF9) : const Color(0xFFE0E0E0),
              shape: isRdblStaged
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: const BorderSide(color: Color(0xFF1976D2), width: 2.5),
                    )
                  : RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: InkWell(
                onTap: canRedouble ? () => _onActionTapped('rdbl') : null,
                borderRadius: BorderRadius.circular(4),
                child: Center(
                  child: Text(
                    'XX',
                    style: TextStyle(
                      color: canRedouble ? Colors.white : const Color(0xFF9E9E9E),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
