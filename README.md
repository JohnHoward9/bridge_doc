# Bridge Bidding Workbench & Memory Practice Simulator

A cross-platform Flutter & Dart application for designing, browsing, testing, and practicing Bridge Bidding Systems using a modular **Core vs. Libraries** YAML architecture, dual-mode constraints, and a **"Most Defined Wins" Specificity Resolution Engine**.

---

## ♠ ♥ ♦ ♣ Key Features

### 1. Specificity Resolution ("The More Defined is Chosen")
When a hand matches multiple legal candidate bids, the engine does not rely on arbitrary order in the file. It evaluates the **Specificity Score** of each candidate and selects the most defined one.

**Example**:
- **Hand**: `♠A3  ♥KQ5432  ♦4  ♣K432` (12 HCP, 6 Hearts, 4 Clubs)
- **Candidate 1**: `1c: (10+hcp, 2+C)` &rarr; Matches, but broad minor preparation (score: ~25).
- **Candidate 2**: `1h: (10+hcp, 5+H)` &rarr; Matches, and **more defined** 5-card major (score: ~68).
- **Result**: The engine deterministically picks **`1H`**!

---

### 2. Modular Architecture: Core vs. Libraries
Systems are no longer monolithic 2,700-line files. Reusable conventions are extracted into pluggable library modules:

```
bridge_doc/
├── assets/
│   ├── core/
│   │   └── systems/
│   │       ├── three_way_club_5cm.yaml   # John & Andy's 3-Way Club (from system20120910.bbs)
│   │       ├── us_standard_2over1.yaml   # US Standard 5-Card Majors, 2/1 GF, Strong NT
│   │       └── uk_acol_4cm.yaml          # UK Acol 4-Card Majors, Weak NT
│   └── libraries/
│       └── conventions/
│           ├── multi_landy.yaml          # Defense vs 1NT
│           ├── drury.yaml                # 2C Drury 3-4 card major enquiry
│           ├── rkcb_1430.yaml            # Roman Key Card Blackwood 1430
│           └── one_nt_responses.yaml     # Stayman & Jacoby Transfers
```

Systems import conventions using simple YAML:
```yaml
system: "3-Way Club (5-Card Majors)"
imports:
  - "assets/libraries/conventions/multi_landy.yaml"
  - "assets/libraries/conventions/drury.yaml"
  - "assets/libraries/conventions/rkcb_1430.yaml"
  - "assets/libraries/conventions/one_nt_responses.yaml"
```

---

### 3. Dual-Mode Constraint Engine & Pluggable Valuation
Constraints can be written in either format:
- **Semantic YAML**:
  ```yaml
  rule:
    hcp: [15, 17]
    shape: balanced
    suits: { hearts: "<=4", spades: "<=4" }
  ```
- **Natural DSL Shorthand**:
  ```yaml
  rule: "15-17hcp, balanced, 4-h, 4-s"
  ```
- **Pluggable Valuation**: Abstract `HandValuationEngine` with default Milton Work points (A=4, K=3, Q=2, J=1), ready for Machine Learning (ML) vector feature extraction.

---

### 4. Interactive "Test My Memory" Partnership Simulator
- **Partnership Deals (North & South)**: Generates complete, mutually exclusive 13-card hands from the same 52-card deck for both North (Partner) and South (You).
- **First Bidder Selection**:
  - **North (Partner) bids first**: North evaluates North's 13-card hand against the system opening bids using `SpecificityResolver` and opens automatically (e.g. opens 1♥). East passes, and it becomes your turn to respond!
  - **South (You) bids first**: You open the bidding from the Bidding Box; once confirmed, North automatically responds based on North's hand!
- **Partner Hand Peek Toggle**: You can keep partner's cards hidden for authentic blind practice or tap "Peek Partner Cards" to see what partner holds.
- **Live 4-Seat Auction Board**: Visual table tracking `West | North | East | South` throughout multiple rounds of bidding.
- **Interactive Bidding Box**: Standard bridge box layout (Pass, Dbl, Rdbl, 1♣..7NT).
- **Instant Diagnostic Feedback**:
  - ✅ Green confirmation explaining why the chosen bid matches and is most defined.
  - ❌ Red alert explaining rule violations and showing all candidates ranked by ANTLR `p#` priority and specificity.
  - Quick-test button for `A3:KQ5432:4:K432`.

---

## 🏃 Running the Application

In your terminal:

```powershell
cd C:\Users\johnh\Documents\josulasa\bridge_doc

# Run on Windows Desktop
flutter run -d windows

# Or run in Chrome / Web browser
flutter run -d chrome
```
