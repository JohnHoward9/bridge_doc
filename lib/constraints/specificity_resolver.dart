import '../models/bidding_system.dart';
import '../models/hand.dart';
import '../evaluators/valuation_engine.dart';
import 'constraint_parser.dart';
import 'hand_constraint.dart';

/// Container for a candidate bid and its evaluation against a hand.
class CandidateMatch {
  final BiddingNode node;
  final MatchResult matchResult;
  final double specificityScore;

  const CandidateMatch({
    required this.node,
    required this.matchResult,
    required this.specificityScore,
  });

  bool get isMatch => matchResult.isMatch;
}

/// Resolves the winning bid among multiple candidates by choosing
/// the highest-priority (p# from ANTLR Bridge.g) and most-defined bid.
class SpecificityResolver {
  final ConstraintParser parser;
  final HandValuationEngine valuation;

  SpecificityResolver({
    ConstraintParser? parser,
    HandValuationEngine? valuation,
  })  : parser = parser ?? ConstraintParser(),
        valuation = valuation ?? MiltonWorkValuation();

  /// Evaluates [candidates] against [hand], automatically unwrapping any `~>` conditional
  /// continuation branches that match the hand.
  /// Returns all matching playable bids sorted by priority (p#) and specificity score.
  List<CandidateMatch> evaluateCandidates(
    Hand hand,
    List<BiddingNode> candidates, {
    Map<String, Fragment>? fragments,
    Map<String, String>? activeVariables,
  }) {
    final playable = resolvePlayableCandidates(
      hand,
      candidates,
      fragments: fragments,
      activeVariables: activeVariables,
    );

    final List<CandidateMatch> matches = [];

    for (final node in playable) {
      if (node.rule == null || node.rule!.trim().isEmpty) {
        // If node has no rule, treat as broad default/signoff
        matches.add(CandidateMatch(
          node: node,
          matchResult: const MatchResult(isMatch: true, satisfiedCriteria: ['Default bid']),
          specificityScore: 1.0,
        ));
        continue;
      }

      final constraint = parser.parse(node.rule!);
      final result = constraint.evaluate(hand, valuation);

      if (result.isMatch) {
        matches.add(CandidateMatch(
          node: node,
          matchResult: result,
          specificityScore: result.specificityScore,
        ));
      }
    }

    // Sort order:
    // 1. Explicit p# priority from ANTLR Bridge.g (lower number = higher precedence, e.g. p#1 > p#3 > p#5)
    // 2. Specificity Score ("the more defined is chosen")
    matches.sort((a, b) {
      final pA = a.node.effectivePriority;
      final pB = b.node.effectivePriority;

      if (pA != null && pB != null && pA != pB) {
        return pA.compareTo(pB);
      }
      if (pA != null && pB == null) return -1;
      if (pA == null && pB != null) return 1;

      return b.specificityScore.compareTo(a.specificityScore);
    });

    return matches;
  }

  /// Resolves candidate bridge calls by unwrapping any ~> conditional continuation branches
  /// that match the bidder's [hand]. If [candidates] contains continuation routers (~>),
  /// they are evaluated against [hand]; matching routers are recursively unwrapped until concrete
  /// physical bridge calls (e.g. 1s, 1nt, 2c, pass) are reached.
  List<BiddingNode> resolvePlayableCandidates(
    Hand hand,
    List<BiddingNode> candidates, {
    Map<String, Fragment>? fragments,
    Map<String, String>? activeVariables,
  }) {
    final List<BiddingNode> playable = [];
    final vars = activeVariables ?? const {};

    for (final node in candidates) {
      if (node.isConditionalBranch) {
        // Evaluate condition of this continuation branch against hand
        bool branchMatches = true;
        if (node.rule != null && node.rule!.trim().isNotEmpty) {
          final constraint = parser.parse(node.rule!);
          final result = constraint.evaluate(hand, valuation);
          branchMatches = result.isMatch;
        }

        if (branchMatches) {
          // Recursively unwrap children of this matching continuation router
          final mergedVars = Map<String, String>.from(vars)..addAll(node.variables);
          final children = node.getEffectiveChildren(mergedVars, fragments: fragments);
          playable.addAll(resolvePlayableCandidates(
            hand,
            children,
            fragments: fragments,
            activeVariables: mergedVars,
          ));
        }
      } else {
        // Concrete table call (e.g. 1s, 1nt, 2c, pass)
        playable.add(node);
      }
    }

    return playable;
  }

  /// Selects the best, highest priority / most defined bid for the given [hand].
  /// Returns null if no candidates match.
  BiddingNode? resolveBestBid(
    Hand hand,
    List<BiddingNode> candidates, {
    Map<String, Fragment>? fragments,
    Map<String, String>? activeVariables,
  }) {
    final matches = evaluateCandidates(
      hand,
      candidates,
      fragments: fragments,
      activeVariables: activeVariables,
    );
    if (matches.isEmpty) return null;
    return matches.first.node;
  }
}

