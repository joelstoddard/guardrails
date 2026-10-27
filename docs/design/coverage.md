# Coverage and mutation testing of the hook scripts and lib files

The plugins' logic is bash: the hook scripts that guard publishing, commits and pushes,
and the `lib/` files that parse the commands they inspect. Without a measurement, an
agent can add a branch to a hook with no test for it and every check stays green.
`tests/coverage.sh` measures line coverage and fails when it falls, and
`tests/mutate.sh` checks that the tests catch a fault in the lines they run; see
[Mutation](#mutation).

The tools are ported from the
[dotfiles](https://github.com/joelstoddard/dotfiles/blob/main/docs/design/coverage-and-mutation.md),
which measured these scripts before they moved here.

## Why the tool is in the repo

The dotfiles chose a tracer of their own because `kcov` is Linux-only in nixpkgs and
`bashcov` is not packaged. A small tracer in plain bash and awk runs on macOS and CI
alike, so an agent can check before opening a PR.

## What is measured

- `plugins/*/hooks/scripts/*.sh`
- `plugins/*/lib/*.sh`

Each glob is one level deep. Trace lines from any other file, including the tests, are
ignored. The awk programs inside these files are measured too, by statement, in rows of
their own; see [awk programs](#awk-programs).

The suites that run are `tests/test_*.sh`, each with bash as `tests/run.sh` does. Each
test file runs on its own with its own trace log. The Python tests check documents and
manifests, not shell, so they are not run.

## Tracing

The tracer changes no test and no script. It writes `file:line` to a log named by
`COV_LOG`, never to stdout or stderr, so tests that check output are not affected.

`BASH_ENV` names `tests/coverage/bash_env.sh`, which every non-interactive bash reads.
It opens a file descriptor on the log, points `BASH_XTRACEFD` at it, sets `PS4` to
print `file:line`, and runs `set -x`. A hook that `run_hook` starts with `bash "$script"`
is traced this way, and so is a lib that a test sources. The commands of a `bash -c`
string name no file, so a trace line such as `++:1` has an empty path; `hits()` skips
it, as the empty path would otherwise resolve to the working directory and, run from
the repo's root, stop the run with `bad array subscript`.

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
- each line of a case label continued with a backslash, `a | \`, but its last. bash
  never traces a label, so that last line is read on its own, and counts if its arm
  holds a command. A pipeline of single words, `ls | \`, reads the same way;
- continuation lines of multi-line strings, heredoc bodies, backslash continuations,
  and `$( )`, `<( )` and `>( )` substitutions that span lines, quoted or not.
  A `<<` inside `(( ))` or `$(( ))` is a shift and opens no heredoc, even when the
  `(( ))` spans lines;
- lines ending in `# coverage: ignore <reason>`. The reason is required. Use the marker
  only for lines that cannot run.

The rules are a heuristic. They need to be consistent, not exact: floors start at
measured values, so each run compares like with like. A line miscounted the same way
every time changes no result.

A multi-line command counts on its first line, but bash credits its hit to a later
line, and which line differs between bash 5.2 and 5.3. So a traced hit on a
continuation line of a counted command, inside a string or a substitution or after a
backslash, is credited to the command's counted line. `executable.awk -v spans=1` prints each such
continuation line with its counted line, and `hits()` rewrites `hits.tsv` with it. When
the floors were first set, nine of the fifteen uncovered lines were such first lines.

Known limits:

- bash reads the commands inside a `$( )` again as it prints them, and numbers them
  from the substitution's `)` line, one line for each line it prints. It numbers those
  inside a `<( )` or `>( )` from the substitution's first line. A substitution whose
  commands bash prints on one line is traced within its own lines, which credit its
  counted line. bash prints each line of code, and each part of a compound command such
  as `while`, `if` or `case`, on a line of its own, even when the source has them on one
  line. So such a substitution is also traced on the lines after it, where its hits
  credit whatever command is there, and can make a line that never ran read as covered.
  `findings-gate.sh:22` is one, and the line after it runs anyway. A `( )` subshell and
  a function body are traced on their own lines. A backtick substitution that spans
  lines is traced from the line after its closing backtick, and is not handled.
- A file a test copies before running is traced under the copy's path and is not
  credited to the original. `test_manifests.sh` runs every hook from a copy under a
  path with a space, so those runs do not count.

Known blind spot: the jq programs in the hooks count as one shell line each, and a test
that runs that line covers all of it. The awk programs have a measure of their own.

## awk programs

Most of the splitter's logic is an awk program in a shell string in `shell-split.sh`,
and several hooks hold smaller ones. The line tracer counts each as the one shell line
that runs it, so the splitter read 100% whether or not its branches were tested. So
coverage also counts the statements of each awk program that ran, under gawk's
profiler, without changing the measured files:

- **The shim.** For a report run, `coverage.sh` sets `COV_AWK`, and `bash_env.sh` then
  defines an `awk` function in every traced bash. A call from a file whose path holds
  `plugins/` goes to `tests/coverage/awk_shim.sh`, with the caller's path; any other
  call runs awk as before. `--trace`, which mutation uses, sets no `COV_AWK`.
- **Two runs.** The shim runs the call under `gawk --profile`, its output thrown away,
  and at the same time with the `awk` on `PATH`, whose output and status the caller
  gets, and waits for both. So the suites still test the system awk, BSD awk on macOS
  and mawk or gawk on Linux, and only the count depends on gawk. The function turns
  xtrace off for the call, as the trace already holds it, and back on after.
- **The same input for both.** The shim reads awk's POSIX options, `-F`, `-v`, `-f` and
  `--`, to find the operands. It copies an operand that is not a regular file, such as
  a `<( )`, which can be read only once. When awk reads stdin, because there is no file
  operand or one is `-`, the shim saves stdin for both runs; otherwise stdin stays the
  caller's. The suites run with stdin from `/dev/null`, so the shim never waits on a
  terminal.
- **Counting.** gawk writes each run's profile: the program printed again, with each
  statement's count. `tests/coverage/profiles.awk` merges them for each file and each
  distinct program in it: a statement counts as run if any run of that program ran it.
  Braces, `else`, and rule and function headers are not statements; a rule's pattern
  and an `if`'s condition are.
- **Rows.** Each measured file with an awk program that ran gets a row `awk:PATH`, with
  a floor and a ceiling like a file's, counting statements. The rows are not in `TOTAL`,
  which counts shell lines. `.coverage/awk-missed.tsv` lists each statement no run
  reached, as gawk prints it.
- **Cost.** Each call starts a bash, copies its input and runs gawk beside the system
  awk, about 20 ms on macOS, so the report run of about 1,760 calls takes about a
  minute longer there. `--trace` and so mutation pay nothing.
- **Failures.** Without gawk, a report run stops with exit 2. A run whose profile gawk
  did not write stops the report with exit 1, as it would otherwise read as nothing to
  measure.
- **The ratchet.** An `awk:` floor follows its file through a rename or a move, and may
  go only once the file no longer has the word `awk` in it.

Known limits:

- An awk program that no test runs has no profile, so it is not in its file's row. Its
  call line reads as uncovered in the file's line row, which every measured file but
  `publish-cmd.sh` holds at 100%.
- The shim reads all of a stdin that awk reads, before either run, even when the
  program stops early, as the one in `allow-gh-api-read.sh` does: a command writing
  into the pipe then never sees awk stop. A program that writes a file or runs a
  command would do it twice; no measured program does.
- gawk and the system awk can differ, as BSD awk does on invalid bytes (#76); the count
  is gawk's path through the program.
- A copied `<( )` operand has a different name, which a program that reads `FILENAME`
  would see. No measured program does.

## Floors and the ratchet

`tests/coverage-floor.tsv` holds one `path<TAB>percent<TAB>most` line per measured
file, and a `TOTAL` line for all of them together. `percent` is the floor, rounded down
to one decimal place, and must match `digits.digit`. `most` is a ceiling, the most
uncovered lines the row may have, a whole number. A path may appear once.

A row passes at or above its floor, and also below it while its uncovered lines stay
within its ceiling. A floor alone punishes deleting covered code: removing two covered
lines from a fully covered `repo-cmd.sh` took the total from 597/600 to 595/598, which
rounds down from 99.5 to 99.4 and failed, though nothing was less tested, and deleting
a covered line from `publish-cmd.sh`, at 94/97, would fail that file the same way.
Deleting code never adds an uncovered line, and losing the test of a line, or adding a
line no test runs, always does, so the count tells the two apart where the percentage
cannot. Rounding to nearest would only move the edge: deleting enough covered lines
crosses it again. Letting `TOTAL` pass whenever every file meets its floor would let a
new file with a low floor of its own drag the total down. A new uncovered line still
fails its row unless enough covered lines come with it to hold the percentage, as
before; the ceiling then stays at the lower count, so a later deletion needs the
percentage again until that line is covered. A row with no ceiling, as in a floor file
from before the ceilings, needs its floor.

- `bash tests/coverage.sh` exits 1 if a measured file or the total is below its floor
  with more uncovered lines than its ceiling, has no floor, or has a malformed or
  duplicated floor or ceiling (status `BAD`).
- `bash tests/coverage.sh --update` sets each floor to its current value and never
  lowers one, and each ceiling to the current count and never raises one. A new
  measured file gets both here.
- `bash tests/coverage.sh --ratchet BASE` compares the floor file with a `BASE` copy,
  such as the one on the PR's base branch. It fails if any floor is lower, if a floor
  is missing while its file still exists, or if a floor on either side is malformed or
  duplicated (`floor invalid`), and if a ceiling rose (`ceiling raised`) or went
  (`ceiling removed`). A base row with no ceiling, as on a base from before them, has
  none to compare.
  `TOTAL` must always exist, on both sides: a base with
  no `TOTAL` row, such as an empty file from a failed `git show`, fails, so a missing
  base can never read as nothing to compare. A floor for a deleted file may go. This
  makes "floors only rise" a machine check and not a habit.
- A file gone from its path counts as moved, and its floor must follow it to the new
  path and not fall there. With `--base REV`, the revision the base floor file comes
  from, git says where it went: `git diff --find-renames --name-status REV` compares
  that revision with the working tree, so a file renamed as it moved keeps its floor,
  and one git saw deleted loses it even when another file has its name. A file git
  does not name, such as one moved with a plain `mv` and not added, and every file
  without `--base`, counts as moved if another file in the repo has its name, as
  `git ls-files` lists the repo: tracked files, and untracked ones git does not
  ignore. A script moved out of the globs, for example into a subdirectory of
  `hooks/scripts/`, loses its floor on `--update`, so the ratchet fails with
  `floor removed: OLD -> NEW`. If git cannot diff against `REV` or list the repo, the
  ratchet fails too.
- `bash tests/coverage.sh --lines FILE` prints the lines of `FILE` that count.

Known limit: without `--base`, the ratchet finds a moved file by its name alone. A
move that also renames the file reads as a deletion, so its floor may go, and a deleted
file whose name another file still has reads as moved to that file. CI passes `--base`.

Exit codes: 0 for success; 1 for a failed test, a missing, low or invalid floor, a
missing argument after `--lines`, `--ratchet` or `--base`, an unreadable base file, a
revision git cannot diff against, or a repo git cannot list; 2 for an unknown option,
`--base` without `--ratchet`, a bash older than 4.1, or no gawk for a report run.

Output goes to `.coverage/`, which git ignores. `.coverage/hits.tsv` lists every traced
line as `test<TAB>path<TAB>line`, with a continuation line's hit on its counted line.
`.coverage/awk-missed.tsv` lists the awk statements no run reached.

## In CI

The `test` job runs `bash tests/coverage.sh`, so a pull request fails if a suite fails,
a file falls below its floor or a new file has none. It is the job's only run of the
shell suites, so CI does not run them twice (#74): the tool prints
`coverage: <suite> passed` for each, and the full output of one that fails. A Python
step runs the Python tests that `tests/run.sh` runs too. The floors were measured on
bash 5.3 (macOS) and on bash 5.2 in Ubuntu 24.04, as on the runner, and matched.

On a pull request, the job also gets the floor file from the PR's base branch
(`$GITHUB_BASE_REF`) and runs `--ratchet` against it, with `--base FETCH_HEAD` so a
renamed file keeps its floor. The diff runs from the base branch's tip, the revision
the floor file comes from, to the checkout, not `BASE...HEAD` from their merge base:
the checkout is one commit deep, so git finds no merge base. A stacked PR compares with its
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
- **A suite fails:** the run stops with exit 1, names the log and prints the suite's
  output.
- **A bash older than 4.1:** the tool refuses to run. A test that starts such a bash
  inside the suite runs it untraced, and its lines show as uncovered.
- **A relative path after `cd`:** traced paths resolve from the tool's working
  directory. A suite that changes directory and then runs a script by a relative path
  loses those hits. Run such scripts by an absolute path.

## Branches

The tracer measures lines, not branches, and has no branch floor. A line that holds a
branch, such as `[[ -n $x ]] && return 0`, `cmd || exit 1` or a one-line
`if x; then y; fi`, reads as covered once any part of it runs. A branch on a line of
its own, such as an `if` body or a case arm, is measured already, as that line: bash
never traces a case label, so a one-line arm counts only when its command runs.

Branches within a line cannot be measured soundly in this tracer, and a measurement
that can read higher than the truth would break the rule the failure modes keep:

- **xtrace says which line ran, not which operand.** It prints each command it runs,
  after expansion, with the line's number. Telling which side of `a && b || c` printed
  it means matching expanded text back to source, and two sides can expand to the same
  text, as in `echo x || echo x`.
- **Counting commands on a line overcounts.** The commands inside a `$( )` on the line
  trace on it too, and those of a `$( )` that bash prints on more than one line trace
  on the lines after it (see [Executable lines](#executable-lines)). So a line could
  show more commands than it has sides, and read a side that never ran as taken.
- **A DEBUG trap changes the code it measures.** `BASH_COMMAND` holds the command before
  expansion, but as bash prints it again: `echo "$v  b"   >/dev/null` reads
  `echo "$v  b" > /dev/null`, so matching it to the source needs bash's printer. And
  the trap is code that runs before every command of the hooks: to reach functions and
  subshells it needs `set -T`, which the hooks would inherit, and it replaces any DEBUG
  trap of their own. The xtrace tracer only writes to its own file descriptor.
- **Probes need a shell parser.** Rewriting each operand into `{ probe; cmd; }` in a copy
  changes the status that `&&`, `||`, `!` and `set -e` read, and placing probes right
  needs a parser of bash, which this repo does not have.

[Mutation testing](#mutation) is the check for these branches instead. It swaps `&&`
and `||`, drops a leading `!`, flips `[[ ]]` tests and exit statuses, and deletes
commands, on every covered line. A branch within a line that no test tells apart leaves
its mutant alive, and the mutation floors hold the score.

## Mutation

Coverage shows that a test ran a line, not that it checks the line. `tests/mutate.sh`
changes one covered line at a time and runs the tests that cover it. A mutant that
leaves every test green survived, and the line is not checked. No maintained mutation
tool exists for shell, so the mutator is plain bash, POSIX awk and perl, ported from the
dotfiles with the coverage tool.

`tests/coverage/mutants.awk` makes the mutants. It works on the executable lines that
`coverage.sh --lines` reports and `hits.tsv` shows as covered. An uncovered line gets
no mutants, because coverage already reports it.

| Operator    | Mutation                                                                     |
| ----------- | ---------------------------------------------------------------------------- |
| Comparison  | `==` and `!=` swap; `-eq`/`-ne`, `-lt`/`-ge`, `-gt`/`-le`, `-z`/`-n` swap    |
| Logic       | `&&` and `\|\|` swap; a leading `! ` is dropped                              |
| Exit status | `exit` or `return` `0` becomes `1`; `1` becomes `0`; `exit 2` becomes `0`    |
| Boolean     | `true` and `false` swap, as whole words                                      |
| Deletion    | a simple command or assignment becomes `:`                                   |

Each restriction keeps a mutant a real fault and not noise:

- **Test operators only inside `[[`, `[` or `test`.** `-n` and `-z` are also options of
  `head`, `sort` and others. Swapping them breaks a command and not a decision.
- **Deletion only of simple commands and assignments.** Deleting `if`, `then`, `do`,
  a line that opens a block, a pipeline or a heredoc, or a continued line gives a script
  that does not parse. Such a mutant is invalid and tells nothing. Declarations with
  `local`, `declare`, `export` or `readonly` are not deleted either.
- **No mutants inside strings or comments.** A changed string is data, and the tests
  that compare it fail for a reason that is not a logic fault. A comment is not code.
  The scanner tracks quotes and backslashes so a `==` in a string is not touched.

### Running the mutants

- **Test selection.** `hits.tsv` maps each test to the lines it ran. A mutant runs only
  the tests that ran its line, and stops at the first one that fails.
- **Isolation.** The run makes one scratch copy of the working tree for each worker, so
  a mutant never touches the checkout. Each worker puts the original file back after
  each mutant. Workers take plan lines by index modulo `-j`, so one worker and many
  workers give the same results. A test runs as `bash tests/test_*.sh` in the copy,
  untraced.
- **Process groups.** A test runs in its own process group, and the wrapper (perl) kills
  the group after the test exits, after a timeout, and when the run itself gets HUP, INT
  or TERM. A mutant that hangs, or a test that leaves a background process, leaves
  nothing running.
- **Interrupted run.** A worker ignores INT, so the main shell stops the workers itself.
  When it exits, for any reason, it sends TERM to each worker and to the wrapper of its
  test, then removes the scratch copies. It does not signal its process group, because
  the caller may share that group.
- **Wall-clock budgets.** One worker per CPU loads the machine, so a test with a time
  budget, such as the 5 s ceilings in `test_guard_publish.sh`, could fail whatever the
  mutant, and read as a kill. Each test that runs a mutant, and its clean run, gets
  `GUARDRAILS_TIME_SCALE=10`, and a budget multiplies its ceiling by
  `${GUARDRAILS_TIME_SCALE:-1}`, so budgets stretch as far as the hang limit below.
  Mutation judges what a test asserts, not speed: a mutant that only makes a guard
  slower is killed only past the hang limit. `coverage.sh` clears the variable, so the
  suites, CI's only run of them, keep their budgets at full strength whatever the
  caller's environment holds. A new test with a wall-clock check reads it the same way.
- **Timeout.** Ten times the clean run of that test, the same `TIME_SCALE`, with a floor
  of 2s. A timeout exits 124 and counts as killed: a mutant that makes a test hang is
  detected. Exit 127 or 255 means the wrapper failed to start the test or to fork. That
  is not a kill: it stops the run with exit 1.
- **Red baseline.** `bash tests/coverage.sh --trace` runs first, and each selected test
  runs once unmutated. If one fails, the run stops with exit 1.

The tool needs bash 5 for `EPOCHREALTIME`, perl, and `pkill` and `pgrep` from procps,
and the suites' own needs, the `claude` CLI among them.

### Invalid mutants and errors that look like a score

A mutant that fails `bash -n` is invalid. It is out of the score, and it is neither
killed nor survived.

A tool error must never read as a clean score, so these stop the run:

- a measured file that does not parse unmutated (exit 1), because every mutant of it
  would be invalid and the file would score 0 of 0;
- a failing `coverage.sh --files` or `coverage.sh --lines` (exit 1), because an empty
  list reads as nothing to mutate;
- a measured file with executable lines and no covered line (exit 1), because its tests
  did not run. A file with no executable lines is skipped without a message;
- a failing suite (exit 1) and a failed worker (exit 1), which includes a test wrapper
  that fails by itself (exit 127 or 255).

A floor breach exits 1. Usage errors exit 2: an ignore row without a reason, a `FILE`
argument that is not measured, `--update` with other arguments, and a `--changed`
revision git cannot diff against. An ignore row that names an unmeasured file matches
nothing. A run with survivors and no floor breach exits 0.

### Results, equivalent mutants and the ignore file

Score is killed divided by killed plus survived, for each file and in total. The table
and the survivors, as `survived file:line operator original -> mutated`, print to
stdout. `.coverage/mutants.tsv` holds every result.

`tests/mutants-ignore.tsv` lists mutants that cannot change behaviour: file, operator,
original line trimmed, and a required reason, separated by tabs. A row matches on the
line text and not the line number, so it survives edits elsewhere in the file. An
ignored mutant is out of the score. A row without a reason stops the run, so no one can
silence a survivor without saying why. Each survivor gets a test that kills it, or a
reasoned ignore row; a survivor that a test could kill stays a survivor, and its file's
floor sits below 100 until a test kills it.

### Use

- `bash tests/mutate.sh --changed` mutates the measured files that differ from where the
  branch left `origin/main`, or are untracked, and fails below a file's floor. Run it
  before a PR that changes measured shell. `--changed REV` compares with `REV` instead.
- `bash tests/mutate.sh --update` runs every file and raises the floors. It is the one
  command that re-measures them after a change, and it never lowers one.
- `bash tests/mutate.sh FILE...` mutates the named measured files.
- `-j N` sets the number of workers. The default is the number of CPUs. One scratch
  copy of the tree exists for each worker.

### Floors

`tests/mutation-floor.tsv` has the format of `tests/coverage-floor.tsv`: one
`path<TAB>percent<TAB>most` line per measured file and a `TOTAL` line, where `percent`
is the score rounded down to one decimal place and `most` the most surviving mutants
the row may have.

- A row passes at or above its floor, and also below it while its survivors stay
  within its ceiling, for the reason given for coverage in
  [Floors and the ratchet](#floors-and-the-ratchet): deleting code whose mutants were
  killed lowers the score and tests nothing less, while a weakened test or new code no
  test checks adds a survivor.
- Every row of the table shows the file's floor, its ceiling and a status: `ok`, `LOW`,
  `NO FLOOR` or `BAD` (a floor that is not `digits.digit`, a ceiling that is not a whole
  number, or a path with two floors). A floor never reads as no limit.
- The run exits 1 when any reported row is not `ok`. The table and the survivors print
  first.
- A full run also checks `TOTAL`. A run of `FILE...` or `--changed` checks only the
  files it mutated and prints no `TOTAL`, because a partial run has no meaningful total.
- `bash tests/mutate.sh --update` runs every file, then sets each floor to its current
  score and each ceiling to its current survivors, never lowering a floor or raising a
  ceiling. A new measured file gets its floor here. Combined with `--changed` or `FILE`
  it exits 2. A run that stops with an error writes nothing, and neither does a
  malformed floor.
- `bash tests/coverage.sh --ratchet BASE tests/mutation-floor.tsv` makes "floors only
  rise" a machine check here too, with the rules in
  [Floors and the ratchet](#floors-and-the-ratchet).

The floors started at the scores measured on the code of `main` at b0d58e5, not at
100: the tests leave many mutants alive, and the floors record that rather than hide
it, 499 of 637 mutants killed (78.3%). Only mutants that cannot change behaviour are in
`tests/mutants-ignore.tsv`. Every other survivor is a test to write, and the weekly run
lists them. Three full runs differed in four mutants, each killed in one run only: the
depth caps at `git-cmd.sh:94` and `publish-cmd.sh:102`, `lint-warn.sh:13` and
`shell-split.sh:231`. Run alone, with no load, every test of each passed, so all four
kills were spurious, and the floors take the counts with those mutants alive (see
Flaky tests below). The third run, on more load, scored 501 of 637 against them and
passed.

### In CI

On a pull request, the `test` job runs `bash tests/mutate.sh --changed FETCH_HEAD` after
the coverage step, so a PR that changes a hook script or lib fails if that file's score
falls below its floor with more survivors than its ceiling. It mutates only the files
the PR changes: a full run took 21 minutes on 14 cores, too long for every PR on the
4-CPU runner. A PR that changes no measured file mutates nothing. One that does runs
the suites under tracing again, inside `mutate.sh`, because the mutants need `hits.tsv`
fresh, and then each mutant's tests.

The weekly workflow, `.github/workflows/mutation.yml`, runs every file every Monday and
by hand, and checks `TOTAL`. It catches what `--changed` cannot see: a PR that weakens
a test without touching the file it tests. It writes the table and the survivors to
the job summary and fails on a floor breach, which notifies the repo owner. The
dotfiles' version also keeps a GitHub issue of the survivors up to date, which needs a
token that can write issues. Every workflow here runs with a read-only token
(`tests/test_workflow.py`), because main updates every installed machine, so the run
reports only in its summary.

The ratchet for the mutation floors, `coverage.sh --ratchet` on the base branch's copy
of `tests/mutation-floor.tsv`, cannot run in the PR that adds that file, as with the
coverage floors: its base has none, and the step has no fallback. It comes in the next
PR, whose base has the file.

### Known limits

- **Uncovered lines get no mutants.** A mutation score says nothing about them. Read it
  with the coverage report.
- **Tests that write into the tree.** A test that writes inside its scratch copy keeps
  that state for the next mutant of the same worker. No suite does so today: each
  writes only under `mktemp`.
- **Equivalent mutants.** Some survivors cannot be killed. Judge each one before an
  ignore row. A row matches every line of its file with the same text, so a line whose
  text another line shares, with a killable mutant, cannot be ignored.
- **CI and macOS differ line by line.** A platform conditional is covered, and so
  mutated, on one branch only.
- **Flaky tests.** A test that fails at random reads as a kill. The run does not retry.
  A spurious kill only raises a score, never lowers it, so floors set from the lowest
  run do not fail at random; a floor set from a run with a spurious kill would. The
  wall-clock budgets were one cause, and are stretched for mutants (see
  [Running the mutants](#running-the-mutants)).
- **Code in another language.** The awk and jq programs in shell strings get no mutants.
- **The scanner reads one line at a time.** It treats a `-n` or `-z` as a test operator
  when `[[`, `[ ` or `test ` comes earlier on the line, even outside the brackets. It
  does not track quotes nested inside `$( )`. Such a mutant breaks a command and is
  killed at once, or changes a string.
