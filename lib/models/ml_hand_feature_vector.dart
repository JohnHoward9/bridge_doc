import 'card.dart';
import 'hand.dart';
import 'seat_belief_state.dart';
import 'bidding_state_context.dart';

/// Extracts standardized numerical feature vectors for Machine Learning hand valuation.
class MLHandFeatureVector {
  static const List<String> featureNames = [
    'raw_hcp',
    'aces',
    'kings',
    'queens',
    'jacks',
    'tens',
    'nines',
    'length_1',
    'length_2',
    'length_3',
    'length_4',
    'shape_4333',
    'shape_5332',
    'shape_6421',
    'shape_6331',
    'honors_in_long_suits_ratio',
    'opp_king_lho_trapped',
    'opp_king_rho_protected',
    'opp_soft_lho',
    'opp_tenace_stopper',
    'is_notrump',
    'has_trump_shortness',
    'partner_working_honor',
  ];

  /// Extracts the feature vector for a given hand and auction context.
  static List<double> extract(
    Hand hand, {
    Suit? trumpSuit,
    Suit? partnerSuit,
    List<OpponentSuitAction> opponentActions = const [],
    SeatBeliefState? partnerBelief,
    bool isNotrumpStrain = false,
  }) {
    final rawHcp = hand.hcp.toDouble();
    final aces = hand.cards.where((c) => c.rank == Rank.ace).length.toDouble();
    final kings = hand.cards.where((c) => c.rank == Rank.king).length.toDouble();
    final queens = hand.cards.where((c) => c.rank == Rank.queen).length.toDouble();
    final jacks = hand.cards.where((c) => c.rank == Rank.jack).length.toDouble();
    final tens = hand.cards.where((c) => c.rank == Rank.ten).length.toDouble();
    final nines = hand.cards.where((c) => c.rank == Rank.nine).length.toDouble();

    // Sorted suit lengths (longest to shortest)
    final suitLengths = [
      MapEntry(Suit.spades, hand.spadesLength),
      MapEntry(Suit.hearts, hand.heartsLength),
      MapEntry(Suit.diamonds, hand.diamondsLength),
      MapEntry(Suit.clubs, hand.clubsLength),
    ]..sort((a, b) => b.value.compareTo(a.value));

    final rawL1 = suitLengths[0].value;
    final rawL2 = suitLengths[1].value;
    final rawL3 = suitLengths[2].value;
    final rawL4 = suitLengths[3].value;

    // Detect extreme misfit: holding a 6+ suit when partner promises at most 1 card
    final isMisfit = partnerBelief != null &&
        rawL1 >= 6 &&
        partnerBelief.maxSuitLength[suitLengths[0].key] != null &&
        partnerBelief.maxSuitLength[suitLengths[0].key]! <= 1;

    // Surplus length over 5 in longest suit (dampened in unplayable misfit)
    final l1 = isMisfit ? 0.0 : (rawL1 - 5).clamp(0, 8).toDouble();
    final l2 = rawL2.toDouble();
    final l3 = rawL3.toDouble();
    final l4 = rawL4.toDouble();

    // Specific shape indicators
    final is4333 = (rawL1 == 4 && rawL2 == 3 && rawL3 == 3 && rawL4 == 3) ? 1.0 : 0.0;
    final is5332 = (rawL1 == 5 && rawL2 == 3 && rawL3 == 3 && rawL4 == 2) ? 1.0 : 0.0;
    final is6421 = (rawL1 == 6 && rawL2 == 4 && rawL3 == 2 && rawL4 == 1) ? 1.0 : 0.0;
    final is6331 = (rawL1 == 6 && rawL2 == 3 && rawL3 == 3 && rawL4 == 1) ? 1.0 : 0.0;

    // Honor concentration: HCP in the 2 longest suits / total HCP
    final longestSuits = [suitLengths[0].key, suitLengths[1].key];
    final longSuitsHcp = hand.suitHcp(longestSuits[0]) + hand.suitHcp(longestSuits[1]);
    final honorsInLongSuitsRatio = rawHcp > 0 ? (longSuitsHcp / rawHcp) : 0.0;

    // Positional opponent actions
    double oppKingLhoTrapped = 0.0;
    double oppKingRhoProtected = 0.0;
    double oppSoftLho = 0.0;
    double oppTenaceStopper = 0.0;

    for (final oppAction in opponentActions) {
      final s = oppAction.suit;
      final oCards = hand.cards.where((c) => c.suit == s).toList();
      if (oCards.isEmpty) continue;

      final hasAce = oCards.any((c) => c.rank == Rank.ace);
      final hasKing = oCards.any((c) => c.rank == Rank.king);
      final hasQueen = oCards.any((c) => c.rank == Rank.queen);
      final hasJack = oCards.any((c) => c.rank == Rank.jack);

      if (hasKing && !hasAce) {
        if (oppAction.position == RelativeOpponentPosition.lho) {
          oppKingLhoTrapped = 1.0;
        } else if (oppAction.position == RelativeOpponentPosition.rho) {
          oppKingRhoProtected = 1.0;
        }
      }

      if ((hasQueen || hasJack) && !hasAce && !hasKing && oCards.length <= 3) {
        if (oppAction.position == RelativeOpponentPosition.lho) {
          oppSoftLho = 1.0;
        }
      }

      if (hasAce && (hasKing || hasQueen)) {
        oppTenaceStopper = 1.0;
      }
    }

    // Strain, Shortness, and Misfit
    double isNotrump = 0.0;
    if (isNotrumpStrain || isMisfit) {
      isNotrump = 1.0;
    }

    double hasTrumpShortness = 0.0;
    if (trumpSuit != null) {
      for (final s in Suit.values) {
        if (s == trumpSuit) continue;
        final len = hand.length(s);
        if (len == 0) {
          hasTrumpShortness = 2.0; // Void
          break;
        } else if (len == 1 && hasTrumpShortness < 1.0) {
          hasTrumpShortness = 1.0; // Singleton
        }
      }
    }

    // Partner mesh & working honor
    double partnerWorkingHonor = 0.0;
    final targetPartnerSuit = partnerSuit ?? trumpSuit;
    if (targetPartnerSuit != null) {
      final pCards = hand.cards.where((c) => c.suit == targetPartnerSuit);
      if (pCards.any((c) => c.rank == Rank.ace || c.rank == Rank.king)) {
        partnerWorkingHonor = 1.0;
      }
    }
    if (partnerBelief != null) {
      final longestSuit = suitLengths[0].key;
      final partnerMinInLongest = partnerBelief.minSuitLength[longestSuit] ?? 0;
      if (partnerMinInLongest >= 3) {
        partnerWorkingHonor = 1.0;
      }
    }

    return [
      rawHcp, // 0
      aces, // 1
      kings, // 2
      queens, // 3
      jacks, // 4
      tens, // 5
      nines, // 6
      l1, // 7
      l2, // 8
      l3, // 9
      l4, // 10
      is4333, // 11
      is5332, // 12
      is6421, // 13
      is6331, // 14
      honorsInLongSuitsRatio, // 15
      oppKingLhoTrapped, // 16
      oppKingRhoProtected, // 17
      oppSoftLho, // 18
      oppTenaceStopper, // 19
      isNotrump, // 20
      hasTrumpShortness, // 21
      partnerWorkingHonor, // 22
    ];
  }
}
