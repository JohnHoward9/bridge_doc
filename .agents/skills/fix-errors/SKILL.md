---
name: fix-errors
description: >
  Scans ./errors/ for unfixed bridge bidding failure hands, reproduces the defect,
  and creates an actionable plan to fix the bidding conventions and add regression tests.
---

# Fix Errors Skill: Bidding Defect Resolution

Use this skill when the user asks to "fix errors", "plan fix for error hands", or runs `/fix-errors`.

## Procedure

1. **Scan `./errors/` for Unfixed Hands**:
   - Check all `.pbn` files in `./errors/`.
   - Identify hands where `[Fixed "No"]` or `[Fixed "False"]` (or where `[Fixed]` tag is missing).
   - If a specific file or slug is provided in the prompt, focus on that target.

2. **Diagnose with `tools/plan_error_fixes.dart`**:
   - Run:
     ```bash
     dart run tools/plan_error_fixes.dart [optional-file-path]
     ```
   - Review the failure output:
     - Which seat failed to bid?
     - What was the hand holding and distribution?
     - Which candidates were in the graph and why did the rule fail to match?

3. **Formulate the Fix Plan Artifact**:
   - Create an implementation plan artifact `fix_<slug>_plan.md` in `<appDataDir>/brain/<conversation-id>/`:
     - **Hand & Auction Details**: Deal diagram, vulnerability, recorded auction.
     - **Defect Root Cause**: Pinpoint the exact YAML file (e.g. `walsh_minors.yaml`, `rkcb_1430.yaml`, `gavin_majors_2over1.yaml`).
     - **Minimal Working Diff**: The smallest modification that addresses the defect.
     - **Reproduction Test**: Dedicated unit test in `test/` reproducing the exact hand and auction.

4. **Execution & Verification**:
   - Apply the YAML change.
   - Run the reproduction test and full test suite (`flutter test`).
   - When verified, update the hand's status in `./errors/` to `[Fixed "Yes"]`.
