import '../models/bidding_system.dart';
import 'compiled_auction_graph.dart';

/// Compiles a [BridgeSystem] (including all imported convention libraries and fragments)
/// into a fully indexed [CompiledBiddingGraph] with O(1) sequence state lookups.
class BiddingGraphCompiler {
  final BridgeSystem system;
  final int maxDepth;

  BiddingGraphCompiler({
    required this.system,
    this.maxDepth = 12,
  });

  /// Compiles the entire system into a [CompiledBiddingGraph].
  CompiledBiddingGraph compile() {
    final Map<String, CompiledAuctionState> sequenceIndex = {};

    final initialVars = Map<String, String>.from(system.definitions);

    // 1. Expand opening bids (both our side and opposition openings)
    final List<BiddingNode> rootCandidates = [];
    for (final b in system.openingBids) {
      final resolved = b.withResolvedFragmentMetadata(system.fragments);
      for (final exp in resolved.expandCompoundBid()) {
        rootCandidates.add(exp.substituted(initialVars));
      }
    }
    for (final b in system.oppositionOpeningBids) {
      final resolved = b.withResolvedFragmentMetadata(system.fragments);
      for (final exp in resolved.expandCompoundBid()) {
        rootCandidates.add(exp.substituted(initialVars));
      }
    }

    final rootState = CompiledAuctionState(
      sequenceKey: '',
      sequence: const [],
      activeVariables: initialVars,
      candidateNodes: rootCandidates,
    );
    sequenceIndex[''] = rootState;

    // 2. Recursively compile sequence tree
    final flattenedRoot = _flattenCandidates(rootCandidates, initialVars);
    rootState.candidateNodes.clear();
    rootState.candidateNodes.addAll(flattenedRoot);

    _compileTransitions(
      parentState: rootState,
      candidates: flattenedRoot,
      activeVars: initialVars,
      sequenceIndex: sequenceIndex,
      depth: 1,
    );

    return CompiledBiddingGraph(
      system: system,
      rootState: rootState,
      sequenceIndex: sequenceIndex,
    );
  }

  List<BiddingNode> _flattenCandidates(List<BiddingNode> nodes, Map<String, String> activeVars) {
    final List<BiddingNode> result = [];
    for (final node in nodes) {
      if (node.isConditionalBranch) {
        final mergedVars = Map<String, String>.from(activeVars)..addAll(node.variables);
        final children = node.getEffectiveChildren(mergedVars, fragments: system.fragments);
        result.addAll(_flattenCandidates(children, mergedVars));
      } else {
        result.add(node);
      }
    }
    return result;
  }

  void _compileTransitions({
    required CompiledAuctionState parentState,
    required List<BiddingNode> candidates,
    required Map<String, String> activeVars,
    required Map<String, CompiledAuctionState> sequenceIndex,
    required int depth,
  }) {
    if (depth > maxDepth) return;

    for (final node in candidates) {
      if (node.isConditionalBranch) {
        continue;
      }

      // Concrete table call (e.g. 1c, 1h, 1s, 1nt, 2c, pass)
      final rawCall = node.isOpponent ? '(${node.displayCall})' : node.displayCall;
      final callKey = CompiledAuctionState.normalizeCallKey(rawCall);
      if (callKey.isEmpty) continue;

      final deduced = BiddingNode.deduceVariablesFromCall(callKey);
      if (activeVars.containsKey('M') && !node.variables.containsKey('M')) {
        deduced.remove('M');
        deduced.remove('OM');
        deduced.remove('M_name');
        deduced.remove('M_sym');
      }
      if (activeVars.containsKey('os') && !node.isOpponent && !node.variables.containsKey('os')) {
        deduced.remove('os');
        deduced.remove('oppos');
        deduced.remove('os_name');
        deduced.remove('os_sym');
      }
      final mergedVars = Map<String, String>.from(activeVars)
        ..addAll(deduced)
        ..addAll(node.variables);
      final newSequence = [...parentState.sequence, callKey];
      final newKey = newSequence.join(':');

      // Fetch children for this call (substituting variables and expanding compound bids)
      final rawCandidates = node.getEffectiveChildren(mergedVars, fragments: system.fragments);
      final nextCandidates = _flattenCandidates(rawCandidates, mergedVars);

      // Create or update CompiledAuctionState for this sequence
      var state = sequenceIndex[newKey];
      if (state == null) {
        state = CompiledAuctionState(
          sequenceKey: newKey,
          sequence: newSequence,
          activeVariables: mergedVars,
          candidateNodes: List.from(nextCandidates),
        );
        sequenceIndex[newKey] = state;
        parentState.transitions[callKey] = state;
      } else {
        // Merge candidates if already present
        for (final cand in nextCandidates) {
          if (!state.candidateNodes.any((existing) => existing.call == cand.call)) {
            state.candidateNodes.add(cand);
          }
        }
      }

      // Recurse to compile follow-up bids from this state
      if (nextCandidates.isNotEmpty) {
        _compileTransitions(
          parentState: state,
          candidates: nextCandidates,
          activeVars: mergedVars,
          sequenceIndex: sequenceIndex,
          depth: depth + 1,
        );
      }
    }
  }
}
