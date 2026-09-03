---
name: concise-comments
description: "Use when writing or editing comments in source code, when a comment is running past two sentences, when explaining non-obvious design context, tradeoffs, constraints or workarounds in code, or when reviewing code that carries long explanatory comment blocks or changelog-style notes. Trigger on 'document this decision', 'explain why this is here', 'make sure the next person understands', 'comment this properly'."
---

# Concise Comments

The source file carries the pointer. A design doc carries the explanation.

## When to use
- Writing or editing any comment, in any language.
- A comment you are drafting has run past two sentences.
- Reviewing code that carries long explanatory comment blocks.

## The four rules

Every comment obeys all four. Check them before you write the comment.

1. **Why, not what.** A comment gives the reason the code is written this way.
   The code already shows what it does. If a reader cannot see what the code
   does, rename the thing instead of adding a comment.
2. **ASD-STE100.** Write every comment in Simplified Technical English.
3. **Not state.** A comment is not a changelog and not a work log. It records no
   part of the process that produced the code. Cite an issue or a design doc
   instead.
4. **Two sentences at most.** Longer context goes into a file in `docs/design/`.

## ASD-STE100 in practice

Apply these rules from the standard:

- Write one idea in each sentence. Keep a sentence to 20 words or fewer.
- Use the active voice. Use the present tense.
- Use one word for one meaning, and the same word for that meaning each time.
- Use the simplest verb form. Do not use a phrasal verb if one verb is enough.
- Do not use metaphors, idioms, jokes or hyperbole.
- Write out an abbreviation at its first use, or link to the term.

Bad: `# Bumped this a bit because the queue was getting hammered in prod.`
Good: `# The queue drops messages above 500 events per second.`

## What the rules apply to

Keyed on content, not on comment syntax:

- **Interface description** — what a function does, its parameters, return value,
  errors raised, a usage example. Belongs in the docstring, JSDoc/TSDoc, Rust
  `///`, or Go doc comment, at whatever length it needs. Rule 4 does not reach
  it. Rules 1 to 3 still do.
- **Design rationale** — why these numbers, what constraint forced them, what
  breaks if someone changes them. Obeys all four rules **wherever it is written,
  module docstring included.** Relocating rationale into a docstring is not
  extraction.

Licence and SPDX headers and generated files are out of scope entirely.

## Protocol

1. **Sort it.** Could a competent reader derive this from the code in front of
   them? Delete the comment. Does it describe the process that produced the code
   ("changed from", "as discussed", "after the refactor")? Delete it, or replace
   it with an issue link. Otherwise it is real rationale: count the sentences it
   needs.
2. **Two sentences or fewer — write it in place.** Done.
3. **More than two — write a design doc.** Use `docs/design/<concept>.md` at the
   repo root, unless the repo documents a different location for design docs.
   Name the file after the concept (`docs/design/retry-semantics.md`), not the
   function.
4. **Write the doc.** Cover the problem, the constraint that forced the design
   (real numbers, real systems), what was rejected and why, and the failure mode if
   someone changes it — plus everything the comment itself would have said.
5. **Leave the pointer.** Up to two sentences: name the concept, give the one
   fact needed at the call site, cite the relative path.
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
# All 40 ingest workers share one circuit breaker. A larger value opens that
# breaker for every worker.
# See docs/design/retry-semantics.md
MAX_ATTEMPTS = 3
```

...plus `docs/design/retry-semantics.md` carrying the breaker thresholds, the
fan-out arithmetic behind the cap, why full jitter rather than equal jitter, and
what to change instead when more resilience is needed.

## Notes
- A comment above a constant or at the top of a file is inline commentary. The
  four rules apply there — it is where over-long blocks land most often.
- The doc says everything the comment said, plus the four items in step 4. If the
  explanation got shorter, it was truncated rather than extracted.
- A pointer cites a relative path a reader can open, or an issue ID.
