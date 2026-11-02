import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/ui/widgets/system_blueprint_editor_widget.dart';

void main() {
  testWidgets('SystemBlueprintEditorWidget renders and handles 1NT range changes and inspect callbacks', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opening1NT = BiddingNode(
      call: '1nt',
      desc: '15-17 Balanced',
      rule: '15-17hcp',
      bids: [
        BiddingNode(call: '2d', desc: 'Transfer to Hearts', rule: '5+h'),
      ],
    );
    final opening1H = BiddingNode(
      call: '1h',
      desc: '1H Opening',
      rule: '12-21hcp 5+h',
    );
    final system = BridgeSystem(
      name: 'Gavin Wolpert Master Series',
      openingBids: [opening1NT, opening1H],
      fragments: {
        'fJacobyTransfer': Fragment(name: 'fJacobyTransfer', desc: 'Jacoby Transfer'),
        'fMultiLandy': Fragment(name: 'fMultiLandy', desc: 'Multi-Landy vs 1NT'),
      },
    );

    BridgeSystem? updatedSystem;
    List<String>? inspectedPath;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SystemBlueprintEditorWidget(
            system: system,
            onSystemChanged: (newSys) => updatedSystem = newSys,
            onInspectBids: (path) => inspectedPath = path,
          ),
        ),
      ),
    );

    // Verify Title & Sections rendered
    expect(find.text('System Blueprint & Convention Wiring'), findsOneWidget);
    expect(find.text('🏛️ Opening Framework'), findsOneWidget);
    expect(find.text('🎯 1NT Response Suite'), findsOneWidget);

    // Verify 1NT Range chips
    expect(find.text('15-17 Strong NT'), findsOneWidget);
    expect(find.text('12-14 Weak NT'), findsOneWidget);

    // Click '12-14 Weak NT' chip
    await tester.tap(find.text('12-14 Weak NT'));
    await tester.pumpAndSettle();

    expect(updatedSystem, isNotNull);
    expect(updatedSystem!.openingBids.first.rule, contains('12-14hcp'));

    // Click 'Inspect / Edit Bids' for Jacoby Transfers
    final inspectButtons = find.widgetWithText(ElevatedButton, 'Inspect / Edit Bids');
    expect(inspectButtons, findsWidgets);

    await tester.tap(inspectButtons.first);
    await tester.pumpAndSettle();

    expect(inspectedPath, isNotNull);
    expect(inspectedPath, contains('1nt'));
  });
}
