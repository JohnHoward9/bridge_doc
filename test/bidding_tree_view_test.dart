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
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      // Expand 1nt in Competitive mode
      final card1nt = find.ancestor(of: find.text('1nt'), matching: find.byType(Card)).first;
      await tester.ensureVisible(card1nt);
      await tester.pumpAndSettle();

      final chevron1nt = find.descendant(of: card1nt, matching: find.byIcon(Icons.chevron_right));
      await tester.tap(chevron1nt);
      await tester.pumpAndSettle();

      // Verify opponent Multi-Landy calls like (2c) or (2d) appear
      final allCompetitiveTexts = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').toList();
      final hasMultiLandyInCompetitive = allCompetitiveTexts.any((t) => t.contains('2c') || t.contains('2d'));
      expect(hasMultiLandyInCompetitive, isTrue, reason: 'Competitive mode should display opponent Multi-Landy calls under 1NT');
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
      expect(find.text('Practice Against This Bid 🎯'), findsOneWidget);

      // Ensure visible in the scrollable inspector and tap the practice button
      final practiceBtnFinder = find.text('Practice Against This Bid 🎯');
      await tester.ensureVisible(practiceBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(practiceBtnFinder);
      await tester.pumpAndSettle();

      expect(practicePath, isNotNull);
      expect(practicePath!.first.displayCall, equals('1h'));
    });

    testWidgets('Expanding opponent Multi-Landy 2D under 1NT displays Transfer Lebensohl children', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingTreeView(
              system: system,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Competitive mode
      await tester.tap(find.text('Competitive (All Calls)'));
      await tester.pumpAndSettle();

      // Expand 1nt
      final card1nt = find.ancestor(of: find.text('1nt'), matching: find.byType(Card)).first;
      await tester.ensureVisible(card1nt);
      await tester.pumpAndSettle();

      final chevron1nt = find.descendant(of: card1nt, matching: find.byIcon(Icons.chevron_right));
      await tester.tap(chevron1nt);
      await tester.pumpAndSettle();

      // Find the Opponent Multi-Landy 2d card
      final multiLandy2DDesc = find.textContaining('single-suited major');
      expect(multiLandy2DDesc, findsOneWidget);
      final card2d = find.ancestor(of: multiLandy2DDesc, matching: find.byType(Card)).first;
      await tester.ensureVisible(card2d);
      await tester.pumpAndSettle();

      // Expand 2d
      final chevron2d = find.descendant(of: card2d, matching: find.byIcon(Icons.chevron_right));
      await tester.tap(chevron2d);
      await tester.pumpAndSettle();

      // Verify Transfer Lebensohl responses appear, NOT Jacoby acceptance
      final allTexts = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').toList();
      expect(allTexts.any((t) => t.contains('Negative double')), isTrue, reason: 'Transfer Lebensohl dbl appears');
      expect(allTexts.any((t) => t.contains('Transfer to Clubs')), isTrue, reason: 'Transfer Lebensohl 2NT appears');
      expect(allTexts.any((t) => t.contains('super-accepts transfer')), isFalse, reason: 'Must not mistake opponent 2D for Jacoby transfer');

      // Expand pass under 2d
      final passDesc = find.textContaining('Pass: weak hand without action');
      expect(passDesc, findsOneWidget);
      final cardPass = find.ancestor(of: passDesc, matching: find.byType(Card)).first;
      await tester.ensureVisible(cardPass);
      await tester.pumpAndSettle();

      final chevronPass = find.descendant(of: cardPass, matching: find.byIcon(Icons.chevron_right));
      await tester.tap(chevronPass);
      await tester.pumpAndSettle();

      // Verify Advancer pass or correct appears under pass
      final allTextsAfterPass = tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').toList();
      expect(allTextsAfterPass.any((t) => t.contains('pass or correct to 2S')), isTrue, reason: 'Advancer 2H pass or correct appears under 1NT-(2D)-Pass');
    });
  });
}
