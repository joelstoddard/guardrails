# Line coverage of the hook scripts and lib files

The plugins' logic is bash: the hook scripts that guard publishing, commits and pushes,
and the `lib/` files that parse the commands they inspect. Without a measurement, an
agent can add a branch to a hook with no test for it and every check stays green.
`tests/coverage.sh` measures line coverage and fails when it falls.

The tool is ported from the
[dotfiles](https://github.com/joelstoddard/dotfiles/blob/main/docs/design/coverage-and-mutation.md),
which measured these scripts before they moved here. Its mutation testing is not ported.

## Why the tool is in the repo

The dotfiles chose a tracer of their own because `kcov` is Linux-only in nixpkgs and
`bashcov` is not packaged. A small tracer in plain bash and awk runs on macOS and CI
alike, so an agent can check before opening a PR.

## What is measured

- `plugins/*/hooks/scripts/*.sh`
- `plugins/*/lib/*.sh`

Each glob is one level deep. Trace lines from any other file, including the tests, are
ignored.

The suites that run are `tests/test_*.sh`, each with bash as `tests/run.sh` does. Each
test file runs on its own with its own trace log. The Python tests check documents and
manifests, not shell, so they are not run.

## Tracing

The tracer changes no test and no script. It writes `file:line` to a log named by
`COV_LOG`, never to stdout or stderr, so tests that check output are not affected.

`BASH_ENV` names `tests/coverage/bash_env.sh`, which every non-interactive bash reads.
It opens a file descriptor on the log, points `BASH_XTRACEFD` at it, sets `PS4` to
print `file:line`, and runs `set -x`. A hook that `run_hook` starts with `bash "$script"`
is traced this way, and so is a lib that a test sources.

`BASH_XTRACEFD` and the `{fd}` syntax need bash 4.1, so the tool refuses to run on an
older bash. Stock macOS bash is 3.2, so run it from a Nix or Homebrew bash. The tool's
own tests run in `tests/run.sh`, so the suite needs bash 4.1 too.

## Executable lines

`tests/coverage/executable.awk` decides which lines count. Every line counts except:

- blank lines and comment lines;
- lines that begin with `then`, `else`, `fi`, `do`, `done`, `esac`, `in`, `;;`, `;&`,
  `;;&`, `{`, `}` or `)`, followed by nothing or by a space, `;`, `|`, `&`, `<` or `>`.
  The whole line is skipped, so `then cmd`, `else cmd` and `{ cmd; }` do not count;
- function headers, and case labels on their own or with an empty arm (`pattern) ;;`);
- continuation lines of multi-line strings, heredoc bodies and backslash continuations;
- lines ending in `# coverage: ignore <reason>`. The reason is required. Use the marker
  only for lines that cannot run.

The rules are a heuristic. They need to be consistent, not exact: floors start at
measured values, so each run compares like with like. A line miscounted the same way
every time changes no result.

Known limits:

- A multi-line command counts on its first line, but bash credits a hit to a later
  line, so that first line reads as uncovered.
- A case label continued with a backslash counts as executable but is never traced
  (`git-cmd.sh:16`).
- A file a test copies before running is traced under the copy's path and is not
  credited to the original. `test_manifests.sh` runs every hook from a copy under a
  path with a space, so those runs do not count.
- A `<<` followed by a word starts a heredoc, even inside `(( ))`, so `(( x << y ))`
  would hide every later line of the file. No measured file has one.

Known blind spot: code in another language inside a shell string is not measured. The
awk in `shell-split.sh` and the jq in the hooks count as one shell line each, and a
test that runs that line covers all of it. `shell-split.sh` reads 1 of 1 lines.

## Floors and the ratchet

`tests/coverage-floor.tsv` holds one `path<TAB>percent` line per measured file, and a
`TOTAL` line. Percentages are rounded down to one decimal place. A value must match
`digits.digit`, and a path may appear once.

- `bash tests/coverage.sh` exits 1 if a measured file or the total is below its floor,
  has no floor, or has a malformed or duplicated floor (status `BAD`).
- `bash tests/coverage.sh --update` sets each floor to its current value and never
  lowers one. A new measured file gets its floor here.
- `bash tests/coverage.sh --ratchet BASE` compares the floor file with a `BASE` copy,
  such as the one on the PR's base branch. It fails if any floor is lower, if a floor
  is missing while its file still exists, or if a floor on either side is malformed or
  duplicated (`floor invalid`). `TOTAL` must always exist, on both sides: a base with
  no `TOTAL` row, such as an empty file from a failed `git show`, fails, so a missing
  base can never read as nothing to compare. A floor for a deleted file may go. This
  makes "floors only rise" a machine check and not a habit.
- `bash tests/coverage.sh --lines FILE` prints the lines of `FILE` that count.

Known gap: a measured file that moves out of the globs, for example into a
subdirectory of `hooks/scripts/`, loses its floor on `--update`, and the ratchet
allows that because the old path is gone. Nothing then measures the file.

Exit codes: 0 for success; 1 for a failed test, a missing, low or invalid floor, a
missing argument after `--lines` or `--ratchet`, or an unreadable base file; 2 for an
unknown option or a bash older than 4.1.

Output goes to `.coverage/`, which git ignores. `.coverage/hits.tsv` lists every traced
line as `test<TAB>path<TAB>line`.

## Failure modes

Every one fails the run, or reads as lower coverage, never as higher, so a broken
tracer or a damaged floor file cannot hide a gap.

- **Tracing stops working** (for example, `BASH_ENV` is no longer read): measured files
  report 0% and fall below their floors.
- **A new measured file:** the run fails with `NO FLOOR` until `--update` records one.
- **A suite fails:** the run stops with exit 1 and names the log.
- **A bash older than 4.1:** the tool refuses to run. A test that starts such a bash
  inside the suite runs it untraced, and its lines show as uncovered.
- **A relative path after `cd`:** traced paths resolve from the tool's working
  directory. A suite that changes directory and then runs a script by a relative path
  loses those hits. Run such scripts by an absolute path.
