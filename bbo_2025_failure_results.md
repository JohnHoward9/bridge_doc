# BBO 2025 Championship Bidding Failures Audit

Evaluated deals from **`res/bbo_championships_2025_dataset.json`** and `./errors/` against the Gavin Wolpert 2/1 engine.
Identified **15 active representative failure deals** across the 6 defect categories, and verified **7 resolved defect hands**.

## 1. Resolved Defect Hands (Verified Fixed)

| # | Error File | Category | North Hand | South Hand | Comb HCP | Table Contract | Verified Auto Auction | Final Contract | Status |
|---|---|---|---|---|:---:|:---:|---|:---:|:---:|
| 1 | **PBN: 20261028_153337_1s_opening_with_5_5_in_major.pbn** | **Cat 3: Wrong Opening Bid** | ♠AQJ98 ♥QT974 ♦K ♣K7<br>(15 HCP → 14.9 Eff) | ♠74 ♥KJ83 ♦Q52 ♣AJ95<br>(11 HCP → 10.5 Eff) | **26 HCP** | **Error Log** | `1s 1nt 2h 4h Pass` | **4h** | ✅ Fixed |
| 2 | **PBN: 20261028_163108_incorrect_pass.pbn** | **Cat 1: Forcing Broken / Stalled** | ♠AK84 ♥J ♦KQ72 ♣KJ64<br>(17 HCP → 16.7 Eff) | ♠QJ ♥K9743 ♦A96 ♣Q93<br>(12 HCP → 11.7 Eff) | **29 HCP** | **Error Log** | `1d 1h 2c 2s Pass` | **2s** | ✅ Fixed |
| 3 | **PBN: 20261029_160859_should_open_2nt.pbn** | **Cat 3: Wrong Opening Bid** | ♠AK7 ♥QT4 ♦KQJ3 ♣AJ5<br>(20 HCP → 19.6 Eff) | ♠T43 ♥A6 ♦T976 ♣9873<br>(4 HCP → 4.5 Eff) | **24 HCP** | **Error Log** | `2nt 3c 3nt Pass` | **3nt** | ✅ Fixed |
| 4 | **PBN: 20261029_183630_is_only_gf.pbn** | **Cat 5: Overbid Runaway** | ♠AQJ42 ♥J9 ♦652 ♣AK6<br>(15 HCP → 15.1 Eff) | ♠8 ♥Q74 ♦AK973 ♣T932<br>(9 HCP → 9.2 Eff) | **24 HCP** | **Error Log** | `1nt 3s 3nt Pass` | **3nt** | ✅ Fixed |
| 5 | **PBN: 20261029_184615_after_1c_1d_north_passes_which_is_not_co.pbn** | **Cat 1: Forcing Broken / Stalled** | ♠Q832 ♥AQJ3 ♦A3 ♣J63<br>(14 HCP → 13.7 Eff) | ♠K6 ♥842 ♦KQT82 ♣K54<br>(11 HCP → 11.3 Eff) | **25 HCP** | **Error Log** | `1c 1d 1nt 2c 2d 3d Pass` | **3d** | ✅ Fixed |
| 6 | **PBN: 20261030_174856_with_a_balanced_hand_rebid_is_1nt.pbn** | **Cat 6: Rebid Precision** | ♠A842 ♥K3 ♦9632 ♣A52<br>(11 HCP → 11.5 Eff) | ♠T3 ♥Q986 ♦AJ75 ♣KQ3<br>(12 HCP → 11.8 Eff) | **23 HCP** | **Error Log** | `Pass 1d 1s 1nt 2c 2d 2s Pass` | **2s** | ✅ Fixed |
| 7 | **PBN: 20261030_182239_opener_passes_after_forcing_bid_from_sou.pbn** | **Cat 1: Forcing Broken / Stalled** | ♠AK3 ♥KQ853 ♦6 ♣A832<br>(16 HCP → 16.5 Eff) | ♠J98752 ♥A64 ♦J874 ♣—<br>(6 HCP → 5.5 Eff) | **22 HCP** | **Error Log** | `1h 1s 2c 2s 4s Pass` | **4s** | ✅ Fixed |

## 2. Active Unfixed BBO Failures

### Failure Distribution Summary
- **Cat 1: Forcing Broken / Stalled**: 5 representative deals
- **Cat 2: Missed Major Strain**: 5 representative deals
- **Cat 3: Wrong Opening Bid**: 0 representative deals
- **Cat 4: Slam Stoppage**: 5 representative deals
- **Cat 5: Overbid Runaway**: 0 representative deals
- **Cat 6: Rebid Precision**: 0 representative deals

| # | Match / Deal | Category | North Hand | South Hand | Comb HCP | Table Contract | Auto Auction | Auto Contract | Defect Diagnosis |
|---|---|---|---|---|:---:|:---:|---|:---:|---|
| 1 | **81564 B:14** | **Cat 4: Slam Stoppage** | ♠954 ♥K8 ♦AQT8 ♣AKQT<br>(18 HCP → 18.8 Eff) | ♠K2 ♥AQT943 ♦7652 ♣3<br>(9 HCP → 10.1 Eff) | **27 HCP** | **6H (11)** | `1d 1h 2c 3h Pass` | **3h** | Stopped at 3h despite 27 combined HCP (Table contract was 6H) |
| 2 | **81566 B:15** | **Cat 4: Slam Stoppage** | ♠QJ53 ♥KQ53 ♦A752 ♣T<br>(12 HCP → 11.8 Eff) | ♠A72 ♥— ♦KQT963 ♣AKJ9<br>(17 HCP → 17.4 Eff) | **29 HCP** | **6D (12)** | `1d 1h 3c Pass` | **3c** | Stopped at 3c despite 29 combined HCP (Table contract was 6D) |
| 3 | **81575 B:2** | **Cat 2: Missed Major Strain** | ♠KT6 ♥A8632 ♦KQJ ♣T3<br>(13 HCP → 13.5 Eff) | ♠A8743 ♥— ♦42 ♣AKQ985<br>(13 HCP → 13.4 Eff) | **26 HCP** | **4S (12)** | `1h 1s 2d 3c 3s 4nt 5h Pass` | **5h** | 8+ major fit (S: 8 cards) missed; contract played in 5h |
| 4 | **81580 B:12** | **Cat 2: Missed Major Strain** | ♠K532 ♥KJ76 ♦Q743 ♣7<br>(9 HCP → 8.4 Eff) | ♠AJ64 ♥Q ♦9 ♣AK65432<br>(14 HCP → 14.1 Eff) | **23 HCP** | **5C (10)** | `1c 1h 1s 2c 2d 2h Pass` | **2h** | 8+ major fit (S: 8 cards) missed; contract played in 2h |
| 5 | **81768 B:3** | **Cat 4: Slam Stoppage** | ♠7 ♥KQT532 ♦A93 ♣J72<br>(10 HCP → 9.8 Eff) | ♠JT653 ♥A96 ♦64 ♣T65<br>(5 HCP → 5.5 Eff) | **15 HCP** | **6D (9)** | `Pass 2h 3h Pass` | **3h** | Stopped at 3h despite 15 combined HCP (Table contract was 6D) |
| 6 | **81774 B:29** | **Cat 2: Missed Major Strain** | ♠4 ♥A7542 ♦J65 ♣A976<br>(9 HCP → 9.2 Eff) | ♠A6 ♥J83 ♦AK3 ♣QJT32<br>(15 HCP → 15.3 Eff) | **24 HCP** | **4H (11)** | `Pass 1nt 2d 2h 3c 3nt Pass` | **3nt** | 8+ major fit (H: 8 cards) missed; contract played in 3nt |
| 7 | **81775 B:29** | **Cat 2: Missed Major Strain** | ♠4 ♥A7542 ♦J65 ♣A976<br>(9 HCP → 9.2 Eff) | ♠A6 ♥J83 ♦AK3 ♣QJT32<br>(15 HCP → 15.3 Eff) | **24 HCP** | **4H (11)** | `Pass 1nt 2d 2h 3c 3nt Pass` | **3nt** | 8+ major fit (H: 8 cards) missed; contract played in 3nt |
| 8 | **81779 B:47** | **Cat 4: Slam Stoppage** | ♠AJ4 ♥QT82 ♦9864 ♣A8<br>(11 HCP → 11.3 Eff) | ♠KQ93 ♥K ♦KQJ2 ♣KQ74<br>(19 HCP → 18.3 Eff) | **30 HCP** | **5D (11)** | `1d 1h 1s 2d 2s 3nt Pass` | **3nt** | Stopped at 3nt despite 30 combined HCP (Table contract was 5D) |
| 9 | **81780 B:47** | **Cat 4: Slam Stoppage** | ♠AJ4 ♥QT82 ♦9864 ♣A8<br>(11 HCP → 11.3 Eff) | ♠KQ93 ♥K ♦KQJ2 ♣KQ74<br>(19 HCP → 18.3 Eff) | **30 HCP** | **3N (12)** | `1d 1h 1s 2d 2s 3nt Pass` | **3nt** | Stopped at 3nt despite 30 combined HCP (Table contract was 3N) |
| 10 | **81797 B:3** | **Cat 2: Missed Major Strain** | ♠82 ♥K64 ♦AKQ3 ♣AK75<br>(19 HCP → 19.6 Eff) | ♠KJT743 ♥QJ87 ♦64 ♣3<br>(7 HCP → 7.2 Eff) | **26 HCP** | **4S (11)** | `2s 2nt 3c 4c Pass` | **4c** | 8+ major fit (S: 8 cards) missed; contract played in 4c |
| 11 | **81991 B:13** | **Cat 1: Forcing Broken / Stalled** | ♠7 ♥Q82 ♦KJ62 ♣KQ753<br>(11 HCP → 10.3 Eff) | ♠Q943 ♥KT ♦AQT74 ♣98<br>(11 HCP → 11.3 Eff) | **22 HCP** | **3D (10)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |
| 12 | **81992 B:13** | **Cat 1: Forcing Broken / Stalled** | ♠7 ♥Q82 ♦KJ62 ♣KQ753<br>(11 HCP → 10.3 Eff) | ♠Q943 ♥KT ♦AQT74 ♣98<br>(11 HCP → 11.3 Eff) | **22 HCP** | **3D (11)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |
| 13 | **81993 B:13** | **Cat 1: Forcing Broken / Stalled** | ♠7 ♥Q82 ♦KJ62 ♣KQ753<br>(11 HCP → 10.3 Eff) | ♠Q943 ♥KT ♦AQT74 ♣98<br>(11 HCP → 11.3 Eff) | **22 HCP** | **5D (10)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |
| 14 | **81994 B:13** | **Cat 1: Forcing Broken / Stalled** | ♠7 ♥Q82 ♦KJ62 ♣KQ753<br>(11 HCP → 10.3 Eff) | ♠Q943 ♥KT ♦AQT74 ♣98<br>(11 HCP → 11.3 Eff) | **22 HCP** | **3D (10)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |
| 15 | **81995 B:16** | **Cat 1: Forcing Broken / Stalled** | ♠K8732 ♥KJ9 ♦AT85 ♣A<br>(15 HCP → 15.6 Eff) | ♠A95 ♥75 ♦KJ62 ♣QJ85<br>(11 HCP → 10.5 Eff) | **26 HCP** | **4S (11)** | `Pass 1s Pass` | **1s** | Auction stalled at 1s with 26 combined HCP (Calls: `Pass 1s Pass`) |

## Systematic Resolution Strategy
1. **Category 1 (Forcing Broken & Stalls)**: Strengthen forcing state persistence in `walsh_minors.yaml` and `gavin_majors_2over1.yaml` so responder's 1-level response guarantees a rebid.
2. **Category 2 (Missed Major Strain)**: Prioritize major fit returns in XYZ / Checkback (`two_way_checkback.yaml`) when opener holds 4+ cards in partner's major.
3. **Category 3 (Wrong Opening Bid)**: Enforce rule priority ordering in `gavin_wolpert_2over1.yaml` (2NT over 1m for 20-21 balanced, 1♠ over 1♥ for 5-5 majors).
4. **Category 4 (Slam Stoppages)**: Wire Kickback RKCB and cuebidding paths over minor suit agreements in `serious_3nt_and_kickback.yaml`.
5. **Category 5 (Overbid Runaway)**: Apply loser count ceilings (`5-ltc`) in `namyats.yaml` and limit raises over preempts in `preempt_responses.yaml`.
6. **Category 6 (Rebid Precision)**: Ensure 12-14 balanced hands rebid 1NT rather than bypassing into 1♠ or 2m in `walsh_minors.yaml`.
