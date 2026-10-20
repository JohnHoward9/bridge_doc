import 'card.dart';

/// Represents a bridge hand containing 13 cards.
class Hand {
  final List<BridgeCard> cards;

  Hand(List<BridgeCard> cards) : cards = List.unmodifiable(cards..sort());

  /// Parse a hand from standard colon or dot separated suit format:
  /// Spades:Hearts:Diamonds:Clubs (e.g. "A3:KQ5432:4:K432" or "A3.KQ5432.4.K432")
  factory Hand.fromString(String text) {
    var s = text.trim();
    if (s.startsWith('N:') || s.startsWith('S:') || s.startsWith('E:') || s.startsWith('W:')) {
      s = s.substring(2).trim();
    }

    final delimiter = s.contains(':') ? ':' : '.';
    final parts = s.split(delimiter);
    if (parts.length != 4) {
      throw FormatException('Hand format must be Spades:Hearts:Diamonds:Clubs, got: "$text"');
    }

    final List<BridgeCard> cards = [];
    final suits = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];

    for (int i = 0; i < 4; i++) {
      final suit = suits[i];
      final rankChars = parts[i].trim();
      for (int j = 0; j < rankChars.length; j++) {
        final ch = rankChars[j];
        if (ch == '1' && j + 1 < rankChars.length && rankChars[j + 1] == '0') {
          cards.add(BridgeCard(suit, Rank.ten));
          j++; // skip '0'
        } else {
          final rank = Rank.fromChar(ch);
          if (rank != null) {
            cards.add(BridgeCard(suit, rank));
          }
        }
      }
    }

    return Hand(cards);
  }

  /// Cards in a specific suit.
  List<BridgeCard> cardsInSuit(Suit suit) => cards.where((c) => c.suit == suit).toList();

  /// Length of a specific suit.
  int length(Suit suit) => cards.where((c) => c.suit == suit).length;

  int get spadesLength => length(Suit.spades);
  int get heartsLength => length(Suit.hearts);
  int get diamondsLength => length(Suit.diamonds);
  int get clubsLength => length(Suit.clubs);

  /// Total Milton Work High Card Points (A=4, K=3, Q=2, J=1).
  int get hcp => cards.fold(0, (sum, c) => sum + c.hcp);

  /// Total Aces in hand (0-4).
  int get aceCount => cards.where((c) => c.rank == Rank.ace).length;

  /// Total Kings in hand (0-4).
  int get kingCount => cards.where((c) => c.rank == Rank.king).length;

  /// Total Key Cards for RKCB given [trumpSuit] (4 Aces + King of trumpSuit).
  int keyCardCount(Suit trumpSuit) {
    int count = aceCount;
    if (cards.any((c) => c.suit == trumpSuit && c.rank == Rank.king)) {
      count++;
    }
    return count;
  }

  /// Whether the hand holds the Queen of [trumpSuit].
  bool hasQueen(Suit trumpSuit) => cards.any((c) => c.suit == trumpSuit && c.rank == Rank.queen);

  /// Total controls (A=2, K=1).
  int get controls => aceCount * 2 + kingCount;

  /// Total controls (A=2, K=1) in suits other than [trumpSuit].
  int outsideControls(Suit trumpSuit) {
    int ctrl = 0;
    for (final s in Suit.values) {
      if (s == trumpSuit) continue;
      final suitCards = cardsInSuit(s);
      if (suitCards.any((c) => c.rank == Rank.ace)) ctrl += 2;
      if (suitCards.any((c) => c.rank == Rank.king)) ctrl += 1;
    }
    return ctrl;
  }

  /// Returns the longest suit in the hand (breaking ties by rank order S, H, D, C).
  Suit get longestSuit {
    Suit best = Suit.spades;
    int maxLen = length(Suit.spades);
    for (final s in [Suit.hearts, Suit.diamonds, Suit.clubs]) {
      final len = length(s);
      if (len > maxLen) {
        maxLen = len;
        best = s;
      }
    }
    return best;
  }

  /// Whether [suit] is "solid" (at least [minLength] cards headed by AKQ).
  bool isSolidSuit(Suit suit, {int minLength = 7}) {
    final sCards = cardsInSuit(suit);
    if (sCards.length < minLength) return false;
    final hasA = sCards.any((c) => c.rank == Rank.ace);
    final hasK = sCards.any((c) => c.rank == Rank.king);
    final hasQ = sCards.any((c) => c.rank == Rank.queen);
    return hasA && hasK && hasQ;
  }

  /// Whether the hand holds a solid minor (Clubs or Diamonds, 7+ cards headed by AKQ).
  bool isSolidMinor({int minLength = 7}) {
    return isSolidSuit(Suit.clubs, minLength: minLength) ||
        isSolidSuit(Suit.diamonds, minLength: minLength);
  }

  /// Solid minor suit (or null if none).
  Suit? get solidMinorSuit {
    if (isSolidSuit(Suit.clubs)) return Suit.clubs;
    if (isSolidSuit(Suit.diamonds)) return Suit.diamonds;
    return null;
  }

  /// Controls outside the solid minor (or longest minor).
  int get outsideControlsForSolidMinor {
    final sm = solidMinorSuit;
    if (sm != null) {
      return outsideControls(sm);
    }
    final minor = clubsLength >= diamondsLength ? Suit.clubs : Suit.diamonds;
    return outsideControls(minor);
  }

  /// Losing Trick Count (LTC) across all four suits.
  int get losingTrickCount {
    int ltc = 0;
    for (final suit in [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs]) {
      final sCards = cardsInSuit(suit);
      final len = sCards.length;
      if (len == 0) continue;
      if (len == 1) {
        if (sCards.first.rank != Rank.ace) ltc += 1;
      } else if (len == 2) {
        if (!sCards.any((c) => c.rank == Rank.ace)) ltc += 1;
        if (!sCards.any((c) => c.rank == Rank.king)) ltc += 1;
      } else {
        if (!sCards.any((c) => c.rank == Rank.ace)) ltc += 1;
        if (!sCards.any((c) => c.rank == Rank.king)) ltc += 1;
        if (!sCards.any((c) => c.rank == Rank.queen)) ltc += 1;
      }
    }
    return ltc;
  }

  /// HCP in a specific suit.
  int suitHcp(Suit suit) => cardsInSuit(suit).fold(0, (sum, c) => sum + c.hcp);

  /// Distribution shape sorted descending, e.g. "6421" or "5332".
  String get sortedShapePattern {
    final lengths = [spadesLength, heartsLength, diamondsLength, clubsLength]..sort((a, b) => b.compareTo(a));
    return lengths.join('');
  }

  /// Exact distribution by suit order S-H-D-C, e.g. "2-6-1-4".
  String get exactDistribution => '$spadesLength-$heartsLength-$diamondsLength-$clubsLength';

  /// Whether the hand is balanced (5332, 4432, 4333).
  bool get isBalanced {
    final p = sortedShapePattern;
    return p == '5332' || p == '4432' || p == '4333';
  }

  /// Whether the hand is semi-balanced (5422, 6322 or balanced).
  bool get isSemiBalanced {
    final p = sortedShapePattern;
    return isBalanced || p == '5422' || p == '6322';
  }

  /// Returns true if the suit contains top honors matching [pattern],
  /// e.g. 'HHH' (at least 3 of A, K, Q, J, 10).
  bool hasHonorCount(Suit suit, int count) {
    final honors = cardsInSuit(suit).where((c) => c.rank.value >= Rank.ten.value).length;
    return honors >= count;
  }

  @override
  String toString() {
    String suitCards(Suit s) => cardsInSuit(s).map((c) => c.rank.symbol).join('');
    return '♠${suitCards(Suit.spades)} ♥${suitCards(Suit.hearts)} ♦${suitCards(Suit.diamonds)} ♣${suitCards(Suit.clubs)} ($hcp HCP)';
  }
}
