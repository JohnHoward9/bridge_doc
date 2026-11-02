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

      // Resolve agreedSuit if specified or inherited from active variables
      String? nodeAgreed = node.agreedSuit;
      if (nodeAgreed != null && nodeAgreed.startsWith(r'$')) {
        final varName = nodeAgreed.substring(1);
        nodeAgreed = activeVars[varName] ?? node.variables[varName];
      }
      final currentAgreed = nodeAgreed ?? activeVars['agreedSuit'] ?? node.variables['agreedSuit'];

      final deduced = BiddingNode.deduceVariablesFromCall(callKey);
      if ((activeVars.containsKey('M') || currentAgreed != null) &&
          (node.isOpponent || !node.variables.containsKey('M') || currentAgreed != null)) {
        deduced.remove('M');
        deduced.remove('OM');
        deduced.remove('M_name');
        deduced.remove('M_sym');
      }
      if ((activeVars.containsKey('m') || currentAgreed != null) &&
          (node.isOpponent || !node.variables.containsKey('m') || currentAgreed != null)) {
        deduced.remove('m');
        deduced.remove('om');
        deduced.remove('m_name');
        deduced.remove('m_sym');
      }
      if (activeVars.containsKey('os') && !node.isOpponent && !node.variables.containsKey('os')) {
        deduced.remove('os');
        deduced.remove('oppos');
        deduced.remove('os_name');
        deduced.remove('os_sym');
      }
      final nodeVars = Map<String, String>.from(node.variables);
      if (activeVars.containsKey('M') && node.isOpponent) {
        nodeVars.remove('M');
        nodeVars.remove('OM');
        nodeVars.remove('M_name');
        nodeVars.remove('M_sym');
      }
      if (activeVars.containsKey('m') && node.isOpponent) {
        nodeVars.remove('m');
        nodeVars.remove('om');
        nodeVars.remove('m_name');
        nodeVars.remove('m_sym');
      }
      final mergedVars = Map<String, String>.from(activeVars)
        ..addAll(deduced)
        ..addAll(nodeVars);

      if (currentAgreed != null && currentAgreed.isNotEmpty) {
        mergedVars['agreedSuit'] = currentAgreed;
        mergedVars['agreed_suit'] = currentAgreed;
        mergedVars['trump'] = currentAgreed;
        mergedVars['agreed_name'] = BiddingNode.suitName(currentAgreed);
        mergedVars['agreed_sym'] = BiddingNode.suitSym(currentAgreed);
        if (currentAgreed == 'h' || currentAgreed == 's') {
          mergedVars['M'] = currentAgreed;
          mergedVars['OM'] = BiddingNode.otherMajor(currentAgreed);
          mergedVars['M_name'] = BiddingNode.suitName(currentAgreed);
          mergedVars['M_sym'] = BiddingNode.suitSym(currentAgreed);
        }
      }
      final newSequence = [...parentState.sequence, callKey];
      final newKey = newSequence.join(':');

      // Monotonic forcing level accumulation: force can only escalate (partScore -> game -> slam -> grandSlam)
      final nextForcingLevel = node.forceTo.rank > parentState.forcingLevel.rank
          ? node.forceTo
          : parentState.forcingLevel;

      // Fetch children for this call (substituting variables and expanding compound bids)
      final rawCandidates = node.getEffectiveChildren(mergedVars, fragments: system.fragments);
      final rawFlattened = _flattenCandidates(rawCandidates, mergedVars);

      // Enforce bridge call legality: prune insufficient suit/NT bids
      int lastContractRank = -1;
      String? lastContractCall;
      for (final c in newSequence.reversed) {
        final r = _callRank(c);
        if (r != -1) {
          lastContractRank = r;
          lastContractCall = c;
          break;
        }
      }

      final nextCandidates = <BiddingNode>[];
      for (final cand in rawFlattened) {
        final candRank = _callRank(cand.displayCall);
        if (candRank != -1 && lastContractRank != -1 && candRank <= lastContractRank) {
          continue; // Insufficient bid pruned
        }
        nextCandidates.add(cand);
      }

      // Check if current contract satisfies the accumulated forcing commitment
      final isForceSatisfied = lastContractCall == null ||
          ForcingLevel.isContractSatisfied(lastContractCall, nextForcingLevel);

      if (isForceSatisfied) {
        // Ensure Pass is present as a fallback candidate (priority 999) if not explicitly defined in YAML
        final hasPass = nextCandidates.any((c) => c.call.toLowerCase() == 'pass' || c.displayCall.toLowerCase() == 'pass');
        if (!hasPass) {
          nextCandidates.add(BiddingNode(
            call: 'pass',
            desc: 'Pass to play',
            priority: 999,
          ));
        }
      } else {
        // Partnership is in an unsatisfied force (e.g. Game Force, Slam Force, Grand Slam Force).
        // Passing partner before the forced level is reached is strictly prohibited!
        // However, passing over an OPPONENT call (e.g. lead-directing double, interference)
        // is legal (forcing pass / neutral pass).
        final isOverOpponent = callKey == '(x)' ||
            callKey == 'x' ||
            callKey.startsWith('(') ||
            node.isOpponent;
        if (!isOverOpponent) {
          nextCandidates.removeWhere((c) => c.call.toLowerCase() == 'pass' || c.displayCall.toLowerCase() == 'pass');
        }
      }

      // Create or update CompiledAuctionState for this sequence
      var state = sequenceIndex[newKey];
      if (state == null) {
        state = CompiledAuctionState(
          sequenceKey: newKey,
          sequence: newSequence,
          forcingLevel: nextForcingLevel,
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

  /// Calculates numeric rank for bridge contract calls (1c = 5, ..., 7nt = 39)
  /// Returns -1 for non-contract calls (pass, x, xx).
  static int _callRank(String rawCall) {
    final clean = rawCall.toLowerCase().replaceAll('(', '').replaceAll(')', '').trim();
    if (clean.length < 2) return -1;
    final level = int.tryParse(clean.substring(0, 1));
    if (level == null || level < 1 || level > 7) return -1;
    final strain = clean.substring(1).trim();
    int strainRank;
    switch (strain) {
      case 'c': strainRank = 0; break;
      case 'd': strainRank = 1; break;
      case 'h': strainRank = 2; break;
      case 's': strainRank = 3; break;
      case 'nt': strainRank = 4; break;
      default: return -1;
    }
    return (level * 5) + strainRank;
  }
}
