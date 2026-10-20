import 'package:flutter/material.dart';
import '../../models/card.dart';
import '../../models/hand.dart';
import '../../engine/deal_generator.dart';
import '../../services/hand_parser.dart';

/// Interactive dialog allowing users to enter custom bridge hands or full deals
/// via text paste (dot-notation, multiline, PBN, LIN) or individual suit inputs.
class EnterHandDialog extends StatefulWidget {
  final PartnershipDeal? initialDeal;

  const EnterHandDialog({super.key, this.initialDeal});

  static Future<PartnershipDeal?> show(BuildContext context, {PartnershipDeal? currentDeal}) {
    return showDialog<PartnershipDeal>(
      context: context,
      builder: (ctx) => EnterHandDialog(initialDeal: currentDeal),
    );
  }

  @override
  State<EnterHandDialog> createState() => _EnterHandDialogState();
}

class _EnterHandDialogState extends State<EnterHandDialog> {
  final TextEditingController _pasteController = TextEditingController();

  // Visual card inputs for each seat
  String _selectedSeat = 'N';
  final Map<String, TextEditingController> _spadesControllers = {};
  final Map<String, TextEditingController> _heartsControllers = {};
  final Map<String, TextEditingController> _diamondsControllers = {};
  final Map<String, TextEditingController> _clubsControllers = {};

  String? _parseError;
  Map<String, Hand> _parsedHands = {};

  @override
  void initState() {
    super.initState();

    for (final seat in ['N', 'E', 'S', 'W']) {
      _spadesControllers[seat] = TextEditingController();
      _heartsControllers[seat] = TextEditingController();
      _diamondsControllers[seat] = TextEditingController();
      _clubsControllers[seat] = TextEditingController();
    }

    if (widget.initialDeal != null) {
      _loadDealIntoControllers(widget.initialDeal!);
    }

    _pasteController.addListener(_onPasteTextChanged);
  }

  void _loadDealIntoControllers(PartnershipDeal deal) {
    void populate(String seat, Hand hand) {
      String ranks(Suit s) => hand.cardsInSuit(s).map((c) => c.rank.symbol).join('');
      _spadesControllers[seat]!.text = ranks(Suit.spades);
      _heartsControllers[seat]!.text = ranks(Suit.hearts);
      _diamondsControllers[seat]!.text = ranks(Suit.diamonds);
      _clubsControllers[seat]!.text = ranks(Suit.clubs);
    }

    populate('N', deal.north);
    populate('E', deal.east);
    populate('S', deal.south);
    populate('W', deal.west);
  }

  @override
  void dispose() {
    _pasteController.dispose();
    for (final seat in ['N', 'E', 'S', 'W']) {
      _spadesControllers[seat]!.dispose();
      _heartsControllers[seat]!.dispose();
      _diamondsControllers[seat]!.dispose();
      _clubsControllers[seat]!.dispose();
    }
    super.dispose();
  }

  void _onPasteTextChanged() {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _parsedHands = {};
        _parseError = null;
      });
      return;
    }

    try {
      final hands = HandParser.parseDealText(text);
      if (hands.isEmpty) {
        setState(() {
          _parsedHands = {};
          _parseError = 'No valid cards detected in text.';
        });
      } else {
        // Validate duplicates across parsed hands eagerly
        final allCards = <BridgeCard>{};
        for (final entry in hands.entries) {
          for (final card in entry.value.cards) {
            if (!allCards.add(card)) {
              throw FormatException('Duplicate card ${card.suit.symbol}${card.rank.symbol} detected across hands.');
            }
          }
        }
        setState(() {
          _parsedHands = hands;
          _parseError = null;
        });
      }
    } catch (e) {
      setState(() {
        _parsedHands = {};
        _parseError = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  void _applyQuickSample(String sampleText) {
    _pasteController.text = sampleText;
  }

  void _applyDealAndClose() {
    try {
      Map<String, Hand> handsToApply = {};

      if (_parsedHands.isNotEmpty) {
        handsToApply = Map.from(_parsedHands);
      } else {
        // Collect from visual suit inputs
        for (final seat in ['N', 'E', 'S', 'W']) {
          final s = _spadesControllers[seat]!.text.trim();
          final h = _heartsControllers[seat]!.text.trim();
          final d = _diamondsControllers[seat]!.text.trim();
          final c = _clubsControllers[seat]!.text.trim();

          final hasCards = s.isNotEmpty || h.isNotEmpty || d.isNotEmpty || c.isNotEmpty;
          if (hasCards) {
            final cards = <BridgeCard>[
              ...HandParser.parseSuitRanks(Suit.spades, s),
              ...HandParser.parseSuitRanks(Suit.hearts, h),
              ...HandParser.parseSuitRanks(Suit.diamonds, d),
              ...HandParser.parseSuitRanks(Suit.clubs, c),
            ];
            handsToApply[seat] = Hand(cards);
          }
        }
      }

      if (handsToApply.isEmpty) {
        setState(() {
          _parseError = 'Please enter at least one hand.';
        });
        return;
      }

      final completedDeal = HandParser.completeDeal(handsToApply);
      Navigator.of(context).pop(completedDeal);
    } catch (e) {
      setState(() {
        _parseError = e.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.style, color: Color(0xFF1B5E20)),
            SizedBox(width: 10),
            Text('Enter Custom Deal / Hands', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 580,
          height: 480,
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const TabBar(
                  labelColor: Color(0xFF1B5E20),
                  indicatorColor: Color(0xFF1B5E20),
                  tabs: [
                    Tab(icon: Icon(Icons.paste, size: 18), text: 'Paste Text / Deal'),
                    Tab(icon: Icon(Icons.tune, size: 18), text: 'Suit Inputs'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildPasteTab(),
                    _buildSuitInputsTab(),
                  ],
                ),
              ),
              if (_parseError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _parseError!,
                          style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Load Deal'),
            onPressed: _parseError != null ? null : _applyDealAndClose,
          ),
        ],
      ),
    );
  }

  String _seatName(String code) {
    switch (code) {
      case 'N': return 'North';
      case 'S': return 'South';
      case 'E': return 'East';
      case 'W': return 'West';
      default: return code;
    }
  }

  Widget _buildPasteTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Paste single hand (e.g. K87.AJT976543.K.-) or multiline deal (North:, South:, etc.):',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Expanded(
          flex: 5,
          child: TextField(
            controller: _pasteController,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'North:\nS:K87\nH:AJT976543\nD:K\nC:-\n\nSouth:\nS:AQ2\nH:Q\nD:J9742\nC:QJ75',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Sample Deals: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _applyQuickSample(
                  'North:\nS:K87\nH:AJT976543\nD:K\nC:-\n\nSouth:\nS:AQ2\nH:Q\nD:J9742\nC:QJ75\n\nEast:\nS:JT5\nH:82\nD:AQT83\nC:A64',
                ),
                child: const Text('User Hand (9♥)', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _applyQuickSample(
                  'N:AKJ4.QT5.83.K982 Q83.J94.K76.AJ54 9762.A862.A54.73 T5.K73.QJT92.QT6',
                ),
                child: const Text('PBN Deal', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _pasteController.clear(),
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (_parsedHands.isNotEmpty) ...[
          const Text('Parsed Hands Preview (Missing seats will be auto-completed):',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
          const SizedBox(height: 4),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _parsedHands.entries.map((e) {
                    final h = e.value;
                    String suitText(Suit s) => h.cardsInSuit(s).map((c) => c.rank.symbol).join('');
                    final sText = suitText(Suit.spades);
                    final hText = suitText(Suit.hearts);
                    final dText = suitText(Suit.diamonds);
                    final cText = suitText(Suit.clubs);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${_seatName(e.key)} (${e.key}): ♠${sText.isEmpty ? '-' : sText} ♥${hText.isEmpty ? '-' : hText} ♦${dText.isEmpty ? '-' : dText} ♣${cText.isEmpty ? '-' : cText}  (${h.cards.length} cards, ${h.hcp} HCP)',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSuitInputsTab() {
    final sCtrl = _spadesControllers[_selectedSeat]!;
    final hCtrl = _heartsControllers[_selectedSeat]!;
    final dCtrl = _diamondsControllers[_selectedSeat]!;
    final cCtrl = _clubsControllers[_selectedSeat]!;

    final currentCards = [
      ...HandParser.parseSuitRanks(Suit.spades, sCtrl.text),
      ...HandParser.parseSuitRanks(Suit.hearts, hCtrl.text),
      ...HandParser.parseSuitRanks(Suit.diamonds, dCtrl.text),
      ...HandParser.parseSuitRanks(Suit.clubs, cCtrl.text),
    ];
    final hand = Hand(currentCards);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['N', 'E', 'S', 'W'].map((seat) {
            final isSel = _selectedSeat == seat;
            final label = seat == 'N'
                ? 'North (Partner)'
                : (seat == 'S' ? 'South (You)' : (seat == 'E' ? 'East' : 'West'));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: isSel,
                selectedColor: const Color(0xFFDCFCE7),
                onSelected: (val) {
                  if (val) setState(() => _selectedSeat = seat);
                },
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              _buildSuitRow('♠', Colors.black, sCtrl, 'e.g. K87 or AKQ'),
              const SizedBox(height: 8),
              _buildSuitRow('♥', Colors.red, hCtrl, 'e.g. AJT976543 or Q'),
              const SizedBox(height: 8),
              _buildSuitRow('♦', Colors.orange.shade800, dCtrl, 'e.g. K or J9742'),
              const SizedBox(height: 8),
              _buildSuitRow('♣', Colors.green.shade900, cCtrl, 'e.g. QJ75 or -'),
            ],
          ),
        ),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Text('Cards: ${hand.cards.length}/13',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: hand.cards.length == 13 ? Colors.green.shade800 : Colors.red.shade800,
                )),
            Text('HCP: ${hand.hcp}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text('Controls: ${hand.controls}', style: const TextStyle(fontSize: 12)),
            Text('LTC: ${hand.losingTrickCount}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildSuitRow(String symbol, Color color, TextEditingController ctrl, String hint) {
    return Row(
      children: [
        Container(
          width: 32,
          alignment: Alignment.center,
          child: Text(symbol, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ),
      ],
    );
  }
}
