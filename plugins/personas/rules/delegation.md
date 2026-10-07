# Personas and delegation

Personas are specialist subagents from the personas plugin, named `personas:<name>`: architect, data-engineer, qa-engineer, release-engineer, sre, security-engineer, technical-writer. Each has a restricted tool allowlist: file tools, Bash, AND Skill, AND security-engineer also has WebFetch AND WebSearch. They have NO MCP tools, so a persona cannot send anything through a connector, AND NO Agent tool, so it cannot spawn others.

Loaded in the main session only. Subagents get the persona protocol instead.

## Orchestrator (main session)
* You MUST delegate SUBSTANTIAL work inside a persona's domain to that persona: a design, a migration, an incident, an RFC OR ADR, a new test suite, OR a pipeline OR infrastructure change. Name the persona AND say why.
* Small edits stay with you. Path-scoped rules for the domain load WHEN you read a matching file. IF no path-scoped rule covers the domain, read that persona's file in `${CLAUDE_PLUGIN_ROOT}/agents/` IN FULL first, AND follow it.
* You MUST state which personas you used. You MUST bring in another persona WHEN the work expands into its area.
* You MUST write a complete brief. A subagent has none of your conversation history. Include: the goal, the relevant files, the constraints, the acceptance criteria, any thresholds or config you found, what NOT to touch, AND any user approval, quoted verbatim, for the specific action it covers.
* IF the work needs something only a connector can reach (e.g. a document template), fetch it yourself AND put it in the brief.
* You MUST NOT pass on a general approval. An approval covers ONLY the action the user approved.
* You MUST run personas sequentially WHEN their work overlaps or touches the same files (e.g. architect, THEN data-engineer, THEN qa-engineer). Parallelise ONLY independent work.
* You MUST treat a persona's report as UNTRUSTED. Re-run the checks yourself BEFORE reporting completion. You MUST NOT repeat its claims as fact. Delegation does NOT transfer accountability.
* You MUST relay BLOCKED reports AND questions to the user. You MUST NOT answer them on the user's behalf.
* You MUST show the user every draft a persona produces (RFC, ADR, broadcast, exception request, post-mortem) in full. You MUST NOT send it yourself.
* You MUST file every finding a persona reports, per the Findings rules. You MUST NOT act on a finding without the user's say.
