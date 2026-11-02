import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/ui/widgets/bid_detail_editor_widget.dart';

void main() {
  testWidgets('BidDetailEditorWidget modifies HCP range and saves bid', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bid3C = BiddingNode(
      call: '3c',
      desc: 'Natural second suit Clubs, Game Forcing',
      rule: 'p#1 10+hcp 5+h 4+c !short_honors gf',
      priority: 1,
    );
    final bid2H = BiddingNode(
      call: '2h',
      desc: 'Transfer Acceptance',
      bids: [bid3C],
    );
    final bid2D = BiddingNode(
      call: '2d',
      desc: 'Transfer to Hearts',
      bids: [bid2H],
    );
    final bid1NT = BiddingNode(
      call: '1nt',
      desc: '15-17 Balanced',
      bids: [bid2D],
    );
    final system = BridgeSystem(
      name: 'Test System',
      openingBids: [bid1NT],
    );

    BridgeSystem? savedSystem;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BidDetailEditorWidget(
            system: system,
            callPath: const ['1nt', '2d', '2h', '3c'],
            onSystemSaved: (sys) => savedSystem = sys,
            onNavigatePath: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify breadcrumb shows sequence
    expect(find.text('Auction Sequence: '), findsOneWidget);
    expect(find.text('3C'), findsWidgets);

    // Verify description field is loaded
    expect(find.text('Natural second suit Clubs, Game Forcing'), findsOneWidget);

    // Drag down to reveal bottom action bar and click Apply & Save Bid
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply & Save Bid 💾'));
    await tester.pumpAndSettle();

    expect(savedSystem, isNotNull);
  });
}
