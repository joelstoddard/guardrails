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
- continuation lines of multi-line strings, heredoc bodies and backslash continuations.
  A `<<` inside `(( ))` or `$(( ))` is a shift and opens no heredoc, even when the
  `(( ))` spans lines;
- lines ending in `# coverage: ignore <reason>`. The reason is required. Use the marker
  only for lines that cannot run.

The rules are a heuristic. They need to be consistent, not exact: floors start at
measured values, so each run compares like with like. A line miscounted the same way
every time changes no result.

A multi-line command counts on its first line, but bash credits its hit to a later
line, and which line differs between bash 5.2 and 5.3. So a traced hit on a
continuation line of a counted command, inside a string or after a backslash, is
credited to the command's counted line. `executable.awk -v spans=1` prints each such
continuation line with its counted line, and `hits()` rewrites `hits.tsv` with it. When
the floors were first set, nine of the fifteen uncovered lines were such first lines.

Known limits:

- A command substitution that spans lines outside quotes, as in `x=$(` on one line and
  `)` on a later one, is traced on the line of its `)`, for the commands inside it too.
  That line does not count and is no continuation, so the lines before it read as
  uncovered. No measured file has one.
- A case label continued with a backslash counts as executable but is never traced
  (`git-cmd.sh:16`).
- A file a test copies before running is traced under the copy's path and is not
  credited to the original. `test_manifests.sh` runs every hook from a copy under a
  path with a space, so those runs do not count.

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
- A file gone from its path counts as moved if another file in the repo has its name,
  as `git ls-files` lists the repo: tracked files, and untracked ones git does not
  ignore. Its floor must follow it to the new path and not fall there. A script moved
  out of the globs, for example into a subdirectory of `hooks/scripts/`, loses its
  floor on `--update`, so the ratchet fails with `floor removed: OLD -> NEW`. If git
  cannot list the repo, the ratchet fails too.
- `bash tests/coverage.sh --lines FILE` prints the lines of `FILE` that count.

Known limit: the ratchet finds a moved file by its name. A move that also renames the
file reads as a deletion, so its floor may go. A deleted file whose name another file
still has reads as moved to that file.

Exit codes: 0 for success; 1 for a failed test, a missing, low or invalid floor, a
missing argument after `--lines` or `--ratchet`, an unreadable base file, or a repo git
cannot list; 2 for an unknown option or a bash older than 4.1.

Output goes to `.coverage/`, which git ignores. `.coverage/hits.tsv` lists every traced
line as `test<TAB>path<TAB>line`, with a continuation line's hit on its counted line.

## In CI

The `test` job runs `bash tests/coverage.sh` after the suite, so a pull request fails
if a file falls below its floor or a new file has none. The floors were measured on
bash 5.3 (macOS) and on bash 5.2 in Ubuntu 24.04, as on the runner, and matched.

On a pull request, the job also gets the floor file from the PR's base branch
(`$GITHUB_BASE_REF`) and runs `--ratchet` against it. A stacked PR compares with its
parent branch, not with `main`, so each PR in a stack is checked against the floors it
would merge into. The step has no fallback. If the base has no floor file, `git show`
fails and the step fails, and the tool also rejects an empty base. A push to `main`
skips the step, because a push has no base and its PR already ran the step.

The PR that added the floor file could not run this step, because its base had no
floor file. The dotfiles had the same problem and added a branch that passed when the
base had no floor file. That branch then had to go (dotfiles #149): it would also pass
for any later base that lost its floor file. Here the ratchet came in a second PR,
stacked on the first, whose base already had the floor file. So no code path skips the
comparison.

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
