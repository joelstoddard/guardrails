---
description: Run the lint + tests documented in the repo's agent doc, plus a security sweep, continue through failures, print one READY/NOT-READY summary.
---

# Pre-PR check

Run the current repo's checks on demand. Commands come from the "Commands" section of
the repo's `AGENTS.md`, or `CLAUDE.md` where a repo uses that name; this command does
not assume a toolchain.

## Steps

1. Resolve the repo root (`git rev-parse --show-toplevel`) and read its `AGENTS.md`,
   falling back to `CLAUDE.md`. `AGENTS.md` wins where a repo has both.
2. Find the **Test** and **Lint** commands in the "Commands" section. If either is **not
   documented**, spawn a sub-agent to answer "how is this repo tested / linted?" — it
   inspects the repo's real signals (package.json scripts, Makefile/justfile targets,
   pyproject/tox, CI workflows) and proposes the command. Use its answer for this run and
   offer to record it in that agent doc (following the repo's existing patterns — do not invent
   a format). This lives here, not in the hooks: a synchronous `PreToolUse` hook can't
   spawn a sub-agent, but this on-demand command runs in an agent context and can.
3. Run **Lint**, then **Test**. Do NOT stop at the first failure — run both so the user
   sees the full picture in one pass. Capture pass/fail and key output for each.
4. **Security sweep.** Inspect what this PR would actually publish — the diff against the
   base branch and the new commits' contents (`git log -p <base>..HEAD`) — and ask:
   - Does the history or diff contain **credentials or secrets**? (API keys, tokens,
     passwords, `.env` values, private keys, connection strings.)
   - Does it contain **PII or internal identifiers** that shouldn't be public? (personal or
     work email addresses, employee names, internal hostnames/URLs, customer data.)
   - If this repo is public or promotable, would any of the above be a problem once pushed?

   Report every hit with its `file:line`. Do NOT auto-remove — surface it for a decision
   (a leak already in pushed history needs a rewrite/scrub, not just a new commit).
5. Print one summary:

   | Step     | Status |
   |----------|--------|
   | Lint     | <PASS / FAIL: n findings / NOT DOCUMENTED> |
   | Test     | <PASS / FAIL: n failures / NOT DOCUMENTED> |
   | Security | <CLEAN / REVIEW: n items> |

   **Overall: READY** (all documented checks pass and the security sweep is clean) **/ NOT
   READY** (any failure, or a security item to review).

## Notes

- This is the heavy, on-demand check. The commit/push hooks stay light: commits are only
  blocked on the default branch; pushes are blocked on failing tests.
