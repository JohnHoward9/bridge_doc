import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/services/system_yaml_parser.dart';
import 'package:bridge_bidding_system/ui/bidding_tree_view.dart';
import 'package:bridge_bidding_system/ui/practice_quiz_view.dart';

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

  group('Explorer to Test My Memory Integration Tests', () {
    late BridgeSystem system;

    setUpAll(() async {
      system = await loadGavinSystem();
    });

    testWidgets('BiddingTreeView has Practice button on tree node cards and triggers callback with correct path', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      List<BiddingNode>? practicePath;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingTreeView(
              system: system,
              onPracticeFromNode: (path) {
                practicePath = path;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the direct practice button on tree node cards
      final practiceButton = find.widgetWithText(InkWell, 'Practice');
      expect(practiceButton, findsWidgets);

      // Tap the practice button on the first available node
      await tester.tap(practiceButton.first);
      await tester.pumpAndSettle();

      expect(practicePath, isNotNull);
      expect(practicePath!.isNotEmpty, isTrue);
    });

    testWidgets('BiddingTreeView Inspector panel has prominent Practice Against This Bid button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      List<BiddingNode>? practicePath;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BiddingTreeView(
              system: system,
              onPracticeFromNode: (path) {
                practicePath = path;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click on 1nt card to select it in the inspector
      final card1nt = find.ancestor(of: find.text('1nt'), matching: find.byType(Card)).first;
      await tester.tap(card1nt);
      await tester.pumpAndSettle();

      // Inspector panel should have 'Practice Against This Bid 🎯'
      final inspectorPracticeBtn = find.text('Practice Against This Bid 🎯');
      expect(inspectorPracticeBtn, findsOneWidget);

      await tester.tap(inspectorPracticeBtn);
      await tester.pumpAndSettle();

      expect(practicePath, isNotNull);
      expect(practicePath!.last.call.toLowerCase(), '1nt');
    });

    testWidgets('PracticeQuizView loads initialAuctionPath [1nt] and sets up turn for South', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final node1nt = system.openingBids.firstWhere((b) => b.call.toLowerCase() == '1nt');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeQuizView(
              system: system,
              initialAuctionPath: [node1nt],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify auction history has North 1NT and East Pass
      expect(find.text('1NT'), findsWidgets);
      expect(find.text('Pass'), findsWidgets);

      // 2. Active turn indicator shows South's turn
      expect(find.text('? (Your Turn)'), findsOneWidget);

      // 3. Explorer practice banner is visible
      expect(find.textContaining('Practicing from Bidding Explorer: N: 1NT → E: Pass (South to bid)'), findsOneWidget);

      // 4. Panel 1 North hand reflects 15-17 balanced deal
      // Panel 3 bidding box is ready for South
      expect(find.text('Panel 3: Bidding Box'), findsOneWidget);
    });

    testWidgets('PracticeQuizView loads multi-step path [1c, 1d, 1nt] and sets up South checkback', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final pathNodes = [
        BiddingNode(call: '1c', desc: '1 Club opening'),
        BiddingNode(call: '1d', desc: '1 Diamond response'),
        BiddingNode(call: '1nt', desc: '1NT rebid'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeQuizView(
              system: system,
              initialAuctionPath: pathNodes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sequence is loaded with automatic East/West passes
      // N: 1c, E: Pass, S: 1d, W: Pass, N: 1nt, E: Pass -> South to bid
      expect(find.text('? (Your Turn)'), findsOneWidget);
      expect(find.textContaining('Practicing from Bidding Explorer: N: 1♣ → E: Pass → S: 1♦ → W: Pass → N: 1NT → E: Pass (South to bid)'), findsOneWidget);
    });

    testWidgets('Redeal keeps locked setup auction and Clear resets it', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final node1nt = system.openingBids.firstWhere((b) => b.call.toLowerCase() == '1nt');
      bool clearCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeQuizView(
              system: system,
              initialAuctionPath: [node1nt],
              onClearPracticeAuction: () {
                clearCalled = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Redeal in Panel 1
      final redealBtn = find.text('Redeal');
      expect(redealBtn, findsOneWidget);
      await tester.tap(redealBtn);
      await tester.pumpAndSettle();

      // Sequence should still be locked to 1NT!
      expect(find.text('? (Your Turn)'), findsOneWidget);
      expect(find.textContaining('Practicing from Bidding Explorer: N: 1NT → E: Pass (South to bid)'), findsOneWidget);

      // Now tap Clear
      final clearBtn = find.text('Clear');
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(clearCalled, isTrue);
      // Banner should be gone
      expect(find.textContaining('Practicing from Bidding Explorer:'), findsNothing);
    });
  });
}
