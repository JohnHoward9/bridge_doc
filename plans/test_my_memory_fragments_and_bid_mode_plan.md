# Architecture & Implementation Plan: YAML Fragments Design, 1NT Evaluation & Fixed Bid Mode

## 1. Overview & Objectives

This plan addresses three interrelated items:
1. **Architectural Design**: Answering whether and how YAML fragments should provide a list of applicable bids with conditions.
2. **Fixed Bids in Bid Mode**: Ensuring that in **Bid Mode**, the bids for **North, East, and West** are fixed (read-only, immutable context) and cannot be clicked or overwritten.
3. **The 1NT Evaluation Issue ("Missing 1NT on attached hand")**: Diagnosing and resolving why South's hand (♠Q9 ♥KJ84 ♦K983 ♣865, 9 HCP) over North's 1♠ was rejected when bidding 1NT with the message *"You bid '1nt', but the system requires 'Pass' (Pass (to play / no bids apply))"*.

---

## 2. Architectural Analysis: Should YAML Fragments Provide Applicable Bids with Conditions?

### **Yes, absolutely.** Here is why and how:

In modern bridge bidding modeling, an auction is a state transition graph. At any given state (e.g. after `1♠`), the bidder faces a decision. A **Fragment** is a reusable submodule that defines the **menu of applicable bids** for that exact juncture.

### Ideal Fragment Structure
```yaml
fragments:
  fSpadeResponses:
    desc: "Responses to 1♠ Opening (5+ Spades, 12-21 HCP)"
    # A list / dictionary of all legal, applicable calls at this junction:
    bids:
      pass:
        desc: "Pass (weak hand, 0-5 HCP)"
        rule: "p#10 5-hcp"
        priority: 10

      1nt:
        desc: "Semi-forcing 1NT (6-11 HCP, denies 3+ Spades)"
        rule: "p#3 6-11hcp 2-s"
        priority: 3
        # Continuations from opener:
        bids:
          pass: "12-14hcp balanced"
          2c: "3+c 12-15hcp"
          2d: "3+d 12-15hcp"
          2h: "4+h 12-15hcp"
          2s: "6+s 12-15hcp"

      2c:
        desc: "2/1 Game Force in Clubs (12+ HCP, 4+ Clubs)"
        rule: "p#2 12+hcp 4+c"
        priority: 2

      2d:
        desc: "2/1 Game Force in Diamonds (12+ HCP, 5+ Diamonds)"
        rule: "p#1 12+hcp 5+d"
        priority: 1

      2h:
        desc: "2/1 Game Force in Hearts (12+ HCP, 5+ Hearts)"
        rule: "p#1 12+hcp 5+h"
        priority: 1

      2s:
        desc: "Constructive 3-card raise (6-9 HCP, 3 Spades)"
        rule: "p#3 6-9hcp 3s"
        priority: 3

      2nt:
        desc: "Jacoby 2NT: Game-forcing 4+ Spades (13+ HCP)"
        rule: "p#1 13+hcp 4+s [$M=s, $OM=h]"
        priority: 1
        ref: "fJacoby2NT"
```

### Benefits of this Pattern
1. **Explicit Completeness**: Any hand held by the responder must match exactly one bid (or fall back to Pass). If South has 9 HCP and 2 Spades, it satisfies `6-11hcp 2-s` and maps cleanly to `1NT`.
2. **Conditional Specialization via Variables**:
   A single fragment can serve both `1♥` and `1♠` by using variable parameters:
   - `[$M=h, $OM=s]` for Hearts opening
   - `[$M=s, $OM=h]` for Spades opening
   Conditional rules like `<$M=h> 1s: 4+s` (only applicable over 1H) are cleanly filtered out over 1S because `$M=s`.
3. **Self-Documenting & Inspectable**: The UI can directly inspect the fragment to display the full menu of available candidate bids, their requirements, and their descriptions.

---

## 3. Investigating the "Missing 1NT" Error

### The Symptoms in User's Screenshot
- **Hand**: South holds `♠Q9 ♥KJ84 ♦K983 ♣865` (9 HCP, 2-4-4-3).
- **Auction**: North opened `1♠`, East `Pass`.
- **User bid**: `1NT`.
- **System output**: `You bid "1nt", but the system requires "Pass" (Pass (to play / no bids apply))`.

### Root Cause Analysis
1. `Pass (to play / no bids apply)` is only synthesized when **no candidate bid in the active state matches the hand**.
2. Why would no candidate bid match?
   - **Case A: State Key Mismatch**: When the auction history contains formatted Unicode calls (e.g. `1♠`), if the sequence lookup key is normalized differently (e.g., expecting `1s` vs `1S` vs `(1s)`), `graph.getState(currentSeq)` returns `null`, causing the engine to fall back to `rootState` (Opening Bids). In `rootState`, 9 HCP cannot open `1NT` (which requires 15-17 balanced) or any suit (12+ HCP), so the engine falls back to `Pass`!
   - **Case B: Opponent Call in History**: When East's call is `Pass`, if `extractSystemSequence` does not cleanly distinguish opponent passes from active system passes, the sequence key becomes `['1s', 'pass']` instead of `['1s']`. The graph has no state for `['1s', 'pass']`, again falling back to `rootState`!
   - **Case C: Fragment Resolution in Active Session**: In the desktop app running from the system switcher, if the system was switched dynamically or edited in the YAML tab, the newly parsed graph must properly link and resolve all imported library fragments (e.g. `fGavinSpadeResponses`) without dropping sub-fragments.

### The Fix
1. In [`extractSystemSequence`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/engine/auction_engine.dart):
   Guarantee that:
   - Opponent calls are strictly normalized (`Pass` by E/W is completely stripped from the system sequence key).
   - Suits are converted to canonical lowercase letters (`♠` -> `s`, `♥` -> `h`, `♦` -> `d`, `♣` -> `c`).
   - Partner calls are stripped of whitespace and lowercased.
2. In [`CompiledAuctionState.evaluateCandidates`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/engine/compiled_auction_graph.dart):
   Ensure that if `graph.getState(currentSeq)` is queried, it falls back to the nearest matching state rather than blindly reverting to `rootState`.
3. Provide robust diagnostic feedback in the UI: When a bid fails, display the actual candidates evaluated and the hand attributes that satisfied or missed each rule, so the user and system are always transparently aligned.

---

## 4. Fixing the Bids for North, East, and West in Bid Mode

### Current Behavior
In `practice_quiz_view.dart`:
- Tapping any cell in Panel 2 enters `_isSetupMode = true` and allows editing that cell.
- In Bid Mode, this allows North, East, or West calls to be selected or edited unintentionally.
- Tapping column headers in Panel 2 changes Dealer or triggers redeals.

### Proposed Behavior
In **Bid Mode**:
- **North, East, and West are FIXED**:
  - Their cells in Panel 2 are completely non-interactive (no `onTap` to enter setup mode or edit).
  - Column headers for West, North, and East cannot be clicked to change dealer or redeal while in Bid Mode.
  - Visual styling clearly distinguishes the fixed given auction (clean neutral background, lock icon or subtle badge) from the active user's turn (`? (Your Turn)` highlighted in amber).
- **Setup Mode remains available**:
  - If the user explicitly wants to edit or change the scenario, they click the `[🛠️ Setup Mode]` button in Panel 3 or the `[Edit State]` button in the diagnostic banner.
  - Only when `_isSetupMode == true` can cells and dealer headers be tapped to modify the initial auction.

---

## 5. Verification Plan

### Automated Tests
1. **Unit Test**: Test that `extractSystemSequence` on `[N: 1♠, E: Pass]` produces `['1s']` regardless of Unicode suit symbols or opponent pass formatting.
2. **Evaluation Test**: Verify that South holding `♠Q9 ♥KJ84 ♦K983 ♣865` (9 HCP, 2-4-4-3) over `1♠` evaluates to `1NT` across all 4 system profiles (`gavin_2over1`, `us_2over1`, `3_way_club`, `uk_acol`).
3. **Widget Test**:
   - In Bid Mode, tapping on North, East, or West cells does NOT switch to Setup Mode or select those cells.
   - Bidding `1NT` for South over `1♠` succeeds without diagnostic errors.
   - All existing tests in the suite pass (`flutter test`).
