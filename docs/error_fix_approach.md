# BBO 2025 Bidding Defect Categories & Gavin Wolpert Fix Approach

This document reviews all active failure deals from the 2025 BBO Championship dataset, analyzes their root causes, and details the recommended fixes per defect category according to Gavin Wolpert's expert 2/1 system methods.

---

## 1. Category 3: Wrong Opening Bid

### Active Deals
- **Deal 81577 B:5**: North holds `♠AKJ42 ♥KQ7 ♦A9 ♣A86` (21 HCP, 5-3-2-3 balanced). Opened **2♣** instead of **2NT**! (Auction: `2c 2d 2s 4s Pass`).
- **Deal 82672 B:13**: North holds `♠Q2 ♥KJ963 ♦AKT ♣AKJ` (21 HCP, 2-5-3-3 balanced). Opened **1♥** instead of **2NT**! (Auction: `1h 3h Pass`).

### Root Cause Analysis
In [`assets/libraries/conventions/puppet_stayman_2nt.yaml`](../assets/libraries/conventions/puppet_stayman_2nt.yaml) at line 12:
```yaml
Strong2NTOpening:
  rule: "20-21hcp, balanced, 4-h, 4-s"
```
The constraint `4-h, 4-s` explicitly prevents opening 2NT with any 5-card major, forcing balanced 20-21 HCP hands into either artificial 2♣ (if holding 5 spades) or standard 1-level major openings (if holding 5 hearts).

### Gavin Wolpert Online Continuum & Method
In Gavin Wolpert's Master Series (*Openings & Follow-ups*):
> *"Open 2NT with 20-21 balanced points, including all 5-3-3-2 distributions with a 5-card major. Puppet Stayman (3♣) is specifically designed to uncover whether opener holds a 5-card major or a 4-card major without missing the 5-3 major fit."*

### Recommended Fix
Update `Strong2NTOpening` in `puppet_stayman_2nt.yaml`:
```yaml
rule: "20-21hcp balanced | 20-21hcp s#5332"
priority: 1
```
Removes the `4-h, 4-s` restriction and ensures Puppet Stayman handles the 5-card major discovery.

---

## 2. Category 2: Missed Major Strain

### Active Deals
- **Deals 81774 B:23 & 81775 B:23**:
  - North: `♠T642 ♥KJ ♦T943 ♣A76` (8 HCP, 4 spades)
  - South: `♠AQ85 ♥AQ42 ♦A75 ♣T8` (16 HCP, 4-4 majors)
  - Auction: `1nt 2c 2h 2nt 3nt Pass` (Final Contract: **3NT** on a 4-4 spade fit!).
- **Deal 81774 B:29**:
  - North: `♠4 ♥A7542 ♦J65 ♣A976` (9 HCP, 5 hearts, 4 clubs)
  - South: `♠A6 ♥J83 ♦AK3 ♣QJT32` (15 HCP balanced)
  - Auction: `Pass 1nt 3c 3nt Pass` (Final Contract: **3NT** on a 5-3 heart fit!).
- **Deal 81575 B:2**: Auction `1h 1s 2d 3c 3s 4nt 5h Pass` (Played in **5♥** on an 8-card spade fit).
- **Deal 81580 B:12**: Auction `1c 1h 1s 2c 2d 2h Pass` (Played in **2♥** on an 8-card spade fit).

### Root Cause Analysis
1. **1NT - 2C - 2H - 2NT Continuation**:
   - Responder bids Stayman (`2c`) and rebids `2nt` over opener's `2h`. In standard bridge, this sequence explicitly promises **4 spades** (denying 4 hearts).
   - Opener holding 4-4 in the majors rebid 3NT without checking for a spade fit.
2. **Puppet Stayman Rule in `gavin_1nt_responses.yaml`**:
   - Line 257 has `rule: "10+hcp 4+h ..."` which mistakenly allows hands with **5+ hearts** to bid 3♣ Puppet Stayman instead of transferring with 2♦ Jacoby Transfer!

### Gavin Wolpert Online Continuum & Method
1. **Stayman Major Inference**:
   Over `1NT - 2C - 2H - 2NT`, opener holding 4 spades must bid **4♠** with a maximum (16-17) or **3♠** with a minimum (15). Opener only bids 3NT with 2-3 spades.
2. **Puppet Stayman Scope**:
   Puppet Stayman is only bid when responder does *not* possess a 5-card major (`5-h 5-s`). Hands with 5+ cards in a major always use Jacoby Transfers.

### Recommended Fix
1. In `stayman.yaml` / `gavin_1nt_responses.yaml`:
   - Under `2h` -> `2nt`: Add opener continuations:
     - `4s`: `16-17hcp 4+s` (`priority: 1`)
     - `3s`: `15hcp 4+s` (`priority: 2`)
     - `3nt`: `2-3s` (`priority: 3`)
2. In `gavin_1nt_responses.yaml`:
   - Update 3♣ Puppet Stayman rule: require `5-h 5-s` (at most 4 cards in any major).

---

## 3. Category 5: Overbid Runaway

### Active Deals
- **Deals 82637 B:20 & 82680 B:21**:
  - Opener with only 11 HCP and 5-5 minors opened **4NT** (`rule: "6-11hcp 5+c 5+d"`), resulting in runaway contracts (`5c`).
- **Deals 81570 B:10 & 82045/82046 B:20**:
  - Weak Two opening (`2h` / `2d`) followed by 2NT inquiry. Opener rebid 3-level showing minimum (5-7 HCP), but responder raised to 4M/4D with only 12-14 HCP (18-19 combined HCP).

### Root Cause Analysis
1. **4NT Opening Misdefinition in `preempt_responses.yaml`**:
   - `Preempt4NT` was defined as `rule: "6-11hcp 5+c 5+d"` with `priority: 1`. This hijacked ordinary 1♦ openings for any hand with 5-5 minors and 6-11 HCP!
2. **Weak Two Feature/Ogust Responder Overbid**:
   - In `weak_two_responses.yaml`, responder lacked a ceiling to pass opener's minimum response over 2NT.

### Gavin Wolpert Online Continuum & Method
1. **5-5 Minor Openings**:
   Gavin Wolpert opens 1♦ with 5-5 minors (11-15 HCP). A 4NT opening is reserved for extreme distributions (6-6 or 7-6 minors, preemptive at the 4-level).
2. **Weak Two Inquiries**:
   When opener shows a bad hand / bad suit (minimum 5-7 HCP), responder must **pass** at the 3-level unless holding 16+ HCP.

### Recommended Fix
1. In `preempt_responses.yaml`:
   - Constrain `Preempt4NT`: `rule: "6-11hcp 6+c 6+d 4-ltc | 6-11hcp 7+c 6+d | 6-11hcp 6+c 7+d"`.
2. In `weak_two_responses.yaml`:
   - Over minimum responses (3♣ / 3♦ / 3♥), responder passes with $< 16$ HCP.

---

## 4. Category 1: Forcing Broken / Stalled

### Active Deals
- **Deal 81566 B:15**: Opener with 17 HCP passed responder's 1♥ response holding a heart void (`1d 1h Pass`).
- **Deal 81573 B:4**: Opener with 21 HCP balanced opened 1♠ instead of 2NT, North passed with 4 HCP.
- **Deals 81991, 81992, 81993 B:13**: Both North and South hold 11 HCP with 5-4 distribution and passed out the hand (22 combined HCP).

### Root Cause Analysis & Fixes
1. **1-Level Response Absolute Force**:
   - A 1-level response by an unpassed responder is 100% forcing for one round (F1). In `walsh_minors.yaml`, opener's `pass` must be removed or assigned `priority: 99` with an impossible rule.
2. **2NT Opening Priority**:
   - Permitting 5-card majors in 2NT opening (Category 3 fix) will ensure 21 HCP balanced hands open 2NT rather than 1♠, preventing stallouts.
3. **Rule of 20 Openings**:
   - Ensure `11hcp 5+d 4+c` and `11hcp 5+c 4+d` satisfy the Rule of 20 in 1st and 2nd seats.

---

## 5. Category 4: Slam Stoppages

### Active Deals
- **Deal 81564 B:14**: `1d 1h 2nt 3d 3h 4h Pass` (Stopped at 4♥ with 27 HCP).
- **Deals 81779 & 81780 B:47**: `1d 1h 1s 2d 2s 3nt Pass` (Stopped at 3NT with 30 combined HCP).
- **Deal 81799 B:18**: `1h 1s 3s 4s Pass` (Stopped at 4♠ with 23 HCP, but North has a club void and 4-card spade support).

### Root Cause Analysis & Fixes
1. **30 HCP Stoppages (Deals 81779 & 81780)**:
   - South holds 19 HCP over opener's 2♠ preference/raise. South should initiate Kickback RKCB or cuebid with 3♦/4♦ rather than defaulting to 3NT.
2. **Expectation-Based Void Valuation (Deal 81799)**:
   - With an established spade fit and a club void, North's 15 HCP hand evaluates to 19+ playing strength, triggering RKCB 4NT over 4♠.

---

## Summary of Priority Implementation Sequence

| Phase | Category | Target Files | Key Change |
|:---:|---|---|---|
| **Phase 1** | **Cat 3: Wrong Opening Bid** | `puppet_stayman_2nt.yaml` | Allow 5332 shape (5M) in 2NT opening. |
| **Phase 2** | **Cat 5: Overbid Runaway** | `preempt_responses.yaml`, `weak_two_responses.yaml` | Restrict 4NT opening to 6-6/7-6 minors; cap raises over weak-two minimums. |
| **Phase 3** | **Cat 2: Missed Major Strain** | `gavin_1nt_responses.yaml`, `stayman.yaml` | Add 4♠ over 1NT-2C-2H-2NT with 4-4 majors; restrict Puppet Stayman to 5-h 5-s. |
| **Phase 4** | **Cat 1: Forcing Broken / Stalls** | `walsh_minors.yaml` | Enforce 1-level response F1; ensure Rule of 20 openings in 1st/2nd seats. |
| **Phase 5** | **Cat 4: Slam Stoppages** | `walsh_minors.yaml`, `rkcb_1430.yaml` | Wire Kickback & RKCB paths over 28+ combined HCP agreements. |
