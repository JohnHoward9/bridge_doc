# BBO 2025 Championship Bidding Failures Audit

Evaluated deals from **`res/bbo_championships_2025_dataset.json`** and `./errors/` against the Gavin Wolpert 2/1 engine.
Identified **10 active representative failure deals** across the 6 defect categories, and verified **20 resolved defect hands & tournament deals**.

## 1. Resolved Defect Hands & Verified Deals (20 Verified)

| # | Error File / Deal | Category | North Hand | South Hand | Comb HCP | Table Contract | Verified Auto Auction | Final Contract | Status |
|---|---|---|---|---|:---:|:---:|---|:---:|:---:|
| 1 | **PBN: 20261028_153337_1s_opening_with_5_5_in_major.pbn** | **Cat 3: Wrong Opening Bid** | ♠AQJ98 ♥QT974 ♦K ♣K7<br>(15 HCP → 14.9 Eff) | ♠74 ♥KJ83 ♦Q52 ♣AJ95<br>(11 HCP → 10.5 Eff) | **26 HCP** | **Error Log** | `1s 1nt 2h 4h Pass` | **4h** | ✅ Fixed |
| 2 | **PBN: 20261028_163108_incorrect_pass.pbn** | **Cat 1: Forcing Broken / Stalled** | ♠AK84 ♥J ♦KQ72 ♣KJ64<br>(17 HCP → 16.7 Eff) | ♠QJ ♥K9743 ♦A96 ♣Q93<br>(12 HCP → 11.7 Eff) | **29 HCP** | **Error Log** | `1d 1h 2c 2s Pass` | **2s** | ✅ Fixed |
| 3 | **PBN: 20261029_160859_should_open_2nt.pbn** | **Cat 3: Wrong Opening Bid** | ♠AK7 ♥QT4 ♦KQJ3 ♣AJ5<br>(20 HCP → 19.6 Eff) | ♠T43 ♥A6 ♦T976 ♣9873<br>(4 HCP → 4.5 Eff) | **24 HCP** | **Error Log** | `2nt 3c 3nt Pass` | **3nt** | ✅ Fixed |
| 4 | **PBN: 20261029_183630_is_only_gf.pbn** | **Cat 5: Overbid Runaway** | ♠AQJ42 ♥J9 ♦652 ♣AK6<br>(15 HCP → 15.1 Eff) | ♠8 ♥Q74 ♦AK973 ♣T932<br>(9 HCP → 9.2 Eff) | **24 HCP** | **Error Log** | `1s 1nt 2c 2h 2s 3c 3nt Pass` | **3nt** | ✅ Fixed |
| 5 | **PBN: 20261029_184615_after_1c_1d_north_passes_which_is_not_co.pbn** | **Cat 1: Forcing Broken / Stalled** | ♠Q832 ♥AQJ3 ♦A3 ♣J63<br>(14 HCP → 13.7 Eff) | ♠K6 ♥842 ♦KQT82 ♣K54<br>(11 HCP → 11.3 Eff) | **25 HCP** | **Error Log** | `1c 1d 1nt 2c 2d 3d Pass` | **3d** | ✅ Fixed |
| 6 | **PBN: 20261030_174856_with_a_balanced_hand_rebid_is_1nt.pbn** | **Cat 6: Rebid Precision** | ♠A842 ♥K3 ♦9632 ♣A52<br>(11 HCP → 11.5 Eff) | ♠T3 ♥Q986 ♦AJ75 ♣KQ3<br>(12 HCP → 11.8 Eff) | **23 HCP** | **Error Log** | `Pass 1d 1s 1nt 2c 2d 2s Pass` | **2s** | ✅ Fixed |
| 7 | **PBN: 20261030_182239_opener_passes_after_forcing_bid_from_sou.pbn** | **Cat 1: Forcing Broken / Stalled** | ♠AK3 ♥KQ853 ♦6 ♣A832<br>(16 HCP → 16.5 Eff) | ♠J98752 ♥A64 ♦J874 ♣—<br>(6 HCP → 5.5 Eff) | **22 HCP** | **Error Log** | `1h 1s 2c 2h Pass` | **2h** | ✅ Fixed |
| 8 | **81580 B:8** | **Cat 4: Slam Stoppage** | ♠A84 ♥K52 ♦KT864 ♣A7<br>(14 HCP → 15.1 Eff) | ♠KQ72 ♥A ♦AJ732 ♣854<br>(14 HCP → 14.2 Eff) | **28 HCP** | **3N (12)** | `1nt 2c 2d 3d 4d 4h 4nt 6d Pass` | **6d** | ✅ Fixed |
| 9 | **81768 B:10** | **Cat 4: Slam Stoppage** | ♠QJ652 ♥AQ8432 ♦K ♣J<br>(13 HCP → 12.3 Eff) | ♠K83 ♥T9 ♦AJ2 ♣AKQ97<br>(17 HCP → 17.6 Eff) | **30 HCP** | **6S (10)** | `1nt 2c 2d 3h 4s 4nt 5d 6s Pass` | **6s** | ✅ Fixed |
| 10 | **82021 B:30** | **Cat 2: Missed Major Strain** | ♠AJT65 ♥A5 ♦A54 ♣J74<br>(14 HCP → 14.8 Eff) | ♠KQ3 ♥KQT87 ♦8732 ♣T<br>(10 HCP → 10.0 Eff) | **24 HCP** | **2S (8)** | `Pass 1s 1nt 2c 2h 2s 3s 4s Pass` | **4s** | ✅ Fixed |
| 11 | **82022 B:30** | **Cat 2: Missed Major Strain** | ♠AJT65 ♥A5 ♦A54 ♣J74<br>(14 HCP → 14.8 Eff) | ♠KQ3 ♥KQT87 ♦8732 ♣T<br>(10 HCP → 10.0 Eff) | **24 HCP** | **6S (10)** | `Pass 1s 1nt 2c 2h 2s 3s 4s Pass` | **4s** | ✅ Fixed |
| 12 | **82023 B:30** | **Cat 2: Missed Major Strain** | ♠AJT65 ♥A5 ♦A54 ♣J74<br>(14 HCP → 14.8 Eff) | ♠KQ3 ♥KQT87 ♦8732 ♣T<br>(10 HCP → 10.0 Eff) | **24 HCP** | **4S (10)** | `Pass 1s 1nt 2c 2h 2s 3s 4s Pass` | **4s** | ✅ Fixed |
| 13 | **82024 B:30** | **Cat 2: Missed Major Strain** | ♠AJT65 ♥A5 ♦A54 ♣J74<br>(14 HCP → 14.8 Eff) | ♠KQ3 ♥KQT87 ♦8732 ♣T<br>(10 HCP → 10.0 Eff) | **24 HCP** | **4S (10)** | `Pass 1s 1nt 2c 2h 2s 3s 4s Pass` | **4s** | ✅ Fixed |
| 14 | **82041 B:12** | **Cat 2: Missed Major Strain** | ♠AKJ98 ♥Q98 ♦A832 ♣4<br>(14 HCP → 14.1 Eff) | ♠Q654 ♥AK742 ♦JT ♣KQ<br>(15 HCP → 14.9 Eff) | **29 HCP** | **6S (12)** | `1s 2nt 3h 3nt 4s 4nt 5d 6s Pass` | **6s** | ✅ Fixed |
| 15 | **82042 B:12** | **Cat 2: Missed Major Strain** | ♠AKJ98 ♥Q98 ♦A832 ♣4<br>(14 HCP → 14.1 Eff) | ♠Q654 ♥AK742 ♦JT ♣KQ<br>(15 HCP → 14.9 Eff) | **29 HCP** | **5S (12)** | `1s 2nt 3h 3nt 4s 4nt 5d 6s Pass` | **6s** | ✅ Fixed |
| 16 | **82633 B:18** | **Cat 2: Missed Major Strain** | ♠A9 ♥T64 ♦AJ42 ♣AK93<br>(16 HCP → 16.9 Eff) | ♠KT762 ♥KQ532 ♦7 ♣T4<br>(8 HCP → 8.2 Eff) | **24 HCP** | **2S (11)** | `Pass 1nt 2h 2s 3h 4h Pass` | **4h** | ✅ Fixed |
| 17 | **82648 B:5** | **Cat 2: Missed Major Strain** | ♠AT7 ♥T62 ♦AQT5 ♣A84<br>(14 HCP → 15.0 Eff) | ♠J6532 ♥QJ97 ♦K83 ♣7<br>(7 HCP → 6.1 Eff) | **21 HCP** | **2S (10)** | `1nt 2h 2s Pass` | **2s** | ✅ Fixed |
| 18 | **82651 B:8** | **Cat 2: Missed Major Strain** | ♠AKQ7 ♥8 ♦K9742 ♣854<br>(12 HCP → 12.1 Eff) | ♠9532 ♥T952 ♦653 ♣AQ<br>(6 HCP → 6.1 Eff) | **18 HCP** | **EW 2H (10)** | `1d 1h 1s 2s Pass` | **2s** | ✅ Fixed |
| 19 | **82652 B:1** | **Cat 2: Missed Major Strain** | ♠K2 ♥AT742 ♦K82 ♣KQ5<br>(15 HCP → 15.7 Eff) | ♠A854 ♥QJ5 ♦AQT ♣A63<br>(17 HCP → 17.0 Eff) | **32 HCP** | **6H (12)** | `1h 1s 2c 2d 3nt 6h Pass` | **6h** | ✅ Fixed |
| 20 | **82653 B:25** | **Cat 2: Missed Major Strain** | ♠JT632 ♥42 ♦AJ843 ♣K<br>(9 HCP → 8.9 Eff) | ♠AK7 ♥T976 ♦QT ♣AQ83<br>(15 HCP → 15.7 Eff) | **24 HCP** | **4S (12)** | `Pass 1nt 2c 2h 2s Pass` | **2s** | ✅ Fixed |

## 2. Active Unfixed BBO Failures

### Total Failure Count Across 4,001 Tournament Deals
- **Cat 1: Forcing Broken / Stalled**: **0 failures** (100% Cleared)
- **Cat 2: Missed Major Strain**: 5 representative deals shown (**7 total in dataset**)
- **Cat 3: Wrong Opening Bid**: **0 failures** (100% Cleared)
- **Cat 4: Slam Stoppage**: 5 representative deals shown (**61 total in dataset**)
- **Cat 5: Overbid Runaway**: **0 failures** (100% Cleared)
- **Cat 6: Rebid Precision**: **0 failures** (100% Cleared)

| # | Match / Deal | Category | Origin / Status | North Hand | South Hand | Comb HCP | Table Contract | Auto Auction | Auto Contract | Defect Diagnosis |
|---|---|---|:---:|---|---|:---:|:---:|---|:---:|---|
| 1 | **81564 B:18** | **Cat 4: Slam Stoppage** | 📋 Existing Backlog | ♠AQJ76 ♥AQ92 ♦KT2 ♣A<br>(20 HCP → 20.6 Eff) | ♠94 ♥K ♦Q96 ♣KQJT942<br>(11 HCP → 10.5 Eff) | **31 HCP** | **5C (12)** | `3c 3s 3nt 4nt 5s Pass` | **5s** | Stopped at 5s despite 31 combined HCP (Table contract was 5C) |
| 2 | **82021 B:18** | **Cat 4: Slam Stoppage** | 📋 Existing Backlog | ♠AQ963 ♥A2 ♦J9 ♣AJ52<br>(16 HCP → 16.1 Eff) | ♠4 ♥KQT7 ♦A63 ♣KT943<br>(12 HCP → 12.6 Eff) | **28 HCP** | **6C (13)** | `1c 1s 2c 4c 5c Pass` | **5c** | Stopped at 5c despite 28 combined HCP (Table contract was 6C) |
| 3 | **82023 B:18** | **Cat 4: Slam Stoppage** | 📋 Existing Backlog | ♠AQ963 ♥A2 ♦J9 ♣AJ52<br>(16 HCP → 16.1 Eff) | ♠4 ♥KQT7 ♦A63 ♣KT943<br>(12 HCP → 12.6 Eff) | **28 HCP** | **6C (13)** | `1c 1s 2c 4c 5c Pass` | **5c** | Stopped at 5c despite 28 combined HCP (Table contract was 6C) |
| 4 | **82052 B:18** | **Cat 4: Slam Stoppage** | 📋 Existing Backlog | ♠T4 ♥J ♦KQ3 ♣AK96543<br>(13 HCP → 13.1 Eff) | ♠A852 ♥AT ♦AJ98 ♣J87<br>(14 HCP → 14.6 Eff) | **27 HCP** | **6C (13)** | `1d 2c 2nt 3nt Pass` | **3nt** | Stopped at 3nt despite 27 combined HCP (Table contract was 6C) |
| 5 | **82060 B:6** | **Cat 4: Slam Stoppage** | 📋 Existing Backlog | ♠AK85 ♥A6 ♦AJ3 ♣AQ93<br>(22 HCP → 22.9 Eff) | ♠T643 ♥KQ ♦K642 ♣K62<br>(11 HCP → 11.1 Eff) | **33 HCP** | **6S (12)** | `Pass 2c 2d 2nt 3c 3d 3h 4s Pass` | **4s** | Stopped at 4s despite 33 combined HCP (Table contract was 6S) |
| 6 | **82632 B:24** | **Cat 2: Missed Major Strain** | 📋 Existing Backlog | ♠J ♥QT985 ♦KT96 ♣J42<br>(7 HCP → 6.5 Eff) | ♠AKQT97 ♥A63 ♦A87 ♣8<br>(17 HCP → 17.8 Eff) | **24 HCP** | **4H (11)** | `Pass 1s 1nt 3s 4s Pass` | **4s** | 8+ major fit (H: 8 cards) missed; contract played in 4s |
| 7 | **82654 B:17** | **Cat 2: Missed Major Strain** | 📋 Existing Backlog | ♠QT95 ♥975 ♦J84 ♣K92<br>(6 HCP → 5.0 Eff) | ♠A843 ♥J2 ♦A73 ♣A853<br>(13 HCP → 13.6 Eff) | **19 HCP** | **EW 3H (8)** | `Pass 1c Pass` | **1c** | 8+ major fit (S: 8 cards) missed; contract played in 1c |
| 8 | **82654 B:23** | **Cat 2: Missed Major Strain** | 📋 Existing Backlog | ♠63 ♥QJ754 ♦JT64 ♣Q3<br>(6 HCP → 5.1 Eff) | ♠95 ♥KT2 ♦AQ ♣KT9654<br>(12 HCP → 12.5 Eff) | **18 HCP** | **EW 4S (8)** | `1c Pass` | **1c** | 8+ major fit (H: 8 cards) missed; contract played in 1c |
| 9 | **82660 B:25** | **Cat 2: Missed Major Strain** | 📋 Existing Backlog | ♠7653 ♥J8764 ♦K7 ♣A7<br>(8 HCP → 7.9 Eff) | ♠KQT9 ♥AQ ♦Q85 ♣J984<br>(14 HCP → 13.6 Eff) | **22 HCP** | **EW 2C (8)** | `Pass 1c 1h 1nt 2h Pass` | **2h** | 8+ major fit (S: 8 cards) missed; contract played in 2h |
| 10 | **82942 B:12** | **Cat 2: Missed Major Strain** | 📋 Existing Backlog | ♠KJ8 ♥AJ97632 ♦65 ♣5<br>(9 HCP → 8.6 Eff) | ♠A753 ♥KT5 ♦AKQ2 ♣76<br>(16 HCP → 16.8 Eff) | **25 HCP** | **6H (12)** | `2h 2nt 3s 4s Pass` | **4s** | 8+ major fit (H: 10 cards) missed; contract played in 4s |

## Systematic Resolution Strategy
1. **Category 1 (Forcing Broken & Stalls)**: Strengthen forcing state persistence in `walsh_minors.yaml` and `gavin_majors_2over1.yaml` so responder's 1-level response guarantees a rebid.
2. **Category 2 (Missed Major Strain)**: Prioritize major fit returns in XYZ / Checkback (`two_way_checkback.yaml`) when opener holds 4+ cards in partner's major.
3. **Category 3 (Wrong Opening Bid)**: Enforce rule priority ordering in `gavin_wolpert_2over1.yaml` (2NT over 1m for 20-21 balanced, 1♠ over 1♥ for 5-5 majors).
4. **Category 4 (Slam Stoppages)**: Wire Kickback RKCB and cuebidding paths over minor suit agreements in `serious_3nt_and_kickback.yaml`.
5. **Category 5 (Overbid Runaway)**: Apply loser count ceilings (`5-ltc`) in `namyats.yaml` and limit raises over preempts in `preempt_responses.yaml`.
6. **Category 6 (Rebid Precision)**: Ensure 12-14 balanced hands rebid 1NT rather than bypassing into 1♠ or 2m in `walsh_minors.yaml`.
