import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/ui/bidding_tree_view.dart';
import 'package:bridge_bidding_system/ui/yaml_editor_tab.dart';

void main() {
  testWidgets('Explorer YAML button invokes callback and loads bid in YamlEditorTab', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bid3C = BiddingNode(
      call: '3c',
      desc: 'Natural second suit Clubs, GF',
      rule: '10+hcp 5+h 4+c',
    );
    final bid1NT = BiddingNode(
      call: '1nt',
      desc: '15-17 Balanced',
      rule: '15-17hcp',
      bids: [bid3C],
    );
    final system = BridgeSystem(
      name: 'Integration Test System',
      openingBids: [bid1NT],
    );

    List<BiddingNode>? yamlPath;

    // 1. Test BiddingTreeView has YAML button and calls onViewInYaml
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BiddingTreeView(
            system: system,
            onViewInYaml: (path) => yamlPath = path,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final yamlButtons = find.widgetWithText(InkWell, 'YAML');
    expect(yamlButtons, findsWidgets);

    // Tap YAML button on 1NT
    await tester.tap(yamlButtons.first);
    await tester.pumpAndSettle();

    expect(yamlPath, isNotNull);
    expect(yamlPath!.first.call, '1nt');

    // 2. Test YamlEditorTab preloads with that call
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YamlEditorTab(
            system: system,
            initialFocusedCall: yamlPath!.first.call,
            onSystemUpdated: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify it loads with 1nt in the editor
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, contains('1nt'));
  });
}
