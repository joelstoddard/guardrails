---
name: biases
description: Counter reasoning biases when investigating, debugging, or searching a codebase or history. Follow this skill when looking for every instance of a pattern, diagnosing an incident, judging a past decision, or answering "has this happened before" — anywhere a partial sample could pass for the whole population.
---

## The protocol

Three steps, before any conclusion:

1. **Name the population.** Say what the complete set is — "every call site in
   the repo", "every deploy since the service launched". Not "the recent ones",
   not "the ones I found".
2. **Search all of it, and report the count.** The count comes before reading
   any individual hit. Nine hits when you assumed three changes the answer.
3. **Then sample, and say so.** Reading 5 of 40 is fine. Presenting 5 of 40 as
   if it were 40 is not.

The failure this prevents: reaching for `git log -20` or "the last few days"
when the question was whether something has *ever* happened, then answering
with total confidence from a sample chosen by recency.

## A self-inflicted example

Checking whether a repo tracked a global git-ignore file, an earlier session ran:

    grep -rn "claude/worktrees" --include='ignore' . | grep -v worktrees/

The second `grep -v` filtered out the only matching line, because that line
contained the search term itself. Empty result, read as an answer — "no
git-ignore config is tracked." Wrong: `.config/git/ignore` was tracked all
along. An empty or surprisingly small result is evidence about the query
first, and about the codebase only second.

| Bias | How it shows up | Rule |
|---|---|---|
| Recency | `git log -20` when the question is "has this ever happened" | Search the full range, then narrow |
| Selection | Reading the first 3 of 40 grep hits | Count first, then sample deliberately |
| Confirmation | Only searching for what confirms the hypothesis | Search for disconfirming evidence explicitly |
| Availability | First plausible cause becomes the answer | Enumerate at least two candidates before choosing |
| Outcome | Judging a past decision by how it turned out | Judge on what was knowable at the time |
| Survivorship | "Nothing in the logs" read as "it didn't happen" | Ask what would not have been logged |
| Anchoring | The first file read frames the whole investigation | State the frame, then deliberately look outside it |

## Red flags — stop and re-check

| Thought | Reality |
|---|---|
| "The recent ones are representative" | That is the assumption under test, not a finding. Search the full range. |
| "The first few hits tell the story" | You do not know that until you know how many there are. Count first. |
| "This is obviously the cause" | Name a second candidate and say why it loses. If you cannot, you have not diagnosed it. |
| "Nothing in the logs, so it did not happen" | Ask what would not have been logged. |
| "They should have seen it coming" | Judge on what was knowable then, not on how it turned out. |
| "I already know where this lives" | That is an anchor. Confirm it, cheaply, before building on it. |
| "A full search is too slow" | A wrong answer is slower. Narrow the population, do not sample it silently. |

## When a full search isn't possible

Saying so explicitly — "I searched the last 200 commits, not all 4,000" — is
the required output. Silent narrowing is not.
