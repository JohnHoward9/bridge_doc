import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/ui/yaml_editor_tab.dart';

void main() {
  testWidgets('YamlEditorTab validates modular YAML syntax, shows diagnostics, and blocks invalid apply', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final system = BridgeSystem(
      name: 'Test System',
      openingBids: [
        BiddingNode(call: '1nt', desc: '15-17 Balanced', rule: '15-17hcp s#5332'),
      ],
      fragments: {
        'fJacoby': Fragment(
          name: 'fJacoby',
          desc: 'Jacoby Transfer',
          bids: [
            BiddingNode(call: '2d', desc: 'Transfer to Hearts', rule: '5+h'),
          ],
        ),
      },
    );

    BridgeSystem? appliedSystem;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YamlEditorTab(
            system: system,
            onSystemUpdated: (updated) => appliedSystem = updated,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Dropdown selector has documents (system + fragment)
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('Validate 🔍'), findsOneWidget);
    expect(find.text('Validate & Apply 🚀'), findsOneWidget);

    // Initial valid state
    expect(find.textContaining('Valid ('), findsOneWidget);

    // Inject an invalid rule with a typo '15-17hpc' and bad suit '99+z'
    final textField = find.byType(TextField);
    await tester.enterText(textField, '''
system: "Broken System"
openings:
  - call: 1nt
    desc: "Typo rule"
    rule: 15-17hpc 99+z
''');
    await tester.pumpAndSettle();

    // Click Validate 🔍
    await tester.tap(find.text('Validate 🔍'));
    await tester.pumpAndSettle();

    // Verify Diagnostics panel is shown with error
    expect(find.text('Document Diagnostics & Rule Checker'), findsOneWidget);
    expect(find.textContaining('typo'), findsWidgets);

    // Attempt to click Validate & Apply 🚀 -> should be blocked!
    await tester.tap(find.text('Validate & Apply 🚀'));
    await tester.pumpAndSettle();

    expect(appliedSystem, isNull, reason: 'Invalid YAML must not be applied to the system');

    // Fix the YAML to be completely valid
    await tester.enterText(textField, '''
system: "Fixed System"
openings:
  - call: 1nt
    desc: "15-17 Strong NT"
    rule: 15-17hcp s#5332
''');
    await tester.pumpAndSettle();

    // Click Validate & Apply 🚀 -> now valid!
    await tester.tap(find.text('Validate & Apply 🚀'));
    await tester.pumpAndSettle();

    expect(appliedSystem, isNotNull);
    expect(appliedSystem!.name, equals('Fixed System'));
  });

  testWidgets('YamlEditorTab supports switching between modular documents', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final system = BridgeSystem(
      name: 'Modular System',
      openingBids: [
        BiddingNode(call: '1nt', desc: '15-17 Balanced', rule: '15-17hcp'),
      ],
      fragments: {
        'fStayman': Fragment(
          name: 'fStayman',
          desc: 'Stayman 2C',
          bids: [
            BiddingNode(call: '2c', desc: 'Stayman Ask', rule: '8+hcp 4+M'),
          ],
        ),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YamlEditorTab(
            system: system,
            onSystemUpdated: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Open dropdown and switch to fStayman fragment
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('🧩 Fragment: fStayman'), findsWidgets);

    await tester.tap(find.text('🧩 Fragment: fStayman').last);
    await tester.pumpAndSettle();

    // Editor should now contain ONLY the Stayman fragment YAML
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, contains('fragment: "fStayman"'));
    expect(textField.controller!.text, contains('Stayman Ask'));
  });
}
