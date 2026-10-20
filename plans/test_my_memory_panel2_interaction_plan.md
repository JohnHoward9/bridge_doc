# Implementation Plan: Panel 2 Hand Selection, Dealer in Table, & Filter Modernization

## Overview & Objectives
Simplify and streamline the **Test My Memory** interface based on user feedback:
1. **Remove Target Seat row from Panel 3**: Hand/seat selection is performed directly by clicking on the hand/column/cell in **Panel 2 (Live Auction Board)**.
2. **Dynamic New Deal in Panel 1 upon Bidding**: Every time a bid is entered/updated in Setup Mode, automatically generate a new matching deal in **Panel 1** so the cards reflect the active auction. In Bid Mode, provide immediate new deal progression for practicing the scenario.
3. **Move Dealer Selection to Panel 2**: Remove the Dealer segmented button from the top header bar. Allow setting the dealer by clicking the hand column header (`West`, `North`, `East`, `South`) in Panel 2, decorated with a `👑 Dealer` badge.
4. **Relocate South HCP & Shape Filters**: Remove South HCP, South Shape, and North Opening from the top control bar. Place filter controls directly on the hand columns in **Panel 2** (and on the hand cards in **Panel 1**).

---

## Architecture & Layout

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ Top Control Bar: [System: 2/1 Game Force]  •  [⚡ Test Hand]  •  [Score: 5/6 (83%)]   │
└────────────────────────────────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────┬─────────────────────────────────────────────────┐
│ PANEL 1: HANDS                       │ PANEL 2 & 3: AUCTION & BIDDING BOX              │
├──────────────────────────────────────┼─────────────────────────────────────────────────┤
│ 🃏 Partner Hand                      │ 📋 Quick Presets Bar [1♠-2NT] [1NT-2♣] [Clear]  │
│    (Collapsible / Peeking)           │                                                 │
│                                      │ 🏛️ Panel 2: Live Auction Board                  │
│ 👤 Your Hand                         │   West     │ North 👑  │ East     │ South ⚙️     │
│    14 HCP  3-4-4-2                   │  (Dealer)  │  (You)    │          │ [13-15 Bal]  │
│    [♠ A K Q] [♥ K J] [♦ ...]         │   ---      │   1♠      │  Pass    │   2NT        │
│    • Filter Badge: [13-15 Bal] ⚙️    │   Pass     │  [?]      │          │              │
│    • [Redeal matching auction]       │   *(Tap column header for Dealer/Filters)*      │
│                                      │   *(Tap any cell to select/edit seat)*          │
│                                      │                                                 │
│                                      │ 🎛️ Panel 3: Bidding Box (Directly below LAB)    │
│                                      │   Mode: [🛠️ Setup Mode] [🎯 Bid Mode]           │
│                                      │   [Undo] [Clear] [Switch to Bid Mode ▶]         │
│                                      │   [ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ][ 7 ]           │
│                                      │   [ ♣ ][ ♦ ][ ♥ ][ ♠ ][ NT ]                    │
│                                      │   [ Pass ][ X ][ XX ]                           │
└──────────────────────────────────────┴─────────────────────────────────────────────────┘
```

---

## Detailed Implementation Steps

### 1. Panel 2 Hand/Seat Selection (Remove Target Seat from Panel 3)
- In [`lib/ui/practice_quiz_view.dart`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/ui/practice_quiz_view.dart):
  - In `_buildPanel3BiddingBox`, remove the `Target Seat:` ChoiceChips row (`West`, `North`, `East`, `South`).
  - In `_buildAuctionTable`:
    - Make each column header (`West`, `North`, `East`, `South`) and table cell clickable.
    - Tapping a column header or any cell in that column sets `_selectedEntrySeat` to that seat.
    - Highlight the selected seat/column in Panel 2 with an active border/background.
    - Tapping a bid in the Bidding Box applies to the selected seat and advances clockwise (`W -> N -> E -> S -> W`).

### 2. Auto-Deal Matching Hands in Panel 1 When a Bid is Made
- In `_onBidSelected(String rawBid)`:
  - When a bid is logged or edited in Setup Mode:
    - Update `_auctionHistory`.
    - Extract the normalized sequence: `final seq = _engine.extractSystemSequence(_auctionHistory);`.
    - Automatically generate a fresh board matching the sequence:
      `_currentDeal = _generator.dealBoardForSequence(seq, isNorthDealer: _dealer == DealerSeat.north);`.
    - Panel 1 instantly updates with hands that match the newly entered bids (e.g. North 1♠ deals 12+ HCP & 5+♠; South 2NT deals 13+ HCP & 4+♠).
  - In Bid Mode:
    - After the user submits a bid and receives feedback, provide a quick "Next Deal for this Auction" action to test the exact same auction position with fresh cards.

### 3. Move Dealer Selection to Panel 2 & Remove from Header Bar
- In `_buildTopControlBar`:
  - Remove `Dealer:` `SegmentedButton<DealerSeat>`.
  - Clean up the bar to only show the System Name, "Test Hand" shortcut, and Score pill.
- In `_buildAuctionTable`:
  - In `_buildHeaderCell`:
    - Add a `👑 Dealer` indicator badge on whichever seat is currently the dealer.
    - Allow tapping any seat header to set that seat as Dealer:
      ```dart
      onTap: () {
        setState(() {
          _dealer = seatFromCode(seat);
          // Shift auction or redeal starting from new dealer
        });
      }
      ```
    - Provide a tooltip: `"Tap to set $seat as Dealer"`.

### 4. Move South Shape & HCP Filters to Hands in Panel 2 & Panel 1
- In `_buildTopControlBar`:
  - Remove `South HCP:` and `South Shape:` (and `North Opening:`) dropdowns.
- In `_buildAuctionTable` (Panel 2):
  - In the `South` (and `North`) column headers, add a filter button/icon (`Icons.tune` or `Icons.filter_alt`).
  - Clicking it displays an intuitive filter popup/menu allowing selection of:
    - HCP Range: Any, 0-5, 6-9, 10-12, 13-15, 16+
    - Shape: Any, Balanced, 5+ Major, 5+ Minor, Unbalanced
  - When a filter is active, a badge (e.g. `13-15 Bal`) appears under the seat label.
- In `_buildPanel1Hands` (Panel 1):
  - Include the filter controls/badge directly on the South Hand card header.
  - Applying a filter immediately triggers a deal matching those filters.

---

## Verification Plan & Results

1. **Widget & Unit Tests** (`test/test_my_memory_3panel_test.dart`):
   - [x] Verified Target Seat chips are removed from Panel 3.
   - [x] Verified selecting a seat by tapping the column in Panel 2 sets the target seat.
   - [x] Verified tapping a column header in Panel 2 sets the Dealer (displays `👑 Dealer`).
   - [x] Verified South filter dialog opens via `Icons.tune` on South column header in Panel 2.
   - [x] Verified bidding updates Panel 1 with matching dealt cards.
2. **Full Regression Test Suite**:
   - [x] Executed `flutter test`. All **60 tests passed** with zero regressions.
