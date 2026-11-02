import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_state_context.dart';
import 'package:bridge_bidding_system/evaluators/valuation_engine.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/constraints/hand_constraint.dart';

void main() {
  group('Positional Effective HCP & BiddingStateContext Tests', () {
    test('North holds K of spades; West bids 2S Multi-Landy; Effective HCP drops', () {
      // North holds ♠ K8, ♥ AQ5, ♦ KJ42, ♣ Q862 (raw 15 HCP, balanced)
      final northHand = Hand.fromString('K8.AQ5.KJ42.Q862');
      expect(northHand.hcp, equals(15));

      final valuation = MLHandValuation(strictEffectiveHcp: true);

      // Baseline without opponent bidding: evaluated in neutral notrump context
      final baselineBreakdown = valuation.evaluateBreakdown(northHand);
      final baselineEff = baselineBreakdown.effectiveHcp;
      expect(baselineEff, greaterThanOrEqualTo(14.5));

      // Scenario A: West (LHO of South, RHO/opponent of North) bids 2S Multi-Landy
      // If auction is: North 1NT, East pass, South pass, West 2S (or West bids 2S over 1NT)
      // When West bids 2S, West promises Spades.
      final actionWest2S = OpponentSuitAction(
        suit: Suit.spades,
        position: RelativeOpponentPosition.lho,
        call: '2s',
        seat: 'W',
        isArtificial: true,
        promisedSuits: {Suit.spades},
      );

      final contextLHO = BiddingStateContext(
        holding: northHand,
        auctionHistory: const [
          AuctionEntry(seat: 'N', call: '1NT'),
          AuctionEntry(seat: 'E', call: 'Pass'),
          AuctionEntry(seat: 'S', call: 'Pass'),
          AuctionEntry(seat: 'W', call: '2S'),
        ],
        activeSeat: 'N',
        opponentActions: [actionWest2S],
        valuation: valuation,
      );

      // North's K♠ is under the bidder -> drops by ~1.3 HCP
      expect(contextLHO.effectiveHcp, lessThan(baselineEff - 1.0),
          reason: 'K♠ under opponent spade bidder devalues by > 1.0 HCP');

      // Scenario B: East (RHO of North) bids 2S: North sits behind the bidder
      final actionEast2S = OpponentSuitAction(
        suit: Suit.spades,
        position: RelativeOpponentPosition.rho,
        call: '2s',
        seat: 'E',
        isArtificial: true,
        promisedSuits: {Suit.spades},
      );

      final contextRHO = BiddingStateContext(
        holding: northHand,
        auctionHistory: const [
          AuctionEntry(seat: 'N', call: '1NT'),
          AuctionEntry(seat: 'E', call: '2S'),
        ],
        activeSeat: 'N',
        opponentActions: [actionEast2S],
        valuation: valuation,
      );

      expect(contextRHO.effectiveHcp, greaterThan(contextLHO.effectiveHcp),
          reason: 'Protected K♠ over bidder retains higher value than trapped K♠ under bidder');
    });

    test('BiddingStateContext.extractOpponentActions automatically identifies Multi-Landy 2S and seats', () {
      final history = const [
        AuctionEntry(seat: 'N', call: '1NT'),
        AuctionEntry(seat: 'E', call: 'Pass'),
        AuctionEntry(seat: 'S', call: 'Pass'),
        AuctionEntry(seat: 'W', call: '2S'),
      ];

      // For North, West is RHO (or clockwise step 3)
      final oppActions = BiddingStateContext.extractOpponentActions(
        auctionHistory: history,
        activeSeat: 'N',
      );

      expect(oppActions.length, equals(1));
      expect(oppActions.first.suit, equals(Suit.spades));
      expect(oppActions.first.seat, equals('W'));
      expect(oppActions.first.call, equals('2S'));
    });

    test('HcpConstraint uses BiddingStateContext dynamic Effective HCP when provided', () {
      final northHand = Hand.fromString('K8.AQ5.KJ42.Q862'); // raw 15 HCP
      final valuation = MLHandValuation(strictEffectiveHcp: true);

      // Rule requiring 15+ HCP
      const constraint15Plus = HcpConstraint(min: 15);

      // Baseline context (no opponent action): passes 15+ HCP
      final neutralContext = BiddingStateContext(
        holding: northHand,
        auctionHistory: const [AuctionEntry(seat: 'N', call: '1NT')],
        activeSeat: 'N',
        valuation: valuation,
      );
      final neutralResult = constraint15Plus.evaluate(northHand, valuation, neutralContext);
      expect(neutralResult.isMatch, isTrue);

      // Context with opponent LHO bidding Spades: K♠ is devalued below 15.0
      final actionOpp2S = OpponentSuitAction(
        suit: Suit.spades,
        position: RelativeOpponentPosition.lho,
        call: '2s',
        seat: 'W',
      );
      final downgradedContext = BiddingStateContext(
        holding: northHand,
        auctionHistory: const [
          AuctionEntry(seat: 'N', call: '1NT'),
          AuctionEntry(seat: 'W', call: '2S'),
        ],
        activeSeat: 'N',
        opponentActions: [actionOpp2S],
        valuation: valuation,
      );

      final downgradedResult = constraint15Plus.evaluate(northHand, valuation, downgradedContext);
      expect(downgradedResult.isMatch, isFalse,
          reason: 'Effective HCP dropped below 15.0 due to K♠ under opponent suit');
    });
  });
}
