import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/card.dart';
import '../models/hand.dart';
import '../models/bidding_system.dart';
import '../engine/deal_generator.dart';
import '../engine/compiled_auction_graph.dart';
import '../engine/auction_engine.dart';
import '../constraints/specificity_resolver.dart';
import '../evaluators/ml_bid_evaluator.dart';
import '../evaluators/valuation_engine.dart';
import '../services/board_exporter.dart';
import 'widgets/card_hand_widget.dart';
import 'widgets/bidding_box_widget.dart';
import 'widgets/enter_hand_dialog.dart';
import 'bid_badge.dart';

enum DealerSeat {
  west('West (Opponent)', 'W'),
  north('North (Partner)', 'N'),
  east('East (Opponent)', 'E'),
  south('South (You)', 'S');

  final String label;
  final String code;
  const DealerSeat(this.label, this.code);
}

// Retain FirstBidder for backward compatibility
typedef FirstBidder = DealerSeat;

class AuctionPreset {
  final String label;
  final String description;
  final DealerSeat dealer;
  final List<AuctionEntry> calls;

  const AuctionPreset({
    required this.label,
    required this.description,
    required this.dealer,
    required this.calls,
  });
}

class PracticeQuizView extends StatefulWidget {
  final BridgeSystem system;
  final BridgeSystem? ewSystem;
  final List<BiddingNode>? initialAuctionPath;
  final VoidCallback? onClearPracticeAuction;

  const PracticeQuizView({
    super.key,
    required this.system,
    this.ewSystem,
    this.initialAuctionPath,
    this.onClearPracticeAuction,
  });

  @override
  State<PracticeQuizView> createState() => _PracticeQuizViewState();
}

class _PracticeQuizViewState extends State<PracticeQuizView> {
  final DealGenerator _generator = DealGenerator();
  late AuctionEngine _engine;
  late SpecificityResolver _resolver;

  static const List<String> _seatOrder = ['W', 'N', 'E', 'S'];

  DealerSeat _dealer = DealerSeat.north;
  bool _isSetupMode = false;
  List<AuctionEntry>? _lockedSetupAuction;
  String? _selectedNorthOpening;
  SouthHcpFilter _southHcpFilter = SouthHcpFilter.any;
  SouthShapeFilter _southShapeFilter = SouthShapeFilter.any;
  PartnershipHcpFilter _partnershipFilter = PartnershipHcpFilter.any;
  late PartnershipDeal _currentDeal;
  bool _showNorthHand = true;

  final List<AuctionEntry> _auctionHistory = [];
  List<CandidateCall> _availableCandidates = [];
  int? _selectedCellIndex;
  int? _inspectedHistoryIndex;
  bool _requireBidConfirmation = false;
  MLEdgeCasePrediction? _lastMlPrediction;
  MLHandBreakdown? _lastMlUpgradeBreakdown;

  String get _selectedEntrySeat {
    final dealerIdx = _seatOrder.indexOf(_dealer.code);
    final targetIndex = (_selectedCellIndex != null && _selectedCellIndex! < _auctionHistory.length)
        ? _selectedCellIndex!
        : _auctionHistory.length;
    return _seatOrder[(dealerIdx + targetIndex) % 4];
  }

  String get _nextSeatInOrder {
    final dealerIdx = _seatOrder.indexOf(_dealer.code);
    return _seatOrder[(dealerIdx + _auctionHistory.length) % 4];
  }

  String get _activeTurnSeat => AuctionEngine.determineNextSeat(_auctionHistory, _dealer.code);
  bool get _isUserTurn => !_isAuctionComplete && _submittedBid == null && _availableCandidates.isNotEmpty;

  List<AuctionEntry> get _effectiveHistoryForBiddingBox {
    if (_isSetupMode && _selectedCellIndex != null && _selectedCellIndex! < _auctionHistory.length) {
      return _auctionHistory.sublist(0, _selectedCellIndex!);
    }
    return _auctionHistory;
  }

  String get _effectiveSeatForBiddingBox {
    if (_isSetupMode) {
      return _selectedEntrySeat;
    }
    return _activeTurnSeat;
  }

  static const List<AuctionPreset> _presets = [
    AuctionPreset(
      label: 'Pass → 1♠ (Drury)',
      description: 'North passes, South opens 1♠ in 3rd seat. Test North Reverse Drury 2♣ response.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: 'Pass', desc: 'Pass (0-11 HCP)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '1♠', desc: '1 Spade opening (11+ HCP)'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♠ → 2NT (Jacoby)',
      description: 'North opens 1♠, South bids 2NT Jacoby GF. Test North rebid.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♠', desc: '1 Spade opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '2NT', desc: 'Jacoby 2NT (Game Forcing)'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♥ → 2NT (Jacoby)',
      description: 'North opens 1♥, South bids 2NT Jacoby GF. Test North rebid.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♥', desc: '1 Heart opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '2NT', desc: 'Jacoby 2NT (Game Forcing)'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♣ → 1♥ → 2♥ (Spiral Ask)',
      description: 'North opens 1♣, South bids 1♥, North raises to 2♥. Test South Spiral 2♠ ask.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♣', desc: '1 Club opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '1♥', desc: '1 Heart response (4+ Hearts, 6+ HCP)'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'N', call: '2♥', desc: 'Raise to 2H (3+ Hearts, 12-15 HCP)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♦ → 1♠ → 2♠ (Spiral Ask)',
      description: 'North opens 1♦, South bids 1♠, North raises to 2♠. Test South Spiral 2NT ask.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♦', desc: '1 Diamond opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '1♠', desc: '1 Spade response (4+ Spades, 6+ HCP)'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'N', call: '2♠', desc: 'Raise to 2S (3+ Spades, 12-15 HCP)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♣ → 1♥ → (1♠) (Support Dbl)',
      description: 'North opens 1♣, South bids 1♥, East overcalls 1♠. Test North Support Double.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♣', desc: '1 Club opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '1♥', desc: '1 Heart response (4+ Hearts, 6+ HCP)'),
        AuctionEntry(seat: 'W', call: '1♠', desc: 'Interference 1S overcall'),
      ],
    ),
    AuctionPreset(
      label: '1♥ → 3♦ (Limit Raise Edge)',
      description: 'North opens 1♥, South bids 3♦ (4-card limit raise, 10-11 HCP). Test ML Edge Evaluation.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♥', desc: '1 Heart opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '3♦', desc: '4-card Limit Raise (10-11 HCP, 4+ Hearts)'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♥ → (2♦) (Interference Reopen)',
      description: 'North opens 1♥, East overcalls 2♦. Test South competitive bid and North reopening.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♥', desc: '1 Heart opening'),
        AuctionEntry(seat: 'E', call: '2♦', desc: 'Opposition 2D overcall'),
      ],
    ),
    AuctionPreset(
      label: '1NT → 2♣ (Stayman)',
      description: 'North opens 1NT, South asks with 2♣ Stayman. Test North rebid.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1NT', desc: '1NT opening (15-17 balanced)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '2♣', desc: 'Stayman inquiry'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1NT → 2♦ (Transfer)',
      description: 'North opens 1NT, South transfers with 2♦. Test North rebid.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1NT', desc: '1NT opening (15-17 balanced)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '2♦', desc: 'Jacoby Transfer to Hearts'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♣ → 1♦ (Walsh)',
      description: 'North opens 1♣, South responds 1♦. Test North rebid.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♣', desc: '1 Club opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '1♦', desc: '1 Diamond response'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♠ Opener (Test South)',
      description: 'North opens 1♠. Test South response.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♠', desc: '1 Spade opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '1♠ → 1NT → 2♣ (Bart)',
      description: 'North opens 1♠, South bids 1NT, North rebids 2♣. Test South Reversed Bart.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '1♠', desc: '1 Spade opening'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '1NT', desc: 'Semi-forcing 1NT'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'N', call: '2♣', desc: 'Opener natural minor or minimum'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '2♠ → 2NT (Feature Ask)',
      description: 'North opens weak 2♠. South asks for feature with 2NT.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '2♠', desc: 'Weak Two in Spades (6-card suit, 5-10 HCP)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
        AuctionEntry(seat: 'S', call: '2NT', desc: 'Feature Ask (14+ HCP)'),
        AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
      ],
    ),
    AuctionPreset(
      label: '3♥ Opener (Preempt)',
      description: 'North opens preemptive 3♥ (7-card Hearts). Test South response.',
      dealer: DealerSeat.north,
      calls: [
        AuctionEntry(seat: 'N', call: '3♥', desc: '3-level Preempt (7+ Hearts, 6-10 HCP)'),
        AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
      ],
    ),
  ];

  String? _submittedBid;
  CandidateCall? _expectedBestBid;
  List<CandidateCall>? _allMatches;
  bool? _isCorrect;
  String? _lastCorrectFeedback;
  bool _isAuctionComplete = false;

  int _correctCount = 0;
  int _totalAttempts = 0;

  List<String> get _availableOpeningBids {
    final calls = <String>{};
    for (final node in _engine.graph.rootState.candidateNodes) {
      if (!node.isPass && !node.isConditionalBranch && node.displayCall.isNotEmpty) {
        calls.add(node.displayCall);
      }
    }
    final list = calls.toList();
    list.sort((a, b) {
      final levelA = int.tryParse(a.isNotEmpty ? a[0] : '') ?? 9;
      final levelB = int.tryParse(b.isNotEmpty ? b[0] : '') ?? 9;
      if (levelA != levelB) return levelA.compareTo(levelB);
      return a.compareTo(b);
    });
    return list;
  }

  @override
  void initState() {
    super.initState();
    _initEngine();
    if (widget.initialAuctionPath != null && widget.initialAuctionPath!.isNotEmpty) {
      _loadAuctionFromPath(widget.initialAuctionPath!);
    } else {
      _startNewDeal();
    }
  }

  @override
  void didUpdateWidget(covariant PracticeQuizView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAuctionPath != oldWidget.initialAuctionPath &&
        widget.initialAuctionPath != null &&
        widget.initialAuctionPath!.isNotEmpty) {
      _loadAuctionFromPath(widget.initialAuctionPath!);
    } else if (oldWidget.system != widget.system || oldWidget.ewSystem != widget.ewSystem) {
      _initEngine();
      if (_selectedNorthOpening != null && !_availableOpeningBids.contains(_selectedNorthOpening)) {
        _selectedNorthOpening = null;
      }
      _lockedSetupAuction = null;
      _startNewDeal();
    }
  }

  void _initEngine() {
    _engine = AuctionEngine.fromSystem(
      widget.system,
      ewSystem: widget.ewSystem,
      mlEvaluator: MLBidEvaluator(),
    );
    _resolver = _engine.resolver;
  }

  void _startNewDeal() {
    setState(() {
      _submittedBid = null;
      _expectedBestBid = null;
      _allMatches = null;
      _isCorrect = null;
      _lastCorrectFeedback = null;
      _isAuctionComplete = false;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
      _inspectedHistoryIndex = null;

      final hasSouthFilter = _southHcpFilter != SouthHcpFilter.any || _southShapeFilter != SouthShapeFilter.any;
      bool matchesSouth(Hand southHand) {
        return _southHcpFilter.matches(southHand) && _southShapeFilter.matches(southHand);
      }

      // 1. If setup auction is active (either locked in Bid Mode or currently in Setup Mode with bids):
      final setupSequence = _isSetupMode
          ? (_auctionHistory.isNotEmpty ? List<AuctionEntry>.from(_auctionHistory) : null)
          : (_lockedSetupAuction != null && _lockedSetupAuction!.isNotEmpty ? _lockedSetupAuction : null);

      if (setupSequence != null) {
        final seq = _engine.extractSystemSequence(setupSequence);
        if (seq.isNotEmpty) {
          _currentDeal = _generator.dealBoardForSequence(
            seq,
            isNorthDealer: _dealer == DealerSeat.north,
          );
        } else {
          _currentDeal = _generator.dealTargetedBoard(
            isSouthMatch: hasSouthFilter ? matchesSouth : null,
          );
        }

        _auctionHistory.clear();
        _auctionHistory.addAll(setupSequence);

        if (!_isSetupMode) {
          final activeHand = _activeTurnSeat == 'N' ? _currentDeal.north : _currentDeal.south;
          final state = _engine.graph.getState(seq) ?? _engine.graph.rootState;
          _availableCandidates = state.evaluateCandidates(
            activeHand,
            _resolver,
            fragments: _engine.graph.system.fragments,
          );
          _isAuctionComplete = _availableCandidates.isEmpty && seq.isNotEmpty;
          final lastCall = _auctionHistory.isNotEmpty ? _auctionHistory.last.call : 'board';
          _lastCorrectFeedback = 'Your turn to bid ($_activeTurnSeat) over $lastCall.';
        }
        return;
      }

      if (_partnershipFilter == PartnershipHcpFilter.borderlineGameAccept) {
        _currentDeal = _generator.dealMLBorderlineGameDeal(expectAccept: true);
      } else if (_partnershipFilter == PartnershipHcpFilter.borderlineGameDecline) {
        _currentDeal = _generator.dealMLBorderlineGameDeal(expectAccept: false);
      } else if (_partnershipFilter == PartnershipHcpFilter.marginalSlam) {
        _currentDeal = _generator.dealMLMarginalSlamDeal();
      } else if (_partnershipFilter == PartnershipHcpFilter.mlValuationUpgrade) {
        _currentDeal = _generator.dealMLValuationUpgradeDeal();
      } else if (_partnershipFilter == PartnershipHcpFilter.extremeShapeMajor) {
        _currentDeal = _generator.dealExtremeShapeMajorDeal();
      } else if (_dealer == DealerSeat.north) {
        bool matchesNorth(Hand northHand) {
          if (_selectedNorthOpening == null) return northHand.hcp >= 11;
          final bestBid = _engine.graph.rootState.resolveBestBid(
            northHand,
            _resolver,
            fragments: _engine.graph.system.fragments,
          );
          return bestBid != null &&
              bestBid.displayCall.toLowerCase() == _selectedNorthOpening!.toLowerCase();
        }

        _currentDeal = _generator.dealTargetedBoard(
          isNorthMatch: matchesNorth,
          isSouthMatch: hasSouthFilter ? matchesSouth : null,
          isPartnershipMatch: _partnershipFilter != PartnershipHcpFilter.any
              ? (n, s) => _partnershipFilter.matches(n, s, valuation: _engine.resolver.valuation)
              : null,
        );
      } else {
        bool matchesSouthOpening(Hand southHand) {
          if (!matchesSouth(southHand)) return false;
          return southHand.hcp >= 11;
        }

        _currentDeal = _generator.dealTargetedBoard(
          isNorthMatch: null,
          isSouthMatch: matchesSouthOpening,
          isPartnershipMatch: _partnershipFilter != PartnershipHcpFilter.any
              ? (n, s) => _partnershipFilter.matches(n, s, valuation: _engine.resolver.valuation)
              : null,
        );
      }

      final step = _engine.startDeal(
        deal: _currentDeal,
        isNorthFirst: _dealer == DealerSeat.north,
      );

      _auctionHistory.clear();
      _auctionHistory.addAll(step.updatedHistory);
      _availableCandidates = step.nextValidCandidatesForUser;
      _isAuctionComplete = step.isAuctionComplete;
      _lastCorrectFeedback = step.feedbackMessage;
      _lastMlUpgradeBreakdown = step.mlUpgradeBreakdown;
    });
  }

  void _loadUserExampleHand() {
    setState(() {
      _dealer = DealerSeat.south;
      _submittedBid = null;
      _expectedBestBid = null;
      _allMatches = null;
      _isCorrect = null;
      _lastCorrectFeedback = null;
      _isAuctionComplete = false;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;

      final southHand = Hand.fromString('A3:KQ5432:4:K432');
      final randomBoard = _generator.dealFullBoard();
      _currentDeal = PartnershipDeal(
        north: randomBoard.north,
        east: randomBoard.east,
        south: southHand,
        west: randomBoard.west,
      );

      final step = _engine.startDeal(
        deal: _currentDeal,
        isNorthFirst: false,
      );

      _auctionHistory.clear();
      _auctionHistory.addAll(step.updatedHistory);
      _availableCandidates = step.nextValidCandidatesForUser;
      _isAuctionComplete = step.isAuctionComplete;
      _lastMlUpgradeBreakdown = step.mlUpgradeBreakdown;
    });
  }

  Future<void> _showEnterHandDialog() async {
    final customDeal = await EnterHandDialog.show(context, currentDeal: _currentDeal);
    if (customDeal != null) {
      setState(() {
        _submittedBid = null;
        _expectedBestBid = null;
        _allMatches = null;
        _isCorrect = null;
        _lastCorrectFeedback = null;
        _isAuctionComplete = false;
        _lastMlPrediction = null;
        _lastMlUpgradeBreakdown = null;
        _inspectedHistoryIndex = null;
        _currentDeal = customDeal;

        final step = _engine.startDeal(
          deal: _currentDeal,
          isNorthFirst: _dealer == DealerSeat.north,
        );

        _auctionHistory.clear();
        _auctionHistory.addAll(step.updatedHistory);
        _availableCandidates = step.nextValidCandidatesForUser;
        _isAuctionComplete = step.isAuctionComplete;
        _lastCorrectFeedback = step.feedbackMessage;
        _lastMlUpgradeBreakdown = step.mlUpgradeBreakdown;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom deal loaded successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatCallForDisplay(String bid) {
    final lower = bid.trim().toLowerCase();
    if (lower == 'pass') return 'Pass';
    if (lower == 'dbl' || lower == 'x') return 'Dbl';
    if (lower == 'rdbl' || lower == 'xx') return 'Rdbl';
    if (lower.length >= 2) {
      final level = lower[0];
      final suit = lower.substring(1);
      switch (suit) {
        case 'c': return '$level♣';
        case 'd': return '$level♦';
        case 'h': return '$level♥';
        case 's': return '$level♠';
        case 'nt': return '${level}NT';
      }
    }
    return bid.toUpperCase();
  }

  void _onBidSelected(String rawBid) {
    if (_isSetupMode) {
      final displayCall = _formatCallForDisplay(rawBid);
      setState(() {
        final targetIndex = (_selectedCellIndex != null && _selectedCellIndex! < _auctionHistory.length)
            ? _selectedCellIndex!
            : _auctionHistory.length;
        final seqBefore = _engine.extractSystemSequence(_auctionHistory.sublist(0, targetIndex));
        final stateBefore = _engine.graph.getState(seqBefore) ?? _engine.graph.rootState;
        final cleanCall = rawBid.trim().toLowerCase();
        final nodeMatch = stateBefore.candidateNodes.where(
          (n) => _matchesCall(n.call, cleanCall) || _matchesCall(n.displayCall, cleanCall),
        ).toList();
        final autoDesc = nodeMatch.isNotEmpty ? nodeMatch.first.desc : null;
        final autoRule = nodeMatch.isNotEmpty ? nodeMatch.first.rule : null;

        final seat = _selectedEntrySeat;

        if (_selectedCellIndex != null && _selectedCellIndex! < _auctionHistory.length) {
          // Editing existing cell
          _auctionHistory[_selectedCellIndex!] = AuctionEntry(
            seat: seat,
            call: displayCall,
            desc: autoDesc,
            rule: autoRule,
            isAutomatic: false,
          );
          _selectedCellIndex = _selectedCellIndex! + 1;
        } else {
          // Appending to the current turn cell
          _auctionHistory.add(AuctionEntry(
            seat: seat,
            call: displayCall,
            desc: autoDesc,
            rule: autoRule,
            isAutomatic: false,
          ));
          _selectedCellIndex = _auctionHistory.length;
        }
        _submittedBid = null;
        _isCorrect = null;
        _expectedBestBid = null;
        _allMatches = null;

        // When a bid is made there should be a new deal in Panel 1
        final seq = _engine.extractSystemSequence(_auctionHistory);
        if (seq.isNotEmpty) {
          _currentDeal = _generator.dealBoardForSequence(
            seq,
            isNorthDealer: _dealer == DealerSeat.north,
          );
        }
      });
    } else {
      _handleActiveBid(rawBid);
    }
  }

  void _addInitialBid(String seat, String rawBid) {
    final displayCall = _formatCallForDisplay(rawBid);
    setState(() {
      _auctionHistory.add(AuctionEntry(
        seat: seat,
        call: displayCall,
        isAutomatic: false,
      ));
      _submittedBid = null;
      _isCorrect = null;
      _expectedBestBid = null;
      _allMatches = null;
      _lastCorrectFeedback = null;
      _isAuctionComplete = false;
      _selectedCellIndex = _auctionHistory.length;
    });
  }

  void _undoLastBid() {
    if (_auctionHistory.isEmpty) return;
    setState(() {
      _auctionHistory.removeLast();
      _selectedCellIndex = _auctionHistory.length;
      _submittedBid = null;
      _isCorrect = null;
      _expectedBestBid = null;
      _allMatches = null;
      _lastCorrectFeedback = null;
      _isAuctionComplete = false;
    });
  }

  void _clearAuction() {
    setState(() {
      _lockedSetupAuction = null;
      _auctionHistory.clear();
      _selectedCellIndex = null;
      _submittedBid = null;
      _isCorrect = null;
      _expectedBestBid = null;
      _allMatches = null;
      _lastCorrectFeedback = null;
      _isAuctionComplete = false;
      _availableCandidates = [];
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
      _inspectedHistoryIndex = null;
    });
    widget.onClearPracticeAuction?.call();
    if (!_isSetupMode) {
      _startNewDeal();
    }
  }

  void _removeBidAtIndex(int index) {
    if (index < 0 || index >= _auctionHistory.length) return;
    setState(() {
      _auctionHistory.removeAt(index);
      final dealerIdx = _seatOrder.indexOf(_dealer.code);
      for (int i = 0; i < _auctionHistory.length; i++) {
        final expectedSeat = _seatOrder[(dealerIdx + i) % 4];
        if (_auctionHistory[i].seat != expectedSeat) {
          _auctionHistory[i] = AuctionEntry(
            seat: expectedSeat,
            call: _auctionHistory[i].call,
            desc: _auctionHistory[i].desc,
            rule: _auctionHistory[i].rule,
            isAutomatic: _auctionHistory[i].isAutomatic,
          );
        }
      }
      _selectedCellIndex = _auctionHistory.length;
      _submittedBid = null;
      _isCorrect = null;
      _expectedBestBid = null;
      _allMatches = null;
      _lastCorrectFeedback = null;
      _isAuctionComplete = false;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
    });
  }

  void _switchToSetupMode({bool clearHistory = false}) {
    setState(() {
      _isSetupMode = true;
      if (clearHistory) {
        _auctionHistory.clear();
        _selectedCellIndex = 0;
      } else {
        _selectedCellIndex = _auctionHistory.length;
      }
      _submittedBid = null;
      _isCorrect = null;
      _expectedBestBid = null;
      _allMatches = null;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
      _inspectedHistoryIndex = null;
    });
  }

  void _switchToBidMode() {
    setState(() {
      _isSetupMode = false;
      _lockedSetupAuction = _auctionHistory.isNotEmpty ? List<AuctionEntry>.from(_auctionHistory) : null;
      _selectedCellIndex = null;
      _submittedBid = null;
      _expectedBestBid = null;
      _allMatches = null;
      _isCorrect = null;
      _isAuctionComplete = false;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
      _inspectedHistoryIndex = null;

      final seq = _engine.extractSystemSequence(_auctionHistory);
      if (seq.isNotEmpty) {
        _currentDeal = _generator.dealBoardForSequence(
          seq,
          isNorthDealer: _dealer == DealerSeat.north,
        );
      }

      final activeHand = _activeTurnSeat == 'N' ? _currentDeal.north : _currentDeal.south;
      final state = _engine.graph.getState(seq) ?? _engine.graph.rootState;
      _availableCandidates = state.evaluateCandidates(
        activeHand,
        _resolver,
        fragments: _engine.graph.system.fragments,
      );

      final lastCall = _auctionHistory.isNotEmpty ? _auctionHistory.last.call : 'board';
      _lastCorrectFeedback = 'Your turn to bid ($_activeTurnSeat) over $lastCall.';
    });
  }

  void _loadPreset(AuctionPreset preset) {
    setState(() {
      _dealer = preset.dealer;
      _auctionHistory.clear();
      _auctionHistory.addAll(preset.calls);
      _lockedSetupAuction = List<AuctionEntry>.from(preset.calls);
      _selectedCellIndex = null;
      _isSetupMode = false;
      _submittedBid = null;
      _expectedBestBid = null;
      _allMatches = null;
      _isCorrect = null;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
      _inspectedHistoryIndex = null;

      final seq = _engine.extractSystemSequence(_auctionHistory);
      _currentDeal = _generator.dealBoardForSequence(
        seq,
        isNorthDealer: _dealer == DealerSeat.north,
      );

      final activeHand = _activeTurnSeat == 'N' ? _currentDeal.north : _currentDeal.south;
      final state = _engine.graph.getState(seq) ?? _engine.graph.rootState;
      _availableCandidates = state.evaluateCandidates(
        activeHand,
        _resolver,
        fragments: _engine.graph.system.fragments,
      );
      _isAuctionComplete = _availableCandidates.isEmpty && seq.isNotEmpty;
      _lastCorrectFeedback = 'Loaded preset: ${preset.label}. Bidding for $_activeTurnSeat.';
    });
  }

  void _loadAuctionFromPath(List<BiddingNode> path) {
    if (path.isEmpty) return;

    final List<AuctionEntry> entries = [];
    DealerSeat calculatedDealer = DealerSeat.north;

    final firstIsOpp = path.first.isOpponent || path.first.call.startsWith('(');
    if (firstIsOpp) {
      calculatedDealer = DealerSeat.east;
      entries.add(AuctionEntry(
        seat: 'E',
        call: _formatCallForDisplay(path.first.displayCall),
        desc: path.first.desc.isNotEmpty ? path.first.desc : 'Opponent opening',
        rule: path.first.rule,
        isAutomatic: true,
      ));
      String currentSeat = 'S';
      for (int i = 1; i < path.length; i++) {
        final node = path[i];
        entries.add(AuctionEntry(
          seat: currentSeat,
          call: _formatCallForDisplay(node.displayCall),
          desc: node.desc,
          rule: node.rule,
          isAutomatic: false,
        ));
        currentSeat = _seatOrder[(_seatOrder.indexOf(currentSeat) + 1) % 4];
      }
    } else {
      calculatedDealer = DealerSeat.north;
      int pathIdx = 0;
      String currentSeat = 'N';

      while (pathIdx < path.length) {
        final node = path[pathIdx];

        if (currentSeat == 'N') {
          entries.add(AuctionEntry(
            seat: 'N',
            call: _formatCallForDisplay(node.displayCall),
            desc: node.desc.isNotEmpty ? node.desc : 'Opening bid',
            rule: node.rule,
            isAutomatic: false,
          ));
          pathIdx++;
          currentSeat = 'E';
        } else if (currentSeat == 'E') {
          if (pathIdx < path.length && (path[pathIdx].isOpponent || path[pathIdx].call.startsWith('('))) {
            final oppNode = path[pathIdx];
            entries.add(AuctionEntry(
              seat: 'E',
              call: _formatCallForDisplay(oppNode.displayCall),
              desc: oppNode.desc.isNotEmpty ? oppNode.desc : 'Opposition intervention',
              rule: oppNode.rule,
              isAutomatic: true,
            ));
            pathIdx++;
          } else {
            entries.add(const AuctionEntry(
              seat: 'E',
              call: 'Pass',
              desc: 'Pass',
              isAutomatic: true,
            ));
          }
          currentSeat = 'S';
        } else if (currentSeat == 'S') {
          entries.add(AuctionEntry(
            seat: 'S',
            call: _formatCallForDisplay(node.displayCall),
            desc: node.desc,
            rule: node.rule,
            isAutomatic: false,
          ));
          pathIdx++;
          currentSeat = 'W';
        } else if (currentSeat == 'W') {
          if (pathIdx < path.length && (path[pathIdx].isOpponent || path[pathIdx].call.startsWith('('))) {
            final oppNode = path[pathIdx];
            entries.add(AuctionEntry(
              seat: 'W',
              call: _formatCallForDisplay(oppNode.displayCall),
              desc: oppNode.desc.isNotEmpty ? oppNode.desc : 'Opposition intervention',
              rule: oppNode.rule,
              isAutomatic: true,
            ));
            pathIdx++;
          } else {
            entries.add(const AuctionEntry(
              seat: 'W',
              call: 'Pass',
              desc: 'Pass',
              isAutomatic: true,
            ));
          }
          currentSeat = 'N';
        }
      }

      if (entries.isNotEmpty && entries.last.seat == 'N') {
        entries.add(const AuctionEntry(
          seat: 'E',
          call: 'Pass',
          desc: 'Pass',
          isAutomatic: true,
        ));
      } else if (entries.isNotEmpty && entries.last.seat == 'S') {
        entries.add(const AuctionEntry(
          seat: 'W',
          call: 'Pass',
          desc: 'Pass',
          isAutomatic: true,
        ));
      }
    }

    setState(() {
      _dealer = calculatedDealer;
      _auctionHistory.clear();
      _auctionHistory.addAll(entries);
      _lockedSetupAuction = List<AuctionEntry>.from(entries);
      _selectedCellIndex = null;
      _isSetupMode = false;
      _submittedBid = null;
      _expectedBestBid = null;
      _allMatches = null;
      _isCorrect = null;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
      _inspectedHistoryIndex = null;

      final seq = _engine.extractSystemSequence(_auctionHistory);
      _currentDeal = _generator.dealBoardForSequence(
        seq,
        isNorthDealer: _dealer == DealerSeat.north,
      );

      final activeHand = _activeTurnSeat == 'N' ? _currentDeal.north : _currentDeal.south;
      final state = _engine.graph.getState(seq) ?? _engine.graph.rootState;
      _availableCandidates = state.evaluateCandidates(
        activeHand,
        _resolver,
        fragments: _engine.graph.system.fragments,
      );
      _isAuctionComplete = _availableCandidates.isEmpty && seq.isNotEmpty;
      final lastFriendly = entries.lastWhere((e) => e.call.toLowerCase() != 'pass', orElse: () => entries.last);
      _lastCorrectFeedback = 'Practice auction from Explorer loaded. Bidding for $_activeTurnSeat over ${lastFriendly.call}.';
    });
  }

  static bool _matchesCall(String a, String b) {
    String norm(String s) => s.trim().toLowerCase()
        .replaceAll('♣', 'c')
        .replaceAll('♦', 'd')
        .replaceAll('♥', 'h')
        .replaceAll('♠', 's');
    final nA = norm(a);
    final nB = norm(b);
    if (nA == nB) return true;
    if ((nA == 'pass' && nB == 'p') || (nA == 'p' && nB == 'pass')) return true;
    if ((nA == 'dbl' && (nB == 'x' || nB == 'double')) || (nB == 'dbl' && (nA == 'x' || nA == 'double'))) return true;
    if ((nA == 'rdbl' && (nB == 'xx' || nB == 'redouble')) || (nB == 'rdbl' && (nA == 'xx' || nA == 'redouble'))) return true;
    return false;
  }

  BidDescription _resolveBidDescription(String rawCall) {
    final cleanCall = rawCall.trim().toLowerCase();

    // 1. Check in _availableCandidates for current active turn
    final candMatch = _availableCandidates.where(
      (c) => !c.isOpponent && (_matchesCall(c.call, cleanCall) || _matchesCall(c.displayCall, cleanCall)),
    ).toList();
    if (candMatch.isNotEmpty) {
      final c = candMatch.first;
      return BidDescription(
        call: c.call,
        displayCall: _formatCallForDisplay(c.displayCall),
        description: c.desc.isNotEmpty ? c.desc : 'System call',
        rule: c.rule,
      );
    }

    // 2. Query CompiledBiddingGraph at current auction sequence
    final currentSeq = _engine.extractSystemSequence(_auctionHistory);
    final state = _engine.graph.getState(currentSeq) ?? _engine.graph.rootState;
    final nodeMatch = state.candidateNodes.where(
      (n) => !n.isOpponent && (_matchesCall(n.call, cleanCall) || _matchesCall(n.displayCall, cleanCall)),
    ).toList();
    if (nodeMatch.isNotEmpty) {
      final n = nodeMatch.first;
      return BidDescription(
        call: n.call,
        displayCall: _formatCallForDisplay(n.displayCall),
        description: n.desc.isNotEmpty ? n.desc : 'System convention bid',
        rule: n.rule,
      );
    }

    // 3. Fallback natural / standard bridge descriptions:
    final display = _formatCallForDisplay(rawCall);
    if (_matchesCall(cleanCall, 'pass')) {
      return const BidDescription(
        call: 'pass',
        displayCall: 'Pass',
        description: 'Pass (no bid / no system action)',
      );
    }
    if (_matchesCall(cleanCall, 'dbl') || cleanCall == 'x') {
      return const BidDescription(
        call: 'dbl',
        displayCall: 'Dbl',
        description: 'Takeout / Penalty Double',
      );
    }
    if (_matchesCall(cleanCall, 'rdbl') || cleanCall == 'xx') {
      return const BidDescription(
        call: 'rdbl',
        displayCall: 'Rdbl',
        description: 'Redouble (Values / SOS)',
      );
    }

    return BidDescription(
      call: rawCall,
      displayCall: display,
      description: 'Natural bid $display',
    );
  }

  BidDescription _resolveBidDescriptionForHistory(int historyIndex) {
    if (historyIndex < 0 || historyIndex >= _auctionHistory.length) {
      return _resolveBidDescription('');
    }
    final entry = _auctionHistory[historyIndex];
    if (entry.desc != null && entry.desc!.trim().isNotEmpty) {
      return BidDescription(
        call: entry.call,
        displayCall: _formatCallForDisplay(entry.call),
        description: entry.desc!,
        rule: entry.rule,
      );
    }

    final seqBefore = _engine.extractSystemSequence(_auctionHistory.sublist(0, historyIndex));
    final state = _engine.graph.getState(seqBefore) ?? _engine.graph.rootState;
    final cleanCall = entry.call.trim().toLowerCase();
    final isEntryOpponent = (entry.seat.toUpperCase() == 'E' || entry.seat.toUpperCase() == 'W');
    final nodeMatch = state.candidateNodes.where(
      (n) => n.isOpponent == isEntryOpponent && (_matchesCall(n.call, cleanCall) || _matchesCall(n.displayCall, cleanCall)),
    ).toList();
    if (nodeMatch.isNotEmpty) {
      final n = nodeMatch.first;
      return BidDescription(
        call: n.call,
        displayCall: _formatCallForDisplay(n.displayCall),
        description: n.desc.isNotEmpty ? n.desc : 'System convention bid',
        rule: n.rule,
      );
    }

    return _resolveBidDescription(entry.call);
  }

  Widget _buildInspectedBidCard(AuctionEntry entry) {
    String seatLabel = entry.seat;
    switch (entry.seat.toUpperCase()) {
      case 'N':
        seatLabel = _dealer == DealerSeat.north ? 'North (Dealer / Partner)' : 'North (Partner)';
        break;
      case 'S':
        seatLabel = _dealer == DealerSeat.south ? 'South (Dealer / You)' : 'South (You)';
        break;
      case 'E':
        seatLabel = _dealer == DealerSeat.east ? 'East (Dealer / Opponent)' : 'East (Opponent)';
        break;
      case 'W':
        seatLabel = _dealer == DealerSeat.west ? 'West (Dealer / Opponent)' : 'West (Opponent)';
        break;
    }

    final info = _inspectedHistoryIndex != null
        ? _resolveBidDescriptionForHistory(_inspectedHistoryIndex!)
        : _resolveBidDescription(entry.call);
    final displayCall = info.displayCall;
    final desc = info.description;
    final rule = info.rule;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C5FD), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.05),
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
              const Icon(Icons.info_outline, size: 18, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$seatLabel: $displayCall',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.blueGrey),
                tooltip: 'Close description',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _inspectedHistoryIndex = null;
                    if (_isSetupMode) {
                      _selectedCellIndex = _auctionHistory.length;
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          ),
          if (rule != null && rule.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                'Rule: $rule',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF1E3A8A)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Active player's turn (North or South): delegates evaluation and multi-turn progression to the AuctionEngine!
  void _handleActiveBid(String bid) {
    if (_submittedBid != null || _isAuctionComplete) return;

    final activeSeat = _activeTurnSeat;
    final step = _engine.advanceAuction(
      history: _auctionHistory,
      userCall: bid,
      deal: _currentDeal,
      activeSeat: activeSeat,
    );

    setState(() {
      _totalAttempts++;
      _submittedBid = bid;
      _isCorrect = step.isUserBidCorrect;
      _expectedBestBid = step.expectedBestBid;
      _allMatches = step.allEvaluatedMatches;
      _lastMlPrediction = step.mlPrediction;
      _lastMlUpgradeBreakdown = step.mlUpgradeBreakdown;

      if (step.isUserBidCorrect) {
        _correctCount++;
        _auctionHistory.clear();
        _auctionHistory.addAll(step.updatedHistory);
        _isAuctionComplete = step.isAuctionComplete;
        _lastCorrectFeedback = step.feedbackMessage;
        _availableCandidates = step.nextValidCandidatesForUser;

        // If auction continues, reset input state so active player can bid immediately!
        if (!_isAuctionComplete) {
          _submittedBid = null;
          _isCorrect = null;
          _expectedBestBid = null;
          _allMatches = null;
        }
      } else {
        _lastCorrectFeedback = null;
      }
    });
  }

  void _retryCurrentBid() {
    setState(() {
      _submittedBid = null;
      _expectedBestBid = null;
      _allMatches = null;
      _isCorrect = null;
      _lastMlPrediction = null;
      _lastMlUpgradeBreakdown = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = _totalAttempts > 0 ? ((_correctCount / _totalAttempts) * 100).toStringAsFixed(0) : '0';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Control Bar
              _buildTopControlBar(theme, accuracy),
              const SizedBox(height: 14),

              // Main Area: 2-Column layout on wide screens
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _buildPanel1Hands(theme),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 6,
                      child: _buildRightPanelAuctionAndBidding(theme),
                    ),
                  ],
                )
              else ...[
                _buildPanel1Hands(theme),
                const SizedBox(height: 14),
                _buildRightPanelAuctionAndBidding(theme),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopControlBar(ThemeData theme, String accuracy) {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.psychology, color: Colors.amberAccent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B5E20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('NS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.system.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D47A1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('EW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.ewSystem?.name ?? 'Standard Opposition (Auto-Pass)',
                          style: TextStyle(
                            color: Colors.grey.shade300,
                            fontSize: 11.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.lightGreenAccent,
                side: const BorderSide(color: Colors.lightGreenAccent),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.flash_on, size: 16),
              label: const Text('Test Hand'),
              onPressed: _loadUserExampleHand,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.lightBlueAccent,
                side: const BorderSide(color: Colors.lightBlueAccent),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.file_download, size: 16),
              label: const Text('Export Board'),
              onPressed: () => _showExportBoardDialog(context),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Score: $_correctCount/$_totalAttempts ($accuracy%)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel1Hands(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel 1 Header
        Card(
          elevation: 1,
          color: const Color(0xFFE8F5E9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFA5D6A7)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.style, color: Color(0xFF1B5E20), size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Panel 1: North & South Hands',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1B5E20)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<PartnershipHcpFilter>(
                  tooltip: 'Partnership HCP Filter (ML Edge Practice)',
                  icon: Icon(
                    Icons.tune,
                    size: 18,
                    color: _partnershipFilter != PartnershipHcpFilter.any
                        ? const Color(0xFF0284C7)
                        : const Color(0xFF1B5E20),
                  ),
                  initialValue: _partnershipFilter,
                  onSelected: (filter) {
                    setState(() {
                      _partnershipFilter = filter;
                    });
                    _startNewDeal();
                  },
                  itemBuilder: (context) => PartnershipHcpFilter.values.map((f) {
                    return PopupMenuItem<PartnershipHcpFilter>(
                      value: f,
                      child: Row(
                        children: [
                          Icon(
                            f == _partnershipFilter ? Icons.check : Icons.circle_outlined,
                            size: 14,
                            color: f == _partnershipFilter ? Colors.blue : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(f.label, style: const TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('Enter Hand'),
                  onPressed: _showEnterHandDialog,
                ),
                const SizedBox(width: 4),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Redeal'),
                  onPressed: _startNewDeal,
                ),
              ],
            ),
          ),
        ),
        if (_partnershipFilter != PartnershipHcpFilter.any) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF7DD3FC)),
            ),
            child: Row(
              children: [
                const Icon(Icons.smart_toy, size: 15, color: Color(0xFF0369A1)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Targeted ML Practice: ${_partnershipFilter.label}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _partnershipFilter = PartnershipHcpFilter.any;
                    });
                    _startNewDeal();
                  },
                  child: const Icon(Icons.close, size: 16, color: Color(0xFF0369A1)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),

        // North Hand
        CardHandWidget(
          hand: _currentDeal.north,
          title: _activeTurnSeat == 'N' ? 'Your Hand (North)' : 'Partner Hand (North)',
          icon: _activeTurnSeat == 'N' ? Icons.person : Icons.support_agent,
          headerColor: _activeTurnSeat == 'N' ? const Color(0xFF1B5E20) : const Color(0xFF1565C0),
          isCollapsible: _activeTurnSeat != 'N',
          initiallyCollapsed: _activeTurnSeat != 'N' && !_showNorthHand,
          onRedeal: _activeTurnSeat == 'N' ? _startNewDeal : null,
          mlBreakdown: MLHandValuation().evaluateBreakdown(_currentDeal.north),
        ),
        const SizedBox(height: 10),

        // South Hand
        CardHandWidget(
          hand: _currentDeal.south,
          title: _activeTurnSeat == 'S' ? 'Your Hand (South)' : 'Partner Hand (South)',
          icon: _activeTurnSeat == 'S' ? Icons.person : Icons.support_agent,
          headerColor: _activeTurnSeat == 'S' ? const Color(0xFF1B5E20) : const Color(0xFF1565C0),
          isCollapsible: _activeTurnSeat != 'S',
          initiallyCollapsed: _activeTurnSeat != 'S' && !_showNorthHand,
          onRedeal: _activeTurnSeat == 'S' ? _startNewDeal : null,
          mlBreakdown: MLHandValuation().evaluateBreakdown(_currentDeal.south),
          filterBadge: (_southHcpFilter != SouthHcpFilter.any || _southShapeFilter != SouthShapeFilter.any)
              ? [
                  if (_southHcpFilter != SouthHcpFilter.any) _southHcpFilter.label,
                  if (_southShapeFilter != SouthShapeFilter.any) _southShapeFilter.label,
                ].join(' • ')
              : null,
        ),
      ],
    );
  }

  Widget _buildRightPanelAuctionAndBidding(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Presets & Quick Scenarios Bar
        _buildPresetsBar(theme),
        const SizedBox(height: 10),

        // Live Auction Board (Panel 2)
        _buildAuctionTable(theme),
        const SizedBox(height: 10),

        // ML Hand Valuation & Dynamic Upgrade/Downgrade Card
        if (_lastMlUpgradeBreakdown != null && (_lastMlUpgradeBreakdown!.isUpgraded || _lastMlUpgradeBreakdown!.isDowngraded)) ...[
          _buildMlUpgradeCard(theme),
          const SizedBox(height: 10),
        ],

        // ML Edge-Case Prediction Card (if borderline invitation/slam evaluated)
        if (_lastMlPrediction != null) ...[
          _buildMlPredictionCard(theme),
          const SizedBox(height: 10),
        ],

        // Auction Completed Banner
        if (_isAuctionComplete) ...[
          _buildAuctionCompleteCard(theme),
          const SizedBox(height: 10),
        ],

        // Success / Progress Banner if Auction Continued
        if (_lastCorrectFeedback != null && !_isAuctionComplete && _isCorrect == null) ...[
          _buildSuccessBanner(theme),
          const SizedBox(height: 10),
        ],

        // Error Diagnostic Card if Active Bid Was Incorrect
        if (_isCorrect == false) ...[
          _buildErrorFeedbackCard(theme),
          const SizedBox(height: 10),
        ],

        // Panel 3: Bidding Box (Positioned directly below the Live Auction Board)
        _buildPanel3BiddingBox(theme),
      ],
    );
  }

  Widget _buildPresetsBar(ThemeData theme) {
    return Card(
      elevation: 1,
      color: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_lockedSetupAuction != null) ...[
              Builder(
                builder: (context) {
                  final activeSeatName = _activeTurnSeat == 'S'
                      ? 'South'
                      : (_activeTurnSeat == 'N'
                          ? 'North'
                          : (_activeTurnSeat == 'E' ? 'East' : 'West'));
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.explore, size: 16, color: Color(0xFF16A34A)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Practicing from Bidding Explorer: ${_lockedSetupAuction!.map((e) => "${e.seat}: ${e.call}").join(" → ")} ($activeSeatName to bid)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _clearAuction,
                          child: const Tooltip(
                            message: 'Exit Explorer Practice & Reset Auction',
                            child: Icon(Icons.close, size: 16, color: Color(0xFF16A34A)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            Row(
              children: [
                const Icon(Icons.flash_on, size: 16, color: Color(0xFF0284C7)),
                const SizedBox(width: 6),
                const Text(
                  'Quick Practice Scenarios:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0F172A)),
                ),
                const Spacer(),
                if (_auctionHistory.isNotEmpty || _lockedSetupAuction != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.clear_all, size: 15),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                    onPressed: _clearAuction,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _presets.map((preset) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.play_circle_outline, size: 16, color: Color(0xFF0284C7)),
                      label: Text(preset.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      tooltip: preset.description,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFBAE6FD)),
                      onPressed: () => _loadPreset(preset),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_lastCorrectFeedback Partner rebid automatically. Your turn again!',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20), fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMlPredictionCard(ThemeData theme) {
    if (_lastMlPrediction == null) return const SizedBox.shrink();
    final p = _lastMlPrediction!;
    final isAccept = p.shouldAcceptInvite;
    final probPercent = (p.probMaking * 100).toStringAsFixed(0);
    final surplus = p.expectedResult >= 0
        ? '+${p.expectedResult.toStringAsFixed(2)}'
        : p.expectedResult.toStringAsFixed(2);
    final combHcp = _currentDeal.north.hcp + _currentDeal.south.hcp;
    final combControls = _currentDeal.north.controls + _currentDeal.south.controls;
    final combLtc = _currentDeal.north.losingTrickCount + _currentDeal.south.losingTrickCount;

    return Card(
      elevation: 2,
      color: isAccept ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAccept ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.smart_toy,
                  size: 20,
                  color: isAccept ? const Color(0xFF15803D) : const Color(0xFFB45309),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🤖 Gavin Wolpert ML Edge Model (13,975 BBO Deals)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isAccept ? const Color(0xFF166534) : const Color(0xFF92400E),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isAccept ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isAccept ? 'ACCEPT GAME' : 'DECLINE / PASS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isAccept ? const Color(0xFF15803D) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isAccept
                  ? 'ML evaluates this borderline invitation as favorable with $probPercent% make probability ($surplus expected surplus tricks).'
                  : 'ML evaluates this borderline invitation conservatively ($probPercent% make chance, $surplus expected surplus tricks).',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isAccept ? const Color(0xFF14532D) : const Color(0xFF78350F),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildMlMetricChip('Combined HCP', '$combHcp HCP'),
                _buildMlMetricChip('Controls (A=2,K=1)', '$combControls ctrl'),
                _buildMlMetricChip('Combined LTC', '$combLtc LTC'),
                _buildMlMetricChip('Tree Node Support', '${p.samples} deals'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMlMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black87),
      ),
    );
  }

  Widget _buildMlUpgradeCard(ThemeData theme) {
    if (_lastMlUpgradeBreakdown == null) return const SizedBox.shrink();
    final b = _lastMlUpgradeBreakdown!;
    if (!b.isUpgraded && !b.isDowngraded) return const SizedBox.shrink();

    final isUp = b.isUpgraded;
    final sign = b.netDelta >= 0 ? '+' : '';
    final deltaStr = '$sign${b.netDelta.toStringAsFixed(1)} HCP';

    return Card(
      elevation: 2,
      color: isUp ? const Color(0xFFF5F3FF) : const Color(0xFFFFFBEB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isUp ? const Color(0xFFC4B5FD) : const Color(0xFFFDE68A),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUp ? Icons.auto_awesome : Icons.trending_down,
                  size: 20,
                  color: isUp ? const Color(0xFF6D28D9) : const Color(0xFFB45309),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🤖 ML Hand Valuation & Upgrade Breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isUp ? const Color(0xFF5B21B6) : const Color(0xFF92400E),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isUp ? const Color(0xFFDDD6FE) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isUp ? '🚀 ML UPGRADE ($deltaStr)' : '⚠️ ML DOWNGRADE ($deltaStr)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isUp ? const Color(0xFF5B21B6) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Valuation dynamically adjusted from ${b.rawHcp.toStringAsFixed(0)} raw HCP to ${b.effectiveHcp.toStringAsFixed(1)} effective HCP.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isUp ? const Color(0xFF4C1D95) : const Color(0xFF78350F),
              ),
            ),
            if (b.reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: b.reasons.map((r) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isUp ? const Color(0xFFDDD6FE) : const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    r,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isUp ? const Color(0xFF4C1D95) : const Color(0xFF78350F),
                    ),
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuctionCompleteCard(ThemeData theme) {
    return Card(
      color: const Color(0xFFE8F5E9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF81C784), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.emoji_events, color: Color(0xFF2E7D32), size: 30),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auction Complete! Contract Reached.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B5E20)),
                  ),
                  SizedBox(height: 2),
                  Text('All bidding rounds finished in accordance with the system definition.', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('New Deal'),
              onPressed: _startNewDeal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuctionTable(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.table_restaurant, color: Color(0xFF0D47A1), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Panel 2: Bidding So Far',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF0D47A1)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _isSetupMode
                        ? Colors.amber.shade100
                        : (_lockedSetupAuction != null ? Colors.blue.shade100 : Colors.green.shade100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isSetupMode ? '🛠️ Setup Mode' : '🎯 Bid Mode (Fixed Auction)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _isSetupMode ? Colors.amber.shade900 : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _isSetupMode
                  ? 'Live Auction Board • Dealer: ${_dealer.name.toUpperCase()} • 💡 Tip: Click any cell to edit'
                  : 'Live Auction Board • Dealer: ${_dealer.name.toUpperCase()} (Bids for North, East & West are fixed)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Table(
                border: TableBorder.symmetric(inside: BorderSide(color: Colors.grey.shade300)),
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFE2E8F0)),
                    children: [
                      _buildHeaderCell('West', DealerSeat.west, isYou: false, isPartner: false),
                      _buildHeaderCell('North', DealerSeat.north, isYou: _activeTurnSeat == 'N', isPartner: _activeTurnSeat != 'N'),
                      _buildHeaderCell('East', DealerSeat.east, isYou: false, isPartner: false),
                      _buildHeaderCell('South', DealerSeat.south, isYou: _activeTurnSeat == 'S', isPartner: _activeTurnSeat != 'S'),
                    ],
                  ),
                  ..._buildAuctionRows(),
                ],
              ),
            ),
            if (_inspectedHistoryIndex != null && _inspectedHistoryIndex! < _auctionHistory.length)
              _buildInspectedBidCard(_auctionHistory[_inspectedHistoryIndex!]),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String seatName, DealerSeat seatEnum, {required bool isYou, required bool isPartner}) {
    final isDealer = _dealer == seatEnum;
    final seatCode = seatEnum.code;
    final isSelectedCol = _isSetupMode && _selectedEntrySeat == seatCode;
    final hasFilter = (seatCode == 'S') && (_southHcpFilter != SouthHcpFilter.any || _southShapeFilter != SouthShapeFilter.any);

    String label = seatName;
    if (isYou) {
      label = '$seatName (You)';
    } else if (seatName == 'North' || seatName == 'South') {
      label = '$seatName (Partner)';
    }

    return InkWell(
      onTap: _isSetupMode
          ? () {
              setState(() {
                _dealer = seatEnum;
                _selectedCellIndex = _auctionHistory.length;
                final dealerIdx = _seatOrder.indexOf(_dealer.code);
                for (int i = 0; i < _auctionHistory.length; i++) {
                  final expectedSeat = _seatOrder[(dealerIdx + i) % 4];
                  if (_auctionHistory[i].seat != expectedSeat) {
                    _auctionHistory[i] = AuctionEntry(
                      seat: expectedSeat,
                      call: _auctionHistory[i].call,
                      desc: _auctionHistory[i].desc,
                      rule: _auctionHistory[i].rule,
                      isAutomatic: _auctionHistory[i].isAutomatic,
                    );
                  }
                }
              });
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelectedCol
              ? Colors.amber.shade100
              : isDealer
                  ? const Color(0xFFFFFBEB)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isDealer
              ? Border.all(color: Colors.amber.shade700, width: 1.5)
              : isSelectedCol
                  ? Border.all(color: Colors.amber.shade500, width: 1.2)
                  : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isDealer) ...[
                  const Text('👑', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 2),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: isYou ? const Color(0xFF1B5E20) : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (seatCode == 'S') ...[
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => _showSouthFilterDialog(context),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.tune,
                        size: 14,
                        color: hasFilter ? Colors.purple : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (isDealer)
              Text(
                'Dealer',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
              ),
            if (hasFilter)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Text(
                  [
                    if (_southHcpFilter != SouthHcpFilter.any) _southHcpFilter.label,
                    if (_southShapeFilter != SouthShapeFilter.any) _southShapeFilter.label,
                  ].join(', '),
                  style: TextStyle(fontSize: 9.5, color: Colors.purple.shade900, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSouthFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.purple),
                  SizedBox(width: 8),
                  Text('South Hand Filters', style: TextStyle(fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('HCP Range:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<SouthHcpFilter>(
                    value: _southHcpFilter,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: SouthHcpFilter.values.map((f) => DropdownMenuItem(
                      value: f,
                      child: Text(f.label),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => _southHcpFilter = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Hand Shape:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<SouthShapeFilter>(
                    value: _southShapeFilter,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: SouthShapeFilter.values.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.label),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => _southShapeFilter = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                if (_southHcpFilter != SouthHcpFilter.any || _southShapeFilter != SouthShapeFilter.any)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _southHcpFilter = SouthHcpFilter.any;
                        _southShapeFilter = SouthShapeFilter.any;
                        _startNewDeal();
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
                  ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _startNewDeal();
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply & Redeal'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<TableRow> _buildAuctionRows() {
    final List<TableRow> rows = [];
    final dealerOffset = switch (_dealer) {
      DealerSeat.west => 0,
      DealerSeat.north => 1,
      DealerSeat.east => 2,
      DealerSeat.south => 3,
    };

    final totalHistory = _auctionHistory.length;
    final needsNextTurnSlot = !_isAuctionComplete || _isSetupMode;
    final totalSlotsNeeded = dealerOffset + totalHistory + (needsNextTurnSlot ? 1 : 0);
    final rowCount = ((totalSlotsNeeded + 3) ~/ 4).clamp(2, 20);

    for (int r = 0; r < rowCount; r++) {
      final List<Widget> rowCells = [];
      for (int c = 0; c < 4; c++) {
        final gridIndex = r * 4 + c;
        final colSeat = const ['W', 'N', 'E', 'S'][c];

        if (gridIndex < dealerOffset) {
          rowCells.add(_buildCellContainer(
            text: '—',
            textColor: Colors.grey.shade400,
            bgColor: Colors.transparent,
          ));
        } else {
          final historyIndex = gridIndex - dealerOffset;
          if (historyIndex < totalHistory) {
            final entry = _auctionHistory[historyIndex];
            final isSelected = _selectedCellIndex == historyIndex;

            rowCells.add(_buildClickableCell(
              text: entry.call,
              historyIndex: historyIndex,
              seat: entry.seat,
              isSelected: isSelected,
              isCall: true,
            ));
          } else if (historyIndex == totalHistory && needsNextTurnSlot) {
            final isSelected = _selectedCellIndex == historyIndex;
            final isUser = _activeTurnSeat == 'S' || _activeTurnSeat == 'N';
            final text = _isSetupMode
                ? '[$colSeat next]'
                : (isUser ? '? (Your Turn)' : '? ($_activeTurnSeat to bid)');

            rowCells.add(_buildClickableCell(
              text: text,
              historyIndex: historyIndex,
              seat: _isSetupMode ? colSeat : _activeTurnSeat,
              isSelected: isSelected,
              isTurnPrompt: true,
            ));
          } else {
            rowCells.add(_buildCellContainer(
              text: '',
              textColor: Colors.transparent,
              bgColor: Colors.transparent,
            ));
          }
        }
      }
      rows.add(TableRow(children: rowCells));
    }

    return rows;
  }

  Widget _buildClickableCell({
    required String text,
    required int historyIndex,
    required String seat,
    required bool isSelected,
    bool isCall = false,
    bool isTurnPrompt = false,
  }) {
    Color bgColor = Colors.transparent;
    Color textColor = Colors.black87;
    Border? border;

    final isInspected = _inspectedHistoryIndex == historyIndex && isCall;

    if (isSelected) {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFF92400E);
      border = Border.all(color: const Color(0xFFF59E0B), width: 2);
    } else if (isInspected) {
      bgColor = const Color(0xFFDBEAFE);
      textColor = const Color(0xFF1E40AF);
      border = Border.all(color: const Color(0xFF2563EB), width: 2);
    } else if (isTurnPrompt) {
      bgColor = _isSetupMode ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7);
      textColor = _isSetupMode ? const Color(0xFF0369A1) : const Color(0xFFB45309);
    }

    return InkWell(
      onTap: () {
        if (_isSetupMode) {
          setState(() {
            _selectedCellIndex = historyIndex;
            if (isCall) {
              _inspectedHistoryIndex = historyIndex;
            }
          });
        } else if (isCall) {
          setState(() {
            if (_inspectedHistoryIndex == historyIndex) {
              _inspectedHistoryIndex = null;
            } else {
              _inspectedHistoryIndex = historyIndex;
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          border: border,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: (isSelected || isTurnPrompt || isInspected) ? FontWeight.bold : FontWeight.w600,
              fontSize: 13,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCellContainer({
    required String text,
    required Color textColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      color: bgColor,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildPanel3BiddingBox(ThemeData theme) {
    final activeSeatDisplay = _activeTurnSeat == 'S' ? 'South' : 'North';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Panel 3 Header with Mode Selector
            Row(
              children: [
                const Icon(Icons.dashboard_customize, color: Color(0xFFE65100), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Panel 3: Bidding Box',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFFE65100)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SegmentedButton<bool>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.tune, size: 15),
                      label: Text('Setup Mode', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.psychology, size: 15),
                      label: Text('Bid Mode', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_isSetupMode},
                  onSelectionChanged: (val) {
                    if (val.first) {
                      _switchToSetupMode(clearHistory: false);
                    } else {
                      _switchToBidMode();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Setup Mode Controls
            if (_isSetupMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Text(
                            'Active Seat: $_selectedEntrySeat',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.amber.shade900),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.undo, size: 14),
                          label: const Text('Undo', style: TextStyle(fontSize: 11)),
                          onPressed: _auctionHistory.isNotEmpty ? _undoLastBid : null,
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.clear_all, size: 14),
                          label: const Text('Clear', style: TextStyle(fontSize: 11)),
                          onPressed: (_auctionHistory.isNotEmpty || _lockedSetupAuction != null) ? _clearAuction : null,
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.play_arrow, size: 14),
                          label: const Text('Switch to Bid Mode ▶', style: TextStyle(fontSize: 11)),
                          onPressed: _switchToBidMode,
                        ),
                      ],
                    ),
                    if (_auctionHistory.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: List.generate(_auctionHistory.length, (idx) {
                          final entry = _auctionHistory[idx];
                          return InputChip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${entry.seat}: ${entry.call}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            onDeleted: () => _removeBidAtIndex(idx),
                            deleteIconColor: Colors.black54,
                            backgroundColor: Colors.white,
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              // Bid Mode Active Status Banner
              if (_isCorrect == false) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF9A9A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Incorrect bid "$_submittedBid"! Auction halted.',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFB71C1C)),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC62828),
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.replay, size: 15),
                        label: const Text('Try Again', style: TextStyle(fontSize: 11)),
                        onPressed: _retryCurrentBid,
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB71C1C),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh, size: 15),
                        label: const Text('Deal New Hand', style: TextStyle(fontSize: 11)),
                        onPressed: _startNewDeal,
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.edit_note, size: 14),
                        label: const Text('Edit State', style: TextStyle(fontSize: 11)),
                        onPressed: _switchToSetupMode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: Color(0xFF2E7D32), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isAuctionComplete
                              ? 'Auction completed.'
                              : 'Your turn ($activeSeatDisplay) to bid! Select your call below:',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.edit_note, size: 14),
                        label: const Text('Edit State', style: TextStyle(fontSize: 11)),
                        onPressed: _switchToSetupMode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],

            // Interactive Bidding Box
            BiddingBoxWidget(
              isEnabled: _isSetupMode || (!_isAuctionComplete && _submittedBid == null),
              onBidSelected: _onBidSelected,
              history: _effectiveHistoryForBiddingBox,
              activeSeat: _effectiveSeatForBiddingBox,
              validateLegality: !_isSetupMode,
              requireConfirmation: _requireBidConfirmation,
              onRequireConfirmationChanged: (val) {
                setState(() {
                  _requireBidConfirmation = val;
                });
              },
              descriptionResolver: _resolveBidDescription,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorFeedbackCard(ThemeData theme) {
    final expected = _expectedBestBid;

    return Card(
      elevation: 3,
      color: const Color(0xFFFFEBEE),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFEF9A9A), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cancel, color: Color(0xFFC62828), size: 26),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Incorrect Bid — Auction Halted',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFB71C1C)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Try Again with this Hand'),
                  onPressed: _retryCurrentBid,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB71C1C),
                    side: const BorderSide(color: Color(0xFFEF9A9A)),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Deal New Hand'),
                  onPressed: _startNewDeal,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'You bid "$_submittedBid", but the system requires "${expected?.displayCall ?? "Pass"}" (${expected?.desc ?? ""}).',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red.shade900),
            ),
            if (expected?.rule != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Expected Rule: ${expected!.rule}',
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
            if (_allMatches != null && _allMatches!.where((c) => c.isMatch).isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Matching Candidate Bids Ranked by Priority (p#) & Specificity:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._allMatches!.where((c) => c.isMatch).map((c) {
                final isWinner = c.call == expected?.call;
                final p = c.priority;
                final badgeNode = c.originalNode ?? BiddingNode(call: c.call, desc: c.desc, rule: c.rule);
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isWinner ? const Color(0xFFFFF8E1) : Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isWinner ? Colors.amber.shade600 : Colors.grey.shade300,
                      width: isWinner ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              isWinner ? Icons.star : Icons.circle,
                              size: 14,
                              color: isWinner ? Colors.amber.shade800 : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 6),
                          BidBadge(node: badgeNode, fontSize: 12),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.desc,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (p != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'p#$p',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Spec: ${c.specificityScore.toStringAsFixed(1)}',
                              style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800, fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  void _showExportBoardDialog(BuildContext context) {
    final pbnContent = BoardExporter.exportToPbn(
      deal: _currentDeal,
      history: _auctionHistory,
      options: BoardExportOptions(
        dealer: _dealer.code,
        systemName: widget.system.name,
      ),
    );

    final linContent = BoardExporter.exportToLin(
      deal: _currentDeal,
      history: _auctionHistory,
      options: BoardExportOptions(
        dealer: _dealer.code,
        systemName: widget.system.name,
      ),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.file_download, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('Export Board & Auction', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 350,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.blue,
                    tabs: [
                      Tab(text: 'PBN Format'),
                      Tab(text: 'BBO LIN Format'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildExportTabContent(ctx, pbnContent, 'PBN'),
                        _buildExportTabContent(ctx, linContent, 'LIN'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExportTabContent(BuildContext context, String content, String formatLabel) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text('Copy $formatLabel to Clipboard'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$formatLabel copied to clipboard!')),
            );
          },
        ),
      ],
    );
  }
}
