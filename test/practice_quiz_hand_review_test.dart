import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/hand.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/services/hand_review_service.dart';
import 'package:bridge_bidding_system/engine/deal_generator.dart';
import 'package:bridge_bidding_system/ui/practice_quiz_view.dart';

void main() {
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
  late Directory tempDir;
  late HandReviewService reviewService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quiz_review_test_');
    reviewService = HandReviewService(directory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('PracticeQuizView has Save Hand and Review Hands buttons and dialogs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(
            system: system,
            reviewService: reviewService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify buttons exist
    final saveButton = find.text('Save Hand');
    final errorHandsButton = find.text('Error Hands');
    expect(saveButton, findsOneWidget);
    expect(errorHandsButton, findsOneWidget);

    // 2. Open Save Hand dialog
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Capture Bidding Error Hand'), findsOneWidget);
    expect(find.text('Description *'), findsOneWidget);
    expect(find.text('Error Type / Category *'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 3. Open Review Hands dialog
    final state = tester.state<PracticeQuizViewState>(find.byType(PracticeQuizView));
    state.showReviewHandsDialog(tester.element(find.byType(PracticeQuizView)), preloadedBoards: <ReviewBoard>[]);
    await tester.pumpAndSettle();

    expect(find.text('Review Hands in \\review'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('Saving and then loading a review board resets auction and shows review mode banner', (WidgetTester tester) async {
    final sampleNorth = Hand.fromString('AKQ2.KJT.A432.K');
    final sampleEast = Hand.fromString('987.Q982.T98.J98');
    final sampleSouth = Hand.fromString('J654.A765.KQ.T43');
    final sampleWest = Hand.fromString('T3.43.J765.A7652');
    final sampleDeal = PartnershipDeal(
      north: sampleNorth,
      east: sampleEast,
      south: sampleSouth,
      west: sampleWest,
    );

    late ReviewBoard savedBoard;
    await tester.runAsync(() async {
      await reviewService.saveBoard(
        deal: sampleDeal,
        dealer: 'N',
        shortDescription: 'test_review_hand_problem',
        longDescription: 'Detailed explanation of why this board needs review.',
      );
      final list = await reviewService.listReviewBoards();
      savedBoard = list.first;
    });

    tester.view.physicalSize = const Size(1300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(
            system: system,
            reviewService: reviewService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Review Hands dialog with the preloaded savedBoard
    final state = tester.state<PracticeQuizViewState>(find.byType(PracticeQuizView));
    state.showReviewHandsDialog(tester.element(find.byType(PracticeQuizView)), preloadedBoards: [savedBoard]);
    await tester.pumpAndSettle();

    expect(find.text('test_review_hand_problem'), findsOneWidget);
    expect(find.text('Re-bid Hand'), findsOneWidget);

    // Tap Re-bid Hand
    await tester.tap(find.text('Re-bid Hand'));
    await tester.pumpAndSettle();

    // Dialog closes, Review Mode banner is visible
    expect(find.text('REVIEW MODE'), findsOneWidget);
    expect(find.text('test_review_hand_problem'), findsOneWidget);
    expect(find.text('Detailed explanation of why this board needs review.'), findsOneWidget);

    // Verify auction is reset to the beginning (North opened 1C)
    expect(find.textContaining('Reviewing problem hand: "test_review_hand_problem"'), findsOneWidget);

    // Dismiss review banner
    final closeBanner = find.byTooltip('Exit review mode');
    expect(closeBanner, findsOneWidget);
    await tester.tap(closeBanner);
    await tester.pumpAndSettle();

    expect(find.text('REVIEW MODE'), findsNothing);
  });
}
