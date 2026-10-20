# Implementation Plan: 3-Panel TestMyMemory UI with Editable Bidding Box

## 1. Architectural Overview & Requirements

The goal is to restructure the **Test My Memory (Quiz)** tab ([`PracticeQuizView`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/ui/practice_quiz_view.dart)) into an ergonomic **3-Panel Desktop & Responsive Layout**:

1. **Panel 1 (Hands)**: North (Partner) and South (You) hands displayed cleanly, with HCP, exact distribution, honor cards styling, and peek/collapse capability.
2. **Panel 2 (Bidding So Far)**: Live auction table (`West | North | East | South`) with proper dealer padding, sequence chips, undo/clear controls, and evaluation/diagnostic feedback.
3. **Panel 3 (Bidding Box & Mode Switcher)**: Dual-mode bidding console:
   - **🛠️ Setup Mode (Initial State)**: The Bidding Box is editable for **North, East, West, and South**. Selecting any bid appends it to the initial auction for the active seat, automatically advancing clockwise to the next player.
   - **🎯 Bid Mode (Practice Quiz)**: Tests South's memory against the configured initial state. Submitting a bid evaluates against the active system, provides diagnostics, and triggers automatic partner rebids.

```
+----------------------------------------------------------------------------------------------------+
| Top Control Bar: Dealer Selection (W | N | E | S) • Deal Filters • Test Hand • Score Tracker       |
+----------------------------------------------------------------------------------------------------+
|  PANEL 1: HANDS             |  PANEL 2: BIDDING SO FAR       |  PANEL 3: BIDDING BOX & MODES       |
|                             |                                |                                     |
|  [Partner Hand (North)]     |  [Live Auction Board]          |  Mode: [🛠️ Setup Mode] [🎯 Bid Mode]|
|   • HCP & Distribution      |   West | North | East | South  |                                     |
|   • Peek / Show cards       |   —    | 1H    | Pass | ?(Turn)|  Target Seat: [W] [N] [E] [S]       |
|   • ♠ ♥ ♦ ♣ Card chips      |                                |   (Advances clockwise automatically)|
|                             |  [Sequence & Actions]          |                                     |
|  [Your Hand (South)]        |   • Undo Last • Clear All      |  [Switch to Bid Mode ▶]             |
|   • HCP & Distribution      |   • Context ($M=s)             |                                     |
|   • ♠ ♥ ♦ ♣ Card chips      |                                |  [BBO Bidding Box]                  |
|   • Redeal Button           |  [Feedback & Diagnostics]      |   1 | 2 | 3 | 4 | 5 | 6 | 7         |
|                             |   • Partner feedback           |   ♣ | ♦ | ♥ | ♠ | NT | [Alert]      |
|                             |   • Error diagnostic & retry   |   [Pass]   [X]   [XX]               |
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Key Component Changes

### A. Panel 1: North & South Hands
- Standardize on [`CardHandWidget`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/ui/widgets/card_hand_widget.dart):
  - **North Hand**: Configured with `title: 'Partner Hand (North)'`, `icon: Icons.support_agent`, `headerColor: Color(0xFF1565C0)`, and `isCollapsible: true` (peek/show toggle so cards can be hidden during quiz mode or revealed).
  - **South Hand**: Configured with `title: 'Your Hand (South)'`, `icon: Icons.person`, `headerColor: Color(0xFF1B5E20)`, and full card view showing honors, HCP, and distribution.
  - Redeal and filter actions (HCP, Shape, North Opening) integrated directly at the top of Panel 1.

### B. Panel 2: Bidding So Far
- **Standardized Dealer Table**:
  - Full 4-seat columns: `West | North | East | South`.
  - Supports all 4 dealer options:
    - West dealer: `0` dashes
    - North dealer: `1` dash (`West: —`)
    - East dealer: `2` dashes (`West: —, North: —`)
    - South dealer: `3` dashes (`West: —, North: —, East: —`)
  - Turns highlighted:
    - In **Bid Mode**: `? (Your Turn)` highlighted in amber at South.
    - In **Setup Mode**: `[Next: $seat]` highlighted in the target cell.
- **Auction History Controls**:
  - `Undo Last Bid` (removes last entry and restores active seat).
  - `Clear Auction` (resets sequence back to dealer).
  - Interactive chips for every logged call.
- **Feedback & Diagnostic Cards**:
  - When South makes an incorrect bid: full ANTLR priority table, expected rule, and "Try Again with this Hand" button.
  - When contract reached: "Auction Complete!" banner.

### C. Panel 3: Bidding Box & Mode Switching
- **Dual Mode Toggle**:
  - `[ 🛠️ Setup Mode ]` vs `[ 🎯 Bid Mode ]`.
- **In Setup Mode**:
  - Target Seat Selector: `[ West ] [ North ] [ East ] [ South ]` (advances clockwise automatically when any bid is tapped in the bidding box, or can be manually overridden).
  - Clicking any level/suit or Pass/X/XX on the bidding box immediately logs that bid for the target seat!
  - Prominent `Switch to Bid Mode ▶` button.
- **In Bid Mode**:
  - If the setup sequence stops before South (e.g. North opened 1H), automatically passes for opponents up to South so South is ready to bid.
  - Evaluates South's candidates from the compiled auction graph (`graph.getState(sequence)`).
  - South uses the bidding box to submit their call.
  - Quick action to return to `Edit Initial State` anytime.

---

## 3. Step-by-Step Implementation Steps

1. **Step 1 - [`CardHandWidget`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/ui/widgets/card_hand_widget.dart)**:
   - Enhance widget with `title`, `icon`, `headerColor`, `isCollapsible`, and `initiallyCollapsed` parameters. *(Completed)*
2. **Step 2 - [`CompiledAuctionGraph`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/engine/compiled_auction_graph.dart) & [`AuctionEngine`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/engine/auction_engine.dart)**:
   - Normalize suit symbols (`♣`, `♦`, `♥`, `♠`) to `c, d, h, s` in call keys. *(Completed)*
   - Update `extractSystemSequence` to ignore opponent passes in user-entered history. *(Completed)*
3. **Step 3 - [`PracticeQuizView`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/ui/practice_quiz_view.dart)**:
   - Implement the 3-panel layout with `LayoutBuilder` (responsive side-by-side columns on wide screens, stacked on narrow screens).
   - Implement Setup Mode logic: seat selection, clockwise progression, undo/clear, and initial state persistence.
   - Implement `_switchToBidMode()` transition: auto-filling opponent passes to South's turn and querying next candidates.
4. **Step 4 - Verification**:
   - Run `flutter test` across all 57 existing unit & widget tests to guarantee zero regressions.
   - Verify setup of custom auctions (e.g., North 1NT, East Pass, South 2♣, West Pass, North 2♥, East Pass -> South rebid).
