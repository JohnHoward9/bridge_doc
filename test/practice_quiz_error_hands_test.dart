import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/services/hand_review_service.dart';
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
''';

  final system = SystemYamlParser.fromYaml(yamlSample);
  late Directory tempErrorDir;

  setUp(() async {
    tempErrorDir = await Directory.systemTemp.createTemp('quiz_error_test_');
  });

  tearDown(() async {
    if (await tempErrorDir.exists()) {
      await tempErrorDir.delete(recursive: true);
    }
  });

  testWidgets('PracticeQuizView has Save Error Hand and Error Hands buttons and dialogs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // 1. Verify Error buttons exist in toolbar
    final saveErrorBtn = find.text('Save Hand');
    final errorHandsBtn = find.text('Error Hands');
    expect(saveErrorBtn, findsOneWidget);
    expect(errorHandsBtn, findsOneWidget);

    // 2. Open Save Error Hand Dialog
    await tester.tap(saveErrorBtn);
    await tester.pumpAndSettle();

    expect(find.text('Capture Bidding Error Hand'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Error Type / Category *'), findsOneWidget);
    expect(find.text('Description *'), findsOneWidget);
    expect(find.text('Additional Notes / Failure Details (Optional)'), findsOneWidget);
    expect(find.text('Wrong Bid'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // 3. Open Error Hands Dialog
    final state = tester.state<PracticeQuizViewState>(find.byType(PracticeQuizView));
    state.showErrorHandsDialog(tester.element(find.byType(PracticeQuizView)), preloadedBoards: <ReviewBoard>[]);
    await tester.pumpAndSettle();

    expect(find.text(r'Bidding Error Hands in \errors'), findsOneWidget);
    expect(find.textContaining('All ('), findsOneWidget);
    expect(find.textContaining('Open ('), findsOneWidget);
    expect(find.textContaining('Fixed ('), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    // Close dialog using Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('PracticeQuizView allows adding new category to dropdown and edit error details', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // 1. Open Save Error Hand Dialog
    await tester.tap(find.text('Save Hand'));
    await tester.pumpAndSettle();

    // 2. Tap '+' button to add custom category
    final addCategoryBtn = find.byTooltip('Add new category to list');
    expect(addCategoryBtn, findsOneWidget);
    await tester.tap(addCategoryBtn);
    await tester.pumpAndSettle();

    expect(find.text('Add New Category'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Category Name'), 'Custom Inverted Minor Error');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Verify new category is selected in the dropdown
    expect(find.text('Custom Inverted Minor Error'), findsOneWidget);

    // Cancel save dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('PracticeQuizView allows entering description and saving error hand', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeQuizView(
            system: system,
            errorService: HandReviewService(directory: tempErrorDir),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Save Error Hand Dialog
    await tester.tap(find.text('Save Hand'));
    await tester.pumpAndSettle();

    // Fill in Description
    await tester.enterText(
      find.widgetWithText(TextField, 'Description *'),
      'Test description of bidding failure',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // Verify dialog dismissed and file saved
    expect(find.text('Capture Bidding Error Hand'), findsNothing);
    final files = tempErrorDir.listSync().whereType<File>().toList();
    expect(files.length, 1);
    final content = files.first.readAsStringSync();
    expect(content, contains('[Description "Test description of bidding failure"]'));
    expect(content, contains('[ErrorType "Wrong Bid"]'));
  });
}
