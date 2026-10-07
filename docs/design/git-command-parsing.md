# Detecting whether a command line runs `git <subcommand>`

`plugins/building/lib/git-cmd.sh` answers one question for
the guardrail hooks: does this shell command line actually *run* `git commit` (or
`push`, or …), and if so, which repository will it act on?

## Problem

The first version of the default-branch guard matched the substring `git commit`
anywhere in the command line. That is wrong in the direction that annoys people: a
benign `gh pr create` whose PR body happened to say "git commit" tripped the guard
and blocked the call. Commit messages, grep patterns and PR bodies all routinely
quote git commands.

## The constraint

These are tripwire hooks, deliberately dumb. They run synchronously on every
`Bash` tool call, so parsing has to be cheap, and a parser that is wrong in the
*blocking* direction is worse than one that is wrong in the permissive direction —
a guard that cries wolf trains you to set `ALLOW_DEFAULT_COMMIT=1` out of habit, at
which point it protects nothing.

## Design

For each chained simple command — split on `&&`, `||`, `;`, `|`, a lone `&` and
newlines, but not the `&` of a redirect such as `2>&1` or `&>` —
`_guardrails_invokes_git`:

1. finds the command word, past what can come before it (see below),
2. requires the command word itself to be `git`,
3. skips git's global options before matching the subcommand.

Global options that consume a following separate argument (`-C`, `-c`,
`--git-dir`, `--work-tree`, …) are enumerated in
`_guardrails_git_opt_takes_value`, because skipping them means knowing whether to
advance the index by one token or two.

A command that runs a script of its own is read as one too. `bash -c '…'` (or `-c` in a
cluster such as `-lc`), a here-string fed to a shell, and `eval '…'` are re-scanned to
four levels deep, as `publish-cmd.sh` does; a heredoc fed to a shell is split as script
lines by `shell-split.sh`, as are the `$( )` and backticks in an unquoted heredoc body.
A `cd` inside `sh -c` ends with that child shell, while one inside `eval` lasts. A pipe
into a shell runs commands no guard can see, so `guard-default-branch` asks when the
directory it would run in is on its default branch.

## Finding the command word

A word before the command can hide it: `sudo bash -c '…'`, `env FOO=1 git commit`,
`then bash <<EOF`, `(bash -c …)`. So every reader of a segment, in the publish guard,
the git guards and the shell readers, finds the command word through one lookup,
`_guardrails_command_at` in `shell-split.sh` (#90). It skips:

- `NAME=value` assignments;
- the keywords `!`, `{`, `(`, `if`, `then`, `elif`, `else`, `while`, `until` and `do`,
  and a `(` fused to the next word;
- the wrappers `sudo`, `env`, `nohup`, `exec`, `command`, `time` and `xargs`, with
  their short options. In a cluster such as `-Eu`, the first option that takes a value
  takes the rest of the word, or the next word if none is left, as getopt does.

`command -v` and `-V` name a command without running it, so there `command` is the
command word. `ssh host` runs its command on another host, as you. The lookup sees through
it only to a shell, which is then read like a shell here. `ssh host gh …` keeps `ssh` as
its command word, as before.

The lookup is on the guards' slowest path: a command at the caps can make them read some
65,000 segments. Two measured costs shape it:

- It reads the caller's `toks` array in place. Passing the words as arguments copies
  them on every call, which cost about 8 µs a segment against 3 µs.
- A call to a large function costs more in bash. So `_guardrails_command_at` is a small
  check that every segment pays, and only a first word that can come before a command
  goes on to the loop in `_guardrails_command_skip`. With the guards' functions loaded,
  that cut its cost from about 14 µs a segment to about 7 µs. The check names every word the loop skips, and
  `tests/test_git_cmd.sh` puts each of them first in a segment, so the two cannot drift.

Two readers use the lookup with care:

- **The splitter's awk cannot call it.** To decide whether a heredoc is a shell's script,
  it asks whether a shell's name is a word anywhere before the `<<` in the segment. That
  is a superset of the lookup, so no wrapper hides a shell. It also catches wrappers the
  lookup does not know, such as `docker exec -i c bash <<EOF`. The cost is a false
  positive when a shell's name is a plain argument, as in `grep -w bash <<EOF`.
- **The directory walk follows only a plain `cd`.** A `cd` in a subshell, `(cd /x)`, does
  not last, and one after a keyword, `if false; then cd /x; fi`, may not run. Following
  either could judge a repo other than the one the commit lands in, which is weaker than
  not following it. The same holds for the `cd` in an `eval` behind a keyword.

## Which repository the command acts on

Parsing global options is not optional, because `git -C <path> commit` is a real
commit aimed at a different repo. A guard that ignores `-C` is not merely
bypassable — it is wrong in the other direction too, and that is the case that
actually bites.

Working one-worktree-per-ticket, the shell sits in the primary checkout (usually
on the default branch) while the commit is aimed at a worktree. A hook that
resolves the repo from the payload's `cwd` alone reads the primary checkout's
branch and refuses a commit that was never going to land there.

`_guardrails_git_effective_cwd` exists for this. Both routes to another repo have
to be honoured, and they compose, so segments are walked in order:

| Form | Behaviour |
|---|---|
| `cd <path> && git commit` | The payload `cwd` never changes, so this is the form that bites under worktree-per-ticket. |
| `git -C <path> commit` | Cumulative — each `-C` is relative to the previous one. |

## Two splits, never weaker than one

The splitter carries quote state across lines, so a quoted argument spanning lines
stays data. A shell construct it misreads can leave it inside a quote the shell has
already closed, hiding the lines that follow. So every guard also reads the per-line
split it replaced (`_GUARDRAILS_SPLIT_PER_LINE=1`), and git counts as run if either split
sees it. When the two disagree on the directory, `_guardrails_git_effective_cwd` prints
both and `guard-default-branch` refuses if either is on its default branch. The cost is
that the per-line split's false positives remain for the git guards.

## Reading in time

A hook that runs past its 10 s timeout lets the command through, so `_guardrails_unreadable`
asks about a command the guards could not read in time. It has three caps: 128 KiB of text,
10,000 segments, and 16 shells and evals.

A shell or eval splits its payload again, at up to four more depths, so both the segment and
the length caps count what the guards read again, not only the command (#107). Four nested
`eval`s over 32,700 `;`-joined commands took the publish guard 6.6 s, while the top-level count
saw two segments. Four `eval`s over 128 KiB of words took it 58 s, with no `;` at all.

Splitting every payload to count it would cost as much as the reading it bounds. So the
counts are bounds, made in one awk pass over both splits:

- each line of a split is one segment;
- a word that can take a payload adds one segment for every place after it in its line where
  a split could cut (`;`, `|`, `&`, a backtick, `$(`, `<(`, `>(`), and one for the rest;
- it also adds the characters after it in its line to the text read again. The larger of the
  two splits' totals counts against the 128 KiB cap, as each pass reads one split.

A word can take a payload if `_guardrails_shell_payload` could read one from it: `eval`
always, and `sh`, `bash`, `zsh`, `dash` or `ksh` when a `-c`, alone or in a cluster such
as `-lc`, or a `<<<` follows it in its line. That payload is always text after the word in
the same segment, so these are bounds. A nested payload is counted again through its own
word. Neither depends on which word is the command, so a wrapper before the shell cannot
hide one.

They over-count a shell's name in prose that a `-c` or `<<<` follows, and `eval` in any prose.
In the suites, a 300-line commit message naming shells 12 times counts 306 segments and no
text read again. A 5,000-line script fed to bash counts 5,004 segments and 23 characters, a
`bash -c` over a 100 KiB script reads 102,000 characters again, and every other command
counts at most 140 characters. A shell in a shell over more than 64 KiB asks.

The publish guard checks `curl`, `wget`, `http` and `gh api` lines without starting a process
(#126). It started about seven for each `curl` line, so 4,990 of them took it 180 s. Its URL
scan now costs a regex per URL. So past 32 URLs in one segment a write is read as remote,
which bounds a segment, while the length cap bounds the URLs in a command.

Within the caps, the slowest input measured took 4.1 s of the 10 s budget: one `eval`
re-reading 480 `curl -d` lines of 32 local hosts each, read by guard-publish on macOS at
load 6. It took 3.4 s on Linux. The next slowest took 2.6 to 3.5 s: the same lines without the
`eval`, 32,000 `env` wrappers or assignments before a `git commit`, and one `eval` over 128 KiB
of words.

## What was rejected

- **Substring matching.** The original approach; produced the `gh pr create` false
  positive above.
- **A real shell parser.** Correct, but far too much machinery for a tripwire that
  runs on every Bash call, and a new dependency for hooks that deliberately have
  none beyond git and jq.
- **Resolving the repo from the hook's `cwd` alone.** Simpler, but silently wrong
  under both `git -C` and `cd … &&` — precisely the worktree-per-ticket workflow
  these hooks exist to support.

## Known limitation

Tokens are split on whitespace with no quote handling, so
`git -C '/path with spaces' commit` is not parsed correctly. This is consistent
with the tripwire framing: the failure is fail-open, and the guard lets the command
through rather than blocking it wrongly. For the same reason a quoted or escaped command
word, such as `"bash"` or `ba\sh`, is not recognised, and a long option that takes a
separate value, such as `sudo --user root`, reads its value as the command word.

A shell that runs on another host, as in `ssh host bash <<EOF`, has its script read like
a local one. So `guard-default-branch` judges a `git commit` in it against the local
checkout, and refuses it when that checkout is on its default branch.

## Failure mode if you change this

Tightening the matcher so it blocks more aggressively will start blocking benign
`gh` and `grep` invocations. Keep new matching rules fail-open, and add a
regression case to `tests/test_guard_default_branch.sh` naming the command line
that motivated them.
