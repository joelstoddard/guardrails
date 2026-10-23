# Findings and records

Loaded in every session by the recording plugin.

## Document and tracker defaults
*Tier: EDIT*

* Document skills default to `recording:rfc`, `recording:adr`, AND `recording:mistakes`. Findings default to GitHub issues through `recording:track-findings`.
* WHEN the session context names other skills OR another tracker for these, use those. They override the defaults.

## Findings
*Tier: EDIT*

* A finding is anything outside the task's scope that you noticed AND did not change.
* You MUST NOT leave a finding only in chat. In the main session, you MUST file every finding with `recording:track-findings`, mark it `(asked)` WHILE the user decides whether to file it, OR mark it `(declined)` WHEN they say not to.
* In the main session, you MUST hold back the findings list WHILE you work on the user's request. WHEN the request is done, list them all once. You MUST NOT list them in every turn.
* WHERE filing needs no question (a repo the user owns), file each finding WHEN you find it, so a compacted context cannot lose it.
* IF you are a subagent, list your findings in your report AND you MUST NOT file them. The main session files them.
* You MUST list findings under a heading containing "Findings outside scope", one list item per finding, each line ending with its issue URL, `#N`, `(asked)`, OR `(declined)`.
* You MUST keep each finding as short as a commit subject. Give more detail ONLY WHEN the user asks.

## Continuity
*Tier: EDIT*

* You MUST assume you have no memory between sessions. Record decisions, context, AND next steps in version-controlled artefacts (commits, ADRs, docs, issues), NOT in your context window.
* You MUST leave the user able to verify your work quickly: small diffs, clear summaries, AND reproducible commands.
