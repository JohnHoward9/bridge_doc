import '../models/card.dart';
import '../models/hand.dart';
import '../models/bidding_system.dart';
import '../constraints/specificity_resolver.dart';

/// A concrete bid candidate evaluated at a specific state in the auction.
class CandidateCall {
  final String call;
  final String displayCall;
  final String desc;
  final String? rule;
  final int? priority;
  final double specificityScore;
  final bool isMatch;
  final List<String> satisfiedCriteria;
  final BiddingNode? originalNode;

  const CandidateCall({
    required this.call,
    required this.displayCall,
    this.desc = '',
    this.rule,
    this.priority,
    this.specificityScore = 0.0,
    this.isMatch = false,
    this.satisfiedCriteria = const [],
    this.originalNode,
  });

  bool get isPass => displayCall.toLowerCase() == 'pass' || call.toLowerCase() == 'pass';
  bool get isDbl => displayCall.toLowerCase() == 'dbl' || call.toLowerCase() == 'dbl';
  bool get isOpponent => originalNode?.isOpponent ?? call.startsWith('(');
}

/// An indexed state node in the compiled bidding graph.
/// Represents the auction state reached by a sequence of bids (e.g. `['1c', '1h']`).
class CompiledAuctionState {
  /// Normalized colon-separated sequence key, e.g. "" (root), "1c", "1c:1h", "1c:1h:1s".
  final String sequenceKey;

  /// Ordered list of calls leading to this state, e.g. ['1c', '1h'].
  final List<String> sequence;

  /// Bound context variables at this state, e.g. { 'M': 's', 'OM': 'h' }.
  final Map<String, String> activeVariables;

  /// Available candidate bidding nodes (including concrete calls and unwrapped continuations).
  final List<BiddingNode> candidateNodes;

  /// Transitions to next states: maps child call (e.g. "1s") to next CompiledAuctionState.
  final Map<String, CompiledAuctionState> transitions;

  CompiledAuctionState({
    required this.sequenceKey,
    required this.sequence,
    Map<String, String>? activeVariables,
    List<BiddingNode>? candidateNodes,
    Map<String, CompiledAuctionState>? transitions,
  })  : activeVariables = activeVariables ?? {},
        candidateNodes = candidateNodes ?? [],
        transitions = transitions ?? {};

  /// Normalizes a call for dictionary lookup, e.g. " 1H " -> "1h", "(1s)" -> "(1s)".
  static String normalizeCallKey(String call) {
    var c = call.trim().toLowerCase();
    c = c.replaceAll('♣', 'c').replaceAll('♦', 'd').replaceAll('♥', 'h').replaceAll('♠', 's');
    if (c.contains('.')) {
      final parts = c.split('.');
      if (parts.length == 2) {
        final isParen = c.startsWith('(') && c.endsWith(')');
        c = parts[1];
        if (isParen && !c.endsWith(')')) c = '$c)';
        if (isParen && !c.startsWith('(')) c = '($c';
      }
    }
    return c;
  }

  /// Evaluates all available candidates against [hand] using [resolver],
  /// automatically unwrapping any ~> conditional continuation branches.
  List<CandidateCall> evaluateCandidates(
    Hand hand,
    SpecificityResolver resolver, {
    Map<String, Fragment>? fragments,
  }) {
    final playableNodes = resolver.resolvePlayableCandidates(
      hand,
      candidateNodes,
      fragments: fragments,
      activeVariables: activeVariables,
    );

    final matches = resolver.evaluateCandidates(
      hand,
      playableNodes,
      fragments: fragments,
      activeVariables: activeVariables,
    );

    // Build ordered list of CandidateCall objects
    final List<CandidateCall> results = [];
    final matchedNodeSet = {for (final m in matches) m.node: m};

    for (final node in playableNodes) {
      final match = matchedNodeSet[node];
      if (match != null) {
        results.add(CandidateCall(
          call: node.call,
          displayCall: node.displayCall,
          desc: node.desc,
          rule: node.rule,
          priority: node.effectivePriority,
          specificityScore: match.specificityScore,
          isMatch: true,
          satisfiedCriteria: match.matchResult.satisfiedCriteria,
          originalNode: node,
        ));
      } else {
        results.add(CandidateCall(
          call: node.call,
          displayCall: node.displayCall,
          desc: node.desc,
          rule: node.rule,
          priority: node.effectivePriority,
          specificityScore: 0.0,
          isMatch: false,
          originalNode: node,
        ));
      }
    }

    // Ensure Pass is always available as a candidate call
    final hasExplicitPass = results.any((c) => c.isPass);
    if (!hasExplicitPass) {
      final anyOtherMatch = results.any((c) => c.isMatch);
      results.add(CandidateCall(
        call: 'pass',
        displayCall: 'Pass',
        desc: anyOtherMatch ? 'Pass (below bid requirements)' : 'Pass (to play / no bids apply)',
        priority: 999,
        isMatch: !anyOtherMatch,
        originalNode: BiddingNode(call: 'pass', desc: 'Pass', rule: ''),
      ));
    }

    // Sort matching bids first by priority then specificity
    results.sort((a, b) {
      if (a.isMatch && !b.isMatch) return -1;
      if (!a.isMatch && b.isMatch) return 1;
      if (a.isMatch && b.isMatch) {
        if (a.priority != null && b.priority != null && a.priority != b.priority) {
          return a.priority!.compareTo(b.priority!);
        }
        if (a.priority != null && b.priority == null) return -1;
        if (a.priority == null && b.priority != null) return 1;
        return b.specificityScore.compareTo(a.specificityScore);
      }
      return 0;
    });

    return results;
  }

  /// Resolves the winning, best bid for [hand] at this auction state.
  CandidateCall? resolveBestBid(
    Hand hand,
    SpecificityResolver resolver, {
    Map<String, Fragment>? fragments,
    bool allowOpponent = false,
  }) {
    final candidates = evaluateCandidates(hand, resolver, fragments: fragments);
    final matching = candidates.where((c) => c.isMatch && (allowOpponent || !c.isOpponent)).toList();
    if (matching.isEmpty) {
      return const CandidateCall(
        call: 'pass',
        displayCall: 'Pass',
        desc: 'Pass (no system bids apply)',
        isMatch: true,
        priority: 999,
      );
    }
    return matching.first;
  }
}

/// The complete compiled graph of an entire bridge bidding system.
class CompiledBiddingGraph {
  final BridgeSystem system;
  final CompiledAuctionState rootState;
  final Map<String, CompiledAuctionState> sequenceIndex;

  const CompiledBiddingGraph({
    required this.system,
    required this.rootState,
    required this.sequenceIndex,
  });

  /// Total number of indexed auction states in the graph.
  int get stateCount => sequenceIndex.length;

  /// Look up an auction state by a sequence of calls, e.g. ['1c', '1h'].
  CompiledAuctionState? getState(List<String> calls) {
    if (calls.isEmpty) return rootState;
    final key = calls.map(CompiledAuctionState.normalizeCallKey).join(':');
    final direct = sequenceIndex[key];
    if (direct != null) return direct;
    // Fallback: if sequence starts with 'pass' and wasn't found, fallback to unpassed sequence
    if (calls.isNotEmpty && calls.first.toLowerCase() == 'pass') {
      final subCalls = calls.skip(1).toList();
      if (subCalls.isEmpty) return rootState;
      return getState(subCalls);
    }
    return null;
  }

  /// Look up an auction state by sequence key string, e.g. "1c:1h".
  CompiledAuctionState? getStateByKey(String key) {
    if (key.isEmpty) return rootState;
    final direct = sequenceIndex[key];
    if (direct != null) return direct;
    if (key.toLowerCase().startsWith('pass:')) {
      final subKey = key.substring(5);
      return sequenceIndex[subKey];
    }
    return null;
  }
}
