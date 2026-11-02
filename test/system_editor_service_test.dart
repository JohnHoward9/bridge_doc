import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_bidding_system/models/bidding_system.dart';
import 'package:bridge_bidding_system/models/card.dart';
import 'package:bridge_bidding_system/services/visual_rule_translator.dart';
import 'package:bridge_bidding_system/services/system_editor_service.dart';

void main() {
  group('VisualRuleTranslator', () {
    test('translates complex node rule into VisualBidFormData and back', () {
      final node = BiddingNode(
        call: '3c',
        desc: 'Natural second suit Clubs, Game Forcing',
        rule: 'p#1 10+hcp 5+h 4+c !short_honors gf',
        priority: 1,
      );

      final form = VisualBidFormData.fromNode(node);

      expect(form.call, '3c');
      expect(form.minHcp, 10);
      expect(form.maxHcp, null);
      expect(form.minSuitLength[Suit.hearts], 5);
      expect(form.minSuitLength[Suit.clubs], 4);
      expect(form.requireShortHonors, false);
      expect(form.forcing, ForcingCategory.gameForcing);
      expect(form.priority, 1);

      // Modify form fields
      form.minHcp = 11;
      form.maxHcp = 16;
      form.minSuitLength[Suit.spades] = 5;
      form.shape = ShapeCategory.twoSuited55;

      final updatedNode = form.toNode();
      expect(updatedNode.call, '3c');
      expect(updatedNode.rule, contains('11-16hcp'));
      expect(updatedNode.rule, contains('5+s'));
      expect(updatedNode.rule, contains('!s#5332'));
      expect(updatedNode.rule, contains('!short_honors'));
      expect(updatedNode.rule, contains('gf'));
    });

    test('handles balanced shapes and ranges', () {
      final node = BiddingNode(
        call: '3nt',
        desc: 'Balanced hand to play',
        rule: 'p#2 13-15hcp s#5332 short_honors',
        priority: 2,
      );

      final form = VisualBidFormData.fromNode(node);
      expect(form.minHcp, 13);
      expect(form.maxHcp, 15);
      expect(form.shape, ShapeCategory.balanced);
      expect(form.requireShortHonors, true);

      final reencoded = form.toNode();
      expect(reencoded.rule, contains('13-15hcp'));
      expect(reencoded.rule, contains('short_honors'));
    });
  });

  group('SystemEditorService', () {
    test('resolves paths, updates nodes, and adds children', () {
      final childBid = BiddingNode(
        call: '2c',
        desc: 'Stayman',
        rule: '8+hcp 4+M',
      );
      final opening1NT = BiddingNode(
        call: '1nt',
        desc: '15-17 Balanced',
        rule: r'15-17hcp $bal',
        bids: [childBid],
      );
      final system = BridgeSystem(
        name: 'Test System',
        openingBids: [opening1NT],
      );

      // 1. Resolve path
      final resolved = SystemEditorService.resolvePath(system, ['1nt', '2c']);
      expect(resolved.length, 2);
      expect(resolved[0].call, '1nt');
      expect(resolved[1].call, '2c');

      // 2. Update node at path
      final updatedChild = BiddingNode(
        call: '2c',
        desc: 'Puppet Stayman Modified',
        rule: '10+hcp 3+M',
      );
      final updatedSystem = SystemEditorService.updateNodeAtPath(system, ['1nt', '2c'], updatedChild);

      final reResolved = SystemEditorService.resolvePath(updatedSystem, ['1nt', '2c']);
      expect(reResolved.last.desc, 'Puppet Stayman Modified');
      expect(reResolved.last.rule, '10+hcp 3+M');

      // 3. Add child node
      final transferBid = BiddingNode(
        call: '2d',
        desc: 'Jacoby Transfer to Hearts',
        rule: '5+h',
      );
      final withAdded = SystemEditorService.addChildNodeAtPath(updatedSystem, ['1nt'], transferBid);
      final conts = SystemEditorService.getContinuationsForPath(withAdded, ['1nt']);
      expect(conts.length, 2);
      expect(conts.any((b) => b.call == '2d'), isTrue);

      // 4. Delete node
      final afterDelete = SystemEditorService.deleteNodeAtPath(withAdded, ['1nt', '2c']);
      final afterConts = SystemEditorService.getContinuationsForPath(afterDelete, ['1nt']);
      expect(afterConts.length, 1);
      expect(afterConts.first.call, '2d');
    });

    test('reads and sets 1NT range', () {
      final opening1NT = BiddingNode(
        call: '1nt',
        desc: '15-17 Balanced',
        rule: '15-17hcp bal',
      );
      final system = BridgeSystem(
        name: 'Test System',
        openingBids: [opening1NT],
      );

      final range = SystemEditorService.get1NTRange(system);
      expect(range.$1, 15);
      expect(range.$2, 17);

      final modified = SystemEditorService.set1NTRange(system, 12, 14);
      final newRange = SystemEditorService.get1NTRange(modified);
      expect(newRange.$1, 12);
      expect(newRange.$2, 14);
      expect(modified.openingBids.first.rule, contains('12-14hcp'));
    });
  });
}
