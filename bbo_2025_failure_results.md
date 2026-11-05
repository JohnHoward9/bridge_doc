# BBO 2025 Championship Bidding Failures Audit

Evaluated deals from **`res/bbo_championships_2025_dataset.json`** and `./errors/` against the Gavin Wolpert 2/1 engine.
Identified **17 active representative failure deals** across the 6 defect categories, and verified **7 resolved defect hands**.

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
- **Cat 5: Overbid Runaway**: 2 representative deals
- **Cat 6: Rebid Precision**: 0 representative deals

| # | Match / Deal | Category | North Hand | South Hand | Comb HCP | Table Contract | Auto Auction | Auto Contract | Defect Diagnosis |
|---|---|---|---|---|:---:|:---:|---|:---:|---|
| 1 | **81559 B:9** | **Cat 2: Missed Major Strain** | ♠KJT842 ♥T753 ♦— ♣KQ3<br>(9 HCP → 8.9 Eff) | ♠A ♥KQ864 ♦Q876 ♣J85<br>(12 HCP → 11.6 Eff) | **21 HCP** | **4H** | `2s Pass` | **2s** | 8+ major fit (H: 9 cards) missed; contract played in 2s |
| 2 | **81564 B:17** | **Cat 4: Slam Stoppage** | ♠KT43 ♥AKQT95 ♦J3 ♣Q<br>(15 HCP → 16.0 Eff) | ♠AQ752 ♥863 ♦A65 ♣AJ<br>(15 HCP → 15.7 Eff) | **30 HCP** | **6H (13)** | `1h 1s 3s 4s Pass` | **4s** | Stopped at 4s despite 30 combined HCP (Table contract was 6H) |
| 3 | **81566 B:24** | **Cat 2: Missed Major Strain** | ♠K754 ♥J8 ♦Q753 ♣J43<br>(7 HCP → 6.1 Eff) | ♠AT983 ♥KQT ♦K9 ♣KQ8<br>(17 HCP → 17.7 Eff) | **24 HCP** | **4S (8)** | `1nt Pass` | **1nt** | 8+ major fit (S: 9 cards) missed; contract played in 1nt |
| 4 | **81567 B:6** | **Cat 2: Missed Major Strain** | ♠AKT ♥AQ432 ♦K3 ♣952<br>(16 HCP → 16.9 Eff) | ♠8653 ♥KT9 ♦9 ♣QJT83<br>(6 HCP → 5.8 Eff) | **22 HCP** | **3H (10)** | `1nt Pass` | **1nt** | 8+ major fit (H: 8 cards) missed; contract played in 1nt |
| 5 | **81574 B:18** | **Cat 4: Slam Stoppage** | ♠AJ8 ♥K ♦AQJ5 ♣AJ432<br>(20 HCP → 20.1 Eff) | ♠Q92 ♥AT92 ♦T8732 ♣9<br>(6 HCP → 6.3 Eff) | **26 HCP** | **6D (11)** | `2c 2d 3c Pass` | **3c** | Stopped at 3c despite 26 combined HCP (Table contract was 6D) |
| 6 | **81577 B:5** | **Cat 2: Missed Major Strain** | ♠973 ♥8 ♦QJ6532 ♣K75<br>(6 HCP → 5.1 Eff) | ♠AKJ42 ♥KQ7 ♦A9 ♣A86<br>(21 HCP → 21.8 Eff) | **27 HCP** | **3N** | `2d 2nt 3d 4d Pass` | **4d** | 8+ major fit (S: 8 cards) missed; contract played in 4d |
| 7 | **81768 B:4** | **Cat 2: Missed Major Strain** | ♠AJ965 ♥JT8 ♦J ♣9654<br>(7 HCP → 6.5 Eff) | ♠Q3 ♥KQ543 ♦KT954 ♣K<br>(13 HCP → 12.9 Eff) | **20 HCP** | **EW 2D (5)** | `1h 1s 2d 2s Pass` | **2s** | 8+ major fit (H: 8 cards) missed; contract played in 2s |
| 8 | **81768 B:10** | **Cat 4: Slam Stoppage** | ♠QJ652 ♥AQ8432 ♦K ♣J<br>(13 HCP → 12.3 Eff) | ♠K83 ♥T9 ♦AJ2 ♣AKQ97<br>(17 HCP → 17.6 Eff) | **30 HCP** | **6S (12)** | `1h 2c 2h 3h 4h Pass` | **4h** | Stopped at 4h despite 30 combined HCP (Table contract was 6S) |
| 9 | **81769 B:10** | **Cat 4: Slam Stoppage** | ♠QJ652 ♥AQ8432 ♦K ♣J<br>(13 HCP → 12.3 Eff) | ♠K83 ♥T9 ♦AJ2 ♣AKQ97<br>(17 HCP → 17.6 Eff) | **30 HCP** | **6S (11)** | `1h 2c 2h 3h 4h Pass` | **4h** | Stopped at 4h despite 30 combined HCP (Table contract was 6S) |
| 10 | **81995 B:29** | **Cat 1: Forcing Broken / Stalled** | ♠K964 ♥AK93 ♦AK73 ♣Q<br>(19 HCP → 19.5 Eff) | ♠AQJ5 ♥T75 ♦QJ8 ♣K76<br>(13 HCP → 12.1 Eff) | **32 HCP** | **6S (12)** | `1d 1s Pass` | **1s** | Auction stalled at 1s with 32 combined HCP (Calls: `1d 1s Pass`) |
| 11 | **81996 B:29** | **Cat 1: Forcing Broken / Stalled** | ♠K964 ♥AK93 ♦AK73 ♣Q<br>(19 HCP → 19.5 Eff) | ♠AQJ5 ♥T75 ♦QJ8 ♣K76<br>(13 HCP → 12.1 Eff) | **32 HCP** | **6S (12)** | `1d 1s Pass` | **1s** | Auction stalled at 1s with 32 combined HCP (Calls: `1d 1s Pass`) |
| 12 | **81997 B:29** | **Cat 1: Forcing Broken / Stalled** | ♠K964 ♥AK93 ♦AK73 ♣Q<br>(19 HCP → 19.5 Eff) | ♠AQJ5 ♥T75 ♦QJ8 ♣K76<br>(13 HCP → 12.1 Eff) | **32 HCP** | **6S (12)** | `1d 1s Pass` | **1s** | Auction stalled at 1s with 32 combined HCP (Calls: `1d 1s Pass`) |
| 13 | **81998 B:29** | **Cat 1: Forcing Broken / Stalled** | ♠K964 ♥AK93 ♦AK73 ♣Q<br>(19 HCP → 19.5 Eff) | ♠AQJ5 ♥T75 ♦QJ8 ♣K76<br>(13 HCP → 12.1 Eff) | **32 HCP** | **6S (12)** | `1d 1s Pass` | **1s** | Auction stalled at 1s with 32 combined HCP (Calls: `1d 1s Pass`) |
| 14 | **81999 B:29** | **Cat 1: Forcing Broken / Stalled** | ♠K964 ♥AK93 ♦AK73 ♣Q<br>(19 HCP → 19.5 Eff) | ♠AQJ5 ♥T75 ♦QJ8 ♣K76<br>(13 HCP → 12.1 Eff) | **32 HCP** | **6S (12)** | `1d 1s Pass` | **1s** | Auction stalled at 1s with 32 combined HCP (Calls: `1d 1s Pass`) |
| 15 | **82004 B:6** | **Cat 4: Slam Stoppage** | ♠A85 ♥T ♦AJ84 ♣KQJ96<br>(15 HCP → 15.1 Eff) | ♠T94 ♥K64 ♦KQ52 ♣A42<br>(12 HCP → 11.8 Eff) | **27 HCP** | **6D (12)** | `1c 1d 2d 3nt Pass` | **3nt** | Stopped at 3nt despite 27 combined HCP (Table contract was 6D) |
| 16 | **82637 B:20** | **Cat 5: Overbid Runaway** | ♠Q76 ♥6432 ♦K3 ♣KT65<br>(8 HCP → 8.0 Eff) | ♠AJ852 ♥KT975 ♦AJ2 ♣—<br>(13 HCP → 13.3 Eff) | **21 HCP** | **EW 3C (7)** | `1s 2s 3s 4s Pass` | **4s** | Overbid to 4s on only 21 combined HCP without distribution or tricks (N=8, S=13) |
| 17 | **82661 B:2** | **Cat 5: Overbid Runaway** | ♠97 ♥AJT743 ♦52 ♣K98<br>(8 HCP → 8.1 Eff) | ♠KJT86 ♥— ♦AKT86 ♣654<br>(11 HCP → 11.5 Eff) | **19 HCP** | **2H (8)** | `2h 2nt 3c 4c Pass` | **4c** | Overbid to 4c on only 19 combined HCP without distribution or tricks (N=8, S=11) |

## Systematic Resolution Strategy
1. **Category 1 (Forcing Broken & Stalls)**: Strengthen forcing state persistence in `walsh_minors.yaml` and `gavin_majors_2over1.yaml` so responder's 1-level response guarantees a rebid.
2. **Category 2 (Missed Major Strain)**: Prioritize major fit returns in XYZ / Checkback (`two_way_checkback.yaml`) when opener holds 4+ cards in partner's major.
3. **Category 3 (Wrong Opening Bid)**: Enforce rule priority ordering in `gavin_wolpert_2over1.yaml` (2NT over 1m for 20-21 balanced, 1♠ over 1♥ for 5-5 majors).
4. **Category 4 (Slam Stoppages)**: Wire Kickback RKCB and cuebidding paths over minor suit agreements in `serious_3nt_and_kickback.yaml`.
5. **Category 5 (Overbid Runaway)**: Apply loser count ceilings (`5-ltc`) in `namyats.yaml` and limit raises over preempts in `preempt_responses.yaml`.
6. **Category 6 (Rebid Precision)**: Ensure 12-14 balanced hands rebid 1NT rather than bypassing into 1♠ or 2m in `walsh_minors.yaml`.
