# Rules keywords: converge on BCP 14 (RFC 2119, RFC 8174)

Supersedes the keyword choice in `docs/specs/2026-10-02-personas-design.md`, which kept the
draft's own ALWAYS / NEVER vocabulary. Its other decisions stand.

## Why

The rules defined their own strength keywords: ALWAYS / NEVER ("absolute") beside MUST /
MUST NOT ("a hard property"). BCP 14 already defines requirement keywords, and readers and
models know it without a glossary. A private vocabulary that overlaps it (two words for
"absolute", none for "recommended") is one more thing to learn and to get wrong.

## Decisions

| Decision                | Choice                                                                                                          | Why                                                                                                                                                                                                                                                                                     |
| ----------------------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Definition              | The BCP 14 boilerplate in `conduct.md` "Keywords", "this document" read as "these rules"                                                      | The standard text is the one readers and models recognise                                                                                                                                                                                                                               |
| Strength mapping        | Faithful: ALWAYS → MUST, NEVER → MUST NOT; SHOULD / SHOULD NOT only where a rule already carried a vague escape | Wording converges, strength does not change. A full re-tier would weaken rules with no eval evidence that it is safe                                                                                                                                                                    |
| Phrasing                | "You MUST …"; lines with their own subject keep it                                                              | Full sentences, the usual RFC form. Costs about 4 characters per rule, well inside the 10,000-character cap on rules files                                                                                                                                                              |
| Logic words             | IF / WHEN / WHERE / AND / OR / NOT / BEFORE / THEN / FIRST / LASTLY stay, as a labelled project extension       | BCP 14 defines no logic or ordering words, and these carry meaning the rules rely on                                                                                                                                                                                                    |
| User exceptions         | "A MUST OR MUST NOT admits an exception ONLY WHEN the user explicitly grants one for a specific case"           | Keeps the escape the ALWAYS / NEVER definition carried                                                                                                                                                                                                                                  |
| Dated specs             | Untouched                                                                                                       | They record what was decided at the time                                                                                                                                                                                                                                                |
| Rules outside this repo | Migrate the dotfiles domain rules in a paired PR; no deprecated ALWAYS / NEVER alias                            | `conduct.md` defines the keywords for domain rules too, and the dotfiles rules are the only known ones. An alias would need its own removal later. Rules in other installs lose the definition without notice, but ALWAYS / NEVER keep a plain English meaning close to MUST / MUST NOT |

## Mapping

| Before                                                                                     | After                                                                                |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `ALWAYS X` / `NEVER X`                                                                     | `You MUST X` / `You MUST NOT X`                                                      |
| A vague escape: "ALWAYS prefer …", "NEVER, without good reason, …"                         | `You SHOULD` / `You SHOULD NOT`, without the escape phrase, which SHOULD now carries |
| A narrow, checkable exception: "… UNLESS you have a recorded reason to deviate"            | MUST, with the UNLESS clause kept. It is stricter than SHOULD                        |
| An existing MUST / MUST NOT, or a line with its own subject ("One fault MUST NOT cascade") | Unchanged                                                                            |

Lower-case "always" and "never" keep their plain English meaning: they are not BCP 14 key words.

"Without warrant" and "where practical" are vague escapes too, so those rules are SHOULD.

## Scope

- The five rules files: `building/rules/{conduct,engineering}.md`,
  `personas/rules/{delegation,persona-protocol}.md`, `recording/rules/findings.md`.
- The seven persona agents in `plugins/personas/agents/`.
- The skills that use the keywords: `building:commit`, and `recording:{adr,mistakes,rfc,track-findings}`.
- The rule the `suppression-warn.sh` hook writes into context, which is rules text in a shell string.
- The skill-text fixture in `tests/test_eval_graders.py`, so it mirrors the skill line it stands for.
- In the dotfiles repo, the six domain rules in `.claude/rules/` that use the keywords:
  `api-contracts`, `delivery`, `docs`, `gherkin`, `migrations`, `testing`.

The two PRs go out together. Either can land first: the old `conduct.md` already defines
MUST / MUST NOT, the two dotfiles SHOULD lines read with their usual RFC meaning until the
new definition lands, and a stray ALWAYS / NEVER still reads as plain English.

## Verification

- `tests/test_keywords.sh` fails on an all-capitals ALWAYS or NEVER in any file under
  `plugins/`, hook scripts included, so the old vocabulary cannot drift back. It also fails
  on a MUST sentence that carries its own escape, which the mapping makes a SHOULD. The dotfiles
  `test/unit/test_rules.py` gets the same check over `.claude/rules/`.
- `bash tests/run.sh` (it holds the 10,000-character cap) and `bash tests/lint.sh` pass, and
  so do the dotfiles `bash test/unit/run.sh` and `bash test/lint.sh`.
- The evals are the behavioural check, run by hand: `bash tests/evals.sh <plugin> --runs 1`
  for `building`, `recording` and `personas`. A drop against the 2026-10-06 first runs
  means MUST is a weaker signal to the model than ALWAYS was.
