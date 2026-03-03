# Pre-Push Review Checklist

## Trigger
When the user asks to review changes, requests a pre-push review, or says "/review".

## Purpose
This is a self-evaluation framework. Before any changes are pushed to GitHub, you MUST work through this checklist honestly and thoroughly against the current diff. This is not a rubber stamp — it is a genuine review.

## Rules

### Gather the Diff
- Run `git diff main...HEAD` (or the appropriate base branch) to see all commits that would be pushed.
- If there are also uncommitted changes, run `git diff` and `git diff --staged` to include those in the review.
- Understand what changed, why it changed, and what it affects.

### Evaluate Every Item
- Work through each section below and assess the changes against every item.
- Items may be marked `[N/A]` ONLY if they are genuinely not applicable to the changes in the diff. Provide a brief reason why.
- For all other items, provide a logical and reasonable explanation for your assessment.
- Be honest. If something is uncertain, say so. If something is wrong, flag it.

### Functionality & Security
- Do these changes match what was asked for?
- Do these changes behave as expected?
- Do these changes have the correct permissions?
- Do these changes introduce any security vulnerabilities?
  - If potential vulnerability found:
    - Is this issue relevant to the context?
    - Is it only valid in tests?
    - Is it a false positive?
    - Is a mitigation plan needed?

### Style & Quality
- Have these changes been linted?
- Have debugging artefacts been removed? (`print`/`console.log` statements, commented out code blocks, etc.)
- Do the changes use existing patterns, or establish new ones? Are new patterns justified?
- Is the diff reasonably sized?
- Does this need documenting?

### Tests & Monitoring
- Do these changes need any new tests?
- Do the tests pass?
- Are external dependencies being mocked?
  - If not, why not?
- Has there been a dry run?
- How are we going to monitor these changes?

### Impact & Risk
Think carefully before answering:
- What else do these changes affect?
- Who needs to know about these changes?
- What are the edge cases?
- How could these changes go wrong?
- How could we prevent it?
- How would we undo this change?

## Output Format
Present the review as a checklist with your honest assessment for each item:

```
## Pre-Push Review: <summary of changes>

### Functionality & Security
- [x] Changes match request — <explanation>
- [ ] Behaves as expected — <concern>
- [N/A] Correct permissions — No permission-related changes in this diff
...

### Style & Quality
...

### Tests & Monitoring
...

### Impact & Risk
<Considered summary of risks, edge cases, and rollback strategy>
```

- `[x]` — passes review, with explanation
- `[ ]` — needs attention, with explanation of the concern
- `[N/A]` — genuinely not applicable, with brief reason

### Blocking Issues
If any item is marked `[ ]`, clearly state what needs to be resolved before pushing. Do not recommend pushing until all concerns are addressed or acknowledged by the user.
