import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/bidding_system.dart';
import 'services/system_yaml_parser.dart';
import 'services/system_library_resolver.dart';
import 'ui/bidding_tree_view.dart';
import 'ui/practice_quiz_view.dart';
import 'ui/yaml_editor_tab.dart';
import 'ui/bbs_converter_tab.dart';
import 'ui/definitions_tab.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BridgeBiddingApp());
}

class BridgeBiddingApp extends StatelessWidget {
  const BridgeBiddingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bridge Bidding System & Memory Practice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          primary: const Color(0xFF1B5E20),
          secondary: const Color(0xFFB71C1C),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Independent North-South and East-West systems
  BridgeSystem? _nsSystem;
  BridgeSystem? _ewSystem;
  String _nsProfileKey = 'gavin_2over1';
  String _ewProfileKey = 'uk_acol';

  // Active partnership view for Bidding Explorer, YAML Editor, and Definitions tabs
  String _activeViewPartnership = 'NS'; // 'NS' or 'EW'

  String? _selectedFragmentForTab;
  bool _isLoading = true;

  final Map<String, String> _systemAssetPaths = {
    'gavin_2over1': 'assets/core/systems/gavin_wolpert_2over1.yaml',
    '3_way_club': 'assets/core/systems/three_way_club_5cm.yaml',
    'us_2over1': 'assets/core/systems/us_standard_2over1.yaml',
    'uk_acol': 'assets/core/systems/uk_acol_4cm.yaml',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadSystems(nsKey: _nsProfileKey, ewKey: _ewProfileKey);
  }

  Future<void> _loadSystems({String? nsKey, String? ewKey}) async {
    setState(() => _isLoading = true);
    final targetNs = nsKey ?? _nsProfileKey;
    final targetEw = ewKey ?? _ewProfileKey;

    BridgeSystem? loadedNs;
    BridgeSystem? loadedEw;

    // Load North-South System
    try {
      final nsPath = _systemAssetPaths[targetNs] ?? 'assets/core/systems/gavin_wolpert_2over1.yaml';
      final nsContent = await rootBundle.loadString(nsPath);
      loadedNs = await SystemLibraryResolver.loadSystemWithLibraries(nsContent);
    } catch (e) {
      try {
        final sampleContent = await rootBundle.loadString('assets/samples/system_sample.yaml');
        loadedNs = SystemYamlParser.fromYaml(sampleContent);
      } catch (_) {}
    }

    // Load East-West System (if not pass_only)
    if (targetEw != 'pass_only') {
      try {
        final ewPath = _systemAssetPaths[targetEw] ?? 'assets/core/systems/uk_acol_4cm.yaml';
        final ewContent = await rootBundle.loadString(ewPath);
        loadedEw = await SystemLibraryResolver.loadSystemWithLibraries(ewContent);
      } catch (_) {
        loadedEw = null;
      }
    } else {
      loadedEw = null;
    }

    setState(() {
      _nsProfileKey = targetNs;
      _ewProfileKey = targetEw;
      if (loadedNs != null) _nsSystem = loadedNs;
      _ewSystem = loadedEw;
      _isLoading = false;
    });
  }

  void _swapPartnershipSystems() {
    if (_ewProfileKey == 'pass_only') {
      // If EW was pass_only, make NS pass_only? No, keep NS and make EW the old NS
      return;
    }
    final oldNs = _nsProfileKey;
    final oldEw = _ewProfileKey;
    _loadSystems(nsKey: oldEw, ewKey: oldNs);
  }

  List<BiddingNode>? _practiceAuctionPath;

  void _navigateToPractice(List<BiddingNode> path) {
    setState(() {
      _practiceAuctionPath = path;
      _tabController.animateTo(1); // Index 1 is Practice Quiz
    });
  }

  void _navigateToFragment(String fragmentName) {
    setState(() {
      _selectedFragmentForTab = fragmentName;
      _tabController.animateTo(4); // Index 4 is Definitions & Fragments
    });
  }

  void _showSystemSwitcherDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.swap_horiz, color: Color(0xFF1B5E20)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Select Bidding Systems', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Configure different systems for North-South and East-West', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_calls, color: Color(0xFF1B5E20)),
                      tooltip: 'Swap NS ⇄ EW Systems',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _swapPartnershipSystems();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  labelColor: const Color(0xFF1B5E20),
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: const Color(0xFF1B5E20),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B5E20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('NS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          const Text('North-South (We)'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D47A1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('EW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          const Text('East-West (They)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              height: 480,
              child: TabBarView(
                children: [
                  // Tab 1: North-South
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSystemCard(
                          partnership: 'NS',
                          keyId: 'gavin_2over1',
                          title: 'Gavin Wolpert Master Series (2/1 GF)',
                          badge: 'IntoBridge Official',
                          description: 'Gavin Wolpert expert 2/1: 14.5-17 NT with 4-Way Transfers & Puppet Stayman, Kokish 2♣, Walsh minors, Mixed Raises, Reversed Bart, and Transfer Lebensohl.',
                          icon: Icons.star,
                          iconColor: Colors.amber.shade800,
                        ),
                        const SizedBox(height: 10),
                        _buildSystemCard(
                          partnership: 'NS',
                          keyId: 'us_2over1',
                          title: '5-Card Majors & 2/1 Game Forcing',
                          badge: 'Standard 5CM',
                          description: 'Modern standard: 1♥ and 1♠ require 5+ cards. 2/1 is game forcing, with 1NT semi-forcing, Jacoby 2NT, inverted minors, and 15-17 Strong NT.',
                          icon: Icons.favorite,
                          iconColor: Colors.red.shade700,
                        ),
                        const SizedBox(height: 10),
                        _buildSystemCard(
                          partnership: 'NS',
                          keyId: '3_way_club',
                          title: '3-Way Club (5-Card Majors)',
                          badge: 'Walrus Transfers',
                          description: 'Flexible 1♣: 11-14 weak NT, 11+ natural clubs, or 23+ GF. Features transfer responses [1d-1h] with full inline continuation routing.',
                          icon: Icons.filter_3,
                          iconColor: Colors.green.shade800,
                        ),
                        const SizedBox(height: 10),
                        _buildSystemCard(
                          partnership: 'NS',
                          keyId: 'uk_acol',
                          title: 'UK Acol (4-Card Majors)',
                          badge: 'Traditional 4CM',
                          description: 'Classic British system with 4-card major openings and Weak NT (12-14 HCP).',
                          icon: Icons.shield,
                          iconColor: Colors.blue.shade700,
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: East-West
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSystemCard(
                          partnership: 'EW',
                          keyId: 'pass_only',
                          title: 'Standard Opposition (Auto-Pass)',
                          badge: 'Clean Practice',
                          description: 'East and West pass automatically on every turn. Ideal for pure uncontested partnership practice of North-South conventions.',
                          icon: Icons.pan_tool_outlined,
                          iconColor: Colors.blueGrey,
                        ),
                        const SizedBox(height: 10),
                        _buildSystemCard(
                          partnership: 'EW',
                          keyId: 'uk_acol',
                          title: 'UK Acol (4-Card Majors)',
                          badge: 'Traditional 4CM',
                          description: 'Classic British system with 4-card major openings, aggressive light overcalls, and Weak NT (12-14 HCP).',
                          icon: Icons.shield,
                          iconColor: Colors.blue.shade700,
                        ),
                        const SizedBox(height: 10),
                        _buildSystemCard(
                          partnership: 'EW',
                          keyId: 'us_2over1',
                          title: '5-Card Majors & 2/1 Game Forcing',
                          badge: 'Standard 5CM',
                          description: 'Modern standard: 1♥ and 1♠ require 5+ cards. 2/1 is game forcing, with 1NT semi-forcing, Jacoby 2NT, inverted minors, and 15-17 Strong NT.',
                          icon: Icons.favorite,
                          iconColor: Colors.red.shade700,
                        ),
                        const SizedBox(height: 10),
                        _buildSystemCard(
                          partnership: 'EW',
                          keyId: 'gavin_2over1',
                          title: 'Gavin Wolpert Master Series (2/1 GF)',
                          badge: 'IntoBridge Official',
                          description: 'Gavin Wolpert expert 2/1: 14.5-17 NT with 4-Way Transfers & Puppet Stayman, Kokish 2♣, Walsh minors, and competitive Lebensohl.',
                          icon: Icons.star,
                          iconColor: Colors.amber.shade800,
                        ),
                        const SizedBox(height: 10),
                        _buildSystemCard(
                          partnership: 'EW',
                          keyId: '3_way_club',
                          title: '3-Way Club (5-Card Majors)',
                          badge: 'Walrus Transfers',
                          description: 'Flexible 1♣: 11-14 weak NT, 11+ natural clubs, or 23+ GF. Features transfer responses [1d-1h] with full inline continuation routing.',
                          icon: Icons.filter_3,
                          iconColor: Colors.green.shade800,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Swap NS ⇄ EW'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _swapPartnershipSystems();
                },
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSystemCard({
    required String partnership, // 'NS' or 'EW'
    required String keyId,
    required String title,
    required String badge,
    required String description,
    required IconData icon,
    required Color iconColor,
  }) {
    final isSelected = partnership == 'NS'
        ? _nsProfileKey == keyId
        : _ewProfileKey == keyId;

    final primaryThemeColor = partnership == 'NS' ? const Color(0xFF1B5E20) : const Color(0xFF0D47A1);

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        if (partnership == 'NS') {
          _loadSystems(nsKey: keyId);
        } else {
          _loadSystems(ewKey: keyId);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? primaryThemeColor.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryThemeColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: isSelected ? primaryThemeColor : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryThemeColor : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isSelected ? 'ACTIVE' : badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isSelected)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryThemeColor,
                      side: BorderSide(color: primaryThemeColor),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check, size: 14),
                    label: Text('Set as $partnership System', style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      Navigator.pop(context);
                      if (partnership == 'NS') {
                        _loadSystems(nsKey: keyId);
                      } else {
                        _loadSystems(ewKey: keyId);
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _nsSystem == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final nsSystem = _nsSystem!;
    final ewSystem = _ewSystem;
    final activeViewSystem = _activeViewPartnership == 'NS' ? nsSystem : (ewSystem ?? nsSystem);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F3814),
        foregroundColor: Colors.white,
        elevation: 2,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('♠ ♥ ♦ ♣', style: TextStyle(fontSize: 16, letterSpacing: 2)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('NS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      nsSystem.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text('EW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      ewSystem?.name ?? 'Standard Opposition (Auto-Pass)',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade300),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Quick NS System Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: ['gavin_2over1', 'us_2over1', '3_way_club', 'uk_acol'].contains(_nsProfileKey)
                    ? _nsProfileKey
                    : 'gavin_2over1',
                dropdownColor: const Color(0xFF1E3A20),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'gavin_2over1', child: Text('NS: Gavin 2/1 GF')),
                  DropdownMenuItem(value: 'us_2over1', child: Text('NS: 5CM & 2/1 GF')),
                  DropdownMenuItem(value: '3_way_club', child: Text('NS: 3-Way Club')),
                  DropdownMenuItem(value: 'uk_acol', child: Text('NS: UK Acol 4CM')),
                ],
                onChanged: (val) {
                  if (val != null) _loadSystems(nsKey: val);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Quick EW System Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: ['pass_only', 'uk_acol', 'us_2over1', 'gavin_2over1', '3_way_club'].contains(_ewProfileKey)
                    ? _ewProfileKey
                    : 'uk_acol',
                dropdownColor: const Color(0xFF1E3A20),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: 'pass_only', child: Text('EW: Auto-Pass')),
                  DropdownMenuItem(value: 'uk_acol', child: Text('EW: UK Acol 4CM')),
                  DropdownMenuItem(value: 'us_2over1', child: Text('EW: 5CM & 2/1 GF')),
                  DropdownMenuItem(value: 'gavin_2over1', child: Text('EW: Gavin 2/1 GF')),
                  DropdownMenuItem(value: '3_way_club', child: Text('EW: 3-Way Club')),
                ],
                onChanged: (val) {
                  if (val != null) _loadSystems(ewKey: val);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Switch System Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent.shade700,
              foregroundColor: Colors.black87,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Switch Systems', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            onPressed: _showSystemSwitcherDialog,
          ),
          const SizedBox(width: 8),

          // Rules count badge
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.rule, size: 15, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  '${nsSystem.totalNodesCount} Rules',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.amberAccent,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amberAccent,
          indicatorWeight: 3,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_tree_outlined), text: 'Bidding Explorer'),
            Tab(icon: Icon(Icons.psychology), text: 'Test My Memory (Quiz)'),
            Tab(icon: Icon(Icons.edit_note), text: 'YAML Editor'),
            Tab(icon: Icon(Icons.transform), text: 'BBS Converter'),
            Tab(icon: Icon(Icons.menu_book), text: 'Definitions & Libraries'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Perspective toggle for tabs other than Quiz (Explorer, YAML, Definitions)
          AnimatedBuilder(
            animation: _tabController,
            builder: (ctx, _) {
              final isQuiz = _tabController.index == 1 || _tabController.index == 3;
              if (isQuiz || ewSystem == null) return const SizedBox.shrink();

              return Container(
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Text(
                      'Viewing System Tree for: ',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('North-South (${nsSystem.name})'),
                      selected: _activeViewPartnership == 'NS',
                      selectedColor: Colors.green.shade800,
                      labelStyle: TextStyle(
                        color: _activeViewPartnership == 'NS' ? Colors.white : Colors.grey.shade400,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (sel) {
                        if (sel) setState(() => _activeViewPartnership = 'NS');
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('East-West (${ewSystem.name})'),
                      selected: _activeViewPartnership == 'EW',
                      selectedColor: Colors.blue.shade800,
                      labelStyle: TextStyle(
                        color: _activeViewPartnership == 'EW' ? Colors.white : Colors.grey.shade400,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (sel) {
                        if (sel) setState(() => _activeViewPartnership = 'EW');
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          // Main Tab Contents
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 0: Bidding Explorer
                BiddingTreeView(
                  key: ValueKey('${activeViewSystem.name}_$_activeViewPartnership'),
                  system: activeViewSystem,
                  onNavigateToFragment: _navigateToFragment,
                  onPracticeFromNode: _navigateToPractice,
                ),

                // Tab 1: Memory Quiz & Practice
                PracticeQuizView(
                  key: ValueKey('${_nsProfileKey}_${_ewProfileKey}_${_practiceAuctionPath?.map((n) => n.call).join('>')}'),
                  system: nsSystem,
                  ewSystem: ewSystem,
                  initialAuctionPath: _practiceAuctionPath,
                ),

                // Tab 2: YAML Editor
                YamlEditorTab(
                  key: ValueKey('${activeViewSystem.name}_$_activeViewPartnership'),
                  system: activeViewSystem,
                  onSystemUpdated: (updated) {
                    setState(() {
                      if (_activeViewPartnership == 'NS') {
                        _nsSystem = updated;
                      } else {
                        _ewSystem = updated;
                      }
                    });
                  },
                ),

                // Tab 3: BBS Converter
                BbsConverterTab(
                  onSystemImported: (imported) {
                    setState(() {
                      if (_activeViewPartnership == 'NS') {
                        _nsSystem = imported;
                      } else {
                        _ewSystem = imported;
                      }
                    });
                  },
                ),

                // Tab 4: Definitions & Fragments
                DefinitionsTab(
                  key: ValueKey('${activeViewSystem.name}_$_activeViewPartnership'),
                  system: activeViewSystem,
                  selectedFragment: _selectedFragmentForTab,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
