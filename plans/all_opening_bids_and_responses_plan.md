# Implementation Plan: Comprehensive Architecture for All Opening Bids (Pass → 4NT)

## 1. Goal Description

Establish a complete, cohesive bridge bidding coverage for **every opening bid from Pass through 4NT inclusive** for Gavin Wolpert's system (and other 2/1 profiles in the application).

Currently:
- **1-level openings & 1NT** have full, tournament-grade response suites.
- **2♣** has Kokish Relay over 2♦ waiting, but lacks positive responses.
- **2♦, 2♥, 2♠ (Weak Twos)** are defined as opening bids but have **zero responses** (dead ends).
- **2NT** has full Puppet Stayman & transfer suites.
- **3♣, 3♦, 3♥, 3♠, 3NT, 4♣, 4♦, 4♥, 4♠, 4NT** are completely missing as opening bids and responses.

---

## 2. Complete Opening Bid & Response Architecture

Below is the complete spectrum of opening bids and our suggested implementation approach for each:

```
Level 1:  [Pass]   [1♣]   [1♦]   [1♥]   [1♠]   [1NT]      (Complete)
Level 2:  [2♣] (Partial)   [2♦] [2♥] [2♠] (Missing Resp)   [2NT] (Complete)
Level 3:  [3♣] [3♦] [3♥] [3♠] (Preempts)   [3NT] (Gambling) (Missing)
Level 4:  [4♣] [4♦] (Namyats/Preempts)   [4♥] [4♠] [4NT]    (Missing)
```

---

### Detailed Approaches by Bid Level

#### Level 1: Foundational Openings (✅ Already Complete)
- **Pass**: 0–11 HCP. In 3rd/4th seat, links to `fDrury` over partner's 1M opening.
- **1♣ / 1♦**: Better Minor / Walsh structure (`fWalshClubResponses`, `fWalshDiamondResponses`), inverted minors, 1m-2NT GF, and XYZ / Three-Way Checkback.
- **1♥ / 1♠**: 5-Card Majors (`fGavinHeartResponses`, `fGavinSpadeResponses`) with 2/1 GF, Semi-Forcing 1NT, Reversed Bart, Jacoby 2NT, and Splinters.
- **1NT**: Strong balanced 15–17 HCP (`fGavin1NTResponses`) with 4-Way Transfers, Regular Stayman + Smolen, Puppet Stayman, and 5-5 Minors.

---

#### Level 2: Strong & Weak Two Openings

##### A. 2♣ Strong Artificial (22+ HCP or 8.5+ tricks)
- **Current Status**: Defines `2d` waiting (`fKokishRelay`), but no positive suit responses.
- **Suggested Approach**:
  - Keep `2d` as the primary waiting/relay response (standard in 2/1).
  - Add positive suit responses for hands with 8+ HCP and a good 5+ card suit:
    - `2h`: Positive natural (5+ Hearts, 8+ HCP, game forcing).
    - `2s`: Positive natural (5+ Spades, 8+ HCP, game forcing).
    - `2nt`: Positive balanced (8+ HCP, no 5-card suit).
    - `3c` / `3d`: Positive natural minors (5+ minor, 8+ HCP).

##### B. 2♦, 2♥, 2♠ Weak Twos (5–10 HCP, 6-card suit) — *High Priority*
- **Current Status**: Openings are defined, but **zero responses** exist.
- **Suggested Approach**: Create a dedicated module `weak_two_responses.yaml` (`fWeakTwoResponses`):
  - **Pass**: To play (sub-minimum or misfit, 0–13 HCP).
  - **2NT Forcing Enquiry**: 
    - In standard & Gavin Wolpert, 2NT is the universal asking bid (14+ HCP, game interest).
    - Opener rebids show strength and shape using **Feature Ask** (or **Vinny 2NT / Ogust**):
      - With minimum (5–7 HCP): Opener re-bids original suit at 3-level (`3$os`).
      - With maximum (8–10 HCP): Opener bids outside Ace or King ("Feature"): `3c`, `3d`, `3h`, `3s`, or `3nt` (solid suit / maximum).
  - **Simple Raise (`3$os`)**: Preemptive extension of the preempt (Law of Total Tricks, 3-card support, 6–10 HCP).
  - **Game Raise (`4$os`)**: Preemptive to play (4+ card support, distribution).
  - **New Suits (e.g. 2♠ over 2♥; 3-level new suits)**: Natural, 5+ cards, 1-round forcing (14+ HCP, looking for game in new suit or 3NT).
  - **3NT**: To play (15–17 HCP balanced with outside stoppers).

##### C. 2NT Strong Balanced (20–21 HCP) (✅ Already Complete)
- Complete Puppet Stayman suite (`fPuppetStayman2NT`): `3c` Puppet Stayman, `3d`/`3h` Jacoby transfers, `3s` minor slam try, `3nt` to play.

---

#### Level 3: 3-Level Preempts & Gambling 3NT (❌ Currently Missing)

##### A. 3♣, 3♦, 3♥, 3♠ (3-Level Preempts)
- **Opening Definition**: 6–10 HCP with a good 7-card suit and no outside 4-card major or second suit.
- **Responses** (`fPreemptResponses3Level`):
  - **Pass**: To play.
  - **Simple raise to Game** (`4♥` over 3♥; `4♠` over 3♠; `5♣/5♦` over minors): To play.
  - **3NT**: To play (solid values, stoppers in outside suits).
  - **New Suits**: Natural, 1-round forcing (16+ HCP).

##### B. 3NT Opening: Gambling 3NT
- **Opening Definition**: Solid 7-card minor (AKQxxxx in ♣ or ♦) with **no outside Ace or King** (0–1 outside Queen/Jack, 10–13 total HCP).
- **Responses** (`fGambling3NT`):
  - **Pass**: Responder has stoppers in the other three suits and wants to play 3NT.
  - **4♣ (Pass or Correct)**: Asks opener to pass with clubs, or bid 4♦ with diamonds.
  - **4♦ (Shortness Ask)**: For slam investigation; opener shows singleton/void.
  - **4♥ / 4♠**: Natural to play (long major, independent of opener's minor).
  - **5♣ (Pass or Correct)**: Game invitation in opener's minor.

---

#### Level 4: 4-Level Preempts, Namyats & 4NT (❌ Currently Missing)

##### A. 4♣ and 4♦ Options (Standard Preempt vs. Namyats)
- **Option 1 (Standard 4-Level Preempts)**:
  - `4c`: 8+ Clubs, 6–10 HCP.
  - `4d`: 8+ Diamonds, 6–10 HCP.
- **Option 2 (Namyats — Gavin Wolpert Expert Standard)** *(Recommended)*:
  - `4c`: Shows an 8½ trick hand in **Hearts** (solid/semi-solid 7–8 card Hearts with outside Ace/King, slightly too strong for a weak 4♥ opening).
    - Responses: `4h` (signoff), `4d` (asking for side control), `4nt` (RKCB).
  - `4d`: Shows an 8½ trick hand in **Spades** (solid/semi-solid 7–8 card Spades).
    - Responses: `4s` (signoff), `4h` (asking for side control), `4nt` (RKCB).
  - *Advantage*: Leaves direct `4♥` and `4♠` openings as pure, weak preempts (bad suit, purely distributional).

##### B. 4♥ and 4♠ Openings (4-Level Major Preempts)
- **Opening Definition**: 8-card major (or 7-card weak suit with extreme distribution), 6–10 HCP.
- **Responses**:
  - `pass`: To play (most common).
  - `4nt`: Roman Key Card Blackwood 1430 in opener's major.
  - `5M`: Law of Total Tricks advance.

##### C. 4NT Opening
- **Opening Definition**: Specific Ace Ask or Extreme Minors two-suiter (6-5 or 5-5 in minors, less than opening values).
- **Responses**:
  - `5c` / `5d`: Pass or correct to opener's better minor.

---

## 3. Implementation Plan & Proposed Modules

### Module 1: `assets/libraries/conventions/weak_two_responses.yaml` [NEW]
Contains `fWeakTwoResponses` using `$os` (opening suit) and `$OM` (other major) or explicit suit fragments:
- `fWeakTwoDiamondResponses`
- `fWeakTwoHeartResponses`
- `fWeakTwoSpadeResponses`
Includes Feature Ask responses over 2NT, raises, and new suits.

### Module 2: `assets/libraries/conventions/preempt_responses.yaml` [NEW]
Contains:
- `fPreempt3LevelResponses` (responses to 3♣, 3♦, 3♥, 3♠)
- `fGambling3NT` (responses to 3NT)
- `fNamyats` / `fPreempt4LevelResponses` (responses to 4♣, 4♦, 4♥, 4♠, 4NT)

### Module 3: Update System Profiles [MODIFY]
- **`gavin_wolpert_2over1.yaml`**:
  - Add missing opening bids: `3c`, `3d`, `3h`, `3s`, `3nt`, `4c`, `4d`, `4h`, `4s`, `4nt`.
  - Link `2d`, `2h`, `2s` to `weak_two_responses.yaml`.
  - Add positive suit responses to `2c`.
  - Import the new convention libraries.
- **`us_standard_2over1.yaml`**, **`three_way_club_5cm.yaml`**, **`uk_acol_4cm.yaml`**:
  - Link weak two responses and 3-level/4-level openings to keep all system profiles synchronized.

---

## 4. User Review Required

> [!IMPORTANT]
> **Key Decisions to Confirm**:
> 1. **Weak Two 2NT Response**: Do you prefer **Feature Ask** (shows outside Ace/King when maximum) or **Ogust** (steps showing min/max and good/bad suit)? (Feature Ask is standard in Wolpert 2/1).
> 2. **4♣ / 4♦ Openings**: Do you prefer **Namyats** (4♣ = strong 4♥; 4♦ = strong 4♠) or **Natural Preempts** (4♣ = 8+ clubs; 4♦ = 8+ diamonds)?
> 3. **Rollout Scope**: Should we implement:
>    - **Phase 1 (Immediate)**: Weak Two Responses (2♦, 2♥, 2♠) + 2♣ positive responses.
>    - **Phase 2**: 3-level Preempts + Gambling 3NT.
>    - **Phase 3**: 4-level Preempts / Namyats + 4NT.
>    *(Or all in one comprehensive update?)*

---

## 5. Verification Plan

### Automated Tests
1. Unit tests in `test/weak_two_responses_test.dart` verifying:
   - 2D/2H/2S openings resolve 2NT enquiry, passes, raises, and new suits.
   - Opener answers 2NT enquiry correctly based on minimum vs maximum and feature.
2. Unit tests in `test/preempts_test.dart` verifying 3-level and 4-level bids.
3. Full test run: `flutter test` across all 61+ tests to guarantee 100% passing.
