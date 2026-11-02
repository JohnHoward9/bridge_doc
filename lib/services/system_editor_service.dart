import '../models/bidding_system.dart';

/// Helper service that provides immutable query and mutation methods for [BridgeSystem].
/// Enables visual editing of nodes, continuations, and convention wiring without exposing YAML.
class SystemEditorService {
  /// Normalizes a call string for comparison (lowercase, trimmed, strip brackets).
  static String normalizeCall(String call) {
    return call
        .trim()
        .toLowerCase()
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('♣', 'c')
        .replaceAll('♦', 'd')
        .replaceAll('♥', 'h')
        .replaceAll('♠', 's');
  }

  /// Traverses the system following [callPath] (e.g. `['1nt', '2d', '2h']`).
  /// Follows inline bids as well as fragment references (`ref`).
  /// Returns the chain of [BiddingNode]s found.
  static List<BiddingNode> resolvePath(BridgeSystem system, List<String> callPath) {
    if (callPath.isEmpty) return [];

    final resolved = <BiddingNode>[];
    List<BiddingNode> currentPool = [
      ...system.openingBids,
      ...system.oppositionOpeningBids,
    ];

    for (int i = 0; i < callPath.length; i++) {
      final targetCall = normalizeCall(callPath[i]);
      final match = currentPool.cast<BiddingNode?>().firstWhere(
            (n) => n != null && normalizeCall(n.call) == targetCall,
            orElse: () => null,
          );

      if (match == null) {
        break;
      }

      resolved.add(match);

      // Determine next child pool
      if (match.ref != null && system.fragments.containsKey(match.ref)) {
        currentPool = system.fragments[match.ref]!.bids;
      } else {
        currentPool = match.bids;
      }
    }

    return resolved;
  }

  /// Returns all available child continuations for a given path.
  static List<BiddingNode> getContinuationsForPath(BridgeSystem system, List<String> callPath) {
    if (callPath.isEmpty) {
      return [...system.openingBids];
    }
    final pathNodes = resolvePath(system, callPath);
    if (pathNodes.length != callPath.length) return [];

    final lastNode = pathNodes.last;
    if (lastNode.ref != null && system.fragments.containsKey(lastNode.ref)) {
      return system.fragments[lastNode.ref]!.bids;
    }
    return lastNode.bids;
  }

  /// Updates the node at [callPath] with [updatedNode].
  /// Preserves the node's existing children if [updatedNode.bids] is empty and no new fragment is referenced.
  static BridgeSystem updateNodeAtPath(
    BridgeSystem system,
    List<String> callPath,
    BiddingNode updatedNode,
  ) {
    if (callPath.isEmpty) return system;

    final normPath = callPath.map(normalizeCall).toList();

    // 1. Check if the target is in openingBids
    final newOpenings = _updateInNodeList(
      system.openingBids,
      system.fragments,
      normPath,
      0,
      updatedNode,
    );

    // 2. Check if the target is in oppositionOpeningBids
    final newOppOpenings = _updateInNodeList(
      system.oppositionOpeningBids,
      system.fragments,
      normPath,
      0,
      updatedNode,
    );

    // 3. Also check if root target might have updated fragment contents
    final updatedFragments = Map<String, Fragment>.from(system.fragments);
    for (final entry in system.fragments.entries) {
      final fragBids = entry.value.bids;
      final updatedFragBids = _updateInNodeList(
        fragBids,
        system.fragments,
        normPath,
        0,
        updatedNode,
      );
      if (!_areNodeListsIdentical(fragBids, updatedFragBids)) {
        updatedFragments[entry.key] = Fragment(
          name: entry.value.name,
          desc: entry.value.desc,
          rule: entry.value.rule,
          priority: entry.value.priority,
          aliases: entry.value.aliases,
          bids: updatedFragBids,
        );
      }
    }

    return BridgeSystem(
      name: system.name,
      player: system.player,
      partner: system.partner,
      definitions: Map.from(system.definitions),
      openingBids: newOpenings,
      oppositionOpeningBids: newOppOpenings,
      fragments: updatedFragments,
    );
  }

  /// Adds a child response to the node at [callPath].
  static BridgeSystem addChildNodeAtPath(
    BridgeSystem system,
    List<String> callPath,
    BiddingNode newChild,
  ) {
    if (callPath.isEmpty) {
      // Add as root opening bid
      return BridgeSystem(
        name: system.name,
        player: system.player,
        partner: system.partner,
        definitions: Map.from(system.definitions),
        openingBids: [...system.openingBids, newChild],
        oppositionOpeningBids: system.oppositionOpeningBids,
        fragments: system.fragments,
      );
    }

    final pathNodes = resolvePath(system, callPath);
    if (pathNodes.length != callPath.length) return system;

    final targetNode = pathNodes.last;

    // If target references a fragment, add to that fragment's bids
    if (targetNode.ref != null && system.fragments.containsKey(targetNode.ref)) {
      final frag = system.fragments[targetNode.ref]!;
      final updatedFrag = Fragment(
        name: frag.name,
        desc: frag.desc,
        rule: frag.rule,
        priority: frag.priority,
        aliases: frag.aliases,
        bids: [...frag.bids, newChild],
      );
      final newFragments = Map<String, Fragment>.from(system.fragments);
      newFragments[targetNode.ref!] = updatedFrag;

      return BridgeSystem(
        name: system.name,
        player: system.player,
        partner: system.partner,
        definitions: Map.from(system.definitions),
        openingBids: system.openingBids,
        oppositionOpeningBids: system.oppositionOpeningBids,
        fragments: newFragments,
      );
    }

    // Otherwise add to inline bids
    final updatedTarget = BiddingNode(
      call: targetNode.call,
      desc: targetNode.desc,
      rule: targetNode.rule,
      priority: targetNode.priority,
      ref: targetNode.ref,
      condition: targetNode.condition,
      variables: targetNode.variables,
      bids: [...targetNode.bids, newChild],
    );

    return updateNodeAtPath(system, callPath, updatedTarget);
  }

  /// Deletes the node at [callPath].
  static BridgeSystem deleteNodeAtPath(
    BridgeSystem system,
    List<String> callPath,
  ) {
    if (callPath.isEmpty) return system;

    final normPath = callPath.map(normalizeCall).toList();

    final newOpenings = _deleteInNodeList(system.openingBids, system.fragments, normPath, 0);
    final newOppOpenings = _deleteInNodeList(system.oppositionOpeningBids, system.fragments, normPath, 0);

    final updatedFragments = Map<String, Fragment>.from(system.fragments);
    for (final entry in system.fragments.entries) {
      final fragBids = entry.value.bids;
      final updatedFragBids = _deleteInNodeList(fragBids, system.fragments, normPath, 0);
      if (!_areNodeListsIdentical(fragBids, updatedFragBids)) {
        updatedFragments[entry.key] = Fragment(
          name: entry.value.name,
          desc: entry.value.desc,
          rule: entry.value.rule,
          priority: entry.value.priority,
          aliases: entry.value.aliases,
          bids: updatedFragBids,
        );
      }
    }

    return BridgeSystem(
      name: system.name,
      player: system.player,
      partner: system.partner,
      definitions: Map.from(system.definitions),
      openingBids: newOpenings,
      oppositionOpeningBids: newOppOpenings,
      fragments: updatedFragments,
    );
  }

  // --- Recursive Tree Updating Helpers ---

  static List<BiddingNode> _updateInNodeList(
    List<BiddingNode> list,
    Map<String, Fragment> fragments,
    List<String> path,
    int index,
    BiddingNode replacement,
  ) {
    if (index >= path.length) return list;
    final currentTarget = path[index];

    return list.map((node) {
      if (normalizeCall(node.call) != currentTarget) {
        return node;
      }

      // If this is the final element in path, replace it!
      if (index == path.length - 1) {
        return BiddingNode(
          call: replacement.call,
          desc: replacement.desc,
          rule: replacement.rule,
          priority: replacement.priority,
          ref: replacement.ref,
          condition: replacement.condition,
          variables: replacement.variables,
          bids: replacement.bids.isNotEmpty ? replacement.bids : node.bids,
        );
      }

      // Otherwise recurse down children
      final newChildren = _updateInNodeList(
        node.bids,
        fragments,
        path,
        index + 1,
        replacement,
      );

      return BiddingNode(
        call: node.call,
        desc: node.desc,
        rule: node.rule,
        priority: node.priority,
        ref: node.ref,
        condition: node.condition,
        variables: node.variables,
        bids: newChildren,
      );
    }).toList();
  }

  static List<BiddingNode> _deleteInNodeList(
    List<BiddingNode> list,
    Map<String, Fragment> fragments,
    List<String> path,
    int index,
  ) {
    if (index >= path.length) return list;
    final currentTarget = path[index];

    final result = <BiddingNode>[];
    for (final node in list) {
      if (normalizeCall(node.call) != currentTarget) {
        result.add(node);
        continue;
      }

      // If at end of path, omit this node (delete)
      if (index == path.length - 1) {
        continue;
      }

      // Recurse down children
      final newChildren = _deleteInNodeList(node.bids, fragments, path, index + 1);
      result.add(BiddingNode(
        call: node.call,
        desc: node.desc,
        rule: node.rule,
        priority: node.priority,
        ref: node.ref,
        condition: node.condition,
        variables: node.variables,
        bids: newChildren,
      ));
    }
    return result;
  }

  static bool _areNodeListsIdentical(List<BiddingNode> a, List<BiddingNode> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // --- Macro Blueprint & Convention Queries & Wiring ---

  /// Reads the 1NT opening HCP range from the system definitions or 1NT node.
  static (int minHcp, int maxHcp) get1NTRange(BridgeSystem system) {
    // Check definitions: e.g. "nt_open": "15-17" or "15-17hcp"
    for (final entry in system.definitions.entries) {
      if (entry.key.toLowerCase().contains('nt') || entry.value.contains('hcp')) {
        final m = RegExp(r'(\d+)\s*[-–]\s*(\d+)').firstMatch(entry.value);
        if (m != null) {
          return (int.parse(m.group(1)!), int.parse(m.group(2)!));
        }
      }
    }

    // Check opening 1NT node
    for (final node in system.openingBids) {
      if (normalizeCall(node.call) == '1nt' && node.rule != null) {
        final m = RegExp(r'(\d+)\s*[-–]\s*(\d+)').firstMatch(node.rule!);
        if (m != null) {
          return (int.parse(m.group(1)!), int.parse(m.group(2)!));
        }
      }
    }

    return (15, 17); // Standard default
  }

  /// Sets the 1NT opening HCP range across definitions and opening nodes.
  static BridgeSystem set1NTRange(BridgeSystem system, int minHcp, int maxHcp) {
    final newDefs = Map<String, String>.from(system.definitions);
    newDefs['strong_nt'] = '$minHcp-$maxHcp';
    newDefs['1nt_range'] = '$minHcp-$maxHcp';

    final newOpenings = system.openingBids.map((node) {
      if (normalizeCall(node.call) == '1nt') {
        String updatedRule = node.rule ?? '';
        if (updatedRule.contains(RegExp(r'\d+\s*[-–]\s*\d+\s*hcp'))) {
          updatedRule = updatedRule.replaceAll(
            RegExp(r'\d+\s*[-–]\s*\d+\s*hcp'),
            '$minHcp-${maxHcp}hcp',
          );
        } else {
          updatedRule = '$minHcp-${maxHcp}hcp $updatedRule'.trim();
        }
        return BiddingNode(
          call: node.call,
          desc: node.desc.isNotEmpty ? node.desc : '1NT Opening ($minHcp-$maxHcp)',
          rule: updatedRule,
          priority: node.priority,
          ref: node.ref,
          condition: node.condition,
          variables: node.variables,
          bids: node.bids,
        );
      }
      return node;
    }).toList();

    return BridgeSystem(
      name: system.name,
      player: system.player,
      partner: system.partner,
      definitions: newDefs,
      openingBids: newOpenings,
      oppositionOpeningBids: system.oppositionOpeningBids,
      fragments: system.fragments,
    );
  }

  /// Checks if a convention or gadget is currently active in the system.
  static bool isConventionActive(BridgeSystem system, String conventionId) {
    final id = conventionId.toLowerCase();

    switch (id) {
      case 'jacoby_transfers':
        // Check if 1NT responses include 2d/2h transfer
        return system.fragments.containsKey('fJacobyTransfer') ||
            system.fragments.containsKey('fJacobyTransfers') ||
            system.fragments.containsKey('f1NTResponses') ||
            system.openingBids.any((n) =>
                normalizeCall(n.call) == '1nt' &&
                (n.bids.any((c) => normalizeCall(c.call) == '2d' && c.desc.toLowerCase().contains('transfer')) ||
                 n.ref?.toLowerCase().contains('jacoby') == true ||
                 n.ref?.toLowerCase().contains('1nt') == true));

      case 'stayman':
        return system.fragments.containsKey('fStayman') ||
            system.openingBids.any((n) =>
                normalizeCall(n.call) == '1nt' &&
                (n.bids.any((c) => normalizeCall(c.call) == '2c' && c.desc.toLowerCase().contains('stayman')) ||
                 n.ref != null));

      case 'multi_landy':
        return system.fragments.containsKey('fMultiLandy') ||
            system.oppositionOpeningBids.any((n) =>
                n.ref?.toLowerCase().contains('multilandy') == true ||
                n.desc.toLowerCase().contains('multi-landy') == true);

      case 'drury':
        return system.fragments.containsKey('fDrury') ||
            system.fragments.containsKey('fReverseDrury') ||
            system.openingBids.any((n) =>
                (normalizeCall(n.call) == '1h' || normalizeCall(n.call) == '1s') &&
                n.bids.any((c) => c.desc.toLowerCase().contains('drury')));

      case 'two_way_checkback':
        return system.fragments.containsKey('fTwoWayCheckback') ||
            system.fragments.containsKey('fXYZ');

      case 'support_doubles':
        return system.fragments.containsKey('fSupportDoubles');

      default:
        return system.fragments.keys.any((k) => k.toLowerCase().contains(id));
    }
  }
}
