---
name: concise-comments
description: "Use when writing or editing comments in source code, when a comment is running past three lines, when explaining non-obvious design context, tradeoffs, constraints or workarounds in code, or when reviewing code that carries long explanatory comment blocks. Trigger on 'document this decision', 'explain why this is here', 'make sure the next person understands', 'comment this properly'."
---

# Concise Comments

The source file carries the pointer. A docs file carries the explanation.

## When to use
- Writing or editing any comment, in any language.
- A comment you are drafting has run past three lines.
- Reviewing code that carries long explanatory comment blocks.

## The three shapes

Every comment is one of exactly three shapes. Sort first, then write.

1. **Zero lines** — it restates what the code already says. Delete it. If the code
   needed the comment to be readable, rename the thing instead.
2. **One to three lines** — a non-obvious *why* that fits. State it once.
3. **A pointer** — a non-obvious *why* that does not fit: three lines at most,
   naming the concept and citing a doc path, plus the doc file holding the full
   explanation.

There is no fourth shape. A block of prose in a source file is shape 3, unfinished.

## What the cap applies to

Keyed on content, not on comment syntax:

- **Interface description** — what a function does, its parameters, return value,
  errors raised, a usage example. Belongs in the docstring, JSDoc/TSDoc, Rust
  `///`, or Go doc comment, at whatever length it needs. The cap does not reach it.
- **Design rationale** — why these numbers, what constraint forced them, what
  breaks if someone changes them. Takes one of the three shapes **wherever it is
  written, module docstring included.** Relocating rationale into a docstring is
  not extraction.

Licence and SPDX headers and generated files are out of scope entirely.

## Protocol

1. **Sort it.** Could a competent reader derive this from the code in front of
   them? That is shape 1 — delete it. Otherwise it is real rationale: count the
   lines it needs.
2. **Three or fewer — write it in place.** Done.
3. **More than three — pick the doc location.** Use the repo's existing docs
   directory or docs site if it has one; otherwise create `docs/` at the repo root.
   Name the file after the concept (`docs/retry-semantics.md`), not the function.
4. **Write the doc.** Cover the problem, the constraint that forced the design
   (real numbers, real systems), what was rejected and why, and the failure mode if
   someone changes it — plus everything the comment itself would have said.
5. **Leave the pointer.** Up to three lines: name the concept, give the one
   sentence needed at the call site, cite the relative path.
6. **Report the doc path** in your summary so it surfaces in review.

## Example

Before — 28 lines of prose above the constants:

```python
# The upstream service sits behind a circuit breaker SHARED across every
# worker process talking to it (we currently run 40 ingest workers). The
# breaker opens after 10 consecutive failures within a 30-second window.
# ... 25 more lines ...
MAX_ATTEMPTS = 3
```

After:

```python
# Sized against a circuit breaker shared by all 40 workers, not against what
# one worker tolerates. Raising this trips the breaker fleet-wide.
# See docs/retry-semantics.md
MAX_ATTEMPTS = 3
```

...plus `docs/retry-semantics.md` carrying the breaker thresholds, the fan-out
arithmetic behind the cap, why full jitter rather than equal jitter, and what to
change instead when more resilience is needed.

## Notes
- A comment above a constant or at the top of a file is inline commentary. The
  three shapes apply there — it is where over-long blocks land most often.
- The doc says everything the comment said, plus the four items in step 4. If the
  explanation got shorter, it was truncated rather than extracted.
- A pointer cites a relative path a reader can open.
