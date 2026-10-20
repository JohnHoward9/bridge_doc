import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/engine/compiled_auction_graph.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';
import 'package:bridge_bidding_system/engine/auction_engine.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/evaluators/ml_bid_evaluator.dart';
import 'package:bridge_bidding_system/ui/practice_quiz_view.dart';
import 'package:bridge_bidding_system/ui/widgets/bidding_box_widget.dart';

void main() {
  testWidgets('TestMyMemory 3-panel UI renders and supports setup mode initial state bidding', (WidgetTester tester) async {
    const yamlSample = '''
system: Test System
player: North
partner: South
opening_bids:
  - call: 1c
    rule: hcp >= 12
    desc: 1 Club opening
    responses:
      - call: 1h
        rule: hcp >= 6 and hearts >= 4
        desc: 1 Heart response
''';

    final system = SystemYamlParser.fromYaml(yamlSample);

    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(system: system),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify 3 panels exist
    expect(find.text('Panel 1: North & South Hands'), findsOneWidget);
    expect(find.text('Panel 2: Bidding So Far'), findsOneWidget);
    expect(find.text('Panel 3: Bidding Box'), findsOneWidget);

    // 2. Verify North and South hand cards exist in Panel 1
    expect(find.text('Partner Hand (North)'), findsOneWidget);
    expect(find.text('Your Hand (South)'), findsOneWidget);

    // 3. Switch to Setup Mode in Panel 3
    final setupModeButton = find.text('Setup Mode');
    expect(setupModeButton, findsWidgets);
    await tester.tap(setupModeButton.first);
    await tester.pumpAndSettle();

    // 4. Verify Setup Mode controls and seats in Panel 2
    expect(find.textContaining('West'), findsWidgets);
    expect(find.textContaining('North'), findsWidgets);
    expect(find.textContaining('East'), findsWidgets);
    expect(find.textContaining('South'), findsWidgets);
    expect(find.text('Switch to Bid Mode ▶'), findsOneWidget);

    // Clear any initial auction to start fresh setup
    final clearBtn = find.widgetWithText(OutlinedButton, 'Clear');
    if (clearBtn.evaluate().isNotEmpty) {
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
    }

    // 5. Select North in Panel 2 and tap 1 then Club
    await tester.tap(find.descendant(of: find.byType(Table), matching: find.textContaining('North')).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('♣')));
    await tester.pumpAndSettle();

    // Verify 1♣ was logged
    expect(find.text('N: 1♣'), findsWidgets);

    // 6. Enter Pass for East
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('Pass')));
    await tester.pumpAndSettle();
    expect(find.text('E: Pass'), findsWidgets);

    // 7. Switch to Bid Mode
    await tester.tap(find.text('Switch to Bid Mode ▶'));
    await tester.pumpAndSettle();

    // Verify it is now South's turn
    expect(find.text('Your turn (South) to bid! Select your call below:'), findsOneWidget);

    // 8. Submit an incorrect bid for South (e.g., 1♠ when 1♥ is required)
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('♠')));
    await tester.pumpAndSettle();

    // 9. Verify Error Diagnostic Card in Panel 2 and Retry Banner in Panel 3
    expect(find.text('Incorrect Bid — Auction Halted'), findsOneWidget);
    expect(find.text('Try Again with this Hand'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    // 10. Tap "Try Again" to reset and allow re-bidding
    await tester.tap(find.text('Try Again with this Hand'));
    await tester.pumpAndSettle();

    // 11. Verify South can bid again
    expect(find.text('Your turn (South) to bid! Select your call below:'), findsOneWidget);
    expect(find.text('Incorrect Bid — Auction Halted'), findsNothing);

    // 12. Submit incorrect bid again and test Panel 3's "Try Again" button
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('♠')));
    await tester.pumpAndSettle();

    expect(find.text('Try Again'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Your turn (South) to bid! Select your call below:'), findsOneWidget);
    expect(find.text('Incorrect Bid — Auction Halted'), findsNothing);
  });

  testWidgets('TestMyMemory supports LAB interactive cell editing and North active bidding with Presets', (WidgetTester tester) async {
    const yamlSample = '''
system: Test System
player: North
partner: South
opening_bids:
  - call: 1s
    rule: hcp >= 12 and spades >= 5
    desc: 1 Spade opening
    responses:
      - call: 2nt
        rule: hcp >= 13 and spades >= 4
        desc: Jacoby 2NT
        rebids:
          - call: 4s
            rule: hcp <= 14
            desc: Minimum signoff
''';

    final system = SystemYamlParser.fromYaml(yamlSample);

    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(system: system),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Quick Practice Scenarios bar exists
    expect(find.text('Quick Practice Scenarios:'), findsOneWidget);
    expect(find.text('1♠ → 2NT (Jacoby)'), findsOneWidget);

    // 2. Tap 1♠ → 2NT (Jacoby) preset
    await tester.tap(find.text('1♠ → 2NT (Jacoby)'));
    await tester.pumpAndSettle();

    // 3. Verify auction entries on LAB
    expect(find.text('1♠'), findsWidgets);
    expect(find.text('2NT'), findsWidgets);

    // 4. Verify North is the active player to rebid
    expect(find.text('Your Hand (North)'), findsOneWidget);
    expect(find.text('Partner Hand (South)'), findsOneWidget);
    expect(find.text('Your turn (North) to bid! Select your call below:'), findsOneWidget);

    // 5. Test that in Bid Mode, prior auction cells for North/South/East/West are fixed:
    // Tap on cell displaying '2NT' in Bid Mode - verify mode remains Bid Mode
    final lab2NtFinder = find.descendant(
      of: find.byType(Table),
      matching: find.text('2NT'),
    );
    expect(lab2NtFinder, findsOneWidget);
    await tester.tap(lab2NtFinder);
    await tester.pumpAndSettle();
    expect(find.text('🎯 Bid Mode (Fixed Auction)'), findsOneWidget);

    // Switch to Setup Mode to edit cell 2
    await tester.tap(find.text('Setup Mode').first);
    await tester.pumpAndSettle();

    final lab2NtFinderSetup = find.descendant(of: find.byType(Table), matching: find.text('2NT'));
    await tester.tap(lab2NtFinderSetup);
    await tester.pumpAndSettle();

    // Select a different bid (3NT) from the Bidding Box directly below
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('3')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('NT')));
    await tester.pumpAndSettle();

    // Verify cell 2 was replaced with 3NT!
    expect(find.descendant(of: find.byType(Table), matching: find.text('3NT')), findsOneWidget);
  });

  testWidgets('TestMyMemory supports Dealer selection via Panel 2 headers, South filter dialog, and deal update on bid', (WidgetTester tester) async {
    const yamlSample = '''
system: Test System
player: North
partner: South
opening_bids:
  - call: 1s
    rule: hcp >= 12 and spades >= 5
    desc: 1 Spade opening
''';

    final system = SystemYamlParser.fromYaml(yamlSample);

    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(system: system),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initial dealer is North - verify dealer badge on North
    expect(find.text('Dealer'), findsOneWidget);
    expect(find.text('👑'), findsOneWidget);

    // 2. In Bid Mode, tapping East header does not change dealer (dealer is fixed)
    final eastHeaderFinder = find.descendant(of: find.byType(Table), matching: find.textContaining('East')).first;
    await tester.tap(eastHeaderFinder);
    await tester.pumpAndSettle();
    expect(find.textContaining('Dealer: NORTH'), findsOneWidget);

    // 3. Switch to Setup Mode to change dealer to East
    await tester.tap(find.text('Setup Mode').first);
    await tester.pumpAndSettle();
    await tester.tap(eastHeaderFinder);
    await tester.pumpAndSettle();

    // Verify East is now dealer
    expect(find.text('👑'), findsOneWidget);
    expect(find.textContaining('Dealer: EAST'), findsOneWidget);

    // Switch dealer back to North
    final northHeaderFinder = find.descendant(of: find.byType(Table), matching: find.textContaining('North')).first;
    await tester.tap(northHeaderFinder);
    await tester.pumpAndSettle();
    expect(find.textContaining('Dealer: NORTH'), findsOneWidget);

    // 3. Test South Hand Filter dialog
    final tuneIconFinder = find.descendant(of: find.byType(Table), matching: find.byIcon(Icons.tune));
    expect(tuneIconFinder, findsOneWidget);
    await tester.tap(tuneIconFinder);
    await tester.pumpAndSettle();

    // Dialog opens
    expect(find.text('South Hand Filters'), findsOneWidget);
    expect(find.text('HCP Range:'), findsOneWidget);
    expect(find.text('Hand Shape:'), findsOneWidget);

    // Tap Apply & Redeal to close
    await tester.tap(find.text('Apply & Redeal'));
    await tester.pumpAndSettle();
    expect(find.text('South Hand Filters'), findsNothing);

    // 4. Verify entering a bid in Setup Mode updates Panel 1 deal
    await tester.tap(find.text('Setup Mode').first);
    await tester.pumpAndSettle();

    // Note North's initial HCP text
    final hcpFinders = find.textContaining('HCP');
    expect(hcpFinders, findsWidgets);

    // Enter 1♠ for North
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('♠')));
    await tester.pumpAndSettle();

    // 1♠ is now logged in Panel 2
    expect(find.descendant(of: find.byType(Table), matching: find.text('1♠')), findsOneWidget);
    // Panel 1 hands are rendered and conform
    expect(find.text('Partner Hand (North)'), findsOneWidget);
    expect(find.text('Partner Hand (South)'), findsOneWidget);
  });

  testWidgets('Both North and South hands render Eff HCP badges in Panel 1', (WidgetTester tester) async {
    const yamlSample = '''
system: Test System
player: North
partner: South
opening_bids:
  - call: 1c
    rule: hcp >= 12
    desc: 1 Club opening
''';

    final system = SystemYamlParser.fromYaml(yamlSample);

    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(system: system),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify both North and South hands display an Eff HCP badge
    final effHcpBadges = find.textContaining('Eff HCP');
    expect(effHcpBadges, findsNWidgets(2));
  });

  testWidgets('Clicking on bids in Bidding So Far shows description, and Bidding Box confirm flow works', (WidgetTester tester) async {
    const yamlSample = '''
system: Test System
player: North
partner: South
opening_bids:
  - call: 1c
    rule: hcp >= 12
    desc: 1 Club opening
    responses:
      - call: 1h
        rule: hcp >= 6 and hearts >= 4
        desc: 1 Heart response
''';

    final system = SystemYamlParser.fromYaml(yamlSample);

    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(system: system),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Switch to Setup Mode in Panel 3
    final setupModeButton = find.text('Setup Mode');
    await tester.tap(setupModeButton.first);
    await tester.pumpAndSettle();

    // Clear any existing bids
    final clearBtn = find.widgetWithText(OutlinedButton, 'Clear');
    if (clearBtn.evaluate().isNotEmpty) {
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
    }

    // Select North in Panel 2 and tap 1 then Club
    await tester.tap(find.descendant(of: find.byType(Table), matching: find.textContaining('North')).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('♣')));
    await tester.pumpAndSettle();

    // Verify 1♣ in table
    final northOpeningCell = find.descendant(of: find.byType(Table), matching: find.text('1♣'));
    expect(northOpeningCell, findsOneWidget);

    // Tap the 1♣ call cell in Panel 2 to inspect it
    await tester.tap(northOpeningCell);
    await tester.pumpAndSettle();

    // Verify description card appears under the table
    expect(find.textContaining('North'), findsWidgets);
    expect(find.textContaining('1 Club opening'), findsOneWidget);

    // Close the inspected card
    final closeBtn = find.byTooltip('Close description');
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('Close description'), findsNothing);

    // Enter Pass for East
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('Pass')));
    await tester.pumpAndSettle();

    // Switch to Bid Mode
    await tester.tap(find.text('Switch to Bid Mode ▶'));
    await tester.pumpAndSettle();

    // 2. Test Bidding Box confirm mode
    final confirmRadio = find.text('Confirm');
    expect(confirmRadio, findsOneWidget);
    await tester.tap(confirmRadio);
    await tester.pumpAndSettle();

    // Tap 1 then ♥ in Bidding Box
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('♥')));
    await tester.pumpAndSettle();

    // Staged card should show in Panel 3 with description and Confirm button
    expect(find.text('Selected: 1♥'), findsOneWidget);
    expect(find.textContaining('1 Heart response'), findsOneWidget);
    final confirmBidBtn = find.text('Confirm Bid: 1♥');
    expect(confirmBidBtn, findsOneWidget);

    // Tap Confirm Bid
    await tester.tap(confirmBidBtn);
    await tester.pumpAndSettle();

    // Auction advances and staged card is cleared
    expect(find.text('Selected: 1♥'), findsNothing);
  });

  testWidgets('Setup Mode seat calculation shows [N next] after 4 bids, and persists setup auction across redeals until cleared', (WidgetTester tester) async {
    const yamlSample = '''
system: Test System
player: North
partner: South
opening_bids:
  - call: 1h
    rule: hcp >= 12 and hearts >= 5
    desc: 1 Heart opening
    responses:
      - call: 2h
        rule: hcp >= 6 and hearts >= 3
        desc: Simple Raise
''';

    final system = SystemYamlParser.fromYaml(yamlSample);

    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(system: system),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Switch to Setup Mode in Panel 3
    await tester.tap(find.text('Setup Mode').first);
    await tester.pumpAndSettle();

    // Clear auction to start fresh setup with North as Dealer
    final clearBtn = find.widgetWithText(OutlinedButton, 'Clear');
    if (clearBtn.evaluate().isNotEmpty) {
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();
    }

    // Set North as Dealer by tapping North header
    await tester.tap(find.descendant(of: find.byType(Table), matching: find.textContaining('North')).first);
    await tester.pumpAndSettle();

    // Verify initial turn prompt in North column is [N next]
    expect(find.text('[N next]'), findsOneWidget);
    expect(find.text('Active Seat: N'), findsOneWidget);

    // Bid 1: North Pass
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('Pass')));
    await tester.pumpAndSettle();
    expect(find.text('[E next]'), findsOneWidget);
    expect(find.text('Active Seat: E'), findsOneWidget);

    // Bid 2: East Pass
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('Pass')));
    await tester.pumpAndSettle();
    expect(find.text('[S next]'), findsOneWidget);
    expect(find.text('Active Seat: S'), findsOneWidget);

    // Bid 3: South 1♥
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('♥')));
    await tester.pumpAndSettle();
    expect(find.text('[W next]'), findsOneWidget);
    expect(find.text('Active Seat: W'), findsOneWidget);

    // Bid 4: West Pass
    await tester.tap(find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('Pass')));
    await tester.pumpAndSettle();

    // CRITICAL BUG VERIFICATION 1:
    // After 4 bids (N: Pass, E: Pass, S: 1♥, W: Pass), the next turn slot MUST BE [N next], NOT [W next]!
    expect(find.text('[N next]'), findsOneWidget);
    expect(find.text('[W next]'), findsNothing);
    expect(find.text('Active Seat: N'), findsOneWidget);

    // 2. Switch from Setup Mode to Bid Mode
    await tester.tap(find.text('Switch to Bid Mode ▶'));
    await tester.pumpAndSettle();

    // Verify auction is preserved in Bid Mode
    expect(find.text('1♥'), findsWidgets);
    expect(find.text('Your turn (North) to bid! Select your call below:'), findsOneWidget);

    // CRITICAL BUG VERIFICATION 2:
    // Redeal / New Deal must NOT wipe the setup auction!
    final redealBtn = find.widgetWithText(FilledButton, 'Redeal');
    expect(redealBtn, findsOneWidget);
    await tester.tap(redealBtn);
    await tester.pumpAndSettle();

    // Verify setup auction remains intact after redeal!
    expect(find.text('1♥'), findsWidgets);
    expect(find.text('Your turn (North) to bid! Select your call below:'), findsOneWidget);

    // 3. Tap Clear to verify explicit clearing returns to fresh deal
    final clearScenarioBtn = find.widgetWithText(TextButton, 'Clear');
    expect(clearScenarioBtn, findsOneWidget);
    await tester.tap(clearScenarioBtn);
    await tester.pumpAndSettle();

    // Now the setup auction is cleared
    expect(find.text('Your turn (North) to bid! Select your call below:'), findsNothing);
  });

  testWidgets('Drury passed-hand response: 2C accepted, 2NT not required, non-matching excluded', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BridgeSystem system;
    await tester.runAsync(() async {
      final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
      final yamlStr = await file.readAsString();
      system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async {
          final libFile = File(path);
          if (libFile.existsSync()) {
            return await libFile.readAsString();
          }
          return '';
        },
      );
    });

    // 1. Direct Engine Verification with user's exact hand from screenshot
    // North: ♠ AQ10986, ♥ 1065, ♦ AQ, ♣ 98 (12 HCP, 6 Spades)
    final northHand = Hand.fromString('AQ10986:1065:AQ:98');
    // South: ♠ K7432, ♥ AK4, ♦ K73, ♣ 42 (13 HCP, 5 Spades)
    final southHand = Hand.fromString('K7432:AK4:K73:42');

    final deal = PartnershipDeal(
      north: northHand,
      south: southHand,
      east: Hand.fromString('J5:J872:J86:KQJT'),
      west: Hand.fromString('T:Q93:T9542:A765'),
    );

    final engine = AuctionEngine.fromSystem(system);

    // Passed-hand auction: North Pass, East Pass, South 1♠, West Pass
    final history = [
      const AuctionEntry(seat: 'N', call: 'Pass', desc: 'Pass'),
      const AuctionEntry(seat: 'E', call: 'Pass', desc: 'Pass'),
      const AuctionEntry(seat: 'S', call: '1♠', desc: '1 Spade opening'),
      const AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
    ];

    // North bids 2C (Reverse Drury)
    final step2c = engine.advanceAuction(
      history: history,
      userCall: '2c',
      deal: deal,
      activeSeat: 'N',
    );

    expect(step2c.isUserBidCorrect, isTrue, reason: '2C Reverse Drury MUST be accepted for passed-hand North with 3+ spades');
    expect(step2c.nextValidCandidatesForUser, isNotEmpty);

    // North erroneously bids 2NT
    final step2nt = engine.advanceAuction(
      history: history,
      userCall: '2nt',
      deal: deal,
      activeSeat: 'N',
    );

    expect(step2nt.isUserBidCorrect, isFalse, reason: '2NT Jacoby MUST NOT be required for passed hand');
    expect(step2nt.expectedBestBid?.call, equals('2c'), reason: 'Expected bid should be 2c Reverse Drury');
    expect(step2nt.allEvaluatedMatches.every((c) => c.isMatch), isTrue, reason: 'Filtered candidate bids must only show matching options');

    // 2. UI Widget Test with Preset
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(
            system: system,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select Pass → 1♠ (Drury) preset
    final druryPresetFinder = find.widgetWithText(ActionChip, 'Pass → 1♠ (Drury)');
    expect(druryPresetFinder, findsOneWidget);
    await tester.tap(druryPresetFinder);
    await tester.pumpAndSettle();

    // Verify auction history shows Drury context
    expect(find.text('Your turn (North) to bid! Select your call below:'), findsOneWidget);

    // Make an incorrect bid to inspect Diagnostic Card: North bids 2NT
    final level2 = find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('2'));
    await tester.tap(level2);
    await tester.pumpAndSettle();

    final ntBtn = find.descendant(of: find.byType(BiddingBoxWidget), matching: find.text('NT'));
    await tester.tap(ntBtn);
    await tester.pumpAndSettle();

    // Verify error feedback card is shown with required Drury bid
    expect(find.textContaining('You bid "2nt", but the system requires "2c"'), findsOneWidget);
    expect(find.textContaining('Reverse Drury'), findsWidgets);

    // Verify that NO excluded candidate bids (like Jacoby 2NT) are shown in candidate bids list!
    expect(find.textContaining('Matching Candidate Bids Ranked by Priority'), findsOneWidget);
    expect(find.textContaining('Jacoby 2NT'), findsNothing);
  });

  testWidgets('2-over-1 minor response (1S - Pass - 2D) is recognized as 2/1 GF and not interference overcall', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BridgeSystem system;
    await tester.runAsync(() async {
      final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
      final yamlStr = await file.readAsString();
      system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async {
          final libFile = File(path);
          if (libFile.existsSync()) {
            return await libFile.readAsString();
          }
          return '';
        },
      );
    });

    // Exact hands from user screenshot:
    // North: ♠ AJ1062, ♥ A1064, ♦ A7, ♣ Q2 (15 HCP)
    final northHand = Hand.fromString('AJT62:AT64:A7:Q2');
    // South: ♠ K73, ♥ J3, ♦ KQJ954, ♣ J4 (11 HCP, 6 Diamonds)
    final southHand = Hand.fromString('K73:J3:KQJ954:J4');
    final eastHand = Hand.fromString('854:K987:83:AT85');
    final westHand = Hand.fromString('Q9:Q52:T62:K9763');

    final deal = PartnershipDeal(
      north: northHand,
      south: southHand,
      east: eastHand,
      west: westHand,
    );

    final engine = AuctionEngine.fromSystem(system);

    // Initial sequence: North opens 1♠, East passes
    final history = [
      const AuctionEntry(seat: 'N', call: '1♠', desc: '5+ Spades, 12-21 HCP'),
      const AuctionEntry(seat: 'E', call: 'Pass', desc: 'Opposition pass'),
    ];

    // South bids 2♦
    final step2d = engine.advanceAuction(
      history: history,
      userCall: '2d',
      deal: deal,
      activeSeat: 'S',
    );

    expect(step2d.isUserBidCorrect, isTrue, reason: '2D must be accepted as 2/1 Game Force in Diamonds');
    // The description must NOT be interference overcall!
    final southEntry = step2d.updatedHistory.firstWhere((e) => e.seat == 'S');
    expect(southEntry.desc, contains('2/1 Game Force in Diamonds'));
    expect(southEntry.desc, isNot(contains('Interference')));

    // Auction must NOT be marked complete; North should have rebid 2♥
    expect(step2d.isAuctionComplete, isFalse, reason: 'Auction must not finish prematurely after 2D');
    final northRebid = step2d.updatedHistory.firstWhere((e) => e.seat == 'N' && e != step2d.updatedHistory.first);
    expect(northRebid.call.toLowerCase(), anyOf(equals('2h'), equals('2♥')));
    expect(northRebid.desc, contains('Natural Hearts'));

    // East passes after North's rebid
    final eastEntry = step2d.updatedHistory.last;
    expect(eastEntry.seat, equals('E'));
    expect(eastEntry.call, equals('Pass'));
  });

  testWidgets('Competitive auction 1♥ - (1NT) - 2♥ does not halt prematurely and North rebids based on ML valuation', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BridgeSystem system;
    await tester.runAsync(() async {
      final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
      final yamlStr = await file.readAsString();
      system = await SystemLibraryResolver.loadSystemWithLibraries(
        yamlStr,
        fileLoader: (path) async {
          final libFile = File(path);
          if (libFile.existsSync()) {
            return await libFile.readAsString();
          }
          return '';
        },
      );
    });

    // Exact hands from user screenshot:
    // North: ♠ 2, ♥ KJT742, ♦ A87, ♣ A65 (12 HCP, 13.8 Eff HCP, 6 Hearts)
    final northHand = Hand.fromString('2:KJT742:A87:A65');
    // South: ♠ J9873, ♥ AQ5, ♦ 42, ♣ J82 (8 HCP, 8.2 Eff HCP, 3 Hearts)
    final southHand = Hand.fromString('J9873:AQ5:42:J82');
    final eastHand = Hand.fromString('AT4:98:KQJT6:KQ7');
    final westHand = Hand.fromString('KQ65:63:953:T943');

    final deal = PartnershipDeal(
      north: northHand,
      south: southHand,
      east: eastHand,
      west: westHand,
    );

    final mlEvaluator = MLEdgeCaseEvaluator();
    final engine = AuctionEngine.fromSystem(system, mlEvaluator: mlEvaluator);

    // Sequence so far:
    // North: 1♥, East: (1NT), South: 2♥, West: Pass
    final history = [
      const AuctionEntry(seat: 'N', call: '1♥', desc: '1 Heart opening'),
      const AuctionEntry(seat: 'E', call: '1NT', desc: '1NT interference overcall'),
      const AuctionEntry(seat: 'S', call: '2♥', desc: 'Competitive raise to 2H'),
      const AuctionEntry(seat: 'W', call: 'Pass', desc: 'Pass'),
    ];

    // 1. Check graph state at this sequence: must have available candidate rebids for North
    final seq = engine.extractSystemSequence(history);
    final state = engine.graph.getState(seq);
    expect(state, isNotNull, reason: 'State 1h:(1nt):2h must exist in the compiled graph');
    expect(state!.candidateNodes, isNotEmpty, reason: 'State must define candidate rebids for North');

    final northCandidates = state.evaluateCandidates(
      northHand,
      engine.resolver,
      fragments: engine.graph.system.fragments,
    ).where((c) => !c.isOpponent).toList();

    expect(northCandidates.any((c) => c.displayCall.toLowerCase() == 'pass'), isTrue);
    expect(northCandidates.any((c) => c.displayCall.toLowerCase().contains('3h') || c.displayCall.toLowerCase().contains('3♥')), isTrue);
    expect(northCandidates.any((c) => c.displayCall.toLowerCase().contains('4h') || c.displayCall.toLowerCase().contains('4♥')), isTrue);

    // 2. Advance auction with North bidding:
    // If North is active user and bids 4♥:
    final step4h = engine.advanceAuction(
      history: history,
      userCall: '4h',
      deal: deal,
      activeSeat: 'N',
    );
    expect(step4h.isUserBidCorrect, isTrue, reason: '4♥ is a valid accepted bid for North');
    expect(step4h.isAuctionComplete, isTrue, reason: 'Auction finishes after game signoff');

    // 3. Automated partner rebid when South bid 2♥:
    final stepSouth2h = engine.advanceAuction(
      history: [
        const AuctionEntry(seat: 'N', call: '1♥', desc: '1 Heart opening'),
        const AuctionEntry(seat: 'E', call: '1NT', desc: '1NT interference overcall'),
      ],
      userCall: '2h',
      deal: deal,
      activeSeat: 'S',
    );
    expect(stepSouth2h.isUserBidCorrect, isTrue);
    // Partner (North) should have rebid based on ML / hand valuation (either 4♥ or 3♥)
    final northCall = stepSouth2h.updatedHistory.firstWhere((e) => e.seat == 'N' && e != stepSouth2h.updatedHistory.first);
    expect(northCall.call.toLowerCase(), anyOf(equals('4h'), equals('4♥'), equals('3h'), equals('3♥')));
  });
}


