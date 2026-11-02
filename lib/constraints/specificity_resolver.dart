import '../models/bidding_system.dart';
import '../models/card.dart';
import '../models/hand.dart';
import '../models/bidding_state_context.dart';
import '../evaluators/valuation_engine.dart';
import '../evaluators/ml_bid_evaluator.dart';
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
    BiddingStateContext? context,
  }) {
    final playable = resolvePlayableCandidates(
      hand,
      candidates,
      fragments: fragments,
      activeVariables: activeVariables,
      context: context,
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

      final constraint = parser.parse(node.rule!, agreedTrump: context?.agreedTrump);
      final result = constraint.evaluate(hand, valuation, context);

      if (result.isMatch) {
        if (context != null && context.isOpeningAuction) {
          final decision = _evaluateOpeningPreempt(node, hand, context);
          if (decision != null && !decision.shouldPreempt) {
            continue; // Filtered out by ML tactical preempt evaluation
          }
        }

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
    BiddingStateContext? context,
  }) {
    final List<BiddingNode> playable = [];
    final vars = activeVariables ?? const {};

    for (final node in candidates) {
      if (node.isConditionalBranch) {
        // Evaluate condition of this continuation branch against hand
        bool branchMatches = true;
        if (node.rule != null && node.rule!.trim().isNotEmpty) {
          final constraint = parser.parse(node.rule!, agreedTrump: context?.agreedTrump);
          final result = constraint.evaluate(hand, valuation, context);
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
            context: context,
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

  /// Evaluates an opening bid against MLPreempt rules (Rule of 2/3/4, seat, vulnerability, suit quality).
  PreemptDecision? _evaluateOpeningPreempt(
    BiddingNode node,
    Hand hand,
    BiddingStateContext context,
  ) {
    final cleanCall = node.call.toLowerCase().replaceAll('(', '').replaceAll(')', '').trim();
    if (cleanCall.length < 2) return null;
    final level = int.tryParse(cleanCall[0]);
    if (level == null || level < 2 || level > 4) return null;

    final isMulti = cleanCall == '2d' &&
        (node.ref == 'MultiTwoDiamonds' ||
            node.desc.toLowerCase().contains('multi') ||
            (node.rule != null && (node.rule!.contains('6h') || node.rule!.contains('6s'))));

    final isWeakOrPreempt = isMulti ||
        (node.ref != null && (node.ref!.contains('Weak') || node.ref!.contains('Preempt'))) ||
        node.desc.toLowerCase().contains('weak') ||
        node.desc.toLowerCase().contains('preempt') ||
        (node.rule != null &&
            (node.rule!.contains('5-10hcp') ||
                node.rule!.contains('6-10hcp') ||
                node.rule!.contains('0-11hcp')));

    if (!isWeakOrPreempt && hand.hcp > 10) return null;

    Suit? suit;
    if (isMulti) {
      suit = hand.heartsLength >= 6 ? Suit.hearts : (hand.spadesLength >= 6 ? Suit.spades : null);
    } else {
      final suitChar = cleanCall[1];
      if (suitChar == 'c') suit = Suit.clubs;
      else if (suitChar == 'd') suit = Suit.diamonds;
      else if (suitChar == 'h') suit = Suit.hearts;
      else if (suitChar == 's') suit = Suit.spades;
    }

    if (suit == null) return null;

    return MLPowerEngine.evaluatePreempt(
      hand,
      suit: suit,
      level: level,
      seat: context.seatPosition,
      vuln: context.vulnerability,
    );
  }
}

