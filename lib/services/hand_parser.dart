import 'dart:math';
import '../models/card.dart';
import '../models/hand.dart';
import '../engine/deal_generator.dart';

/// Comprehensive parsing service for user-entered bridge hands and deals.
/// Supports multiline suit notation, PBN dot-notation, LIN format, and PBN deals.
class HandParser {
  /// Parses a single suit's rank characters into a list of [BridgeCard]s.
  /// Handles '10' or 'T', dashes '-' or voids.
  static List<BridgeCard> parseSuitRanks(Suit suit, String text) {
    final List<BridgeCard> cards = [];
    final clean = text.trim().toUpperCase().replaceAll('-', '').replaceAll(' ', '');
    for (int i = 0; i < clean.length; i++) {
      final ch = clean[i];
      if (ch == '1' && i + 1 < clean.length && clean[i + 1] == '0') {
        cards.add(BridgeCard(suit, Rank.ten));
        i++; // skip '0'
      } else {
        final rank = Rank.fromChar(ch);
        if (rank != null) {
          cards.add(BridgeCard(suit, rank));
        }
      }
    }
    return cards;
  }

  /// Parses a single hand from text in various formats:
  /// - Dot separated: "K87.AJT976543.K.-" or "K87.AJT976543.K."
  /// - Colon separated: "K87:AJT976543:K:-"
  /// - Multiline:
  ///     S: K87
  ///     H: AJT976543
  ///     D: K
  ///     C: -
  /// - LIN format: "SK87HAJT976543DKC"
  static Hand parseSingleHand(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      throw const FormatException('Hand text cannot be empty');
    }

    // Strip seat prefix if present, e.g. "North:" or "N:"
    text = text.replaceFirst(RegExp(r'^(North|South|East|West|[NSEW])\s*:\s*', caseSensitive: false), '').trim();

    // 1. Check for multiline or explicit suit labels (S:, H:, D:, C: or ♠, ♥, ♦, ♣)
    final suitMap = <Suit, String>{};
    final suitRegex = RegExp(r'([SHDC♠♥♦♣])\s*[:\.]?\s*([0-9TJQKA\- ]*)', caseSensitive: false);
    final matches = suitRegex.allMatches(text).toList();
    if (matches.length >= 2 && matches.any((m) => m.group(1)!.toUpperCase().startsWith('S') || m.group(1) == '♠')) {
      for (final m in matches) {
        final suitChar = m.group(1)!;
        final rankStr = m.group(2) ?? '';
        final suit = Suit.fromString(suitChar);
        if (suit != null) {
          suitMap[suit] = rankStr;
        }
      }
      final List<BridgeCard> cards = [];
      for (final s in [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs]) {
        cards.addAll(parseSuitRanks(s, suitMap[s] ?? ''));
      }
      return Hand(cards);
    }

    // 2. Check for LIN format: "SAK5HQJTD984CK765"
    if (RegExp(r'^[SHDC][0-9TJQKA]+', caseSensitive: false).hasMatch(text) && text.toUpperCase().contains('H')) {
      String? currentSuitStr;
      final buffer = StringBuffer();
      final Map<String, String> linSuits = {'S': '', 'H': '', 'D': '', 'C': ''};
      for (int i = 0; i < text.length; i++) {
        final char = text[i].toUpperCase();
        if ('SHDC'.contains(char)) {
          if (currentSuitStr != null) {
            linSuits[currentSuitStr] = buffer.toString();
            buffer.clear();
          }
          currentSuitStr = char;
        } else {
          buffer.write(char);
        }
      }
      if (currentSuitStr != null) {
        linSuits[currentSuitStr] = buffer.toString();
      }

      final List<BridgeCard> cards = [];
      cards.addAll(parseSuitRanks(Suit.spades, linSuits['S']!));
      cards.addAll(parseSuitRanks(Suit.hearts, linSuits['H']!));
      cards.addAll(parseSuitRanks(Suit.diamonds, linSuits['D']!));
      cards.addAll(parseSuitRanks(Suit.clubs, linSuits['C']!));
      return Hand(cards);
    }

    // 3. Dot or colon separated: "K87.AJT976543.K.-" or "K87:AJT976543:K:"
    final delimiter = text.contains(':') ? ':' : '.';
    final parts = text.split(delimiter);
    if (parts.length == 4) {
      final List<BridgeCard> cards = [];
      cards.addAll(parseSuitRanks(Suit.spades, parts[0]));
      cards.addAll(parseSuitRanks(Suit.hearts, parts[1]));
      cards.addAll(parseSuitRanks(Suit.diamonds, parts[2]));
      cards.addAll(parseSuitRanks(Suit.clubs, parts[3]));
      return Hand(cards);
    }

    throw FormatException(
      'Could not parse hand: "$input". Expected format like "K87.AJT976543.K.-" or "S:K87 H:AJT976543 D:K C:-"',
    );
  }

  /// Parses multiple hands from a freeform deal text.
  /// Can parse:
  /// - Full PBN deal: `[Deal "N:K87.AJT976543.K. JT5.82.AQT83.A64 AQ2.Q.J9742.QJ75 9643.K.65.KT9832"]`
  /// - PBN line: `N:K87.AJT976543.K.- JT5.82.AQT83.A64 AQ2.Q.J9742.QJ75 9643.K.65.KT9832`
  /// - Multiline labeled format:
  ///     North:
  ///     S: K87
  ///     H: AJT976543
  ///     D: K
  ///     C: -
  ///     South:
  ///     S: AQ2
  ///     ...
  static Map<String, Hand> parseDealText(String input) {
    final Map<String, Hand> result = {};
    var text = input.trim();

    // 1. Check for standard PBN Deal tag: [Deal "N:hand1 hand2 hand3 hand4"]
    final dealTagMatch = RegExp(r'\[Deal\s+"([NSEW]):([^"]+)"\]', caseSensitive: false).firstMatch(text);
    if (dealTagMatch != null) {
      final startSeat = dealTagMatch.group(1)!.toUpperCase();
      final dealBody = dealTagMatch.group(2)!.trim();
      return _parsePbnDealBody(startSeat, dealBody);
    }

    // 2. Check for PBN line: N:hand1 hand2 hand3 hand4
    final pbnLineMatch = RegExp(r'^([NSEW]):([A-Za-z0-9\.\-\s]+)$').firstMatch(text);
    if (pbnLineMatch != null && pbnLineMatch.group(2)!.trim().split(RegExp(r'\s+')).length >= 2) {
      final startSeat = pbnLineMatch.group(1)!.toUpperCase();
      final dealBody = pbnLineMatch.group(2)!.trim();
      return _parsePbnDealBody(startSeat, dealBody);
    }

    // 3. Multiline format with explicit seat headers (e.g. "North:", "South:", etc.)
    final seatSectionRegex = RegExp(
      r'(North|South|East|West|[NSEW])\s*:\s*([^]+?)(?=(?:North|South|East|West|[NSEW])\s*:|$)',
      caseSensitive: false,
    );
    final seatMatches = seatSectionRegex.allMatches(text).toList();
    if (seatMatches.isNotEmpty) {
      for (final m in seatMatches) {
        final seatLabel = m.group(1)!.toUpperCase();
        final body = m.group(2)!.trim();
        String seatCode = 'N';
        if (seatLabel.startsWith('N')) seatCode = 'N';
        if (seatLabel.startsWith('S')) seatCode = 'S';
        if (seatLabel.startsWith('E')) seatCode = 'E';
        if (seatLabel.startsWith('W')) seatCode = 'W';

        try {
          result[seatCode] = parseSingleHand(body);
        } catch (_) {}
      }
      if (result.isNotEmpty) return result;
    }

    // 4. Try parsing as a single hand if no seat headers were found
    try {
      final single = parseSingleHand(text);
      result['S'] = single; // default to user's seat South
      return result;
    } catch (_) {}

    return result;
  }

  static Map<String, Hand> _parsePbnDealBody(String firstSeat, String body) {
    final Map<String, Hand> result = {};
    final seatOrder = ['N', 'E', 'S', 'W'];
    int startIdx = seatOrder.indexOf(firstSeat);
    if (startIdx == -1) startIdx = 0;

    final handStrings = body.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    for (int i = 0; i < handStrings.length && i < 4; i++) {
      final seat = seatOrder[(startIdx + i) % 4];
      try {
        result[seat] = parseSingleHand(handStrings[i]);
      } catch (_) {}
    }
    return result;
  }

  /// Completes a [PartnershipDeal] from a map of [specifiedHands] (any subset of N, E, S, W).
  /// Verifies no duplicate cards exist across specified hands.
  /// Any unassigned seat receives 13 cards from the remaining 52-card deck.
  static PartnershipDeal completeDeal(
    Map<String, Hand> specifiedHands, {
    Random? random,
  }) {
    final rng = random ?? Random();

    // Check for duplicate cards
    final Set<BridgeCard> seenCards = {};
    for (final entry in specifiedHands.entries) {
      for (final card in entry.value.cards) {
        if (seenCards.contains(card)) {
          throw FormatException('Duplicate card "$card" found in ${entry.key} hand');
        }
        seenCards.add(card);
      }
    }

    // Calculate remaining unassigned cards
    final allCards = DealGenerator.createDeck();
    final remainingCards = allCards
        .where((c) => !seenCards.contains(c))
        .toList()
      ..shuffle(rng);

    final completedHands = <String, Hand>{};

    for (final seat in ['N', 'E', 'S', 'W']) {
      if (specifiedHands.containsKey(seat) && specifiedHands[seat]!.cards.length == 13) {
        completedHands[seat] = specifiedHands[seat]!;
      } else if (specifiedHands.containsKey(seat) && specifiedHands[seat]!.cards.isNotEmpty) {
        // Hand is partially specified: complete it to 13 cards
        final existing = List<BridgeCard>.from(specifiedHands[seat]!.cards);
        final needed = 13 - existing.length;
        if (needed > 0 && remainingCards.length >= needed) {
          existing.addAll(remainingCards.take(needed));
          remainingCards.removeRange(0, needed);
        }
        completedHands[seat] = Hand(existing);
      } else {
        // Seat not specified: allocate 13 cards from remaining deck
        final cards = remainingCards.take(13).toList();
        remainingCards.removeRange(0, min(13, remainingCards.length));
        completedHands[seat] = Hand(cards);
      }
    }

    return PartnershipDeal(
      north: completedHands['N']!,
      east: completedHands['E']!,
      south: completedHands['S']!,
      west: completedHands['W']!,
    );
  }
}
