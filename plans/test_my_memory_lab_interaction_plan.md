# Implementation Plan: Intuitive Live Auction Board (LAB) Interaction & Multi-Seat Quiz Setup

## Goal Description
Redesign the **Test My Memory** layout and interaction model so that:
1. **Bidding Box directly below the Live Auction Board (LAB):** Shift from an unwieldy 3-column layout to a clean 2-column layout (Hands on Left, Live Auction Board + Bidding Box on Right).
2. **Clickable LAB Cells:** Users can click directly on any cell in the Live Auction Board to select it, and then choose a bid from the Bidding Box to fill or edit that cell.
3. **Intuitive Initial Sequence Setup:** Provide a simple, frictionless way to configure any auction state (e.g., `North: 1♠ → East: Pass → South: 2NT → West: Pass`) and immediately be in position to test the next seat (e.g., test **North's** rebid over Jacoby 2NT, or test **South's** response).

---

## Architecture & Layout

### 2 Columns - Direct Vertical Association
```
┌──────────────────────────────────────┬──────────────────────────────────────┐
│ Left Column: Hands                   │ Right Column: Auction & Bidding Box  │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ 🃏 Partner Hand (e.g. South)          │ 📋 Quick Sequence Presets Bar        │
│    (Collapsible / Peeking)           │    [1♠-2NT Jacoby] [1NT-2♣] [Custom] │
│                                      │                                      │
│ 👤 Active Hand to Bid (e.g. North)   │ 🏛️ Live Auction Board (LAB)          │
│    14 HCP  3-4-4-2                   │    West | North | East | South       │
│    [♠ A K Q] [♥ K J] [♦ ...]         │    ---  |  1♠   | Pass |  2NT        │
│                                      │    Pass |  [?]  |      |             │
│ ⚙️ Deal & Filter Controls            │    *(Click any cell to edit/select)* │
│    [Redeal] [HCP Filter] [Shape]     │                                      │
│                                      │ ⚠️ Error Diagnostic / Result Card    │
│                                      │    *(Shown only when needed)*         │
│                                      │                                      │
│                                      │ 🎛️ Bidding Box (Directly Below LAB) │
│                                      │    [ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ][ 7 ]│
│                                      │    [ ♣ ][ ♦ ][ ♥ ][ ♠ ][ NT ]        │
│                                      │    [ Pass ][ X ][ XX ]                │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

---

## Implemented Enhancements

1. **[`lib/engine/auction_engine.dart`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/engine/auction_engine.dart)**:
   - Added `activeSeat` support to `advanceAuction` (`'N'` or `'S'`). Whichever player has the active turn is tested against their actual hand, system rules, and automatic partner/opponent rebids symmetrically.
   - Added `AuctionEngine.determineNextSeat(history, dealerCode)` to determine active turn seat dynamically based on dealer offset and history length.

2. **[`lib/engine/deal_generator.dart`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/engine/deal_generator.dart)**:
   - Added `dealBoardForSequence(List<String> systemSequence, {bool isNorthDealer})` ensuring realistic matching cards for initial setups (e.g. North 12+ HCP & 5+♠, South 13+ HCP & 4+♠ for Jacoby 2NT).

3. **[`lib/ui/practice_quiz_view.dart`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/ui/practice_quiz_view.dart)**:
   - **Bidding Box position**: Unified Card positioned directly beneath the Live Auction Board in the right panel.
   - **Clickable LAB cells**: Every call cell on the Live Auction Board is wrapped with `InkWell`. Clicking any cell selects it, highlights with an amber focus border, and allows immediate replacement via the Bidding Box.
   - **Quick Practice Presets Bar**: One-click scenario loading (`1♠ → 2NT (Jacoby)`, `1♥ → 2NT (Jacoby)`, `1NT → 2♣ (Stayman)`, `1NT → 2♦ (Transfer)`, `1♣ → 1♦ (Walsh)`), with matching cards and automatic active-seat positioning.
   - **Dynamic Seat Bidding**: Seamlessly switches active seat between North and South: displays "Your Hand (North)" / "Your Hand (South)" and tests North rebids over responses or South responses over openings.
   - **Error Handling & Retry**: Includes "Try Again" action buttons in both the error card and Bidding Box banner, resetting the state to allow immediate re-bidding with the same hand.

---

## Verification Results

- **Unit & Widget Tests**: `flutter test test/test_my_memory_3panel_test.dart` passes (2/2 tests).
  - Verifies setup mode initial state bidding, retry banner, and error diagnostics.
  - Verifies quick scenario preset loading for `1♠ → 2NT (Jacoby)`, active turn for North, and interactive cell editing directly on the Live Auction Board table.
- **Full Test Suite**: `flutter test` passes all 59 tests with 0 failures across the entire codebase.
