import '../models/hand.dart';
import '../models/bidding_system.dart';
import '../models/bidding_state_context.dart';
import '../models/seat_belief_state.dart';
import '../constraints/constraint_parser.dart';
import '../constraints/specificity_resolver.dart';
import '../evaluators/ml_bid_evaluator.dart';
import '../evaluators/ml_strain_model.dart';
import '../evaluators/valuation_engine.dart';
import 'deal_generator.dart';
import 'compiled_auction_graph.dart';
import 'bidding_graph_compiler.dart';

/// Represents a single bid logged in the auction record.
class AuctionEntry {
  final String seat; // 'N', 'E', 'S', 'W'
  final String call;
  final String? desc;
  final String? rule;
  final bool isAutomatic;

  const AuctionEntry({
    required this.seat,
    required this.call,
    this.desc,
    this.rule,
    this.isAutomatic = false,
  });
}

/// The result returned by [AuctionEngine.advanceAuction] after each user action.
class AuctionStepResult {
  final List<AuctionEntry> updatedHistory;
  final bool isUserBidCorrect;
  final String feedbackMessage;
  final CandidateCall? expectedBestBid;
  final List<CandidateCall> allEvaluatedMatches;
  final List<CandidateCall> nextValidCandidatesForUser;
  final bool isAuctionComplete;
  final MLEdgeCasePrediction? mlPrediction;
  final MLHandBreakdown? mlUpgradeBreakdown;
  final AuctionBeliefState? beliefState;
  final MLPartnershipEvaluation? partnershipEvaluation;

  const AuctionStepResult({
    required this.updatedHistory,
    required this.isUserBidCorrect,
    required this.feedbackMessage,
    this.expectedBestBid,
    this.allEvaluatedMatches = const [],
    this.nextValidCandidatesForUser = const [],
    this.isAuctionComplete = false,
    this.mlPrediction,
    this.mlUpgradeBreakdown,
    this.beliefState,
    this.partnershipEvaluation,
  });
}

/// The stateful auction engine injected via IOC to orchestrate the entire auction.
class AuctionEngine {
  final CompiledBiddingGraph graph;
  final SpecificityResolver resolver;
  final SpecificityResolver botResolver;
  final CompiledBiddingGraph? ewGraph;
  final SpecificityResolver? ewResolver;
  final SpecificityResolver? botEwResolver;
  final MLEdgeCaseEvaluator? mlEvaluator;
  final Vulnerability vulnerability;

  AuctionEngine({
    required this.graph,
    SpecificityResolver? resolver,
    SpecificityResolver? botResolver,
    this.ewGraph,
    this.ewResolver,
    SpecificityResolver? botEwResolver,
    HandValuationEngine? valuation,
    this.mlEvaluator,
    this.vulnerability = Vulnerability.none,
  })  : resolver = resolver ?? SpecificityResolver(
          parser: ConstraintParser(definitions: graph.system.definitions),
          valuation: valuation ?? MLHandValuation(strictEffectiveHcp: false),
        ),
        botResolver = botResolver ?? SpecificityResolver(
          parser: ConstraintParser(definitions: graph.system.definitions),
          valuation: MLHandValuation(strictEffectiveHcp: true),
        ),
        botEwResolver = botEwResolver ?? (ewGraph != null ? SpecificityResolver(
          parser: ConstraintParser(definitions: ewGraph.system.definitions),
          valuation: MLHandValuation(strictEffectiveHcp: true),
        ) : null);

  /// Convenient accessors for North-South and East-West systems.
  BridgeSystem get nsSystem => graph.system;
  BridgeSystem? get ewSystem => ewGraph?.system;

  /// Factory constructor to compile and assemble an [AuctionEngine] directly from a [BridgeSystem],
  /// with optional separate [ewSystem] for the opposing East-West partnership.
  factory AuctionEngine.fromSystem(
    BridgeSystem system, {
    BridgeSystem? ewSystem,
    MLEdgeCaseEvaluator? mlEvaluator,
    HandValuationEngine? valuation,
    Vulnerability vulnerability = Vulnerability.none,
  }) {
    final compiler = BiddingGraphCompiler(system: system);
    final compiledGraph = compiler.compile();

    CompiledBiddingGraph? compiledEwGraph;
    SpecificityResolver? ewRes;
    SpecificityResolver? botEwRes;
    if (ewSystem != null) {
      final ewCompiler = BiddingGraphCompiler(system: ewSystem);
      compiledEwGraph = ewCompiler.compile();
      ewRes = SpecificityResolver(
        parser: ConstraintParser(definitions: ewSystem.definitions),
        valuation: valuation ?? MLHandValuation(strictEffectiveHcp: false),
      );
      botEwRes = SpecificityResolver(
        parser: ConstraintParser(definitions: ewSystem.definitions),
        valuation: MLHandValuation(strictEffectiveHcp: true),
      );
    }

    return AuctionEngine(
      graph: compiledGraph,
      resolver: SpecificityResolver(
        parser: ConstraintParser(definitions: system.definitions),
        valuation: valuation ?? MLHandValuation(strictEffectiveHcp: false),
      ),
      botResolver: SpecificityResolver(
        parser: ConstraintParser(definitions: system.definitions),
        valuation: MLHandValuation(strictEffectiveHcp: true),
      ),
      ewGraph: compiledEwGraph,
      ewResolver: ewRes,
      botEwResolver: botEwRes,
      mlEvaluator: mlEvaluator,
      vulnerability: vulnerability,
    );
  }

  /// Extracts the sequence of bidding calls (ignoring opponent passes) from history.
  /// If [forEastWest] is true, East and West are treated as the friendly partnership,
  /// and North and South calls are treated as opposition calls (in parentheses).
  List<String> extractSystemSequence(List<AuctionEntry> history, {bool forEastWest = false}) {
    final List<String> seq = [];
    for (final entry in history) {
      final c = entry.call.trim();
      final isOpponent = forEastWest
          ? (entry.seat == 'N' || entry.seat == 'S')
          : (entry.seat == 'E' || entry.seat == 'W');

      // Ignore opponent passes. We only preserve passes made by friendly side or in competitive auctions.
      if (c.toLowerCase() == 'pass' && isOpponent) {
        continue;
      }
      if (isOpponent && !c.startsWith('(') && c.toLowerCase() != 'pass') {
        seq.add(CompiledAuctionState.normalizeCallKey('($c)'));
      } else {
        seq.add(CompiledAuctionState.normalizeCallKey(c));
      }
    }
    return seq;
  }

  /// Resolves the call for an opponent seat ('E' or 'W') using the E-W system if available,
  /// otherwise defaults to a standard automatic pass.
  AuctionEntry resolveOpponentCall({
    required String seat,
    required Hand hand,
    required List<AuctionEntry> currentHistory,
  }) {
    if (ewGraph == null || ewResolver == null) {
      return AuctionEntry(
        seat: seat,
        call: 'Pass',
        desc: 'Opposition pass',
        isAutomatic: true,
      );
    }

    final ewSeq = extractSystemSequence(currentHistory, forEastWest: true);
    final ewState = ewGraph!.getState(ewSeq) ?? (ewSeq.isEmpty ? ewGraph!.rootState : null);
    if (ewState == null) {
      return AuctionEntry(
        seat: seat,
        call: 'Pass',
        desc: 'Opposition pass',
        isAutomatic: true,
      );
    }

    final oppActions = BiddingStateContext.extractOpponentActions(
      auctionHistory: currentHistory,
      activeSeat: seat,
    );
    final ewContext = BiddingStateContext(
      holding: hand,
      auctionHistory: currentHistory,
      activeSeat: seat,
      opponentActions: oppActions,
      valuation: (botEwResolver ?? ewResolver!).valuation,
      vulnerability: vulnerability,
    );

    final bestBid = ewState.resolveBestBid(
      hand,
      botEwResolver ?? ewResolver!,
      fragments: ewGraph!.system.fragments,
      context: ewContext,
    );

    if (bestBid != null && !bestBid.isPass && bestBid.displayCall.isNotEmpty) {
      return AuctionEntry(
        seat: seat,
        call: bestBid.displayCall,
        desc: bestBid.desc.isNotEmpty ? bestBid.desc : 'System overcall/bid',
        rule: bestBid.rule,
        isAutomatic: true,
      );
    }

    return AuctionEntry(
      seat: seat,
      call: 'Pass',
      desc: 'Opposition pass',
      isAutomatic: true,
    );
  }

  /// Initializes the start of a new deal based on who bids first.
  AuctionStepResult startDeal({
    required PartnershipDeal deal,
    required bool isNorthFirst,
  }) {
    if (!isNorthFirst) {
      // South bids first: root state
      final rootState = graph.rootState;
      final southCandidates = rootState.evaluateCandidates(
        deal.south,
        resolver,
        fragments: graph.system.fragments,
      ).where((c) => !c.isOpponent).toList();
      final matchingSouthCandidates = southCandidates.where((c) => c.isMatch).toList();

      MLHandBreakdown? southBreakdown;
      if (resolver.valuation is MLHandValuation) {
        southBreakdown = (resolver.valuation as MLHandValuation).evaluateBreakdown(deal.south);
      }

      return AuctionStepResult(
        updatedHistory: const [],
        isUserBidCorrect: true,
        feedbackMessage: 'Your turn to open (South)',
        nextValidCandidatesForUser: southCandidates,
        isAuctionComplete: false,
        mlUpgradeBreakdown: southBreakdown,
      );
    }

    // North bids first: evaluate North's opening call
    final rootState = graph.rootState;
    final northBestBid = rootState.resolveBestBid(
      deal.north,
      botResolver,
      fragments: graph.system.fragments,
    );

    MLHandBreakdown? northBreakdown;
    if (botResolver.valuation is MLHandValuation) {
      northBreakdown = (botResolver.valuation as MLHandValuation).evaluateBreakdown(deal.north);
    }

    if (northBestBid == null || northBestBid.isPass) {
      // North passes
      return AuctionStepResult(
        updatedHistory: const [
          AuctionEntry(seat: 'N', call: 'Pass', desc: 'No opening available', isAutomatic: true),
        ],
        isUserBidCorrect: true,
        feedbackMessage: 'North passed. Auction ended.',
        isAuctionComplete: true,
        mlUpgradeBreakdown: northBreakdown,
      );
    }

    // North opens
    final history = [
      AuctionEntry(
        seat: 'N',
        call: northBestBid.displayCall,
        desc: northBestBid.desc,
        rule: northBestBid.rule,
        isAutomatic: true,
      ),
    ];

    // East evaluates or passes
    final eastCall = resolveOpponentCall(
      seat: 'E',
      hand: deal.east,
      currentHistory: history,
    );
    history.add(eastCall);

    final openSeq = extractSystemSequence(history);
    final nextState = graph.getState(openSeq);

    List<CandidateCall> southCandidates = [];
    if (nextState != null) {
      southCandidates = nextState.evaluateCandidates(
        deal.south,
        resolver,
        fragments: graph.system.fragments,
      ).where((c) => !c.isOpponent).toList();
    }

    final feedback = eastCall.call.toLowerCase() == 'pass'
        ? 'North opened ${northBestBid.displayCall}. Your turn to respond.'
        : 'North opened ${northBestBid.displayCall}, East bid ${eastCall.call} (${eastCall.desc}). Your turn to respond.';

    final belief = buildBeliefState(history);
    final historyCalls = history.map((e) => e.call).toList();
    final currentForcing = graph.getState(historyCalls)?.forcingLevel ?? ForcingLevel.partScore;
    final partnerEval = history.isNotEmpty
        ? MLStrainBiddingModel.evaluatePartnership(
            deal.south,
            belief.get('N'),
            forcingLevel: currentForcing,
            isOpponentActive: belief.isOpponentActive('S'),
          )
        : null;

    return AuctionStepResult(
      updatedHistory: history,
      isUserBidCorrect: true,
      feedbackMessage: feedback,
      nextValidCandidatesForUser: southCandidates,
      isAuctionComplete: southCandidates.isEmpty,
      mlUpgradeBreakdown: northBreakdown,
      beliefState: belief,
      partnershipEvaluation: partnerEval,
    );
  }

  static const List<String> seatOrder = ['W', 'N', 'E', 'S'];

  /// Extracts the auction belief state accumulated from [history].
  static AuctionBeliefState buildBeliefState(List<AuctionEntry> history) {
    final belief = AuctionBeliefState();
    for (final entry in history) {
      belief.recordCall(
        seat: entry.seat,
        call: entry.call,
        rule: entry.rule,
        desc: entry.desc,
      );
    }
    return belief;
  }

  /// Determines the seat whose turn it is next given the current [history] and [dealerCode].
  static String determineNextSeat(List<AuctionEntry> history, String dealerCode) {
    final dealerIdx = seatOrder.indexOf(dealerCode.toUpperCase());
    final idx = dealerIdx == -1 ? 0 : dealerIdx;
    return seatOrder[(idx + history.length) % 4];
  }

  /// Evaluates and advances the auction when the active user ([activeSeat], defaults to 'S') submits [userCall].
  /// Automatically progresses opposition pass, partner's rebid, opposition pass, and yields the next valid candidates.
  AuctionStepResult advanceAuction({
    required List<AuctionEntry> history,
    required String userCall,
    required PartnershipDeal deal,
    String activeSeat = 'S',
  }) {
    final isNorthUser = activeSeat.toUpperCase() == 'N';
    final evalHand = isNorthUser ? deal.north : deal.south;
    final partnerHand = isNorthUser ? deal.south : deal.north;
    final partnerSeat = isNorthUser ? 'S' : 'N';
    final nextOpponentSeat = isNorthUser ? 'E' : 'W';
    final subsequentOpponentSeat = isNorthUser ? 'W' : 'E';

    final currentSeq = extractSystemSequence(history);
    final currentState = graph.getState(currentSeq) ?? graph.rootState;

    final userOppActions = BiddingStateContext.extractOpponentActions(
      auctionHistory: history,
      activeSeat: activeSeat,
    );
    final userContext = BiddingStateContext(
      holding: evalHand,
      auctionHistory: history,
      activeSeat: activeSeat,
      opponentActions: userOppActions,
      valuation: resolver.valuation,
      vulnerability: vulnerability,
    );
    final userBreakdown = userContext.breakdown;

    final isUserOpponent = (activeSeat.toUpperCase() == 'E' || activeSeat.toUpperCase() == 'W');

    // Evaluate user's call against current state using active player's hand and state context
    final allMatches = currentState.evaluateCandidates(
      evalHand,
      resolver,
      fragments: graph.system.fragments,
      context: userContext,
    ).where((c) => c.isOpponent == isUserOpponent).toList();
    final bestBid = currentState.resolveBestBid(
      evalHand,
      resolver,
      fragments: graph.system.fragments,
      allowOpponent: isUserOpponent,
      context: userContext,
    );

    final cleanUserCall = userCall.trim().toLowerCase();
    final effectiveBestBid = bestBid ?? const CandidateCall(
      call: 'pass',
      displayCall: 'Pass',
      desc: 'Pass (no system bids apply)',
      isMatch: true,
      priority: 999,
    );
    final matchingCalls = allMatches.where((c) => c.isMatch).toList();
    final matchingCandidate = matchingCalls.cast<CandidateCall?>().firstWhere(
      (c) => c != null && (c.displayCall.toLowerCase() == cleanUserCall || c.call.toLowerCase() == cleanUserCall),
      orElse: () => null,
    );

    final isCorrect = effectiveBestBid.displayCall.toLowerCase() == cleanUserCall ||
        effectiveBestBid.call.toLowerCase() == cleanUserCall ||
        (matchingCandidate != null &&
            (effectiveBestBid.priority == null ||
                (matchingCandidate.priority ?? 999) <= (effectiveBestBid.priority ?? 999)));

    if (!isCorrect) {
      // User bid is incorrect: return diagnosis without advancing
      final bestName = effectiveBestBid.displayCall;
      final bestDesc = effectiveBestBid.desc.isNotEmpty ? ' (${effectiveBestBid.desc})' : '';
      return AuctionStepResult(
        updatedHistory: history,
        isUserBidCorrect: false,
        feedbackMessage: '❌ Incorrect bid $userCall. Expected $bestName$bestDesc.',
        expectedBestBid: effectiveBestBid,
        allEvaluatedMatches: matchingCalls,
        nextValidCandidatesForUser: matchingCalls,
        isAuctionComplete: false,
        mlUpgradeBreakdown: userBreakdown,
      );
    }

    // User bid is correct! Record user's call using the accepted candidate
    final acceptedBid = matchingCandidate ?? effectiveBestBid;
    final updatedHistory = List<AuctionEntry>.from(history);
    updatedHistory.add(AuctionEntry(
      seat: activeSeat.toUpperCase(),
      call: acceptedBid.displayCall,
      desc: acceptedBid.desc,
      rule: acceptedBid.rule,
      isAutomatic: false,
    ));

    // If user passed or auction is naturally complete
    if (acceptedBid.isPass) {
      return AuctionStepResult(
        updatedHistory: updatedHistory,
        isUserBidCorrect: true,
        feedbackMessage: '✅ Correct! Pass. Auction complete.',
        expectedBestBid: effectiveBestBid,
        isAuctionComplete: true,
        mlUpgradeBreakdown: userBreakdown,
      );
    }

    // Opposition evaluates call using EW system (or passes)
    final opp1Hand = nextOpponentSeat == 'E' ? deal.east : deal.west;
    final opp1Call = resolveOpponentCall(
      seat: nextOpponentSeat,
      hand: opp1Hand,
      currentHistory: updatedHistory,
    );
    updatedHistory.add(opp1Call);

    // Partner rebids automatically based on partner's hand!
    final partnerSeq = extractSystemSequence(updatedHistory);
    final partnerState = graph.getState(partnerSeq);
    if (partnerState == null || partnerState.candidateNodes.isEmpty) {
      // No further system rebids defined: auction complete
      return AuctionStepResult(
        updatedHistory: updatedHistory,
        isUserBidCorrect: true,
        feedbackMessage: '✅ Correct! Bid $userCall accepted. Final contract reached.',
        expectedBestBid: bestBid,
        isAuctionComplete: true,
        mlUpgradeBreakdown: userBreakdown,
      );
    }

    final partnerOppActions = BiddingStateContext.extractOpponentActions(
      auctionHistory: updatedHistory,
      activeSeat: partnerSeat,
    );
    final partnerContext = BiddingStateContext(
      holding: partnerHand,
      auctionHistory: updatedHistory,
      activeSeat: partnerSeat,
      opponentActions: partnerOppActions,
      valuation: botResolver.valuation,
      vulnerability: vulnerability,
    );

    var partnerBestBid = partnerState.resolveBestBid(
      partnerHand,
      botResolver,
      fragments: graph.system.fragments,
      allowOpponent: false,
      context: partnerContext,
    );

    MLEdgeCasePrediction? mlPrediction;

    // ML Edge-Case Evaluation: Consult ML model strictly on borderline invitational deals (22-25 or 29-32 HCP)
    if (mlEvaluator != null) {
      final combHcp = deal.north.hcp + deal.south.hcp;
      final effNorth = resolver.valuation.evaluatePoints(deal.north);
      final effSouth = resolver.valuation.evaluatePoints(deal.south);
      final combEffHcp = effNorth + effSouth;
      final isEdgeCase = (combHcp >= 22 && combHcp <= 25) ||
          (combEffHcp >= 22 && combEffHcp <= 25) ||
          (combHcp >= 20 && combHcp <= 25 && (deal.north.heartsLength >= 6 || deal.north.spadesLength >= 6 || deal.south.heartsLength >= 6 || deal.south.spadesLength >= 6)) ||
          (combHcp >= 29 && combHcp <= 32) ||
          (combEffHcp >= 29 && combEffHcp <= 32);
      if (isEdgeCase) {
        final matches = partnerState.evaluateCandidates(
          partnerHand,
          botResolver,
          fragments: graph.system.fragments,
          context: partnerContext,
        ).where((c) => c.isMatch && !c.isOpponent).toList();

        final gameMatch = matches.firstWhere(
          (c) {
            final l = int.tryParse(c.displayCall.trim().substring(0, 1)) ?? 0;
            final isNtGame = l >= 3 && c.displayCall.toLowerCase().contains('nt');
            final isMajorGame = l >= 4 && (c.displayCall.toLowerCase().contains('h') || c.displayCall.toLowerCase().contains('s'));
            final isSlam = l >= 6;
            return isNtGame || isMajorGame || isSlam;
          },
          orElse: () => const CandidateCall(call: '', displayCall: '', isMatch: false),
        );

        final inviteMatch = matches.firstWhere(
          (c) {
            final l = int.tryParse(c.displayCall.trim().substring(0, 1)) ?? 0;
            return l == 3 && !c.isPass;
          },
          orElse: () => const CandidateCall(call: '', displayCall: '', isMatch: false),
        );

        final partscoreOrPassMatch = matches.firstWhere(
          (c) => c.isPass || (int.tryParse(c.displayCall.trim().substring(0, 1)) ?? 9) <= 3,
          orElse: () => const CandidateCall(call: '', displayCall: '', isMatch: false),
        );

        if ((gameMatch.isMatch || inviteMatch.isMatch) && partscoreOrPassMatch.isMatch) {
          final level = gameMatch.isMatch
              ? (int.tryParse(gameMatch.displayCall.trim().substring(0, 1)) ?? 4)
              : 3;
          final strainCall = gameMatch.isMatch ? gameMatch.displayCall : inviteMatch.displayCall;
          final strain = strainCall.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
          final intermediateBelief = buildBeliefState(updatedHistory);
          final userBelief = intermediateBelief.get(activeSeat);
          final isOppActive = intermediateBelief.isOpponentActive(activeSeat);
          mlPrediction = mlEvaluator!.evaluateWithBelief(
            myHand: partnerHand,
            partnerBelief: userBelief,
            contractLevel: level,
            strain: strain,
            isOpponentActive: isOppActive,
          );

          if (mlPrediction.shouldAcceptInvite) {
            partnerBestBid = gameMatch.isMatch ? gameMatch : inviteMatch;
          } else {
            partnerBestBid = partscoreOrPassMatch;
          }
        }
      }
    }

    if (partnerBestBid == null || partnerBestBid.isPass) {
      // Partner has no further rebid / passes out
      updatedHistory.add(AuctionEntry(
        seat: partnerSeat,
        call: 'Pass',
        desc: 'Pass / contract signed off',
        isAutomatic: true,
      ));

      final mlNote = mlPrediction != null
          ? ' [🤖 ML: ${(mlPrediction.probMaking * 100).toStringAsFixed(0)}% make chance]'
          : '';

      return AuctionStepResult(
        updatedHistory: updatedHistory,
        isUserBidCorrect: true,
        feedbackMessage: '✅ Correct! Partner passed. Final contract reached.$mlNote',
        expectedBestBid: bestBid,
        isAuctionComplete: true,
        mlPrediction: mlPrediction,
        mlUpgradeBreakdown: userBreakdown,
      );
    }

    // Partner bids!
    updatedHistory.add(AuctionEntry(
      seat: partnerSeat,
      call: partnerBestBid.displayCall,
      desc: partnerBestBid.desc,
      rule: partnerBestBid.rule,
      isAutomatic: true,
    ));

    // Subsequent opposition evaluates call using EW system (or passes)
    final opp2Hand = subsequentOpponentSeat == 'W' ? deal.west : deal.east;
    final opp2Call = resolveOpponentCall(
      seat: subsequentOpponentSeat,
      hand: opp2Hand,
      currentHistory: updatedHistory,
    );
    updatedHistory.add(opp2Call);

    // Next turn is back to active player! Query next state
    final nextSeq = extractSystemSequence(updatedHistory);
    final nextState = graph.getState(nextSeq);

    final nextOppActions = BiddingStateContext.extractOpponentActions(
      auctionHistory: updatedHistory,
      activeSeat: activeSeat,
    );
    final nextContext = BiddingStateContext(
      holding: evalHand,
      auctionHistory: updatedHistory,
      activeSeat: activeSeat,
      opponentActions: nextOppActions,
      valuation: resolver.valuation,
      vulnerability: vulnerability,
    );

    List<CandidateCall> nextCandidates = [];
    if (nextState != null) {
      nextCandidates = nextState.evaluateCandidates(
        evalHand,
        resolver,
        fragments: graph.system.fragments,
        context: nextContext,
      ).where((c) => c.isOpponent == isUserOpponent).toList();
    }
    final isAuctionComplete = nextCandidates.isEmpty;
    final nextBestBid = nextState?.resolveBestBid(
      evalHand,
      resolver,
      fragments: graph.system.fragments,
      allowOpponent: isUserOpponent,
      context: nextContext,
    );

    final mlNote = mlPrediction != null
        ? ' [🤖 ML: ${(mlPrediction.probMaking * 100).toStringAsFixed(0)}% make chance]'
        : '';

    final currentBelief = buildBeliefState(updatedHistory);
    final partnerBelief = currentBelief.partnerOf(activeSeat);
    final historyCalls = updatedHistory.map((e) => e.call).toList();
    final currentForcing = graph.getState(historyCalls)?.forcingLevel ?? ForcingLevel.partScore;
    final partnerEval = MLStrainBiddingModel.evaluatePartnership(
      evalHand,
      partnerBelief,
      forcingLevel: currentForcing,
      isOpponentActive: currentBelief.isOpponentActive(activeSeat),
    );

    return AuctionStepResult(
      updatedHistory: updatedHistory,
      isUserBidCorrect: true,
      feedbackMessage: '✅ Correct! Partner rebid ${partnerBestBid.displayCall} (${partnerBestBid.desc}).$mlNote',
      expectedBestBid: nextBestBid,
      nextValidCandidatesForUser: nextCandidates,
      isAuctionComplete: isAuctionComplete,
      mlPrediction: mlPrediction,
      mlUpgradeBreakdown: userBreakdown,
      beliefState: currentBelief,
      partnershipEvaluation: partnerEval,
    );
  }
}
