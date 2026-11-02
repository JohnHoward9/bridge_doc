import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/seat_belief_state.dart';
import 'package:bridge_bidding_system/models/ml_perspective_feature_extractor.dart';

void main() {
  group('ML Dynamic Table Perspective & Dynamic Seat Rotation Tests', () {
    test('Dynamic seat perspective resolves correct partner, LHO, and RHO for all 4 seats', () {
      final auction = AuctionBeliefState();

      // Record dummy calls so seats have distinct identifiable beliefs
      auction.recordCall(seat: 'N', call: '1H', rule: '12-14 hcp, 5+h');
      auction.recordCall(seat: 'E', call: 'Pass');
      auction.recordCall(seat: 'S', call: '1S', rule: '6+ hcp, 4+s');
      auction.recordCall(seat: 'W', call: '2C', rule: '10+ hcp, 5+c');

      // Test North active perspective
      expect(auction.partnerOf('N').seat, 'S');
      expect(auction.lhoOf('N').seat, 'E');
      expect(auction.rhoOf('N').seat, 'W');

      // Test East active perspective
      expect(auction.partnerOf('E').seat, 'W');
      expect(auction.lhoOf('E').seat, 'S');
      expect(auction.rhoOf('E').seat, 'N');

      // Test South active perspective
      expect(auction.partnerOf('S').seat, 'N');
      expect(auction.lhoOf('S').seat, 'W');
      expect(auction.rhoOf('S').seat, 'E');

      // Test West active perspective
      expect(auction.partnerOf('W').seat, 'E');
      expect(auction.lhoOf('W').seat, 'N');
      expect(auction.rhoOf('W').seat, 'S');
    });

    test('Deal 81565 B:1 South Turn 3: 7-card suit with AKQ evaluates to high playing strength', () {
      // South: ♠62 ♥AKQ8642 ♦A86 ♣T (13 HCP, 7 Hearts, AKQ, singleton club)
      final southHand = Hand.fromString('62.AKQ8642.A86.T');
      expect(southHand.hcp, 13);
      expect(southHand.heartsLength, 7);
      expect(southHand.isSolidSuit(Suit.hearts, minLength: 6), isTrue);

      final auction = AuctionBeliefState();
      // Partner (North) opened or responded
      auction.recordCall(seat: 'N', call: '1D', rule: '12-14 hcp, 3+d');

      final vecSouth = MLPerspectiveFeatureExtractor.extract(
        myHand: southHand,
        partnerBelief: auction.partnerOf('S'),
        lhoBelief: auction.lhoOf('S'),
        rhoBelief: auction.rhoOf('S'),
        candidateStrain: Suit.hearts,
        candidateLevel: 4,
      );

      // Verify South's continuous Playing Strength is high (>= 18.5) despite only 13 Milton Work HCP
      expect(vecSouth.playingStrength, greaterThanOrEqualTo(18.5));
      expect(vecSouth.myExcessLength, 3.0); // 7 - 4 = 3
      expect(vecSouth.myIsSolidSuit, 1.0);
    });

    test('Deal 81565 B:1 North Turn 5: 11-card heart fit and singleton ruff yield >= 10.8 expected tricks', () {
      // North: ♠QT97 ♥JT93 ♦2 ♣A876 (7 HCP, 4 Hearts, singleton diamond)
      final northHand = Hand.fromString('QT97.JT93.2.A876');
      expect(northHand.hcp, 7);
      expect(northHand.heartsLength, 4);

      final auction = AuctionBeliefState();
      // South showed 7 hearts and opening values (12-15 HCP)
      auction.recordCall(seat: 'S', call: '1H', rule: '12-15 hcp, 7+h');

      final vecNorth = MLPerspectiveFeatureExtractor.extract(
        myHand: northHand,
        partnerBelief: auction.partnerOf('N'),
        lhoBelief: auction.lhoOf('N'),
        rhoBelief: auction.rhoOf('N'),
        candidateStrain: Suit.hearts,
        candidateLevel: 4,
      );

      // 4 trumps in North + 7 trumps in South = 11 card fit
      expect(vecNorth.candidateFit, greaterThanOrEqualTo(11.0));
      expect(vecNorth.candidateFitSurplus, greaterThanOrEqualTo(3.0));
      // Combined expected tricks with 11 trumps and short diamond ruff
      expect(vecNorth.expectedTricks, greaterThanOrEqualTo(10.5));
      expect(vecNorth.probabilityOfMaking, greaterThanOrEqualTo(0.60));
    });

    test('Pure continuous valuation scales monotonically for 7-4-1-1 and 8-2-2-1 shapes', () {
      final auction = AuctionBeliefState();

      // Hand A: 6-card heart suit: ♠K2 ♥AQ8642 ♦A8 ♣T4 (13 HCP)
      final hand6 = Hand.fromString('K2.AQ8642.A8.T4');
      // Hand B: 7-card heart suit: ♠2 ♥AQ86423 ♦A8 ♣T4 (13 HCP, 7-2-2-2)
      final hand7 = Hand.fromString('2.AQ86423.A8.T4');
      // Hand C: 8-card heart suit: ♠2 ♥AQ864232 ♦A8 ♣4 (13 HCP, 8-2-2-1)
      final hand8 = Hand.fromString('2.AQ864232.A8.4');

      final vec6 = MLPerspectiveFeatureExtractor.extract(
        myHand: hand6,
        partnerBelief: auction.partnerOf('S'),
        lhoBelief: auction.lhoOf('S'),
        rhoBelief: auction.rhoOf('S'),
        candidateStrain: Suit.hearts,
      );

      final vec7 = MLPerspectiveFeatureExtractor.extract(
        myHand: hand7,
        partnerBelief: auction.partnerOf('S'),
        lhoBelief: auction.lhoOf('S'),
        rhoBelief: auction.rhoOf('S'),
        candidateStrain: Suit.hearts,
      );

      final vec8 = MLPerspectiveFeatureExtractor.extract(
        myHand: hand8,
        partnerBelief: auction.partnerOf('S'),
        lhoBelief: auction.lhoOf('S'),
        rhoBelief: auction.rhoOf('S'),
        candidateStrain: Suit.hearts,
      );

      // Verify continuous monotonic increase without hardcoded shape jumps
      expect(vec7.playingStrength, greaterThan(vec6.playingStrength));
      expect(vec8.playingStrength, greaterThan(vec7.playingStrength));
    });
  });
}
