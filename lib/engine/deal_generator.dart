import 'dart:math';
import '../models/card.dart';
import '../models/hand.dart';
import '../constraints/hand_constraint.dart';
import '../evaluators/valuation_engine.dart';

/// Represents a full 4-hand bridge board dealt from one 52-card deck.
class PartnershipDeal {
  final Hand north;
  final Hand east;
  final Hand south;
  final Hand west;

  const PartnershipDeal({
    required this.north,
    required this.east,
    required this.south,
    required this.west,
  });
}

/// Filter for Combined Partnership High Card Point range (ideal for targeted ML Edge-Case practice).
enum PartnershipHcpFilter {
  any('Any Combined HCP', null, null),
  borderlineGame('22–25 Combined (Edge Game Invite)', 22, 25),
  borderlineGameAccept('22–25 Combined (ML Edge — Game Accept)', 22, 25),
  borderlineGameDecline('22–25 Combined (ML Edge — Game Decline)', 22, 25),
  marginalSlam('29–32 Combined (Edge Slam Decision)', 29, 32),
  mlValuationUpgrade('ML Valuation Upgrade (10–11 Upgrades to 12+ Open)', null, null),
  extremeShapeMajor('Extreme Shape Major (8+ Major, Low LTC)', null, null);

  final String label;
  final int? min;
  final int? max;
  const PartnershipHcpFilter(this.label, this.min, this.max);

  bool matches(Hand north, Hand south, {HandValuationEngine? valuation}) {
    final comb = north.hcp + south.hcp;
    if (min != null && comb < min!) return false;
    if (max != null && comb > max!) return false;

    if (this == PartnershipHcpFilter.borderlineGameAccept) {
      final controls = north.controls + south.controls;
      final ltc = north.losingTrickCount + south.losingTrickCount;
      return controls >= 5 && ltc <= 14;
    }
    if (this == PartnershipHcpFilter.borderlineGameDecline) {
      final controls = north.controls + south.controls;
      final ltc = north.losingTrickCount + south.losingTrickCount;
      return controls <= 4 || ltc >= 15;
    }
    if (this == PartnershipHcpFilter.mlValuationUpgrade) {
      final v = valuation ?? MLHandValuation();
      final northRaw = north.hcp;
      final northEff = v.evaluatePoints(north);
      final southRaw = south.hcp;
      final southEff = v.evaluatePoints(south);
      return (northRaw <= 11 && northEff >= 12.0) || (southRaw <= 11 && southEff >= 12.0);
    }
    if (this == PartnershipHcpFilter.extremeShapeMajor) {
      final hasExtremeNorth = north.heartsLength >= 8 || north.spadesLength >= 8;
      final hasExtremeSouth = south.heartsLength >= 8 || south.spadesLength >= 8;
      final otherHandHcp = hasExtremeNorth ? south.hcp : north.hcp;
      return (hasExtremeNorth || hasExtremeSouth) && otherHandHcp >= 10;
    }
    return true;
  }
}

/// Filter for South's High Card Point range.
enum SouthHcpFilter {
  any('Any HCP', null, null),
  weak('0–7 HCP (Weak)', 0, 7),
  invitational('8–9 HCP (Invitational)', 8, 9),
  medium('10–12 HCP', 10, 12),
  choiceOfGames('10–15 HCP (Game Forcing)', 10, 15),
  gameForcing('10+ HCP (Game Forcing)', 10, null),
  strong('16+ HCP (Slam Interest)', 16, null);

  final String label;
  final int? min;
  final int? max;
  const SouthHcpFilter(this.label, this.min, this.max);

  bool matches(Hand hand) {
    if (min != null && hand.hcp < min!) return false;
    if (max != null && hand.hcp > max!) return false;
    return true;
  }
}

/// Filter for South's distribution shape.
enum SouthShapeFilter {
  any('Any Shape'),
  smolen54('5–4 in Majors (5H-4S / 4H-5S)'),
  smolen5h4s('5 Hearts & 4 Spades'),
  smolen5s4h('5 Spades & 4 Hearts'),
  stayman4M('4-card Major (Stayman)'),
  both4M('Both 4-card Majors (4H & 4S)'),
  transferHearts('5+ Hearts (Transfer to 2H)'),
  transferSpades('5+ Spades (Transfer to 2S)'),
  single5M('Single 5-card Major (5H 3-S or 5S 3-H)'),
  sixMajor('6+ Major'),
  fiveFiveMajors('5–5 in Majors'),
  balanced('Balanced (5332, 4432, 4333)'),
  semiBalanced('Semi-Balanced (5422, 6322)'),
  sixMinor('6+ Minor (Clubs or Diamonds)');

  final String label;
  const SouthShapeFilter(this.label);

  bool matches(Hand hand) {
    switch (this) {
      case SouthShapeFilter.any:
        return true;
      case SouthShapeFilter.smolen54:
        return (hand.heartsLength == 5 && hand.spadesLength == 4) ||
               (hand.spadesLength == 5 && hand.heartsLength == 4);
      case SouthShapeFilter.smolen5h4s:
        return hand.heartsLength == 5 && hand.spadesLength == 4;
      case SouthShapeFilter.smolen5s4h:
        return hand.spadesLength == 5 && hand.heartsLength == 4;
      case SouthShapeFilter.stayman4M:
        return (hand.heartsLength == 4 && hand.spadesLength <= 3) ||
               (hand.spadesLength == 4 && hand.heartsLength <= 3) ||
               (hand.heartsLength == 4 && hand.spadesLength == 4);
      case SouthShapeFilter.both4M:
        return hand.heartsLength >= 4 && hand.spadesLength >= 4;
      case SouthShapeFilter.transferHearts:
        return hand.heartsLength >= 5;
      case SouthShapeFilter.transferSpades:
        return hand.spadesLength >= 5;
      case SouthShapeFilter.single5M:
        return (hand.heartsLength == 5 && hand.spadesLength <= 3) ||
               (hand.spadesLength == 5 && hand.heartsLength <= 3);
      case SouthShapeFilter.sixMajor:
        return hand.heartsLength >= 6 || hand.spadesLength >= 6;
      case SouthShapeFilter.fiveFiveMajors:
        return hand.heartsLength >= 5 && hand.spadesLength >= 5;
      case SouthShapeFilter.balanced:
        return hand.isBalanced;
      case SouthShapeFilter.semiBalanced:
        return hand.isSemiBalanced;
      case SouthShapeFilter.sixMinor:
        return hand.clubsLength >= 6 || hand.diamondsLength >= 6;
    }
  }
}

/// Generates random or targeted bridge deals.
class DealGenerator {
  final Random _random;
  final HandValuationEngine _valuation;

  DealGenerator({Random? random, HandValuationEngine? valuation})
      : _random = random ?? Random(),
        _valuation = valuation ?? MiltonWorkValuation();

  /// Returns a full fresh 52-card deck.
  static List<BridgeCard> createDeck() {
    final List<BridgeCard> deck = [];
    for (final suit in Suit.values) {
      for (final rank in Rank.values) {
        deck.add(BridgeCard(suit, rank));
      }
    }
    return deck;
  }

  /// Deals a full 52-card board across North, East, South, West.
  PartnershipDeal dealFullBoard() {
    final deck = createDeck()..shuffle(_random);
    return PartnershipDeal(
      north: Hand(deck.sublist(0, 13)),
      east: Hand(deck.sublist(13, 26)),
      south: Hand(deck.sublist(26, 39)),
      west: Hand(deck.sublist(39, 52)),
    );
  }

  /// Deals a completely random 13-card hand.
  Hand dealRandomHand() {
    final deck = createDeck()..shuffle(_random);
    return Hand(deck.take(13).toList());
  }

  /// Deals a board where North holds an opening hand (11+ HCP).
  PartnershipDeal dealWhereNorthOpens({int maxAttempts = 500}) {
    for (int i = 0; i < maxAttempts; i++) {
      final board = dealFullBoard();
      if (board.north.hcp >= 11) {
        return board;
      }
    }
    return dealFullBoard();
  }

  /// Deals a board where North's hand satisfies [isTargetMatch].
  PartnershipDeal dealWhereNorthOpensTarget({
    required bool Function(Hand northHand) isTargetMatch,
    int maxAttempts = 1500,
  }) {
    for (int i = 0; i < maxAttempts; i++) {
      final board = dealFullBoard();
      if (isTargetMatch(board.north)) {
        return board;
      }
    }
    return dealWhereNorthOpens();
  }

  /// Deals a board satisfying both North and South criteria.
  /// Uses a two-stage shuffle: once a candidate North is found, the remaining 39 cards
  /// are shuffled across South/East/West to quickly satisfy South's filter.
  PartnershipDeal dealTargetedBoard({
    bool Function(Hand northHand)? isNorthMatch,
    bool Function(Hand southHand)? isSouthMatch,
    bool Function(Hand north, Hand south)? isPartnershipMatch,
    int maxOuterAttempts = 400,
    int maxInnerAttempts = 200,
  }) {
    final deck = createDeck();
    for (int outer = 0; outer < maxOuterAttempts; outer++) {
      deck.shuffle(_random);
      final northHand = Hand(deck.sublist(0, 13));

      if (isNorthMatch != null && !isNorthMatch(northHand)) {
        continue;
      }

      // North is valid! Now find a matching South from remaining 39 cards
      final remaining = deck.sublist(13);
      for (int inner = 0; inner < maxInnerAttempts; inner++) {
        remaining.shuffle(_random);
        final southHand = Hand(remaining.sublist(0, 13));
        if ((isSouthMatch == null || isSouthMatch(southHand)) &&
            (isPartnershipMatch == null || isPartnershipMatch(northHand, southHand))) {
          final eastHand = Hand(remaining.sublist(13, 26));
          final westHand = Hand(remaining.sublist(26, 39));
          return PartnershipDeal(
            north: northHand,
            east: eastHand,
            south: southHand,
            west: westHand,
          );
        }
      }
    }
    // Fallback if no matching deal could be found within attempt budget
    return isNorthMatch != null
        ? dealWhereNorthOpensTarget(isTargetMatch: isNorthMatch)
        : dealFullBoard();
  }

  /// Deals a board where South holds an opening hand (11+ HCP).
  PartnershipDeal dealWhereSouthOpens({int maxAttempts = 500}) {
    for (int i = 0; i < maxAttempts; i++) {
      final board = dealFullBoard();
      if (board.south.hcp >= 11) {
        return board;
      }
    }
    return dealFullBoard();
  }

  /// Deals a 13-card hand that satisfies the given [constraint].
  Hand? dealTargetedHand(HandConstraint constraint, {int maxAttempts = 1000}) {
    for (int i = 0; i < maxAttempts; i++) {
      final hand = dealRandomHand();
      final result = constraint.evaluate(hand, _valuation);
      if (result.isMatch) {
        return hand;
      }
    }
    return null;
  }

  /// Preset deal generators for targeted training scenarios.
  Hand dealMajorOpeningHand() {
    final constraint = const CompositeConstraint(
      children: [
        HcpConstraint(min: 10, max: 21),
        CompositeConstraint(
          children: [
            SuitLengthConstraint(suit: Suit.hearts, min: 5),
            SuitLengthConstraint(suit: Suit.spades, min: 5),
          ],
          isAnd: false, // OR
        ),
      ],
      isAnd: true,
    );
    return dealTargetedHand(constraint) ?? dealRandomHand();
  }

  Hand dealStrongNtHand() {
    final constraint = const CompositeConstraint(
      children: [
        HcpConstraint(min: 15, max: 17),
        ShapeConstraint(requiresBalanced: true),
        SuitLengthConstraint(suit: Suit.hearts, max: 4),
        SuitLengthConstraint(suit: Suit.spades, max: 4),
      ],
      isAnd: true,
    );
    return dealTargetedHand(constraint) ?? dealRandomHand();
  }

  Hand dealWeakHand() {
    final constraint = const HcpConstraint(min: 0, max: 9);
    return dealTargetedHand(constraint) ?? dealRandomHand();
  }

  /// Deals a board where North and South hands match the initial bidding calls in [systemSequence].
  PartnershipDeal dealBoardForSequence(List<String> systemSequence, {bool isNorthDealer = true}) {
    if (systemSequence.isEmpty) {
      return isNorthDealer ? dealWhereNorthOpens() : dealWhereSouthOpens();
    }

    final c0 = systemSequence[0].toLowerCase().replaceAll(RegExp(r'[^0-9a-z]'), '');
    final c1 = systemSequence.length > 1
        ? systemSequence[1].toLowerCase().replaceAll(RegExp(r'[^0-9a-z]'), '')
        : null;

    bool Function(Hand)? openerFilter;
    bool Function(Hand)? responderFilter;

    if (c0 == 'pass') {
      openerFilter = (h) => h.hcp <= 11;
      if (c1 == '1s') {
        responderFilter = (h) => h.hcp >= 12 && h.spadesLength >= 5;
        // For passed hand responding to 1S with Drury, passed hand holds 9-11 HCP with 3+ spades
        openerFilter = (h) => h.hcp >= 9 && h.hcp <= 11 && h.spadesLength >= 3;
      } else if (c1 == '1h') {
        responderFilter = (h) => h.hcp >= 12 && h.heartsLength >= 5;
        // For passed hand responding to 1H with Drury, passed hand holds 9-11 HCP with 3+ hearts
        openerFilter = (h) => h.hcp >= 9 && h.hcp <= 11 && h.heartsLength >= 3;
      }
    } else if (c0 == '1s') {
      openerFilter = (h) => h.hcp >= 12 && h.spadesLength >= 5;
    } else if (c0 == '1h') {
      openerFilter = (h) => h.hcp >= 12 && h.heartsLength >= 5;
    } else if (c0 == '1nt') {
      openerFilter = (h) => h.hcp >= 15 && h.hcp <= 17 && h.isBalanced;
    } else if (c0 == '1c') {
      openerFilter = (h) => h.hcp >= 12 && h.clubsLength >= 3;
    } else if (c0 == '1d') {
      openerFilter = (h) => h.hcp >= 12 && h.diamondsLength >= 3;
    } else if (c0 == '2c') {
      openerFilter = (h) => (h.isBalanced && h.hcp >= 22) || h.hcp >= 20 || (h.losingTrickCount <= 4 && h.hcp >= 16);
    } else if (c0 == '2h' || c0 == '2s' || c0 == '2d') {
      final suitLength = (c0 == '2h') ? (Hand h) => h.heartsLength : (c0 == '2s' ? (Hand h) => h.spadesLength : (Hand h) => h.diamondsLength);
      openerFilter = (h) => h.hcp >= 5 && h.hcp <= 10 && suitLength(h) >= 6;
    } else {
      openerFilter = (h) => h.hcp >= 11;
    }

    if (c1 != null) {
      if ((c0 == '1s' || c0 == '1h') && c1 == '2nt') {
        final majorSuitLength = (c0 == '1s') ? (Hand h) => h.spadesLength : (Hand h) => h.heartsLength;
        responderFilter = (h) => h.hcp >= 13 && majorSuitLength(h) >= 4;
      } else if (c0 == '2c' && c1 == '2d') {
        responderFilter = (h) => true; // 2D waiting / negative
      } else if (c0 == '1nt' && c1 == '2c') {
        responderFilter = (h) => h.hcp >= 8 && (h.heartsLength >= 4 || h.spadesLength >= 4);
      } else if (c0 == '1nt' && c1 == '2d') {
        responderFilter = (h) => h.heartsLength >= 5;
      } else if (c0 == '1nt' && c1 == '2h') {
        responderFilter = (h) => h.spadesLength >= 5;
      } else if (c0 == '1c' && c1 == '1d') {
        responderFilter = (h) => h.hcp >= 6 && h.diamondsLength >= 4;
      } else if ((c0 == '1c' || c0 == '1d') && c1 == '1h') {
        responderFilter = (h) => h.hcp >= 6 && h.heartsLength >= 4;
      } else if ((c0 == '1c' || c0 == '1d') && c1 == '1s') {
        responderFilter = (h) => h.hcp >= 6 && h.spadesLength >= 4;
      } else if ((c0 == '1h' || c0 == '1s') && c1 == '2c') {
        responderFilter = (h) => h.hcp >= 12 && h.clubsLength >= 3;
      } else if ((c0 == '1h' || c0 == '1s') && c1 == '2d') {
        responderFilter = (h) => h.hcp >= 12 && h.diamondsLength >= 4;
      } else if (c0 == '1s' && c1 == '2h') {
        responderFilter = (h) => h.hcp >= 12 && h.heartsLength >= 5;
      } else if ((c0 == '1h' || c0 == '1s') && c1 == '3d') {
        // 4-card limit raise (10-11 HCP) over major opening: ML edge case (22-25 combined HCP)
        final majorSuitLength = (c0 == '1s') ? (Hand h) => h.spadesLength : (Hand h) => h.heartsLength;
        openerFilter = (h) => h.hcp >= 12 && h.hcp <= 15 && majorSuitLength(h) >= 5;
        responderFilter = (h) => h.hcp >= 10 && h.hcp <= 11 && majorSuitLength(h) >= 4;
      } else if (c0 == '1s' && c1 == '1nt') {
        responderFilter = (h) => h.hcp >= 6 && h.hcp <= 12 && h.spadesLength <= 2;
      }
    }

    // Check third bid (e.g. 1m - 1x - 1NT checkback)
    if (systemSequence.length > 2) {
      final c2 = systemSequence[2].toLowerCase().replaceAll(RegExp(r'[^0-9a-z]'), '');
      if (c2 == '1nt') {
        openerFilter = (h) => h.hcp >= 12 && h.hcp <= 14 && h.isBalanced;
      }
    }

    final northFilter = isNorthDealer ? openerFilter : responderFilter;
    final southFilter = isNorthDealer ? responderFilter : openerFilter;

    final isEdgeSeq = (c0 == '1h' || c0 == '1s') && c1 == '3d';

    return dealTargetedBoard(
      isNorthMatch: northFilter,
      isSouthMatch: southFilter,
      isPartnershipMatch: isEdgeSeq
          ? (n, s) {
              final comb = n.hcp + s.hcp;
              return comb >= 22 && comb <= 25;
            }
          : null,
    );
  }

  /// Generates a board in the Borderline Game Decision window (22–25 Combined HCP).
  /// If [expectAccept] is true, generates a hand with 8+ fit that the ML model accepts.
  /// If [expectAccept] is false, generates a hand without 8-card fit that the ML model declines.
  PartnershipDeal dealMLBorderlineGameDeal({String strain = 'h', bool? expectAccept}) {
    final s = strain.toLowerCase();
    final isHearts = s.contains('h');
    final isSpades = s.contains('s');
    final isNt = s.contains('nt');

    return dealTargetedBoard(
      isNorthMatch: (n) {
        if (isNt) return n.hcp >= 15 && n.hcp <= 17 && n.isBalanced;
        if (isHearts) return n.hcp >= 12 && n.hcp <= 15 && n.heartsLength >= 5;
        if (isSpades) return n.hcp >= 12 && n.hcp <= 15 && n.spadesLength >= 5;
        return n.hcp >= 12 && n.hcp <= 15;
      },
      isSouthMatch: (sHand) {
        if (expectAccept == false) {
          if (isHearts) return sHand.hcp >= 9 && sHand.hcp <= 11 && sHand.heartsLength <= 2;
          if (isSpades) return sHand.hcp >= 9 && sHand.hcp <= 11 && sHand.spadesLength <= 2;
        } else {
          if (isHearts) return sHand.hcp >= 9 && sHand.hcp <= 11 && sHand.heartsLength >= 3;
          if (isSpades) return sHand.hcp >= 9 && sHand.hcp <= 11 && sHand.spadesLength >= 3;
        }
        return sHand.hcp >= 9 && sHand.hcp <= 11;
      },
      isPartnershipMatch: (n, sHand) {
        final combHcp = n.hcp + sHand.hcp;
        if (combHcp < 22 || combHcp > 25) return false;
        final spadeFit = n.spadesLength + sHand.spadesLength;
        final heartFit = n.heartsLength + sHand.heartsLength;
        final maxFit = spadeFit > heartFit ? spadeFit : heartFit;
        final controls = n.controls + sHand.controls;
        final ltc = n.losingTrickCount + sHand.losingTrickCount;
        if (expectAccept == null) return true;
        if (expectAccept) {
          return maxFit >= 8 && controls >= 5 && ltc <= 14;
        } else {
          return maxFit <= 8 && ltc >= 15;
        }
      },
    );
  }

  /// Generates a board in the Marginal Slam Decision window (29–32 Combined HCP).
  PartnershipDeal dealMLMarginalSlamDeal({String strain = 's', bool? expectAccept}) {
    final s = strain.toLowerCase();
    final isHearts = s.contains('h');
    final isSpades = s.contains('s');

    return dealTargetedBoard(
      isNorthMatch: (n) {
        if (isHearts) return n.hcp >= 15 && n.hcp <= 19 && n.heartsLength >= 5;
        if (isSpades) return n.hcp >= 15 && n.hcp <= 19 && n.spadesLength >= 5;
        return n.hcp >= 15 && n.hcp <= 19;
      },
      isSouthMatch: (sHand) {
        if (isHearts) return sHand.hcp >= 12 && sHand.hcp <= 15 && sHand.heartsLength >= 3;
        if (isSpades) return sHand.hcp >= 12 && sHand.hcp <= 15 && sHand.spadesLength >= 3;
        return sHand.hcp >= 12 && sHand.hcp <= 15;
      },
      isPartnershipMatch: (n, sHand) {
        final combHcp = n.hcp + sHand.hcp;
        if (combHcp < 29 || combHcp > 32) return false;
        if (expectAccept == null) return true;
        final controls = n.controls + sHand.controls;
        final ltc = n.losingTrickCount + sHand.losingTrickCount;
        if (expectAccept) {
          return controls >= 9 && ltc <= 8;
        } else {
          return controls <= 7 || ltc >= 10;
        }
      },
    );
  }

  /// Generates a deal where raw HCP is 10–11, but ML Hand Valuation upgrades it to 12+ Effective HCP.
  PartnershipDeal dealMLValuationUpgradeDeal() {
    final mlVal = MLHandValuation();
    return dealTargetedBoard(
      isNorthMatch: (n) {
        final raw = n.hcp;
        if (raw < 10 || raw > 11) return false;
        final eff = mlVal.evaluatePoints(n);
        return eff >= 12.0 && (n.heartsLength >= 5 || n.spadesLength >= 5);
      },
      isSouthMatch: (sHand) => sHand.hcp >= 10 && sHand.hcp <= 13,
    );
  }

  /// Generates a deal with extreme major shape (8+ cards, low LTC) opposite opening/invitational values.
  PartnershipDeal dealExtremeShapeMajorDeal() {
    for (int attempt = 0; attempt < 50; attempt++) {
      final deck = createDeck()..shuffle(_random);
      final suit = _random.nextBool() ? Suit.hearts : Suit.spades;
      final targetLength = 8 + _random.nextInt(2); // 8 or 9 cards

      final suitCards = deck.where((c) => c.suit == suit).toList();
      final otherCards = deck.where((c) => c.suit != suit).toList();

      final northCards = <BridgeCard>[
        ...suitCards.take(targetLength),
        ...otherCards.take(13 - targetLength),
      ];
      final north = Hand(northCards);

      // Check LTC <= 5
      if (north.losingTrickCount > 5) continue;

      final remaining = deck.where((c) => !northCards.contains(c)).toList();
      // South needs 10-13 HCP
      for (int sAttempt = 0; sAttempt < 100; sAttempt++) {
        remaining.shuffle(_random);
        final south = Hand(remaining.take(13).toList());
        if (south.hcp >= 10 && south.hcp <= 13) {
          final east = Hand(remaining.skip(13).take(13).toList());
          final west = Hand(remaining.skip(26).take(13).toList());
          return PartnershipDeal(north: north, east: east, south: south, west: west);
        }
      }
    }
    return dealFullBoard();
  }
}
