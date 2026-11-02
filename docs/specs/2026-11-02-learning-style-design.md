# Learning style: present and take in information the way the user learns

## Why

Replies arrive as a wall of text. The user must dig through it to find the context and the
decisions Claude needs from them. People take in information in different ways: by reading,
listening, seeing or doing. The same person changes with environment, time of day and mental
capacity.

The skill gives a framework of presentation styles. The user picks one or more for the
session. The plugin does NOT encode any one user's preference.

## What it is

A skill, `learning-style`, in the `building` plugin, next to the `clear` output style it
works with. The user invokes it with one or more style names:

```
/building:learning-style visual doing
```

The skill body loads into the conversation and applies until the session ends. No file
stores the choice. A user who wants a default writes it in their own `~/.claude/CLAUDE.md`,
outside the plugin.

## The styles

| Style                     | Output: what Claude presents                                                                       | Input: what Claude takes in                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `reading`                 | Structured text, as `clear` gives now. The baseline.                                               | Written specs and messages.                                            |
| `seeing` (alias `visual`) | A diagram in place of prose, at the smallest medium that carries it (below).                       | Hand-drawn sketches, photos with captions, screenshots, diagram files. |
| `doing`                   | A small runnable throwaway spike the user can try, in place of a description of how it would work. | The user's own edits to a spike, and what they report from trying it.  |
| `listening`               | A short spoken summary (below).                                                                    | Speech that Claude Code transcribes.                                   |

### Medium for `seeing`

Claude picks the smallest medium that carries the concept:

1. A handful of components and their links: ASCII art in the terminal.
2. Something more complex: a local HTML page opened in the browser.
3. A design other people must see: a claude.ai Artifact.

### Input from images

Claude reads the image as the main source and the caption as context for it, not as a
separate spec. When part of a sketch is unclear, Claude asks about that part, for example
"Does this arrow mean data flows from A to B?"

### Spikes for `doing`

1. For a concept that is not code, such as two architecture options or a data flow, the spike
   is a toy simulation: for example one small script per option that fakes its data flow, which
   the user runs and compares.
2. Spikes and `seeing` HTML pages go in the session scratchpad folder, outside the repo. Claude
   gives the full absolute path each time. The files go away after the session.
3. A spike is throwaway. The test-first and no-dead-code rules do not apply to it, because it is
   outside the repo and never committed. Keeping a spike is a new request that goes through the
   normal workflow.

### Combined styles

More than one style can be active. For each reply, Claude picks the style that best fits the
information. Claude does not use every active style in every reply.

## Goals

1. Abstract concepts (architecture options, data flow, relationships between classes or
   services) reach the user in the style they chose.
2. The decision Claude needs from the user stays easy to find in every style. It stays as the
   last line in the terminal, per `clear`, even when the content is in a browser page or an
   Artifact.
3. The user can change style mid-session by running the command again.

## Non-goals

1. Remembering the style across sessions.
2. Detecting the user's style or asking about it unprompted.
3. Encoding any one user's preference in the plugin.

## Anti-goals

These make the skill a failure even if it works:

1. **A document where a sentence would do.** The styles are tools for abstract concepts. A
   short answer stays a short sentence in every style. Claude uses a diagram, an HTML page, an
   Artifact or a spike only when the concept needs it.
2. **Burying the decision.** A diagram or page that hides what Claude needs from the user.

## Constraints

1. Follows the repo's skill conventions; `tests/run.sh` and `tests/lint.sh` pass. In
   particular, no command substitution in the skill file (`tests/test_skill_preambles.sh`),
   and any `allowed-tools` wildcard over a write-capable command must be justified in
   `tests/test_skill_tools.py`.
2. Publishing an Artifact makes content reachable by URL. The skill must not publish one
   without the user asking for something to share, per the conduct rules on communicating on
   the user's behalf.
3. The `building` manifest description names its skills; add `learning-style` to it.

## Decided by the user

1. Styles are a framework; the plugin encodes no personal preference.
2. "Doing" means a runnable spike the user can try.
3. A command sets the style. It lasts for the session only.
4. Input includes hand-drawn sketches, photos with captions and transcribed speech.
5. Medium for `seeing` depends on the content: ASCII for simple, HTML for complex, an Artifact
   for something to share.
6. More than one style can be active; Claude picks per reply.
7. Anti-goal 1, in the user's words: "If you don't need to use these, don't."
8. `doing` for a non-code concept is a toy simulation.
9. Spikes and HTML pages go in the session scratchpad.

## Calls made by Claude (check these)

1. The skill lives in `building`, beside the `clear` output style.
2. `visual` is an alias for `seeing`, because the user typed `visual`.
3. `listening` output: the text reply stays, so the decision stays the last terminal line. The
   macOS `say` command also reads a short summary aloud, only for a reply that carries a
   concept. A one-line answer is not spoken. Where `say` is absent, Claude says so once and
   falls back to `reading`.
4. An unknown style name: Claude asks once what the user means, then applies the user's
   description for the rest of the session. Nothing is stored, so non-goal 3 holds.
5. After a long session compacts, the style can drop out of context. Running the command again
   restores it. No hook re-injects it.
6. Running the command again replaces the active set. `/building:learning-style reading`
   resets to the baseline.
7. The skill sets `disable-model-invocation: true`, so only the user turns it on (non-goal 2).

## Left to the builder

1. The skill's exact wording, following `superpowers:writing-skills`.
2. Whether an eval case covers anti-goal 1 (a simple question with `visual` active gets a
   short text reply), and its grader.
