import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/ui/practice_quiz_view.dart';
import 'package:bridge_bidding_system/ui/widgets/enter_hand_dialog.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';

void main() {
  testWidgets('EnterHandDialog opens from PracticeQuizView toolbar', (WidgetTester tester) async {
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

    // Verify "Enter Hand" button is visible
    final enterHandBtn = find.widgetWithText(FilledButton, 'Enter Hand');
    expect(enterHandBtn, findsOneWidget);

    // Tap "Enter Hand" to open the dialog
    await tester.tap(enterHandBtn);
    await tester.pumpAndSettle();

    // Verify dialog title is shown
    expect(find.text('Enter Custom Deal / Hands'), findsOneWidget);
    expect(find.text('Paste Text / Deal'), findsOneWidget);
    expect(find.text('Suit Inputs'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Enter Custom Deal / Hands'), findsNothing);
  });

  testWidgets('EnterHandDialog parses user 9-heart hand preset and loads deal', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    PartnershipDeal? loadedDeal;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                loadedDeal = await EnterHandDialog.show(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap "User Hand (9♥)" sample button
    final sampleButton = find.text('User Hand (9♥)');
    expect(sampleButton, findsOneWidget);
    await tester.tap(sampleButton);
    await tester.pumpAndSettle();

    // Verify preview shows N, S, and E
    expect(find.textContaining('North (N)'), findsOneWidget);
    expect(find.textContaining('South (S)'), findsOneWidget);
    expect(find.textContaining('East (E)'), findsOneWidget);
    expect(find.textContaining('11 HCP'), findsWidgets);
    expect(find.textContaining('12 HCP'), findsWidgets);

    // Verify "Load Deal" button is enabled
    final loadBtn = find.widgetWithText(FilledButton, 'Load Deal');
    expect(loadBtn, findsOneWidget);

    await tester.tap(loadBtn);
    await tester.pumpAndSettle();

    expect(loadedDeal, isNotNull);
    // Verify North has 9 hearts (AJT976543)
    expect(loadedDeal!.north.cardsInSuit(Suit.hearts).length, equals(9));
    expect(loadedDeal!.north.cardsInSuit(Suit.clubs).length, equals(0)); // void
    // Verify South has 13 cards, West was completed automatically
    expect(loadedDeal!.south.cards.length, equals(13));
    expect(loadedDeal!.west.cards.length, equals(13));
  });

  testWidgets('EnterHandDialog detects duplicate cards and shows error', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EnterHandDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter conflicting hands with duplicate Ace of Spades in North and South
    final textField = find.byType(TextField);
    await tester.enterText(
      textField,
      'North:\nS:AKQ\nH:JT9\nD:876\nC:5432\n\nSouth:\nS:AK\nH:8765\nD:5432\nC:AK',
    );
    await tester.pumpAndSettle();

    // Verify error is shown
    expect(find.textContaining('Duplicate card ♠A'), findsOneWidget);

    // "Load Deal" button should be disabled
    final loadBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Load Deal'));
    expect(loadBtn.onPressed, isNull);
  });
}
