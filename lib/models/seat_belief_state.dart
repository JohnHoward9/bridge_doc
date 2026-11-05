import '../models/card.dart';
import '../models/hand.dart';
import 'bridge_probabilities.dart';

/// Represents the accumulated knowledge / belief state about a specific seat (N, E, S, W)
/// based on their calls and conventions throughout the auction.
class SeatBeliefState {
  final String seat;
  final int minHcp;
  final int maxHcp;
  final Map<Suit, int> minSuitLength;
  final Map<Suit, int> maxSuitLength;
  final bool isBalanced;
  final bool isGameForcing;
  final bool isInvitational;
  final List<String> bidHistory;
  final List<String> shownFeatures;
  final Set<Suit> controlledSuits;

  /// Exact conditional expected HCP E[HCP | minHcp <= HCP <= maxHcp]
  /// calculated via a priori probability distribution (mean 10.00, std 4.13).
  double get expectedHcp => BridgeProbabilities.conditionalExpectedHcp(minHcp: minHcp, maxHcp: maxHcp);

  SeatBeliefState({
    required this.seat,
    this.minHcp = 0,
    this.maxHcp = 37,
    Map<Suit, int>? minSuitLength,
    Map<Suit, int>? maxSuitLength,
    this.isBalanced = false,
    this.isGameForcing = false,
    this.isInvitational = false,
    List<String>? bidHistory,
    List<String>? shownFeatures,
    Set<Suit>? controlledSuits,
  })  : minSuitLength = minSuitLength ?? {for (var s in Suit.values) s: 0},
        maxSuitLength = maxSuitLength ?? {for (var s in Suit.values) s: 13},
        bidHistory = List.unmodifiable(bidHistory ?? const []),
        shownFeatures = List.unmodifiable(shownFeatures ?? const []),
        controlledSuits = Set.unmodifiable(controlledSuits ?? const {});

  /// Creates a copy of this state with updated parameters.
  SeatBeliefState copyWith({
    int? minHcp,
    int? maxHcp,
    Map<Suit, int>? minSuitLength,
    Map<Suit, int>? maxSuitLength,
    bool? isBalanced,
    bool? isGameForcing,
    bool? isInvitational,
    List<String>? bidHistory,
    List<String>? shownFeatures,
    Set<Suit>? controlledSuits,
  }) {
    return SeatBeliefState(
      seat: seat,
      minHcp: minHcp ?? this.minHcp,
      maxHcp: maxHcp ?? this.maxHcp,
      minSuitLength: minSuitLength ?? Map.from(this.minSuitLength),
      maxSuitLength: maxSuitLength ?? Map.from(this.maxSuitLength),
      isBalanced: isBalanced ?? this.isBalanced,
      isGameForcing: isGameForcing ?? this.isGameForcing,
      isInvitational: isInvitational ?? this.isInvitational,
      bidHistory: bidHistory ?? this.bidHistory,
      shownFeatures: shownFeatures ?? this.shownFeatures,
      controlledSuits: controlledSuits ?? Set.from(this.controlledSuits),
    );
  }

  /// Whether the partnership is confirmed to have 1st or 2nd round control in [suit].
  /// 1st round: Ace or Void in [hand] or shown by partner.
  /// 2nd round: King or Singleton in [hand] or shown by partner.
  bool hasControlInSuit(Hand hand, Suit suit) {
    if (controlledSuits.contains(suit)) return true;
    final len = hand.length(suit);
    if (len == 0 || len == 1) return true; // Void (1st) or Singleton (2nd)
    final cards = hand.cardsInSuit(suit);
    return cards.any((c) => c.rank == Rank.ace || c.rank == Rank.king); // Ace (1st) or King (2nd)
  }

  /// Returns true if any side suit outside [trumpSuit] lacks 1st or 2nd round control
  /// across the partnership. RKCB should NOT be bid when this returns true.
  bool hasUncontrolledSideSuit(Hand hand, Suit trumpSuit) {
    for (final s in Suit.values) {
      if (s == trumpSuit) continue;
      if (!hasControlInSuit(hand, s)) return true;
    }
    return false;
  }

  /// Calculates the guaranteed minimum total trump fit between [hand] and this seat in [suit].
  int totalGuaranteedFit(Hand hand, Suit suit) {
    return hand.length(suit) + (minSuitLength[suit] ?? 0);
  }

  /// True if guaranteed to have an 8-card or longer golden trump fit.
  bool hasGoldenFit(Hand hand, Suit suit) {
    return totalGuaranteedFit(hand, suit) >= 8;
  }

  /// Returns the guaranteed minimum combined fit for all 4 suits between [hand] and this seat.
  Map<Suit, int> allGuaranteedFits(Hand hand) {
    return {
      for (final s in Suit.values) s: totalGuaranteedFit(hand, s),
    };
  }

  /// Calculates the guaranteed fit in the primary trump suit.
  /// If [trumpSuit] is null, returns the maximum fit across all 4 suits.
  int primaryFit(Hand hand, [Suit? trumpSuit]) {
    if (trumpSuit != null) return totalGuaranteedFit(hand, trumpSuit);
    int maxFit = 0;
    for (final s in Suit.values) {
      final f = totalGuaranteedFit(hand, s);
      if (f > maxFit) maxFit = f;
    }
    return maxFit;
  }

  /// The suit with the highest guaranteed fit with [hand].
  Suit bestFitSuit(Hand hand) {
    Suit best = Suit.spades;
    int maxFit = -1;
    for (final s in Suit.values) {
      final f = totalGuaranteedFit(hand, s);
      if (f > maxFit) {
        maxFit = f;
        best = s;
      }
    }
    return best;
  }

  /// Calculates the guaranteed fit in the best secondary suit (excluding [primarySuit]).
  /// This detects double fits, e.g. 8+ Spades AND 8+ Clubs!
  int secondaryFit(Hand hand, [Suit? primarySuit]) {
    final effectivePrimary = primarySuit ?? bestFitSuit(hand);
    int maxSideFit = 0;
    for (final s in Suit.values) {
      if (s == effectivePrimary) continue;
      final f = totalGuaranteedFit(hand, s);
      if (f > maxSideFit) maxSideFit = f;
    }
    return maxSideFit;
  }

  /// The suit of the best secondary fit with [hand] (excluding [primarySuit]).
  Suit? secondaryFitSuit(Hand hand, [Suit? primarySuit]) {
    final effectivePrimary = primarySuit ?? bestFitSuit(hand);
    Suit? bestSide;
    int maxSideFit = 0;
    for (final s in Suit.values) {
      if (s == effectivePrimary) continue;
      final f = totalGuaranteedFit(hand, s);
      if (f > maxSideFit) {
        maxSideFit = f;
        bestSide = s;
      }
    }
    return maxSideFit >= 7 ? bestSide : null;
  }

  /// True if the partnership holds a Double Fit:
  /// An 8+ card primary fit AND an 8+ card secondary fit across any two suits!
  bool hasDoubleFit(Hand hand, [Suit? trumpSuit]) {
    final prim = primaryFit(hand, trumpSuit);
    final sec = secondaryFit(hand, trumpSuit);
    return prim >= 8 && sec >= 8;
  }

  /// Calculates mathematically expected continuous suit lengths (summing to 13.0)
  /// conditioned on shown auction ranges using exact hypergeometric conditional expectations.
  Map<Suit, double> expectedSuitLengths({Hand? myHand, bool isOpponentActive = false}) {
    final expected = <Suit, double>{};
    double allocatedCards = 0.0;
    final unshownSuits = <Suit>[];

    for (final s in Suit.values) {
      final minL = minSuitLength[s] ?? 0;
      final maxL = maxSuitLength[s] ?? 13;

      if (minL == maxL && minL > 0) {
        // Exact length known
        expected[s] = minL.toDouble();
        allocatedCards += minL;
      } else if (minL > 0 || maxL < 13) {
        // Bounded range: compute exact conditional expectation E[L | minL <= L <= maxL]
        final myL = myHand != null ? myHand.length(s) : 0;
        final expL = BridgeProbabilities.conditionalExpectedSuitLength(
          minLen: minL,
          maxLen: maxL,
          myLen: myL,
        );
        expected[s] = expL;
        allocatedCards += expL;
      } else {
        unshownSuits.add(s);
      }
    }

    // Distribute remaining cards among unshown suits
    final remainingCards = (13.0 - allocatedCards).clamp(0.0, 13.0);
    if (unshownSuits.isNotEmpty) {
      final perSuit = remainingCards / unshownSuits.length;
      for (final s in unshownSuits) {
        expected[s] = double.parse(perSuit.toStringAsFixed(2));
      }
    }

    // Normalize so sum across all 4 suits is exactly 13.0
    final currentSum = expected.values.fold(0.0, (a, b) => a + b);
    if (currentSum > 0 && (currentSum - 13.0).abs() > 0.01) {
      final scale = 13.0 / currentSum;
      for (final s in Suit.values) {
        if (expected.containsKey(s)) {
          expected[s] = double.parse((expected[s]! * scale).toStringAsFixed(2));
        }
      }
    }

    return expected;
  }

  /// Calculates expected partnership fit in [suit] using exact conditional expectations.
  double expectedPartnershipFit(Hand myHand, Suit suit, {bool isOpponentActive = false}) {
    final expLengths = expectedSuitLengths(myHand: myHand, isOpponentActive: isOpponentActive);
    return myHand.length(suit) + (expLengths[suit] ?? 3.25);
  }

  /// Evaluates working honors in [hand] that mesh directly with this seat's shown suit length.
  /// Honors in suits where partner has 4+ cards are 100% active.
  double workingHonorsHcp(Hand hand) {
    double working = 0.0;
    for (final suit in Suit.values) {
      final pLen = minSuitLength[suit] ?? 0;
      if (pLen >= 4) {
        for (final c in hand.cards.where((card) => card.suit == suit)) {
          working += c.rank.hcp;
        }
      }
    }
    return working;
  }

  /// Evaluates secondary honors (Queens & Jacks) in suits where partner is known short (<= 1).
  /// In suit play, secondary honors facing shortness are often wasted.
  double wastedHonorsHcp(Hand hand) {
    double wasted = 0.0;
    for (final suit in Suit.values) {
      final pMax = maxSuitLength[suit] ?? 13;
      if (pMax <= 1) {
        for (final c in hand.cards.where((card) => card.suit == suit)) {
          if (c.rank == Rank.queen || c.rank == Rank.jack) {
            wasted += c.rank.hcp;
          }
        }
      }
    }
    return wasted;
  }

  /// True if [hand] holds a reliable stopper in [suit] (Ace, King-x, Queen-x-x, Jack-10-x-x).
  static bool hasStopper(Hand hand, Suit suit) {
    final cards = hand.cards.where((c) => c.suit == suit).toList();
    if (cards.any((c) => c.rank == Rank.ace)) return true;
    if (cards.any((c) => c.rank == Rank.king) && cards.length >= 2) return true;
    if (cards.any((c) => c.rank == Rank.queen) && cards.length >= 3) return true;
    if (cards.any((c) => c.rank == Rank.jack) && cards.any((c) => c.rank == Rank.ten) && cards.length >= 3) return true;
    return false;
  }

  /// Summary description of known profile, e.g. "10-18 HCP, 5+ ♥, 4+ ♣, GF".
  String get summaryText {
    final parts = <String>[];
    if (minHcp > 0 || maxHcp < 37) {
      parts.add(maxHcp < 37 ? '$minHcp-$maxHcp HCP' : '$minHcp+ HCP');
    }
    for (final s in Suit.values) {
      final len = minSuitLength[s] ?? 0;
      if (len >= 4) {
        parts.add('$len+ ${s.symbol}');
      }
    }
    if (isBalanced) parts.add('Balanced');
    if (isGameForcing) parts.add('Game Force');
    if (isInvitational) parts.add('Invitational');
    return parts.isEmpty ? 'Unannounced' : parts.join(', ');
  }

  /// Extracts minimum and maximum suit length bounds from a [rule] or description string.
  /// Handles "5+h", "5h 4s", "6s", "4=h", "5-6h", "(5-6)s", "3-s", "dist#2452", and variable bindings.
  static ({Map<Suit, int> minSuit, Map<Suit, int> maxSuit}) parseRuleSuitBounds(
    String text, [
    Map<String, String>? vars,
  ]) {
    final minSuit = <Suit, int>{};
    final maxSuit = <Suit, int>{};

    var clean = text.toLowerCase();
    if (vars != null) {
      vars.forEach((k, v) {
        clean = clean.replaceAll('\$$k', v.toLowerCase());
      });
    }

    // Exact distribution pattern like dist#2452 (S, H, D, C)
    final distMatch = RegExp(r'dist#(\d)(\d)(\d)(\d)').firstMatch(clean);
    if (distMatch != null) {
      final s = int.parse(distMatch.group(1)!);
      final h = int.parse(distMatch.group(2)!);
      final d = int.parse(distMatch.group(3)!);
      final c = int.parse(distMatch.group(4)!);
      minSuit[Suit.spades] = s; maxSuit[Suit.spades] = s;
      minSuit[Suit.hearts] = h; maxSuit[Suit.hearts] = h;
      minSuit[Suit.diamonds] = d; maxSuit[Suit.diamonds] = d;
      minSuit[Suit.clubs] = c; maxSuit[Suit.clubs] = c;
      return (minSuit: minSuit, maxSuit: maxSuit);
    }

    for (final suit in Suit.values) {
      final sChar = suit.name[0]; // s, h, d, c
      final fullName = suit.name;
      final sym = suit.symbol;
      final sPat = sChar == 'h' ? r'h(?!cp)' : sChar;

      // 1. Min pattern: 5+h, 4+ clubs
      final plusRegex = RegExp('(\\d+)\\s*\\+\\s*(?:$sPat|$fullName|$sym)', caseSensitive: false);
      final plusMatch = plusRegex.firstMatch(clean);
      if (plusMatch != null) {
        final val = int.tryParse(plusMatch.group(1)!);
        if (val != null) minSuit[suit] = val;
      }

      // 2. Range pattern: 5-6h, (5-6)s
      final rangeRegex = RegExp(r'\(?(\d+)\s*-\s*(\d+)\)?\s*(?:' + sPat + r'|' + fullName + r'|' + sym + r')', caseSensitive: false);
      final rangeMatch = rangeRegex.firstMatch(clean);
      if (rangeMatch != null) {
        final low = int.tryParse(rangeMatch.group(1)!);
        final high = int.tryParse(rangeMatch.group(2)!);
        if (low != null) minSuit[suit] = low;
        if (high != null) maxSuit[suit] = high;
      }

      // 3. Exact pattern: 4=h, 5=s
      final exactEqualRegex = RegExp('(\\d+)\\s*=\\s*(?:$sPat|$fullName|$sym)', caseSensitive: false);
      final exactEqualMatch = exactEqualRegex.firstMatch(clean);
      if (exactEqualMatch != null) {
        final val = int.tryParse(exactEqualMatch.group(1)!);
        if (val != null) {
          minSuit[suit] = val;
          maxSuit[suit] = val;
        }
      }

      // 4. Standalone count like "5h 4s" or "6s" (avoid matching digits in "15-17" or "hcp")
      final tokenRegex = RegExp(r'(?:^|[\s,;|])(\d+)\s*(?:' + sPat + r'|' + fullName + r'|' + sym + r')(?=[\s,;|]|$)', caseSensitive: false);
      final tokenMatch = tokenRegex.firstMatch(clean);
      if (tokenMatch != null) {
        final val = int.tryParse(tokenMatch.group(1)!);
        if (val != null && val >= 3) {
          if (!minSuit.containsKey(suit) || val > minSuit[suit]!) {
            minSuit[suit] = val;
          }
        }
      }

      // 5. Max / shortness pattern: 3-s, 1-h, 0-d, 2-c
      final minusRegex = RegExp('(\\d+)\\s*-\\s*(?:$sPat|$fullName|$sym)', caseSensitive: false);
      final minusMatch = minusRegex.firstMatch(clean);
      if (minusMatch != null) {
        final val = int.tryParse(minusMatch.group(1)!);
        if (val != null) {
          maxSuit[suit] = val;
        }
      }
    }

    return (minSuit: minSuit, maxSuit: maxSuit);
  }
}

/// Tracks the entire auction belief state across all 4 seats (N, E, S, W).
class AuctionBeliefState {
  final Map<String, SeatBeliefState> _seats;

  AuctionBeliefState([Map<String, SeatBeliefState>? initialSeats])
      : _seats = initialSeats ?? {
          'N': SeatBeliefState(seat: 'N'),
          'E': SeatBeliefState(seat: 'E'),
          'S': SeatBeliefState(seat: 'S'),
          'W': SeatBeliefState(seat: 'W'),
        };

  SeatBeliefState get(String seat) {
    final s = seat.toUpperCase();
    return _seats[s] ?? SeatBeliefState(seat: s);
  }

  SeatBeliefState partnerOf(String seat) {
    switch (seat.toUpperCase()) {
      case 'N': return get('S');
      case 'S': return get('N');
      case 'E': return get('W');
      case 'W': return get('E');
      default: return get('S');
    }
  }

  /// Left-Hand Opponent (LHO) sitting immediately clockwise.
  SeatBeliefState lhoOf(String seat) {
    switch (seat.toUpperCase()) {
      case 'N': return get('E');
      case 'E': return get('S');
      case 'S': return get('W');
      case 'W': return get('N');
      default: return get('E');
    }
  }

  /// Right-Hand Opponent (RHO) sitting immediately counter-clockwise.
  SeatBeliefState rhoOf(String seat) {
    switch (seat.toUpperCase()) {
      case 'N': return get('W');
      case 'E': return get('N');
      case 'S': return get('E');
      case 'W': return get('S');
      default: return get('W');
    }
  }

  List<SeatBeliefState> opponentsOf(String seat) {
    switch (seat.toUpperCase()) {
      case 'N':
      case 'S':
        return [get('E'), get('W')];
      case 'E':
      case 'W':
      default:
        return [get('N'), get('S')];
    }
  }

  /// Updates the belief state for [seat] given a call with its [rule] string and [desc].
  void recordCall({
    required String seat,
    required String call,
    String? rule,
    String? desc,
    Map<String, String>? activeVariables,
  }) {
    final s = seat.toUpperCase();
    var current = get(s);

    int newMinHcp = current.minHcp;
    int newMaxHcp = current.maxHcp;
    final newMinSuit = Map<Suit, int>.from(current.minSuitLength);
    final newMaxSuit = Map<Suit, int>.from(current.maxSuitLength);
    bool newIsBalanced = current.isBalanced;
    bool newIsGf = current.isGameForcing;
    bool newIsInv = current.isInvitational;
    final newShownFeatures = List<String>.from(current.shownFeatures);
    final newHistory = List<String>.from(current.bidHistory)..add(call);

    final normCall = call.toLowerCase().trim();
    final combinedText = '$normCall ${rule ?? ''} ${desc ?? ''}'.toLowerCase();

    // Natural inferences from standard call patterns when rule/desc are not fully specified:
    if (newHistory.length == 1) {
      if (normCall == '1c') {
        if (newMinHcp < 12) newMinHcp = 12;
        if ((newMinSuit[Suit.clubs] ?? 0) < 3) newMinSuit[Suit.clubs] = 3;
      } else if (normCall == '1d') {
        if (newMinHcp < 12) newMinHcp = 12;
        if ((newMinSuit[Suit.diamonds] ?? 0) < 3) newMinSuit[Suit.diamonds] = 3;
      } else if (normCall == '1h') {
        if (newMinHcp < 12) newMinHcp = 12;
        if ((newMinSuit[Suit.hearts] ?? 0) < 5) newMinSuit[Suit.hearts] = 5;
      } else if (normCall == '1s') {
        if (newMinHcp < 12) newMinHcp = 12;
        if ((newMinSuit[Suit.spades] ?? 0) < 5) newMinSuit[Suit.spades] = 5;
      } else if (normCall == '1nt') {
        if (newMinHcp < 15) newMinHcp = 15;
        if (newMaxHcp > 17) newMaxHcp = 17;
        newIsBalanced = true;
      }
    } else if (newHistory.length == 2 && normCall == '1nt') {
      if (newMinHcp < 12) newMinHcp = 12;
      if (newMaxHcp > 14) newMaxHcp = 14;
      newIsBalanced = true;
    }

    // 1. Parse HCP: e.g. "15-17", "10+", "12-14", "8-9"
    final rangeRegex = RegExp(r'(\d+)\s*[-–]\s*(\d+)\s*(?:hcp|points)?');
    final plusRegex = RegExp(r'(\d+)\s*\+\s*(?:hcp|points)?');
    final minusRegex = RegExp(r'(\d+)\s*-\s*(?:hcp|points)?');

    final rangeMatch = rangeRegex.firstMatch(combinedText);
    if (rangeMatch != null) {
      final low = int.tryParse(rangeMatch.group(1)!);
      final high = int.tryParse(rangeMatch.group(2)!);
      if (low != null && low > newMinHcp) newMinHcp = low;
      if (high != null && high < newMaxHcp) newMaxHcp = high;
      newShownFeatures.add('$newMinHcp-$newMaxHcp HCP');
    } else {
      final plusMatch = plusRegex.firstMatch(combinedText);
      if (plusMatch != null) {
        final low = int.tryParse(plusMatch.group(1)!);
        if (low != null && low > newMinHcp) newMinHcp = low;
        newShownFeatures.add('$newMinHcp+ HCP');
      }
      final minusMatch = minusRegex.firstMatch(combinedText);
      if (minusMatch != null) {
        final high = int.tryParse(minusMatch.group(1)!);
        if (high != null && high < newMaxHcp) newMaxHcp = high;
      }
    }

    // 2. Parse Suit Lengths across all 4 suits: handles "5+h", "5h 4s", "6s", "4=h", "5-6h", "3-s", "dist#..."
    final suitBounds = parseRuleSuitBounds(combinedText, activeVariables);
    for (final entry in suitBounds.minSuit.entries) {
      if (entry.value > (newMinSuit[entry.key] ?? 0)) {
        newMinSuit[entry.key] = entry.value;
        newShownFeatures.add('${entry.value}+ ${entry.key.symbol}');
      }
    }
    for (final entry in suitBounds.maxSuit.entries) {
      if (entry.value < (newMaxSuit[entry.key] ?? 13)) {
        newMaxSuit[entry.key] = entry.value;
      }
    }

    // 3. Balanced shape
    if (combinedText.contains('balanced') || combinedText.contains('1nt') || combinedText.contains('2nt')) {
      newIsBalanced = true;
      newShownFeatures.add('Balanced');
      for (final suit in Suit.values) {
        if ((newMinSuit[suit] ?? 0) < 2) newMinSuit[suit] = 2;
        if ((newMaxSuit[suit] ?? 13) > 5) newMaxSuit[suit] = 5;
      }
    }

    // 4. Game Force / Invitational
    if (combinedText.contains('game force') || combinedText.contains('game_force') || combinedText.contains('gf')) {
      newIsGf = true;
      newShownFeatures.add('Game Force');
    }
    if (combinedText.contains('invit') || combinedText.contains('invite')) {
      newIsInv = true;
      newShownFeatures.add('Invitational');
    }

    // 5. Automatic shortness inference: if total min length across suits is large (e.g. 5H + 4C = 9),
    // then other suits cannot exceed (13 - 9) = 4!
    int totalMinLength = 0;
    for (final len in newMinSuit.values) {
      totalMinLength += len;
    }
    for (final suit in Suit.values) {
      final ownMin = newMinSuit[suit] ?? 0;
      final maxPossible = 13 - (totalMinLength - ownMin);
      if (maxPossible < (newMaxSuit[suit] ?? 13)) {
        newMaxSuit[suit] = maxPossible;
      }
    }

    _seats[s] = current.copyWith(
      minHcp: newMinHcp,
      maxHcp: newMaxHcp,
      minSuitLength: newMinSuit,
      maxSuitLength: newMaxSuit,
      isBalanced: newIsBalanced,
      isGameForcing: newIsGf,
      isInvitational: newIsInv,
      bidHistory: newHistory,
      shownFeatures: newShownFeatures.toSet().toList(),
    );
  }

  /// Extracts minimum and maximum suit length bounds from a [rule] or description string.
  static ({Map<Suit, int> minSuit, Map<Suit, int> maxSuit}) parseRuleSuitBounds(
    String text, [
    Map<String, String>? vars,
  ]) =>
      SeatBeliefState.parseRuleSuitBounds(text, vars);

  /// True if opponents of [seat] (defaults to 'S') have made any active call (non-Pass).
  bool isOpponentActive([String seat = 'S']) {
    return opponentsOf(seat).any((opp) =>
        opp.bidHistory.any((call) {
          final c = call.toLowerCase().trim();
          return c.isNotEmpty && c != 'p' && c != 'pass';
        }));
  }

  /// True if any opponent (East or West relative to South) has made an active call.
  bool get isAnyOpponentActive => isOpponentActive('S');

  /// Empirical probability of a bad trump split (e.g. 4-1 or 5-0 in an 8-card fit;
  /// 4-0 or 3-1 in a 9-card fit), conditioned on whether opponents are active or silent.
  /// Mined directly from 13,975 BBO Championship deals.
  double opponentTrumpBadSplitProb(Suit trumpSuit, int partnershipTrumpCount, {String seat = 'S'}) {
    final active = isOpponentActive(seat);
    if (partnershipTrumpCount >= 10) {
      return active ? 0.015 : 0.008;
    } else if (partnershipTrumpCount == 9) {
      // 4 cards out: 4-0 split risk
      return active ? 0.0664 : 0.0566; // 6.6% active vs 5.7% silent
    } else if (partnershipTrumpCount == 8) {
      // 5 cards out: 4-1 or 5-0 split risk
      return active ? 0.2987 : 0.2612; // 29.9% active vs 26.1% silent
    } else {
      // 7-card fit or worse (6+ cards out): 4-2, 5-1, or 6-0
      return active ? 0.762 : 0.684;
    }
  }
}
