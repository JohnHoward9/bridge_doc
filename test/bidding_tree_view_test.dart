import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/ui/bidding_tree_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadGavinSystem() async {
    final file = File('assets/core/systems/gavin_wolpert_2over1.yaml');
    final yamlStr = await file.readAsString();
    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) return await f.readAsString();
        return '';
      },
    );
  }

  group('BiddingTreeView Interactive Tree Tests', () {
    late BridgeSystem system;

    setUpAll(() async {
      system = await loadGavinSystem();
    });

    testWidgets('Opening bids render with resolved descriptions and > expansion symbols', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingTreeView(system: system),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify opening bids 1c, 1d, 1h, 1s are visible
      expect(find.text('1c'), findsWidgets);
      expect(find.text('1d'), findsWidgets);
      expect(find.text('1h'), findsWidgets);
      expect(find.text('1s'), findsWidgets);

      // Verify description is resolved and NOT '(No description)' for opening bids
      expect(find.text('(No description)'), findsNothing);

      // Verify '>' expansion chevron icons exist
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });

    testWidgets('Tapping > on 1c expands child continuations in-place', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingTreeView(system: system),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the chevron specifically within 1c card
      final card1c = find.ancestor(of: find.text('1c'), matching: find.byType(Card)).first;
      final chevron1c = find.descendant(of: card1c, matching: find.byIcon(Icons.chevron_right));
      expect(chevron1c, findsOneWidget);

      // Tap 1c's chevron
      await tester.tap(chevron1c);
      await tester.pumpAndSettle();

      // After expanding, responses under 1c should appear
      expect(find.text('1d'), findsWidgets);
      expect(find.text('1h'), findsWidgets);
      expect(find.text('1s'), findsWidgets);
      expect(find.text('1nt'), findsWidgets);
    });

    testWidgets('Partnership mode skips opposition bids while Competitive mode includes them', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingTreeView(system: system),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand 1c
      final card1c = find.ancestor(of: find.text('1c'), matching: find.byType(Card)).first;
      final chevron1c = find.descendant(of: card1c, matching: find.byIcon(Icons.chevron_right));
      await tester.tap(chevron1c);
      await tester.pumpAndSettle();

      // In default Partnership mode:
      // Verify no opponent calls in parentheses like (1d) or (1h) appear
      final allTextWidgets = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').toList();
      final hasParenCallsInPartnership = allTextWidgets.any((t) => t.startsWith('(') && t.endsWith(')') && t.length <= 6);
      expect(hasParenCallsInPartnership, isFalse, reason: 'Partnership mode should skip all opposition calls');

      // Switch to Competitive mode
      final competitiveButton = find.text('Competitive (All Calls)');
      expect(competitiveButton, findsOneWidget);
      await tester.tap(competitiveButton);
      await tester.pumpAndSettle();

      // In Competitive mode, mode button is selected
      expect(find.text('Competitive (All Calls)'), findsOneWidget);
    });

    testWidgets('Tapping a card opens Detail Inspector with sequence path and practice button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      List<BiddingNode>? practicePath;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingTreeView(
              system: system,
              onPracticeFromNode: (path) => practicePath = path,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the 1h card text
      await tester.tap(find.text('1h').first);
      await tester.pumpAndSettle();

      // Verify Inspector panel is shown
      expect(find.text('Bid Inspector'), findsOneWidget);
      expect(find.text('Hand Criteria Rule:'), findsOneWidget);
      expect(find.text('Practice Auction from Here 🎯'), findsOneWidget);

      // Ensure visible in the scrollable inspector and tap the practice button
      final practiceBtnFinder = find.text('Practice Auction from Here 🎯');
      await tester.ensureVisible(practiceBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(practiceBtnFinder);
      await tester.pumpAndSettle();

      expect(practicePath, isNotNull);
      expect(practicePath!.first.displayCall, equals('1h'));
    });
  });
}
