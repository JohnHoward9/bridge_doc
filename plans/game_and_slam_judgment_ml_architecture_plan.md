# Game and Slam Judgment & Machine Learning Architecture Plan

## 1. Goal Description

In contract bridge, bidding systems establish the **grammar and constraints** of bids (e.g., "1♥ promises 5+ Hearts and 9–23 HCP; 4♠ is Kickback RKCB"). However, at critical junctures in an auction, a player faces **judgment thresholds**:
1. **Partscore vs Game**: Pass at the 2/3-level vs bid game directly.
2. **Investigate Game vs Bid Game**: Make an invitational game try (e.g., trial bid, 2NT over 1NT) vs blast game directly.
3. **Game vs Slam**: Settle in 4M/3NT/5m vs explore beyond game.
4. **Investigate Slam vs Bid Slam**: Use Serious 3NT, cuebidding, or RKCB/Kickback vs bid 6 directly.

This plan details the best architecture to integrate **bridge decision theory, Monte Carlo simulation, and Machine Learning (ML)** to evaluate these forks accurately, estimate trick distributions and expected values (EV), and guide the engine and user.

---

## 2. Decision Theory & Mathematical Thresholds

Bridge scoring (IMPs and Matchpoints) creates asymmetric payoffs that dictate mathematically optimal decision thresholds:

```
+-----------------------------------------------------------------------------------------+
| Decision Level   | Vul (IMPs)     | Non-Vul (IMPs) | Matchpoints   | Optimal Action    |
+-----------------------------------------------------------------------------------------+
| Game (3NT/4M)    | P(Make) ≥ 37%  | P(Make) ≥ 50%  | P(Make) ≥ 50% | Bid Game          |
| Game Try (Invite)| 25% ≤ P < 37%  | 35% ≤ P < 50%  | 35% ≤ P < 50% | Investigate Game  |
| Small Slam (6x)  | P(Make) ≥ 50%  | P(Make) ≥ 50%  | P(Make) ≥ 50% | Bid Slam          |
| Slam Try (Ask)   | 25% ≤ P < 50%  | 25% ≤ P < 50%  | 25% ≤ P < 50% | Investigate Slam  |
| Grand Slam (7x)  | P(Make) ≥ 75%  | P(Make) ≥ 75%  | P(Make) ≥ 75% | Bid Grand Slam    |
+-----------------------------------------------------------------------------------------+
```

### Why Raw HCP Fails for Judgment
Raw Milton Work HCP (4-3-2-1) ignores:
1. **Working vs Wasted Honors**: An Ace/King in partner's long suit generates 2+ tricks; a Queen opposite partner's singleton is wasted.
2. **Trump Fit Multiplication**: An 8-card fit adds ~1 trick; a 9-card fit adds ~2 tricks (The Law of Total Tricks).
3. **Controls vs Soft Points**: 32 HCP without an Ace loses two immediate tricks; 28 HCP with first-round controls makes 6.
4. **Distribution & Shape Potential**: 5431 and 6421 hands produce significantly more tricks on offense than 4333 hands with identical HCP.

---

## 3. High-Level System Architecture

```mermaid
flowchart TD
    A["Current Player's Hand (13 cards)"] --> D["Judgment & ML Engine"]
    B["Auction History & Inferred Partner Constraints"] --> D
    C["Vulnerability & Scoring (Vul/Non-Vul, IMPs/MPs)"] --> D

    subgraph "Judgment & ML Engine"
        D1["Hand Feature Extractor (52-dim binary + KnR + LTC + Controls)"]
        D2["Belief State / Partner Distribution Sampler"]
        D3["ML Value Network / Monte Carlo Evaluator"]
        D4["Expected Value (EV) & Probability Calculator"]
        D1 --> D3
        D2 --> D3
        D3 --> D4
    end

    D4 --> E{"Action Class"}
    E -->|P(Game) < 30%| F["Signoff (Partscore)"]
    E -->|30% ≤ P(Game) < 50%| G["Investigate Game (Trial Bid / Invite)"]
    E -->|P(Game) ≥ 50% (or ≥37% Vul)| H["Bid Game (3NT / 4M / 5m)"]
    E -->|25% ≤ P(Slam) < 50%| I["Investigate Slam (Serious 3NT / RKCB / Kickback)"]
    E -->|P(Slam) ≥ 50% & Key Controls Clear| J["Bid Slam (6x / 7x)"]

    F --> K["SpecificityResolver / AuctionEngine Bid Selection"]
    G --> K
    H --> K
    I --> K
    J --> K
```

---

## 4. The 3 Phased Approaches for Implementation

### Approach 1: Advanced Heuristic Valuation + Monte Carlo Belief Rollout (Fastest to Deliver, Transparent)
- **Component A: Advanced Valuation**:
  - Implement **Kaplan-Rubens (KnR)**, **Losing Trick Count (LTC)**, and **Working Honor Adjustments** in `lib/evaluators/valuation_engine.dart`.
- **Component B: Inferred Constraint Sampler**:
  - Use `DealGenerator` to sample $N = 100$ candidate partner hands satisfying partner's disclosed bids.
- **Component C: Empirical Trick Estimation**:
  - Calculate combined trick potential across the $N$ sampled boards.
  - Determine $P(\text{make game})$ and $P(\text{make slam})$.
- **Pros**: 100% written in Dart; zero external Python/C++ dependencies; immediate mathematical explainability in the UI.

### Approach 2: Deep Neural Network / Machine Learning Model (Offline Trained, Ultra-Fast Inference)
- **Model Structure**:
  - **Input Layer**:
    - 52 inputs: One-hot player hand.
    - 16 inputs: Partner disclosed parameters (min/max HCP, min/max lengths in ♠, ♥, ♦, ♣).
    - 4 inputs: Agreed trump strain (or NT).
    - 2 inputs: Vulnerability (We Vul, They Vul).
    - 2 inputs: Scoring format (IMPs / Matchpoints).
  - **Hidden Layers**: 3 Fully-Connected Dense layers (128 $\to$ 64 $\to$ 32) with ReLU activation and Dropout.
  - **Output Heads**:
    - **Head 1 (Regression)**: Expected tricks in candidate strains ($E[T]$).
    - **Head 2 (Distribution)**: Softmax over trick counts ($P(T=7), P(T=8), \dots, P(T=13)$).
    - **Head 3 (Policy / Decision)**: Classification logits: `[Signoff, InviteGame, BidGame, InviteSlam, BidSlam]`.
- **Inference in Flutter**:
  - Pure Dart matrix multiplication weights, OR TensorFlow Lite (`tflite_flutter`), OR ONNX Runtime (`onnxruntime`).
  - Execution time: **< 2 milliseconds** per evaluation.

### Approach 3: The Hybrid Engine (Recommended Best Practice)
- **Instant Mode (<5ms)**: Uses the Neural Network / Heuristic Value Engine to rank and classify bids in real-time during quiz play and table bidding.
- **Deep Analysis Mode (On Demand)**: Runs Monte Carlo deal rollouts with double dummy trick calculation to show the user the exact percentage breakdown:
  - *"In 100 simulated partner hands matching 2NT: 68 made 4♥, 22 made 3♥+1, 10 went down. Vulnerable game is +2.8 IMPs expectation. Recommendation: Bid 4♥."*

---

## 5. Proposed Code Changes & Architecture

### Component 1: Evaluators & Feature Extraction

#### [MODIFY] [`lib/evaluators/valuation_engine.dart`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/evaluators/valuation_engine.dart)
- Expand `HandValuationEngine` with:
  - `double evaluateKnR(Hand hand)`: Kaplan-Rubens metric.
  - `int losingTrickCount(Hand hand)`: Losing Trick Count (LTC).
  - `double evaluateWorkingPoints(Hand hand, {Suit? trumpSuit, Set<Suit>? partnerLongSuits})`: Downgrades unsupported queens/jacks, upgrades fitting honors.
  - `HandEvaluationProfile evaluateComprehensive(Hand hand, {Suit? trumpSuit})`.

#### [NEW] `lib/evaluators/ml_decision_evaluator.dart`
- Class `MlDecisionEvaluator`:
  - `GameSlamDecision evaluateDecision({required Hand hand, required AuctionContext context, required List<CandidateCall> candidates})`
  - Returns `DecisionOutcome`:
    - `DecisionTier tier` (`partscore`, `investigateGame`, `bidGame`, `investigateSlam`, `bidSlam`)
    - `double gameProbability`
    - `double slamProbability`
    - `double expectedScore`
    - `String explanation`

### Component 2: Bidding Engine Integration

#### [MODIFY] [`lib/engine/auction_engine.dart`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/engine/auction_engine.dart) & [`lib/constraints/specificity_resolver.dart`](file:///c:/Users/johnh/Documents/josulasa/bridge_doc/lib/constraints/specificity_resolver.dart)
- Connect `MlDecisionEvaluator` when evaluating multiple competing candidate bids at a decision node:
  - When candidates span multiple decision tiers (e.g. `Pass` vs `3H` invite vs `4H` game, or `4H` signoff vs `4S/4NT` slam try vs `6H` slam), the ML Decision Tier guides the winning bid selection.

### Component 3: UI & Advisory Display

#### [NEW] `lib/ui/widgets/game_slam_advisor_widget.dart`
- A visual card/sheet displayed in the Practice View:
  - Progress bars for **Game Probability ($P$)** and **Slam Probability ($P$)**.
  - Recommendation chip: **"INVESTIGATE GAME (38%–52%)"** or **"BID GAME (68%)"**.
  - Natural language advice explaining honor fit and trump texture.

---

## 6. Verification Plan

### Automated Tests
1. **Decision Threshold Unit Tests (`test/game_slam_decision_test.dart`)**:
   - Verify borderline 1NT invitations: 8 HCP aceless flat 4333 chooses `Pass`; 8 HCP with 10s/9s and 5-card suit chooses `2NT Invite` or `3NT`.
   - Verify game acceptance: Opener with minimum (12 HCP) declines game try; opener with maximum (14 HCP) accepts game try.
   - Verify slam investigation: Partnership with 33 HCP and controls launches RKCB; partnership missing 2 quick losers signs off in 4M.
2. **Full Regression Suite**:
   - Ensure all 92 existing tests pass with 0 regressions.

---

## 7. User Review Required

> [!IMPORTANT]
> **Questions for Alignment Before Proceeding**:
> 1. Would you like to start with **Approach 1 (Pure Dart Heuristic + Monte Carlo Belief Sampler)**, which runs instantly with zero external binary dependencies and gives full mathematical breakdown?
> 2. Should the ML decision recommendations be available as an **advisory coach in the UI** (showing win percentages and advice), or should it directly drive the automated AI bidding partner, or **both**?
