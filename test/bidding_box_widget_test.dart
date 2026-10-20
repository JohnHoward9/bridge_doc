import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/ui/widgets/bidding_box_widget.dart';

void main() {
  group('BiddingBoxWidget Tests', () {
    testWidgets('Renders all levels 1-7, suits, alert, and action buttons', (WidgetTester tester) async {
      String? selectedBid;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingBoxWidget(
              validateLegality: false,
              onBidSelected: (bid) => selectedBid = bid,
            ),
          ),
        ),
      );

      // Verify numbers 1-7 exist
      for (int i = 1; i <= 7; i++) {
        expect(find.text('$i'), findsOneWidget);
      }

      // Verify suits exist
      expect(find.text('♣'), findsOneWidget);
      expect(find.text('♦'), findsOneWidget);
      expect(find.text('♥'), findsOneWidget);
      expect(find.text('♠'), findsOneWidget);
      expect(find.text('NT'), findsOneWidget);

      // Verify alert button exists
      expect(find.text('A'), findsOneWidget);

      // Verify action buttons exist
      expect(find.text('Pass'), findsOneWidget);
      expect(find.text('X'), findsOneWidget);
      expect(find.text('XX'), findsOneWidget);

      // Default level is 1. Tapping Spade should select '1s'
      await tester.tap(find.text('♠'));
      await tester.pump();
      expect(selectedBid, '1s');

      // Tapping level 3 then Hearts should select '3h'
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('♥'));
      await tester.pump();
      expect(selectedBid, '3h');

      // Tapping NT should select '3nt'
      await tester.tap(find.text('NT'));
      await tester.pump();
      expect(selectedBid, '3nt');

      // Tapping Pass
      await tester.tap(find.text('Pass'));
      await tester.pump();
      expect(selectedBid, 'pass');

      // Tapping X
      await tester.tap(find.text('X'));
      await tester.pump();
      expect(selectedBid, 'dbl');

      // Tapping XX
      await tester.tap(find.text('XX'));
      await tester.pump();
      expect(selectedBid, 'rdbl');
    });

    testWidgets('Disabled state prevents taps', (WidgetTester tester) async {
      String? selectedBid;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingBoxWidget(
              isEnabled: false,
              onBidSelected: (bid) => selectedBid = bid,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pass'), warnIfMissed: false);
      await tester.pump();
      expect(selectedBid, isNull);

      await tester.tap(find.text('♠'), warnIfMissed: false);
      await tester.pump();
      expect(selectedBid, isNull);
    });

    testWidgets('Legal bid filtering: after 1S by partner (North), only 1NT and Pass available at level 1; no dbl or redbl', (WidgetTester tester) async {
      String? selectedBid;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingBoxWidget(
              activeSeat: 'S',
              history: const [
                AuctionEntry(seat: 'N', call: '1s'),
                AuctionEntry(seat: 'E', call: 'Pass'),
              ],
              onBidSelected: (bid) => selectedBid = bid,
            ),
          ),
        ),
      );

      // 1. At level 1: 1♣, 1♦, 1♥, 1♠ must be disabled and cannot be tapped
      selectedBid = null;
      await tester.tap(find.text('♣'));
      await tester.pump();
      expect(selectedBid, isNull, reason: '1♣ is lower than 1♠ and must be disabled');

      await tester.tap(find.text('♦'));
      await tester.pump();
      expect(selectedBid, isNull, reason: '1♦ is lower than 1♠ and must be disabled');

      await tester.tap(find.text('♥'));
      await tester.pump();
      expect(selectedBid, isNull, reason: '1♥ is lower than 1♠ and must be disabled');

      await tester.tap(find.text('♠'));
      await tester.pump();
      expect(selectedBid, isNull, reason: '1♠ is equal to current contract and must be disabled');

      // 2. Double (X) and Redouble (XX) must be disabled (partner bid 1S, undoubled)
      await tester.tap(find.text('X'));
      await tester.pump();
      expect(selectedBid, isNull, reason: 'Cannot double partner contract');

      await tester.tap(find.text('XX'));
      await tester.pump();
      expect(selectedBid, isNull, reason: 'Cannot redouble undoubled contract');

      // 3. 1NT must be legal and selectable at level 1
      await tester.tap(find.text('NT'));
      await tester.pump();
      expect(selectedBid, '1nt', reason: '1NT is higher than 1♠ and must be legal');

      // 4. Pass must be legal and selectable
      selectedBid = null;
      await tester.tap(find.text('Pass'));
      await tester.pump();
      expect(selectedBid, 'pass', reason: 'Pass is always legal');

      // 5. Selecting level 2 allows 2♣ (and all suits at level 2)
      selectedBid = null;
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('♣'));
      await tester.pump();
      expect(selectedBid, '2c', reason: '2♣ is higher than 1♠ and must be legal');
    });

    testWidgets('Legal bid filtering: after 1H by opponent (East), Double (X) is enabled', (WidgetTester tester) async {
      String? selectedBid;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingBoxWidget(
              activeSeat: 'S',
              history: const [
                AuctionEntry(seat: 'E', call: '1h'),
              ],
              onBidSelected: (bid) => selectedBid = bid,
            ),
          ),
        ),
      );

      // Double should be enabled against opponent's 1H
      await tester.tap(find.text('X'));
      await tester.pump();
      expect(selectedBid, 'dbl', reason: 'Can double opponent contract');

      // Redouble should remain disabled
      selectedBid = null;
      await tester.tap(find.text('XX'));
      await tester.pump();
      expect(selectedBid, isNull, reason: 'Cannot redouble opponent contract that was not doubled');
    });

    testWidgets('Legal bid filtering: after 1H by partner doubled by East, Redouble (XX) is enabled', (WidgetTester tester) async {
      String? selectedBid;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingBoxWidget(
              activeSeat: 'S',
              history: const [
                AuctionEntry(seat: 'N', call: '1h'),
                AuctionEntry(seat: 'E', call: 'dbl'),
              ],
              onBidSelected: (bid) => selectedBid = bid,
            ),
          ),
        ),
      );

      // Redouble should be enabled on partner's doubled contract
      await tester.tap(find.text('XX'));
      await tester.pump();
      expect(selectedBid, 'rdbl', reason: 'Can redouble partner doubled contract');

      // Double should remain disabled
      selectedBid = null;
      await tester.tap(find.text('X'));
      await tester.pump();
      expect(selectedBid, isNull, reason: 'Cannot double after opponent doubled');
    });

    testWidgets('Confirm mode via radio button stages bid, shows description/rule, and requires confirm button', (WidgetTester tester) async {
      String? selectedBid;
      bool confirmMode = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingBoxWidget(
              validateLegality: false,
              requireConfirmation: false,
              onRequireConfirmationChanged: (val) => confirmMode = val,
              descriptionResolver: (call) {
                if (call == '1s') {
                  return const BidDescription(
                    call: '1s',
                    displayCall: '1♠',
                    description: 'Opening 1 Spade (5+ Spades, 12-21 HCP)',
                    rule: 'spades >= 5 and hcp >= 12',
                  );
                }
                return null;
              },
              onBidSelected: (bid) => selectedBid = bid,
            ),
          ),
        ),
      );

      // Verify radio buttons exist
      expect(find.text('Direct'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);

      // Switch to Confirm mode via radio button
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(confirmMode, isTrue);

      // Tap 1 then Spade: should NOT immediately call onBidSelected
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('♠'));
      await tester.pump();

      expect(selectedBid, isNull, reason: 'In confirm mode, bid is not submitted immediately');

      // Verify staged bid card appears with description and rule
      expect(find.text('Selected: 1♠'), findsOneWidget);
      expect(find.textContaining('Opening 1 Spade (5+ Spades, 12-21 HCP)'), findsOneWidget);
      expect(find.textContaining('Rule: spades >= 5 and hcp >= 12'), findsOneWidget);

      // Verify Confirm button exists
      final confirmBtn = find.text('Confirm Bid: 1♠');
      expect(confirmBtn, findsOneWidget);

      // Tap Confirm
      await tester.tap(confirmBtn);
      await tester.pump();

      expect(selectedBid, '1s');
      // After confirmation, staged card disappears
      expect(find.text('Selected: 1♠'), findsNothing);
    });

    testWidgets('Staged bid can be cancelled', (WidgetTester tester) async {
      String? selectedBid;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingBoxWidget(
              validateLegality: false,
              requireConfirmation: true,
              onBidSelected: (bid) => selectedBid = bid,
            ),
          ),
        ),
      );

      // Tap Pass: stages Pass
      await tester.tap(find.text('Pass'));
      await tester.pump();

      expect(selectedBid, isNull);
      expect(find.text('Selected: Pass'), findsOneWidget);

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      // Staged card dismissed without submitting
      expect(selectedBid, isNull);
      expect(find.text('Selected: Pass'), findsNothing);
    });
  });
}
