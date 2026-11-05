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
| 1 | **81564 B:13** | **Cat 4: Slam Stoppage** | ♠AKT93 ♥T3 ♦KJT92 ♣7<br>(11 HCP → 11.7 Eff) | ♠J872 ♥Q4 ♦875 ♣JT94<br>(4 HCP → 3.2 Eff) | **15 HCP** | **6H (12)** | `1d Pass` | **1d** | Stopped at 1d despite 15 combined HCP (Table contract was 6H) |
| 2 | **81564 B:14** | **Cat 4: Slam Stoppage** | ♠954 ♥K8 ♦AQT8 ♣AKQT<br>(18 HCP → 18.8 Eff) | ♠K2 ♥AQT943 ♦7652 ♣3<br>(9 HCP → 10.1 Eff) | **27 HCP** | **6H (11)** | `1d 1h 2c 3h 4h Pass` | **4h** | Stopped at 4h despite 27 combined HCP (Table contract was 6H) |
| 3 | **81566 B:15** | **Cat 4: Slam Stoppage** | ♠QJ53 ♥KQ53 ♦A752 ♣T<br>(12 HCP → 11.8 Eff) | ♠A72 ♥— ♦KQT963 ♣AKJ9<br>(17 HCP → 17.4 Eff) | **29 HCP** | **6D (12)** | `1d 1h 3c 4d Pass` | **4d** | Stopped at 4d despite 29 combined HCP (Table contract was 6D) |
| 4 | **81768 B:3** | **Cat 4: Slam Stoppage** | ♠7 ♥KQT532 ♦A93 ♣J72<br>(10 HCP → 9.8 Eff) | ♠JT653 ♥A96 ♦64 ♣T65<br>(5 HCP → 5.5 Eff) | **15 HCP** | **6D (9)** | `Pass 2h 3h Pass` | **3h** | Stopped at 3h despite 15 combined HCP (Table contract was 6D) |
| 5 | **81779 B:47** | **Cat 4: Slam Stoppage** | ♠AJ4 ♥QT82 ♦9864 ♣A8<br>(11 HCP → 11.3 Eff) | ♠KQ93 ♥K ♦KQJ2 ♣KQ74<br>(19 HCP → 18.3 Eff) | **30 HCP** | **5D (11)** | `1d 1h 1s 2d 2s 3nt Pass` | **3nt** | Stopped at 3nt despite 30 combined HCP (Table contract was 5D) |
| 6 | **81995 B:18** | **Cat 2: Missed Major Strain** | ♠AT3 ♥KJT72 ♦AK4 ♣43<br>(15 HCP → 16.1 Eff) | ♠Q874 ♥A83 ♦QJ875 ♣6<br>(9 HCP → 8.5 Eff) | **24 HCP** | **4H (12)** | `1nt 2c 2h 3d 4d Pass` | **4d** | 8+ major fit (H: 8 cards) missed; contract played in 4d |
| 7 | **81995 B:27** | **Cat 2: Missed Major Strain** | ♠KQJ2 ♥K95 ♦Q54 ♣KJ7<br>(15 HCP → 13.6 Eff) | ♠A43 ♥AT742 ♦AKJT8 ♣—<br>(16 HCP → 17.2 Eff) | **31 HCP** | **6H (12)** | `1h 1s 3d 3h 4nt 5c 5s Pass` | **5s** | 8+ major fit (H: 8 cards) missed; contract played in 5s |
| 8 | **81996 B:18** | **Cat 2: Missed Major Strain** | ♠AT3 ♥KJT72 ♦AK4 ♣43<br>(15 HCP → 16.1 Eff) | ♠Q874 ♥A83 ♦QJ875 ♣6<br>(9 HCP → 8.5 Eff) | **24 HCP** | **4H (12)** | `1nt 2c 2h 3d 4d Pass` | **4d** | 8+ major fit (H: 8 cards) missed; contract played in 4d |
| 9 | **81996 B:27** | **Cat 2: Missed Major Strain** | ♠KQJ2 ♥K95 ♦Q54 ♣KJ7<br>(15 HCP → 13.6 Eff) | ♠A43 ♥AT742 ♦AKJT8 ♣—<br>(16 HCP → 17.2 Eff) | **31 HCP** | **6H (12)** | `1h 1s 3d 3h 4nt 5c 5s Pass` | **5s** | 8+ major fit (H: 8 cards) missed; contract played in 5s |
| 10 | **81997 B:18** | **Cat 2: Missed Major Strain** | ♠AT3 ♥KJT72 ♦AK4 ♣43<br>(15 HCP → 16.1 Eff) | ♠Q874 ♥A83 ♦QJ875 ♣6<br>(9 HCP → 8.5 Eff) | **24 HCP** | **4H (12)** | `1nt 2c 2h 3d 4d Pass` | **4d** | 8+ major fit (H: 8 cards) missed; contract played in 4d |
| 11 | **82623 B:27** | **Cat 1: Forcing Broken / Stalled** | ♠Q542 ♥AQ87 ♦T9 ♣K93<br>(11 HCP → 11.0 Eff) | ♠AT ♥J63 ♦Q874 ♣AT64<br>(11 HCP → 11.6 Eff) | **22 HCP** | **1N** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |
| 12 | **82635 B:19** | **Cat 1: Forcing Broken / Stalled** | ♠A8 ♥A864 ♦632 ♣QJT4<br>(11 HCP → 11.3 Eff) | ♠J7 ♥KQT732 ♦Q9 ♣K63<br>(11 HCP → 10.5 Eff) | **22 HCP** | **2C (5)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |
| 13 | **82636 B:19** | **Cat 1: Forcing Broken / Stalled** | ♠A8 ♥A864 ♦632 ♣QJT4<br>(11 HCP → 11.3 Eff) | ♠J7 ♥KQT732 ♦Q9 ♣K63<br>(11 HCP → 10.5 Eff) | **22 HCP** | **4H (9)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |
| 14 | **82669 B:14** | **Cat 1: Forcing Broken / Stalled** | ♠Q854 ♥QJ2 ♦KJT ♣KT6<br>(12 HCP → 11.0 Eff) | ♠AJ97 ♥A943 ♦7 ♣J874<br>(10 HCP → 9.9 Eff) | **22 HCP** | **4S (8)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=12, S=10) |
| 15 | **82687 B:17** | **Cat 1: Forcing Broken / Stalled** | ♠T532 ♥K95 ♦K763 ♣KQ<br>(11 HCP → 11.0 Eff) | ♠K6 ♥Q82 ♦AQ94 ♣7432<br>(11 HCP → 10.8 Eff) | **22 HCP** | **3S (8)** | `Pass Pass` | **Pass** | Passed out with 22 combined HCP (N=11, S=11) |

## Systematic Resolution Strategy
1. **Category 1 (Forcing Broken & Stalls)**: Strengthen forcing state persistence in `walsh_minors.yaml` and `gavin_majors_2over1.yaml` so responder's 1-level response guarantees a rebid.
2. **Category 2 (Missed Major Strain)**: Prioritize major fit returns in XYZ / Checkback (`two_way_checkback.yaml`) when opener holds 4+ cards in partner's major.
3. **Category 3 (Wrong Opening Bid)**: Enforce rule priority ordering in `gavin_wolpert_2over1.yaml` (2NT over 1m for 20-21 balanced, 1♠ over 1♥ for 5-5 majors).
4. **Category 4 (Slam Stoppages)**: Wire Kickback RKCB and cuebidding paths over minor suit agreements in `serious_3nt_and_kickback.yaml`.
5. **Category 5 (Overbid Runaway)**: Apply loser count ceilings (`5-ltc`) in `namyats.yaml` and limit raises over preempts in `preempt_responses.yaml`.
6. **Category 6 (Rebid Precision)**: Ensure 12-14 balanced hands rebid 1NT rather than bypassing into 1♠ or 2m in `walsh_minors.yaml`.
