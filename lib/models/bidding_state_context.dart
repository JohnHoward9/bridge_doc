import 'card.dart';
import 'hand.dart';
import '../evaluators/valuation_engine.dart';
import '../evaluators/ml_bid_evaluator.dart';
import '../engine/auction_engine.dart';

/// Relative position of an opponent bidder to the active seat.
enum RelativeOpponentPosition {
  lho, // Left-Hand Opponent (acts after active seat)
  rho, // Right-Hand Opponent (acts before active seat)
  unknown,
}

/// Helper to return partner's seat identifier ('N' <-> 'S', 'E' <-> 'W').
String partnerOfSeat(String seat) {
  switch (seat.toUpperCase()) {
    case 'N':
      return 'S';
    case 'S':
      return 'N';
    case 'E':
      return 'W';
    case 'W':
      return 'E';
    default:
      return '';
  }
}

/// Computes the relative opponent position (LHO or RHO) of [oppSeat] relative to [mySeat].
RelativeOpponentPosition relativePositionOf({
  required String mySeat,
  required String oppSeat,
}) {
  final me = mySeat.toUpperCase();
  final opp = oppSeat.toUpperCase();
  if (me.isEmpty || opp.isEmpty || me == opp || partnerOfSeat(me) == opp) {
    return RelativeOpponentPosition.unknown;
  }

  // Clockwise order: N (0) -> E (1) -> S (2) -> W (3)
  const order = ['N', 'E', 'S', 'W'];
  final myIdx = order.indexOf(me);
  final oppIdx = order.indexOf(opp);
  if (myIdx == -1 || oppIdx == -1) return RelativeOpponentPosition.unknown;

  if ((myIdx + 1) % 4 == oppIdx) {
    return RelativeOpponentPosition.lho;
  }
  if ((myIdx + 3) % 4 == oppIdx) {
    return RelativeOpponentPosition.rho;
  }
  return RelativeOpponentPosition.unknown;
}

/// Records a significant opponent action that affects hand valuation and defense rules.
class OpponentSuitAction {
  final Suit suit;
  final RelativeOpponentPosition position;
  final String call;
  final String seat;
  final bool isArtificial;
  final Set<Suit> promisedSuits;

  const OpponentSuitAction({
    required this.suit,
    required this.position,
    required this.call,
    required this.seat,
    this.isArtificial = false,
    this.promisedSuits = const {},
  });

  @override
  String toString() => 'OpponentSuitAction($seat: $call, suit: ${suit.name}, pos: ${position.name})';
}

/// Comprehensive contextual state passed to constraint evaluation and auction resolvers.
///
/// Encapsulates holding, full auction history, contextual variables, partner/opponent actions,
/// and dynamically evolving Effective HCP (incorporating positional honor adjustments).
class BiddingStateContext {
  final Hand holding;
  final List<AuctionEntry> auctionHistory;
  final String activeSeat;
  final Map<String, String> variables;
  final Suit? partnerSuit;
  final Suit? agreedTrump;
  final List<OpponentSuitAction> opponentActions;
  final HandValuationEngine valuation;
  final Vulnerability vulnerability;
  final SeatPosition? explicitSeatPosition;

  late final MLHandBreakdown breakdown;

  /// Effective HCP incorporating baseline ML valuation and mathematical expectation bonus.
  double get effectiveHcp => breakdown.effectiveHcp + expectationBonus;

  /// Mathematical expectation bonus incorporating fit probability, ruffing trick potential,
  /// and asymmetric game bonus payoffs (+300 non-vul, +500 vul) for unbalanced holdings.
  double get expectationBonus {
    if (holding.isBalanced) return 0.0;

    // 1. Posterior: Trump suit is already agreed
    if (agreedTrump != null) {
      final trumpLen = holding.length(agreedTrump!);
      if (trumpLen >= 4) {
        double bonus = 0.0;
        for (final s in Suit.values) {
          if (s == agreedTrump) continue;
          final l = holding.length(s);
          if (l == 0) bonus += 3.5; // Void with 4+ trumps
          else if (l == 1) bonus += 1.5; // Singleton with 4+ trumps
        }
        return bonus;
      } else if (trumpLen == 3) {
        double bonus = 0.0;
        for (final s in Suit.values) {
          if (s == agreedTrump) continue;
          final l = holding.length(s);
          if (l == 0) bonus += 2.0;
          else if (l == 1) bonus += 0.8;
        }
        return bonus;
      }
      return 0.0;
    }

    // 2. Prior: Unconfirmed fit in constructive auction facing partner opening/rebid
    if (!isOpeningAuction) {
      final shortest = holding.shortestSuitLength;
      if (shortest <= 1) {
        final fourCardSuits = Suit.values.where((s) => holding.length(s) >= 4).length;
        if (fourCardSuits >= 2) {
          double bonus = (shortest == 0)
              ? (fourCardSuits >= 3 ? 3.5 : 2.5) // Void with multiple fit targets
              : (fourCardSuits >= 3 ? 1.5 : 1.0); // Singleton with multiple fit targets
          if (vulnerability.isWeVul) {
            bonus += 0.5; // Payoff asymmetry: +500 vul game bonus
          }
          return bonus;
        }
      }
    }

    return 0.0;
  }

  SeatPosition get seatPosition {
    if (explicitSeatPosition != null) return explicitSeatPosition!;
    int priorPasses = 0;
    for (final entry in auctionHistory) {
      if (entry.call.toLowerCase() == 'pass') {
        priorPasses++;
      } else {
        break;
      }
    }
    switch (priorPasses) {
      case 0:
        return SeatPosition.first;
      case 1:
        return SeatPosition.second;
      case 2:
        return SeatPosition.third;
      case 3:
        return SeatPosition.fourth;
      default:
        return SeatPosition.first;
    }
  }

  bool get isOpeningAuction {
    return auctionHistory.isEmpty || auctionHistory.every((e) => e.call.toLowerCase() == 'pass');
  }

  BiddingStateContext({
    required this.holding,
    required this.auctionHistory,
    required this.activeSeat,
    this.variables = const {},
    this.partnerSuit,
    Suit? agreedTrump,
    this.opponentActions = const [],
    HandValuationEngine? valuation,
    this.vulnerability = Vulnerability.none,
    this.explicitSeatPosition,
  })  : agreedTrump = agreedTrump ??
            (variables['agreedSuit'] != null
                ? Suit.fromString(variables['agreedSuit']!)
                : (variables['trump'] != null
                    ? Suit.fromString(variables['trump']!)
                    : null)),
        valuation = valuation ?? MLHandValuation(strictEffectiveHcp: true) {
    breakdown = _calculateDynamicBreakdown();
  }

  /// Calculates dynamic Effective HCP taking holding, partner fit, and opponent position into account.
  MLHandBreakdown _calculateDynamicBreakdown() {
    if (valuation is MLHandValuation) {
      return (valuation as MLHandValuation).evaluateWithAuctionContext(
        holding,
        partnerSuit: partnerSuit,
        trumpSuit: agreedTrump,
        opponentActions: opponentActions,
      );
    }
    final rawHcp = holding.hcp.toDouble();
    return MLHandBreakdown.raw(rawHcp);
  }

  /// Extracts active opponent actions from [auctionHistory] relative to [activeSeat].
  static List<OpponentSuitAction> extractOpponentActions({
    required List<AuctionEntry> auctionHistory,
    required String activeSeat,
  }) {
    final actions = <OpponentSuitAction>[];
    final partner = partnerOfSeat(activeSeat);

    for (final entry in auctionHistory) {
      final seat = entry.seat.toUpperCase();
      if (seat == activeSeat || seat == partner) continue;

      final relPos = relativePositionOf(mySeat: activeSeat, oppSeat: seat);
      final rawCall = entry.call.toLowerCase().replaceAll('(', '').replaceAll(')', '').trim();

      // Multi-Landy specific patterns
      if (rawCall == '2s') {
        // Multi-Landy 2S shows Spades + minor
        actions.add(OpponentSuitAction(
          suit: Suit.spades,
          position: relPos,
          call: entry.call,
          seat: seat,
          isArtificial: true,
          promisedSuits: {Suit.spades},
        ));
      } else if (rawCall == '2h') {
        // Multi-Landy 2H shows Hearts + minor
        actions.add(OpponentSuitAction(
          suit: Suit.hearts,
          position: relPos,
          call: entry.call,
          seat: seat,
          isArtificial: true,
          promisedSuits: {Suit.hearts},
        ));
      } else if (rawCall == '2c') {
        // Multi-Landy 2C shows both majors
        actions.add(OpponentSuitAction(
          suit: Suit.hearts,
          position: relPos,
          call: entry.call,
          seat: seat,
          isArtificial: true,
          promisedSuits: {Suit.hearts, Suit.spades},
        ));
        actions.add(OpponentSuitAction(
          suit: Suit.spades,
          position: relPos,
          call: entry.call,
          seat: seat,
          isArtificial: true,
          promisedSuits: {Suit.hearts, Suit.spades},
        ));
      } else {
        // Natural suit bids (e.g. 1s, 2d, 3c)
        final lastChar = rawCall.isNotEmpty ? rawCall[rawCall.length - 1] : '';
        Suit? naturalSuit;
        if (lastChar == 's') naturalSuit = Suit.spades;
        if (lastChar == 'h') naturalSuit = Suit.hearts;
        if (lastChar == 'd') naturalSuit = Suit.diamonds;
        if (lastChar == 'c') naturalSuit = Suit.clubs;

        if (naturalSuit != null && !rawCall.contains('nt') && rawCall != 'pass') {
          actions.add(OpponentSuitAction(
            suit: naturalSuit,
            position: relPos,
            call: entry.call,
            seat: seat,
            promisedSuits: {naturalSuit},
          ));
        }
      }
    }

    return actions;
  }

  /// Interrogates whether the holding has a stopper in [suit].
  bool hasStopper(Suit suit) {
    final sCards = holding.cards.where((c) => c.suit == suit).toList();
    if (sCards.any((c) => c.rank == Rank.ace)) return true;
    if (sCards.any((c) => c.rank == Rank.king) && sCards.length >= 2) return true;
    if (sCards.any((c) => c.rank == Rank.queen) && sCards.length >= 3) return true;
    if (sCards.any((c) => c.rank == Rank.jack) &&
        sCards.any((c) => c.rank == Rank.ten) &&
        sCards.length >= 4) {
      return true;
    }
    return false;
  }

  /// Interrogates whether any opponent has actively bid [suit].
  bool isOpponentSuit(Suit suit) => opponentActions.any((a) => a.suit == suit);
}
