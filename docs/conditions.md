# Bridge Bidding System (BBS) Condition Specification

In `.bbs` (Bridge Bidding System) files, conditions specified inside parentheses `(...)` define the requirements that a bridge hand must satisfy for a bid to be valid.

---

## 1. `p#<n>` — Evaluation Priority (Candidate Preference)

* **Definition**: Priority rank of the candidate bid during rule evaluation.
* **Mechanism**: Lower numbers represent higher priority (`p#1` is evaluated before `p#2`, which is evaluated before `p#5`, etc.). When a hand satisfies multiple rules in the same bidding state, the highest-priority candidate is selected first.
* **Examples**:
  * `(p#2 16+hcp)`: Priority 2 evaluation with 16+ HCP.
  * `(p#5 10-11hcp)`: Priority 5 evaluation (chosen only if no higher-priority bid applies).

---

## 2. `hcp` — Milton Work High Card Points

* **Definition**: High Card Point count according to the standard Milton Work scale ($A=4, K=3, Q=2, J=1$).
* **Syntaxes**:
  * `16+hcp`: 16 or more HCP (minimum 16).
  * `14-hcp`: 14 or fewer HCP (maximum 14).
  * `15-17hcp`: Between 15 and 17 HCP inclusive.
  * `12hcp`: Exactly 12 HCP.

---

## 3. Suit Length Conditions

* **Syntax**: `<length><operator><suit>` where `<suit>` is:
  * Suit character: `c` (Clubs), `d` (Diamonds), `h` (Hearts), `s` (Spades).
  * Variable: `$M` (Anchor Major), `$OM` (Other Major), `$m` (Anchor Minor), `$om` (Other Minor).
  * Placeholder: `%` (Suit variable in compound bids like `[4c-4d]`).
* **Examples**:
  * `4+$M`: 4 or more cards in the agreed/anchor major suit.
  * `1-c`: 1 or fewer cards in Clubs (singleton or void).
  * `2-$M`: 2 or fewer cards in the major suit.
  * `5+h`: 5 or more Hearts.
  * `6s`: Exactly 6 Spades.
  * `5%`: 5 cards in whichever suit is matched by `%`.

---

## 4. `s#<shape>` — Unordered Hand Distribution

* **Definition**: General hand distribution patterns sorted by suit length regardless of specific suits.
* **Examples**:
  * `s#5332`: Any 5-3-3-2 hand (e.g. 5=3=3=2, 3=5=3=2, 2=3=3=5, etc.).
  * `s#5332|5422`: Either a 5-3-3-2 or a 5-4-2-2 hand pattern.
  * `s#54xx`: Any hand with at least one 5-card suit and one 4-card suit (`x` matches remaining lengths).
  * `s#6xxx`: Any hand with at least one 6-card suit.
  * `!s#4333`: Negated pattern — hand must **not** be 4-3-3-3.

---

## 5. `d#<shape>` — Exact Ordered Suit Distribution ($S \cdot H \cdot D \cdot C$)

* **Definition**: Exact distribution matched in strict **Spades – Hearts – Diamonds – Clubs** suit order.
* **Examples**:
  * `d#1354`: Exactly 1 Spade, 3 Hearts, 5 Diamonds, and 4 Clubs.
  * `d#44xx`: Exactly 4 Spades, 4 Hearts, with any minor distribution.
  * `d#4xx5`: Exactly 4 Spades, 5 Clubs, and any combination of Hearts and Diamonds.

---

## 6. `n#<honors>[suit]` — Named Honors Holding

* **Definition**: Presence of specific high honor cards.
* **Examples**:
  * `n#a|k`: Contains at least an Ace or a King in the suit.
  * `n#a|k%`: Contains an Ace or a King in suit `%`.
  * `n#AK|AQ|KQc`: Contains AK, AQ, or KQ in Clubs (at least two of the top three honors).
  * `n#akq$M`: Contains at least one top honor (A, K, or Q) in `$M`.

---

## 7. `q#<quality>` — Suit Quality / Honor Density

* **Definition**: Concentration of honor cards in a suit (`h` or `H` represents an honor: A, K, or Q).
* **Examples**:
  * `q#h+c` or `q#H+c`: At least 1 honor in Clubs.
  * `q#hh+s` or `q#Hh+s`: At least 2 honors in Spades.
  * `q#hhh+%`: At least 3 honors in suit `%`.
  * `q#hh-$M`: At most 2 honors in major `$M`.
  * `!q#H+$M`: Negated — does **not** hold a top honor in `$M`.

---

## 8. Suit Comparison Operators

* **Definition**: Relative length comparisons between suits.
* **Examples**:
  * `c>=*`: Clubs is the longest or equal-longest suit among all four suits.
  * `d>=*`: Diamonds is the longest or equal-longest suit.
  * `c>=d`: Club length is greater than or equal to Diamond length.
  * `h>=s`: Heart length is greater than or equal to Spade length.
  * `d>c`: Diamond length is strictly greater than Club length.

---

## 9. Delimiters, Operators, and Control Syntax

| Token | Meaning | Example |
| :--- | :--- | :--- |
| **`knr`** | Kaplan-Rubens hand evaluation metric | `27+knr` |
| **`,` (comma)** | Logical **OR** between alternative rules | `p#6 2+c $weakbal, 4+c 12+hcp` |
| **Space** | Logical **AND** between conditions | `1-c 15+hcp` (short clubs **and** 15+ HCP) |
| **`!`** | Logical **NOT** (negation) | `!$bal`, `!q#H+$M` |
| **`?<n>`** | Ambiguity / Step level marker at end of declaration | `?1`, `?2` |
| **`<$M=h>`** | Inline variable branch filter condition | `<$M=h> [3s,4c,4d]` (active only when `$M` is Hearts) |
| **`[$M=h, $OM=s]`** | Variable binding / assignment | Binds `$M=h` and `$OM=s` for downstream nodes |
| **`$name`** | Macro reference defined in `BidDefinitions [...]` | `$bal` (`s#5332\|4432\|4333`), `$weakbal` |
| **`->fName`** | Subroutine / fragment reference | `->fMultiLandy` |
| **`~>`** | Inline conditional continuation router | `~>"Support" (3s)` |
