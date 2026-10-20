import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/services/system_library_resolver.dart';
import 'package:bridge_bidding_system/engine/bidding_graph_compiler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BridgeSystem> loadSystemProfile(String relativePath) async {
    final file = File(relativePath);
    if (!file.existsSync()) {
      throw Exception('System file not found at: ${file.absolute.path}');
    }
    final yamlStr = await file.readAsString();

    return await SystemLibraryResolver.loadSystemWithLibraries(
      yamlStr,
      fileLoader: (path) async {
        final f = File(path);
        if (f.existsSync()) {
          return await f.readAsString();
        }
        return '';
      },
    );
  }

  group('Ref Metadata Inheritance Tests', () {
    test('Gavin Wolpert 2/1: Opening bids inherit desc, rule, and variables via ref only', () async {
      final system = await loadSystemProfile('assets/core/systems/gavin_wolpert_2over1.yaml');

      // 1. Check Pass -> 1H (Drury)
      final passNode = system.openingBids.firstWhere((b) => b.call == 'pass');
      final pass1hRaw = passNode.bids.firstWhere((b) => b.call == '1h');
      expect(pass1hRaw.desc, isEmpty, reason: 'Caller must not define desc');
      expect(pass1hRaw.rule, isNull, reason: 'Caller must not define rule');
      expect(pass1hRaw.ref, equals('fDrury'));

      final pass1hResolved = pass1hRaw.withResolvedFragmentMetadata(system.fragments);
      expect(pass1hResolved.desc, contains('Hearts'));
      expect(pass1hResolved.rule, contains('5+h'));
      expect(pass1hResolved.variables['M'], equals('h'));
      expect(pass1hResolved.variables['OM'], equals('s'));
      expect(pass1hResolved.bids, isNotEmpty, reason: 'Must inherit Drury responses');

      // 2. Check Pass -> 1S (Drury)
      final pass1sRaw = passNode.bids.firstWhere((b) => b.call == '1s');
      expect(pass1sRaw.desc, isEmpty, reason: 'Caller must not define desc');
      expect(pass1sRaw.rule, isNull, reason: 'Caller must not define rule');
      expect(pass1sRaw.ref, equals('fDrury'));

      final pass1sResolved = pass1sRaw.withResolvedFragmentMetadata(system.fragments);
      expect(pass1sResolved.desc, contains('Spades'));
      expect(pass1sResolved.rule, contains('5+s'));
      expect(pass1sResolved.variables['M'], equals('s'));
      expect(pass1sResolved.variables['OM'], equals('h'));
      expect(pass1sResolved.bids, isNotEmpty, reason: 'Must inherit Drury responses');

      // 3. Check 1H opening bid (GavinHeartOpening)
      final open1hRaw = system.openingBids.firstWhere((b) => b.call == '1h');
      expect(open1hRaw.desc, isEmpty, reason: 'Caller must not define desc');
      expect(open1hRaw.rule, isNull, reason: 'Caller must not define rule');
      expect(open1hRaw.ref, equals('GavinHeartOpening'));

      final open1hResolved = open1hRaw.withResolvedFragmentMetadata(system.fragments);
      expect(open1hResolved.desc, contains('Gavin 5+ Hearts'));
      expect(open1hResolved.rule, contains('12-21hcp'));
      expect(open1hResolved.variables['M'], equals('h'));

      // 4. Check 1S opening bid (GavinSpadeOpening)
      final open1sRaw = system.openingBids.firstWhere((b) => b.call == '1s');
      expect(open1sRaw.desc, isEmpty, reason: 'Caller must not define desc');
      expect(open1sRaw.rule, isNull, reason: 'Caller must not define rule');
      expect(open1sRaw.ref, equals('GavinSpadeOpening'));

      final open1sResolved = open1sRaw.withResolvedFragmentMetadata(system.fragments);
      expect(open1sResolved.desc, contains('Gavin 5+ Spades'));
      expect(open1sResolved.rule, contains('12-21hcp'));
      expect(open1sResolved.variables['M'], equals('s'));
    });

    test('Gavin Wolpert 2/1: Opposition opening bids inherit desc, rule, and variables via ref only', () async {
      final system = await loadSystemProfile('assets/core/systems/gavin_wolpert_2over1.yaml');

      // 1. (2c_majors)
      final opp2cRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(2c_majors)');
      expect(opp2cRaw.desc, isEmpty, reason: 'Caller must not define desc');
      expect(opp2cRaw.rule, isNull, reason: 'Caller must not define rule');
      expect(opp2cRaw.ref, equals('fTwoClubMajorsDefense'));

      final opp2cResolved = opp2cRaw.withResolvedFragmentMetadata(system.fragments);
      expect(opp2cResolved.desc, equals('Opposition 2C Opening (Both Majors, 8-13 HCP)'));
      expect(opp2cResolved.rule, equals('8-13hcp 4+h 4+s'));
      expect(opp2cResolved.bids, isNotEmpty);

      // 2. (2h) Weak Two
      final opp2hRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(2h)');
      expect(opp2hRaw.desc, isEmpty);
      expect(opp2hRaw.rule, isNull);
      expect(opp2hRaw.ref, equals('fWeakTwoDefense'));

      final opp2hResolved = opp2hRaw.withResolvedFragmentMetadata(system.fragments);
      expect(opp2hResolved.desc, contains('Hearts'));
      expect(opp2hResolved.rule, contains('6h'));
      expect(opp2hResolved.variables['os'], equals('h'));
      expect(opp2hResolved.variables['OM'], equals('s'));

      // 3. (2s) Weak Two
      final opp2sRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(2s)');
      final opp2sResolved = opp2sRaw.withResolvedFragmentMetadata(system.fragments);
      expect(opp2sResolved.desc, contains('Spades'));
      expect(opp2sResolved.rule, contains('6s'));
      expect(opp2sResolved.variables['os'], equals('s'));
      expect(opp2sResolved.variables['OM'], equals('h'));

      // 4. (1c) Minor Defense
      final opp1cRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(1c)');
      final opp1cResolved = opp1cRaw.withResolvedFragmentMetadata(system.fragments);
      expect(opp1cResolved.desc, contains('Clubs'));
      expect(opp1cResolved.rule, contains('3+c'));
      expect(opp1cResolved.variables['om'], equals('c'));

      // 5. (1h) Major Defense
      final opp1hRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(1h)');
      final opp1hResolved = opp1hRaw.withResolvedFragmentMetadata(system.fragments);
      expect(opp1hResolved.desc, contains('Hearts'));
      expect(opp1hResolved.rule, contains('5+h'));
      expect(opp1hResolved.variables['M'], equals('h'));
      expect(opp1hResolved.variables['OM'], equals('s'));

      // 6. (2d_ekren)
      final oppEkrenRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(2d_ekren)');
      final oppEkrenResolved = oppEkrenRaw.withResolvedFragmentMetadata(system.fragments);
      expect(oppEkrenResolved.desc, contains('Ekren'));
      expect(oppEkrenResolved.rule, contains('5-10hcp 4+h 4+s'));

      // 7. (2d_multi)
      final oppMultiRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(2d_multi)');
      final oppMultiResolved = oppMultiRaw.withResolvedFragmentMetadata(system.fragments);
      expect(oppMultiResolved.desc, contains('Multi'));
      expect(oppMultiResolved.rule, contains('5-10hcp'));

      // 8. (1c_strong)
      final oppStrongCRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(1c_strong)');
      final oppStrongCResolved = oppStrongCRaw.withResolvedFragmentMetadata(system.fragments);
      expect(oppStrongCResolved.desc, contains('Strong / Precision'));
      expect(oppStrongCResolved.rule, equals('16+hcp'));

      // 9. (1nt) Strong NT
      final opp1ntRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(1nt)');
      final opp1ntResolved = opp1ntRaw.withResolvedFragmentMetadata(system.fragments);
      expect(opp1ntResolved.desc, contains('Strong NT'));
      expect(opp1ntResolved.rule, equals('15-17hcp'));

      // 10. (50%Weak.1nt) Weak NT
      final oppWeak1ntRaw = system.oppositionOpeningBids.firstWhere((b) => b.call == '(50%Weak.1nt)');
      final oppWeak1ntResolved = oppWeak1ntRaw.withResolvedFragmentMetadata(system.fragments);
      expect(oppWeak1ntResolved.desc, contains('Weak NT'));
      expect(oppWeak1ntResolved.rule, equals('12-14hcp'));
    });

    test('Kokish Kraft Weak NT: Opening bids inherit desc and rule via ref only', () async {
      final system = await loadSystemProfile('assets/core/systems/kokish_kraft_weak_nt.yaml');

      // Check 1C opening bid
      final open1cRaw = system.openingBids.firstWhere((b) => b.call == '1c');
      expect(open1cRaw.desc, isEmpty, reason: 'Caller must not define desc');
      expect(open1cRaw.rule, isNull, reason: 'Caller must not define rule');
      final open1cResolved = open1cRaw.withResolvedFragmentMetadata(system.fragments);
      expect(open1cResolved.desc, contains('1C: 15-20 HCP'));
      expect(open1cResolved.rule, contains('15-20hcp'));

      // Check 1D opening bid
      final open1dRaw = system.openingBids.firstWhere((b) => b.call == '1d');
      expect(open1dRaw.desc, isEmpty);
      expect(open1dRaw.rule, isNull);
      final open1dResolved = open1dRaw.withResolvedFragmentMetadata(system.fragments);
      expect(open1dResolved.desc, contains('1D: 15-20 HCP'));
      expect(open1dResolved.rule, contains('15-20hcp'));

      // Check 1NT opening bid
      final open1ntRaw = system.openingBids.firstWhere((b) => b.call == '1nt');
      final open1ntResolved = open1ntRaw.withResolvedFragmentMetadata(system.fragments);
      expect(open1ntResolved.desc, contains('Weak Notrump'));
      expect(open1ntResolved.rule, contains('11-14hcp'));

      // Check 3NT Kantar
      final open3ntRaw = system.openingBids.firstWhere((b) => b.call == '3nt');
      final open3ntResolved = open3ntRaw.withResolvedFragmentMetadata(system.fragments);
      expect(open3ntResolved.desc, contains('Kantar 3NT'));
      expect(open3ntResolved.rule, contains('7+h, p#1 7+s'));
    });

    test('BiddingGraphCompiler compiles successfully with caller ref-only metadata inheritance', () async {
      final gavinSystem = await loadSystemProfile('assets/core/systems/gavin_wolpert_2over1.yaml');
      final gavinCompiler = BiddingGraphCompiler(system: gavinSystem);
      final gavinGraph = gavinCompiler.compile();

      expect(gavinGraph.stateCount, greaterThan(20));
      expect(gavinGraph.rootState.candidateNodes.any((n) => n.call == '1h'), isTrue);
      expect(gavinGraph.rootState.candidateNodes.any((n) => n.call == '1s'), isTrue);
      expect(gavinGraph.rootState.candidateNodes.any((n) => n.call == '(2c_majors)'), isTrue);

      final kokishSystem = await loadSystemProfile('assets/core/systems/kokish_kraft_weak_nt.yaml');
      final kokishCompiler = BiddingGraphCompiler(system: kokishSystem);
      final kokishGraph = kokishCompiler.compile();

      expect(kokishGraph.stateCount, greaterThan(20));
      expect(kokishGraph.rootState.candidateNodes.any((n) => n.call == '1c'), isTrue);
      expect(kokishGraph.rootState.candidateNodes.any((n) => n.call == '1nt'), isTrue);
    });
  });
}
