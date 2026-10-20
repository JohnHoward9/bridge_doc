import '../models/card.dart';
import '../models/hand.dart';
import '../engine/deal_generator.dart';
import '../engine/auction_engine.dart';

/// Metadata configuration for exported bridge boards.
class BoardExportOptions {
  final String event;
  final String site;
  final String date;
  final String boardNumber;
  final String dealer; // 'N', 'E', 'S', 'W'
  final String vulnerable; // 'None', 'NS', 'EW', 'All'
  final String systemName;
  final String scoring;

  const BoardExportOptions({
    this.event = 'Gavin Wolpert Practice Studio',
    this.site = 'Antigravity Bridge',
    this.date = '2026.10.15',
    this.boardNumber = '1',
    this.dealer = 'N',
    this.vulnerable = 'None',
    this.systemName = 'Gavin Wolpert 2/1 GF',
    this.scoring = 'IMP',
  });
}

/// Service for serializing bridge deals and auctions into standard Portable Bridge
/// Notation (PBN) and Bridge Base Online (BBO LIN) formats.
class BoardExporter {
  /// Formats a [Hand] into standard PBN dot-separated format:
  /// `Spades.Hearts.Diamonds.Clubs` (e.g. `AKJ4.QT5.83.K982`).
  static String handToPbn(Hand hand) {
    String suitSymbols(Suit s) => hand.cardsInSuit(s).map((c) => c.rank.symbol).join('');
    return '${suitSymbols(Suit.spades)}.${suitSymbols(Suit.hearts)}.${suitSymbols(Suit.diamonds)}.${suitSymbols(Suit.clubs)}';
  }

  /// Formats a [Hand] into BBO LIN suit notation:
  /// `S<spades>H<hearts>D<diamonds>C<clubs>` (e.g. `SAKJ4HQT5D83CK982`).
  static String handToLin(Hand hand) {
    String suitSymbols(Suit s) => hand.cardsInSuit(s).map((c) => c.rank.symbol).join('');
    return 'S${suitSymbols(Suit.spades)}H${suitSymbols(Suit.hearts)}D${suitSymbols(Suit.diamonds)}C${suitSymbols(Suit.clubs)}';
  }

  /// Normalizes a bidding call for PBN (e.g. '1H', 'Pass', 'X', 'XX', '3NT').
  static String normalizeCallForPbn(String call) {
    var c = call.trim().toUpperCase();
    c = c.replaceAll('♠', 'S').replaceAll('♥', 'H').replaceAll('♦', 'D').replaceAll('♣', 'C');
    if (c == 'PASS') return 'Pass';
    if (c == 'DBL' || c == 'X') return 'X';
    if (c == 'RDBL' || c == 'XX') return 'XX';
    return c;
  }

  /// Normalizes a bidding call for BBO LIN (e.g. '1H', 'p', 'd', 'r', '3N').
  static String normalizeCallForLin(String call) {
    var c = call.trim().toLowerCase();
    c = c.replaceAll('♠', 's').replaceAll('♥', 'h').replaceAll('♦', 'd').replaceAll('♣', 'c');
    if (c == 'pass') return 'p';
    if (c == 'dbl' || c == 'x') return 'd';
    if (c == 'rdbl' || c == 'xx') return 'r';
    if (c.endsWith('nt')) return '${c.substring(0, c.length - 2)}N';
    return c.toUpperCase();
  }

  /// Exports a complete deal and auction history into standard Portable Bridge Notation (PBN v2.1).
  static String exportToPbn({
    required PartnershipDeal deal,
    List<AuctionEntry> history = const [],
    BoardExportOptions options = const BoardExportOptions(),
  }) {
    final buffer = StringBuffer();
    buffer.writeln('% PBN 2.1 Exported by Antigravity Bridge Studio');
    buffer.writeln('[Event "${options.event}"]');
    buffer.writeln('[Site "${options.site}"]');
    buffer.writeln('[Date "${options.date}"]');
    buffer.writeln('[Board "${options.boardNumber}"]');
    buffer.writeln('[Dealer "${options.dealer.toUpperCase()}"]');
    buffer.writeln('[Vulnerable "${options.vulnerable}"]');
    buffer.writeln('[Scoring "${options.scoring}"]');
    buffer.writeln('[BiddingSystem "${options.systemName}"]');

    // Standard PBN deal order starting with North: N:North East South West
    final nPbn = handToPbn(deal.north);
    final ePbn = handToPbn(deal.east);
    final sPbn = handToPbn(deal.south);
    final wPbn = handToPbn(deal.west);
    buffer.writeln('[Deal "N:$nPbn $ePbn $sPbn $wPbn"]');

    if (history.isNotEmpty) {
      buffer.writeln('[Auction "${options.dealer.toUpperCase()}"]');
      final calls = history.map((e) => normalizeCallForPbn(e.call)).toList();
      for (int i = 0; i < calls.length; i += 4) {
        final chunk = calls.skip(i).take(4).join(' ');
        buffer.writeln(chunk);
      }
    }

    return buffer.toString();
  }

  /// Exports a complete deal and auction history into Bridge Base Online (BBO LIN) notation.
  static String exportToLin({
    required PartnershipDeal deal,
    List<AuctionEntry> history = const [],
    BoardExportOptions options = const BoardExportOptions(),
  }) {
    final buffer = StringBuffer();
    final bNum = options.boardNumber;
    buffer.write('qx|o$bNum|ah|Board $bNum|');

    // Dealer code in LIN: 1=South, 2=West, 3=North, 4=East
    final dealerNum = switch (options.dealer.toUpperCase()) {
      'S' => '1',
      'W' => '2',
      'N' => '3',
      'E' => '4',
      _ => '3',
    };

    // Vulnerability in LIN: o=None, n=NS, e=EW, b=Both
    final vulnCode = switch (options.vulnerable.toLowerCase()) {
      'none' || 'o' => 'o',
      'ns' || 'n' => 'n',
      'ew' || 'e' => 'e',
      'all' || 'both' || 'b' => 'b',
      _ => 'o',
    };
    buffer.write('sv|$vulnCode|');

    // Hands order in LIN md|X...|: starts with dealer, then clockwise
    // e.g. for dealer 3 (North): North, East, South, West
    final handsBySeat = {
      'N': handToLin(deal.north),
      'E': handToLin(deal.east),
      'S': handToLin(deal.south),
      'W': handToLin(deal.west),
    };

    final order = switch (dealerNum) {
      '1' => ['S', 'W', 'N', 'E'],
      '2' => ['W', 'N', 'E', 'S'],
      '3' => ['N', 'E', 'S', 'W'],
      '4' => ['E', 'S', 'W', 'N'],
      _ => ['N', 'E', 'S', 'W'],
    };

    final mdHands = order.map((s) => handsBySeat[s]!).join(',');
    buffer.write('md|$dealerNum$mdHands|');

    // Bids
    for (final entry in history) {
      final linCall = normalizeCallForLin(entry.call);
      buffer.write('mb|$linCall|');
      if (entry.desc != null && entry.desc!.isNotEmpty) {
        buffer.write('an|${entry.desc!.replaceAll('|', '/')}|');
      }
    }

    buffer.write('pg||');
    return buffer.toString();
  }
}
