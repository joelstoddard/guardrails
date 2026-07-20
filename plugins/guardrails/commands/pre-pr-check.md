---
description: Run the repo's AGENTS.md-documented lint + tests, continue through failures, print one READY/NOT-READY summary.
---

# Pre-PR check

Run the current repo's checks on demand. Commands come from the repo's `AGENTS.md`
"Commands" section (the single source of truth); this command does not assume a toolchain.

## Steps

1. Resolve the repo root (`git rev-parse --show-toplevel`) and read its `AGENTS.md`.
2. Find the **Test** and **Lint** commands in the "Commands" section. If either is
   missing, note it in the summary and offer to help document it (following the repo's
   existing patterns — do not invent a format).
3. Run **Lint**, then **Test**. Do NOT stop at the first failure — run both so the user
   sees the full picture in one pass. Capture pass/fail and key output for each.
4. Print one summary:

   | Step | Status |
   |------|--------|
   | Lint | <PASS / FAIL: n findings / NOT DOCUMENTED> |
   | Test | <PASS / FAIL: n failures / NOT DOCUMENTED> |

   **Overall: READY** (all documented checks pass) **/ NOT READY** (any failure).

## Notes

- This is the heavy, on-demand check. The commit/push hooks stay light: commits are only
  blocked on the default branch; pushes are blocked on failing tests.
