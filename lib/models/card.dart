/// Bridge suits in standard rank order (Clubs lowest, Spades highest).
enum Suit {
  clubs,
  diamonds,
  hearts,
  spades;

  String get symbol {
    switch (this) {
      case Suit.clubs:
        return '♣';
      case Suit.diamonds:
        return '♦';
      case Suit.hearts:
        return '♥';
      case Suit.spades:
        return '♠';
    }
  }

  String get shortName {
    switch (this) {
      case Suit.clubs:
        return 'C';
      case Suit.diamonds:
        return 'D';
      case Suit.hearts:
        return 'H';
      case Suit.spades:
        return 'S';
    }
  }

  bool get isMajor => this == Suit.hearts || this == Suit.spades;
  bool get isMinor => this == Suit.clubs || this == Suit.diamonds;

  static Suit? fromString(String str) {
    final s = str.trim().toUpperCase();
    if (s.startsWith('C') || s.contains('♣')) return Suit.clubs;
    if (s.startsWith('D') || s.contains('♦')) return Suit.diamonds;
    if (s.startsWith('H') || s.contains('♥')) return Suit.hearts;
    if (s.startsWith('S') || s.contains('♠')) return Suit.spades;
    return null;
  }
}

/// Bridge card ranks from Two up to Ace.
enum Rank {
  two(2, '2', 0),
  three(3, '3', 0),
  four(4, '4', 0),
  five(5, '5', 0),
  six(6, '6', 0),
  seven(7, '7', 0),
  eight(8, '8', 0),
  nine(9, '9', 0),
  ten(10, 'T', 0),
  jack(11, 'J', 1),
  queen(12, 'Q', 2),
  king(13, 'K', 3),
  ace(14, 'A', 4);

  final int value;
  final String symbol;
  final int hcp;

  const Rank(this.value, this.symbol, this.hcp);

  static Rank? fromChar(String ch) {
    switch (ch.toUpperCase()) {
      case '2':
        return Rank.two;
      case '3':
        return Rank.three;
      case '4':
        return Rank.four;
      case '5':
        return Rank.five;
      case '6':
        return Rank.six;
      case '7':
        return Rank.seven;
      case '8':
        return Rank.eight;
      case '9':
        return Rank.nine;
      case 'T':
      case '1': // e.g. '10'
        return Rank.ten;
      case 'J':
        return Rank.jack;
      case 'Q':
        return Rank.queen;
      case 'K':
        return Rank.king;
      case 'A':
        return Rank.ace;
      default:
        return null;
    }
  }
}

/// Represents a single playing card in bridge.
class BridgeCard implements Comparable<BridgeCard> {
  final Suit suit;
  final Rank rank;

  const BridgeCard(this.suit, this.rank);

  int get hcp => rank.hcp;

  @override
  int compareTo(BridgeCard other) {
    if (suit != other.suit) {
      // Suit order Spades down to Clubs
      return other.suit.index.compareTo(suit.index);
    }
    // High rank first
    return other.rank.value.compareTo(rank.value);
  }

  @override
  String toString() => '${suit.symbol}${rank.symbol}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BridgeCard && runtimeType == other.runtimeType && suit == other.suit && rank == other.rank;

  @override
  int get hashCode => suit.hashCode ^ rank.hashCode;
}
