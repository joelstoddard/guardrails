# Engineering

Loaded in every session by the building plugin, with the conduct rules, which define the keywords AND tiers used here.

## Design & Architecture
*Tier: CHANGE*

* NEVER add complexity without warrant. ALWAYS follow KISS (keep it stupid simple).
* NEVER design systems that are difficult or impossible to revert.
* NEVER design systems for problems that don't exist. ALWAYS validate that issues actually exist, reproducibly, before designing solutions.
* NEVER consolidate concerns.
    * NEVER create a module with more than one responsibility (SRP).
    * NEVER use a subtype that cannot stand in for its base type without changing correctness (LSP).
    * WHEN you define an interface, keep it small (ISP).
    * Inject a dependency ONLY WHEN a test OR a second implementation needs the seam. NEVER add an abstraction with one implementation AND no test that needs it.
* NEVER use external dependencies as a first resort. WHEN one is unavoidable, ALWAYS prefer the standard library, THEN platform-vendor packages, THEN organisation-owned packages, THEN third-party packages.
* ALWAYS use the latest version combination of dependencies that meets the criteria. ALWAYS check the registry or package tooling for current versions. NEVER rely on recall.
* ALWAYS verify the exact package name BEFORE installing. NEVER install a package you cannot confirm exists AND is the intended one (typosquatting AND hallucinated names are real attacks).
* ALWAYS write modules with loose coupling AND high cohesion.
* FIRST make it work, THEN make it good, LASTLY make it fast.
    * ALWAYS measure before optimising.
* ALWAYS make illegal states unrepresentable where the type system allows.
* NEVER share mutable state across module boundaries without explicit ownership.
* ALWAYS record significant decisions AND their trade-offs with the `adr` skill.
* ALWAYS follow the patterns already established in the codebase UNLESS you have a recorded reason to deviate.

---

## Implementation
*Tier: EDIT*

* NEVER, without good reason, repeat yourself (DRY). NEVER abstract until the duplication has appeared at least three times.
* ALWAYS reach potential errors as fast as possible (fail fast).
* NEVER swallow errors. ALWAYS handle an error, propagate it, OR fail loudly.
    * Where possible, surface meaningful logs and errors to end users.
* ALWAYS validate input at system boundaries. NEVER trust data crossing a boundary.
* ALWAYS name things for what they ARE or DO. NEVER use names that need a comment to explain them.
* ALWAYS prefer pure functions and immutability. ALWAYS keep side effects (clock, randomness, network, filesystem, environment) at the edges. Inject them ONLY WHEN a test must control them.
* NEVER commit commented-out code, dead code, OR unreferenced TODOs.
* NEVER leave placeholder, stubbed, OR "not implemented" code behind a claim of completion.
* ALWAYS use stacked diffs (`building:stacked-diffs`) for large bodies of coherent changes.

---

## Testing & Quality

### Charter
*Tier: EDIT*

* ALWAYS create quality through the environment, NOT through instruction. IF a rule matters, a deterministic machine MUST enforce it.
* ALWAYS work inside the constraints (tests, types, linters, metrics, gates). Your code is correct ONLY when it survives them.
* NEVER rely on your own belief that code is correct. Confidence comes from the gauntlet the code survived.
* NEVER submit a change that lowers confidence in the system.
* ALWAYS test behaviour, NEVER implementation details.
* NEVER weaken, skip, delete, OR loosen a test, threshold, OR gate to make a change pass. Fix the code.
* NEVER disable a failing check. IF a check is genuinely wrong, STOP AND ask the user, with evidence.
* ALWAYS add a new constraint when a defect escapes. The escape MUST become impossible to repeat.
* ALWAYS treat the quality gate as the definition of done.
* ALWAYS run the relevant checks yourself BEFORE reporting completion. NEVER hand unverified work to the user.
* IF a constraint you need does not exist (no tests, no linter, no gate), ALWAYS leave the ONE smallest check that fails if your logic breaks, AND propose the larger gate as a finding. NEVER build test infrastructure unasked.

### Quality gates & metrics
*Tier: CHANGE*

* ALWAYS satisfy EVERY gate the project HAS configured (build, types, lint, format, tests, coverage floor, mutation score floor, security scans, performance budgets). NEVER skip one. IF one you would expect is missing, say so as a finding.
* NEVER lower a threshold. Thresholds are ratchets: they may rise, NEVER fall.
* ALWAYS keep cyclomatic complexity, cognitive complexity, duplication, coupling, AND file/function size from regressing.
* NEVER treat any single metric as proof of quality. Combine them.
* NEVER game a metric (assertion-free tests, trivial mutants killed, code split only to lower a number).

### TDD
*Tier: EDIT*

* ALWAYS write a failing test BEFORE writing non-trivial logic (a branch, a loop, a parser, a money OR security path) (red, green, refactor). Trivial one-liners need no test.
* ALWAYS run the test AND watch it fail for the RIGHT reason before making it pass.
* ALWAYS write the minimum code to pass the test. NEVER add behaviour no test demands.
* ALWAYS refactor ONLY when tests are green.

### Static analysis
*Tier: EDIT*

* ALWAYS run type checking in strict mode WHERE the project configures it.
* ALWAYS run linters with warnings treated as errors.
* ALWAYS run formatters automatically. NEVER introduce style changes by hand.
* ALWAYS run static analysis for bugs, code smells, dead code, AND unsafe patterns on EVERY change.
* NEVER suppress a finding to get past a gate. A suppression is permitted ONLY for a proven false positive, scoped to the single finding, with a comment explaining WHY.
* NEVER use type escape hatches (`any`, `ignore`, casts) to silence an error. Fix the type.

### Shift left
*Tier: CHANGE*

* ALWAYS catch defects at the earliest, cheapest stage (types, lint, unit tests, THEN CI, THEN production).
* ALWAYS consider testing and security during design, NOT after implementation.
* NEVER rely on a later stage to catch what an earlier stage could.

---

## Version Control Discipline
*Tier: CHANGE*

* ALWAYS write commit messages that explain WHY, NOT just what.
* NEVER commit secrets, generated artefacts, OR large binaries.
* The `building:commit` skill, the permission deny list, AND the default-branch guard enforce the rest.

---

## Collaboration & Process
*Tier: CHANGE*

* ALWAYS leave code better than you found it, WITHIN the scope of the task. Surface everything else as a finding.
* ALWAYS keep changes small enough to be reviewed properly.
* ALWAYS draft the WHY in pull request descriptions. PRs open as drafts through `building:draft-pr`; promoting one to ready is the user's call.
* ALWAYS review the change, NOT the author.
* NEVER leave knowledge only in your context window. Write it down where the next reader will look.
* ALWAYS ask WHEN blocked or uncertain, NOT after building the wrong thing.
* ALWAYS track technical debt explicitly, as an issue in the session's tracker, with an owner AND a cost of delay. NEVER hide it. IF the owner is unknown, ask; NEVER invent one.
* ALWAYS deprecate with a timeline, a migration path, AND a removal date. NEVER remove without notice.
* ALWAYS pay down the debt you touch, WITHIN the scope of the task.
* ALWAYS respond to review feedback by fixing the cause, NOT by arguing the check away.
* ALWAYS define ownership. EVERY service, API, AND alert MUST have a named owning team. IF it is unknown, ask; NEVER invent one.
