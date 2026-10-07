# Engineering

Loaded in every session by the building plugin, with the conduct rules, which define the keywords AND tiers used here.

## Design & Architecture
*Tier: CHANGE*

* You SHOULD NOT add complexity. You MUST follow KISS (keep it stupid simple).
* You MUST NOT design systems that are difficult or impossible to revert.
* You MUST NOT design systems for problems that don't exist. You MUST validate that issues actually exist, reproducibly, before designing solutions.
* You MUST NOT consolidate concerns.
    * You MUST NOT create a module with more than one responsibility (SRP).
    * You MUST NOT use a subtype that cannot stand in for its base type without changing correctness (LSP).
    * WHEN you define an interface, keep it small (ISP).
    * Inject a dependency ONLY WHEN a test OR a second implementation needs the seam. You MUST NOT add an abstraction with one implementation AND no test that needs it.
* You MUST NOT use external dependencies as a first resort. WHEN one is unavoidable, you SHOULD prefer the standard library, THEN platform-vendor packages, THEN organisation-owned packages, THEN third-party packages.
* You MUST use the latest version combination of dependencies that meets the criteria. You MUST check the registry or package tooling for current versions. You MUST NOT rely on recall.
* You MUST verify the exact package name BEFORE installing. You MUST NOT install a package you cannot confirm exists AND is the intended one (typosquatting AND hallucinated names are real attacks).
* You MUST write modules with loose coupling AND high cohesion.
* FIRST make it work, THEN make it good, LASTLY make it fast.
    * You MUST measure before optimising.
* You MUST make illegal states unrepresentable where the type system allows.
* You MUST NOT share mutable state across module boundaries without explicit ownership.
* You MUST record significant decisions AND their trade-offs with the `adr` skill.
* You MUST follow the patterns already established in the codebase UNLESS you have a recorded reason to deviate.

---

## Implementation
*Tier: EDIT*

* You SHOULD NOT repeat yourself (DRY). You MUST NOT abstract until the duplication has appeared at least three times.
* You MUST reach potential errors as fast as possible (fail fast).
* You MUST NOT swallow errors. You MUST handle an error, propagate it, OR fail loudly.
    * Where possible, surface meaningful logs and errors to end users.
* You MUST name things for what they ARE or DO. You MUST NOT use names that need a comment to explain them.
* You SHOULD prefer pure functions and immutability. You MUST keep side effects (clock, randomness, network, filesystem, environment) at the edges. Inject them ONLY WHEN a test must control them.
* You MUST NOT commit commented-out code, dead code, OR unreferenced TODOs.
* You MUST NOT leave placeholder, stubbed, OR "not implemented" code behind a claim of completion.
* You MUST use stacked diffs (`building:stacked-diffs`) for large bodies of coherent changes.

---

## Testing & Quality

### Charter
*Tier: EDIT*

* You MUST create quality through the environment, NOT through instruction. IF a rule matters, a deterministic machine MUST enforce it.
* You MUST work inside the constraints (tests, types, linters, metrics, gates). Your code is correct ONLY when it survives them.
* You MUST NOT submit a change that lowers confidence in the system.
* You MUST test behaviour; you MUST NOT test implementation details.
* You MUST NOT weaken, skip, delete, OR loosen a test, threshold, OR gate to make a change pass. Fix the code.
* You MUST NOT disable a failing check. IF a check is genuinely wrong, STOP AND ask the user, with evidence.
* You MUST add a new constraint when a defect escapes. The escape MUST become impossible to repeat.
* IF a constraint you need does not exist (no tests, no linter, no gate), you MUST leave the ONE smallest check that fails if your logic breaks, AND propose the larger gate as a finding. You MUST NOT build test infrastructure unasked.

### Quality gates & metrics
*Tier: CHANGE*

* You MUST satisfy EVERY gate the project HAS configured (build, types, lint, format, tests, coverage floor, mutation score floor, complexity limits, security scans, performance budgets). You MUST NOT skip one. IF one you would expect is missing, say so as a finding.
* You MUST NOT lower a threshold. Thresholds are ratchets: they MAY rise AND MUST NOT fall.
* You MUST keep cyclomatic complexity, cognitive complexity, duplication, coupling, AND file/function size from regressing.
    * WHERE the project measures cyclomatic complexity OR CRAP, you MUST measure each function you touch, before AND after, with the project's own tooling. Its complexity may rise ONLY by the branches the task requires, AND its coverage MUST NOT fall. Report each touched function's complexity AND coverage, before AND after.
    * IF the project measures neither, say so as a finding. You MUST NOT install OR run a tool to measure them unasked.
* You MUST NOT treat any single metric as proof of quality. Combine them.
* You MUST NOT game a metric (assertion-free tests, trivial mutants killed, code split only to lower a number).

### TDD
*Tier: EDIT*

* You MUST write a failing test BEFORE writing non-trivial logic (a branch, a loop, a parser, a money OR security path) (red, green, refactor). Trivial one-liners need no test.
* You MUST run the test AND watch it fail for the RIGHT reason before making it pass.
* You MUST write the minimum code to pass the test. You MUST NOT add behaviour no test demands.
* You MUST refactor ONLY when tests are green.

### Static analysis
*Tier: EDIT*

* You MUST run type checking in strict mode WHERE the project configures it.
* You MUST run linters with warnings treated as errors WHERE the project configures them.
* You MUST run formatters automatically WHERE the project configures them. You MUST NOT introduce style changes by hand.
* You MUST run static analysis for bugs, code smells, dead code, AND unsafe patterns on EVERY change, WHERE the project configures it.
* You MUST NOT suppress a finding to get past a gate. A suppression is permitted ONLY for a proven false positive, scoped to the single finding, with a comment explaining WHY.
* You MUST NOT use type escape hatches (`any`, `ignore`, casts) to silence an error. Fix the type.

### Shift left
*Tier: CHANGE*

* You MUST catch defects at the earliest, cheapest stage (types, lint, unit tests, THEN CI, THEN production).
* You MUST consider testing and security during design, NOT after implementation.

---

## Version Control Discipline
*Tier: CHANGE*

* You MUST write commit messages that explain WHY, NOT just what.
* You MUST NOT commit secrets, generated artefacts, OR large binaries.
* The `building:commit` skill, the permission deny list, AND the default-branch guard enforce the rest.

---

## Collaboration & Process
*Tier: CHANGE*

* You MUST leave code better than you found it, WITHIN the scope of the task. Surface everything else as a finding.
* You MUST keep changes small enough to be reviewed properly.
* You MUST draft the WHY in pull request descriptions. PRs open as drafts through `building:draft-pr`; promoting one to ready is the user's call.
* You MUST review the change, NOT the author.
* You MUST track technical debt explicitly, as an issue in the session's tracker, with an owner AND a cost of delay. You MUST NOT hide it. IF the owner is unknown, ask; you MUST NOT invent one.
* You MUST deprecate a published interface (an API, CLI flag, config key, OR file format that others depend on) with a timeline, a migration path, AND a removal date. You MUST NOT remove one without notice. Code your own change made unused is NOT a published interface; remove it.
* You MUST pay down the debt you touch, WITHIN the scope of the task.
* You MUST respond to review feedback by fixing the cause, NOT by arguing the check away.
* You MUST define ownership. EVERY service, API, AND alert MUST have a named owning team. IF it is unknown, ask; you MUST NOT invent one.
