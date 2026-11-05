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
four levels deep, as `publish-cmd.sh` does. A shell's script is the one shell word after
its `-c`, joined across the words its quotes span, as the words after it are the script's
`$0` and arguments, so `bash -c 'git commit' a0` and `su -c 'git commit' root` commit; where its
quote never closes in its segment, the script runs to the segment's end, as before. A script
nested deeper is one no guard reads, so both guards ask about it, as about a pipe into a shell (#102); a heredoc fed to a shell is split as script
lines by `shell-split.sh`, as are the `$( )` and backticks in an unquoted heredoc body.
The body stays a script when the shell also has `-c` or a script file, because either can
run it: `bash -c 'source /dev/stdin' <<EOF` does, and the guards cannot tell which
payloads read their stdin. The cost is a false positive where the payload reads the body
as data, as `bash -c 'cat' <<EOF` does (#93).
When a line opens several heredocs, as in `bash <<A; cat <<B`, their bodies follow it in
turn, and each is read by its own rule: a shell's as script lines up to its delimiter, an
unquoted one's substitutions as commands, a quoted one's not at all (#108). A shell reads
the heredoc its script came from up to the delimiter, whatever the script leaves open there,
a quote, a substitution or a heredoc of its own, so the splitter ends the script there too,
the outermost first, and reads on from where it was before the body. A body starts once the
command that opened it ends, as the shell reads it: after a quote, backtick or substitution
that the command carries across lines, whose commands run first.
A `cd` inside `sh -c` ends with that child shell, while one inside `eval` lasts. A pipe
into a shell runs commands no guard can see, so `guard-default-branch` asks when the
directory it would run in is on its default branch, as `guard-publish` asks. A shell given
`--version` or `--help` exits, or refuses it, before it reads a script, so a pipe into one asks
nothing; `-h` is not one of these, as it sets `hashall` in bash, zsh and ksh, which then read stdin.

So does a pipe into another interpreter that reads its script from stdin: python, node,
perl, ruby, php or lua given no script file, no code (`-c`, `-e`, `-r` and the like), no
module (`-m`) and no option that exits first, such as `--version`, and deno or bun given
`-` as their script (#92). `python3 script.py`, `node -e '…'` and `python3 -m json.tool`
are not, and `jq` is not an interpreter here. Short options are read as getopt reads them,
from a list for each interpreter, so the value in `python3 -W ignore` or `perl -I lib` is
not taken for a script. An option that takes a value but is not in its list has the value
read as a script file, so the pipe asks nothing, as before.

## Finding the command word

A word before the command can hide it: `sudo bash -c '…'`, `env FOO=1 git commit`,
`then bash <<EOF`, `(bash -c …)`. So every reader of a segment, in the publish guard,
the git guards and the shell readers, finds the command word through one lookup,
`_guardrails_command_at` in `shell-split.sh` (#90). It skips:

- `NAME=value` assignments;
- redirects, such as `2>/dev/null` or `> out`, where an operator alone takes the next word
  as its target (#109). The split has already dropped a heredoc's delimiter, and the per-line
  split a here-string's word, so a `<<` alone takes none, nor a `<<<` in the per-line split,
  unless the next word starts with a digit, which the split keeps as a shift's operand (#131).
  A target is one shell word, though a quote or an escaped blank in it spans several words
  of the split, as in `> 'a b c'`, so the words up to the one that closes it go with it.
  Where it does not close in its segment, as in a line cut from a quote spanning lines, only
  its first word does, as before;
- the keywords `!`, `{`, `(`, `if`, `then`, `elif`, `else`, `while`, `until`, `do` and
  `in`, and a `(` fused to the next word;
- a function's header (`f()`, `f ()`, `function f`), a case arm's pattern (a word ending in
  `)`, after `case … in`) and `coproc` with its name, so the body or arm is read (#110);
- the wrappers `sudo`, `env`, `nohup`, `exec`, `command`, `time`, `xargs`, `timeout`,
  `nice`, `stdbuf`, `doas`, `setsid`, `chroot`, `docker exec`, `kubectl exec`, `nsenter`,
  `runuser` and `script`, with their options, and the duration
  of `timeout` and the root of `chroot`. In a cluster such as `-Eu`, the first option
  that takes a value takes the rest of the word, or the next word if none is left, as
  getopt does. A long option that takes a value, such as `sudo --user`, takes the next
  word unless written with `=` (#116). A value or operand is one shell word, joined across
  the words of the split its quotes span, so `sudo -p "Password please:" git commit` commits.

The shell drops a command word's quotes and backslashes, so the lookup does too before it
matches a word: `"bash"`, `'gh'`, `ba\sh` and `$'bash'` are read as `bash`, `gh` and `bash`
(#111). Only a word of 64 characters or fewer is read this way, which any name it matches
is, as the substitution is slow on a long word.

The words after the command are read the same way, in `_guardrails_skip_redirect` and
`_guardrails_unquote`, which the lookup shares. So git's global options and subcommand, and
the words before a publish verb, are read past redirects and without their quotes: `git
2>/dev/null commit`, `git "commit"` and `gh >out pr create` are what they run (#131). So are
`gh api`'s method and body flags and httpie's method: `gh "api" -X "POST"` and `http >out POST`
write (#146). A redirect between `-C` and its directory does not hide the directory, and a redirect's target
is not read as `-C` or as a publish verb. The publish guard still matches an option before a
verb as written, so a quoted `"-w"` stays a word before a verb, as it was before. A word that is one
piece of a quoted argument of several words is read differently; see "Known limitation".

A redirect needs no blank before it, so `bash<<<'…'` feeds bash a script and `git>/dev/null
commit` commits. The lookup, git's skip and the publish guard's lead words read a word with a
redirect fused to it, outside quotes, as the word alone, and skip the redirect's target when it
is the next word (#91). A `-c` fused to text, as in `bash -c"…"`, needs no such reading: bash,
zsh, dash and ksh all take it as a cluster of options and refuse it, and `-c""` leaves the
script in the next word, which is read as before.

A wrapper with no command after it usually fails or prints something, but `chroot DIR`,
`sudo -s` or `-i`, `doas -s`, `ssh host`, `nsenter` and `script FILE` start a shell that reads
commands from stdin, so a pipe into one asks, as a pipe into a shell does, and so does a
here-string (#113, #133). The lookup notes such a wrapper in `_GUARDRAILS_CMD_SHELL` when no
command follows it. `ssh` with `-N`, `-W`, `-O`, `-G`, `-Q` or `-V` starts none. `su` runs its
user's shell, read like a shell: its `-c` gives a payload, and with no `-c` and no argument after
its user, a pipe into it asks. `script -c` runs a command line too, read the same way, where
`script FILE CMD`, and util-linux's `script FILE -- CMD`, run `CMD` as a wrapper's command.

`command -v` and `-V` name a command without running it, so there `command` is the
command word. `ssh host`, `docker exec container`, `kubectl exec pod --` and `nsenter` run
their command elsewhere, as you: on another host, in a container or in another namespace.
`docker exec`, `kubectl exec` and `nsenter` run their words as the command, as `sudo` does,
so the lookup sees through them to it, and `docker exec c gh pr comment …` is read as a
publish. ssh joins the words after its host into a command line that the shell there reads,
so it keeps `ssh` as its command word, unless a shell is that command, and its command line
is a payload, read like `eval`'s, with `_GUARDRAILS_CMD_ARGS` marking where it starts; the
publish guard still reads the words after `ssh` too, as before (#113). ssh reads options
after its host as well, as kubectl does after its pod. `_GUARDRAILS_CMD_REMOTE` notes a
command that one of these runs, as git's repo there is not the local one; see "Commits
elsewhere".

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
  it asks whether a shell's name is a word anywhere in the segment, before the `<<` or
  after it, as in `<<EOF bash`, which feeds the body to bash (#132). That is a superset of
  the lookup, so no wrapper or redirect hides a shell. It also catches wrappers the
  lookup does not know, such as `docker run -i image bash <<EOF`. The cost is a false
  positive when a shell's name is a plain argument, as in `grep -w bash <<EOF`. A word
  counts with its quotes and backslashes dropped, as `ba\sh` does. Inside quotes, only
  the first word counts, and only when the quote ends with it or an option follows it,
  as in `ssh host 'bash -s' <<EOF`. So prose such as `--title "bash fix"` does not make a
  heredoc after it a script.
  With no command, `chroot DIR`, `sudo -s` or `-i`, `doas -s` and `ssh host` start a
  shell, so `chroot` and `ssh` count as a shell's name, and so does an option with an `s`
  or `i` among its first five characters after `sudo` or `doas` (#113, #133). So
  `sudo -u root tee f <<EOF` stays data, and `sudo -i tee f <<EOF` and
  `ssh host 'cat > f' <<EOF` cost a false positive, as `grep -w bash <<EOF` does.
  A body is run indirectly, too, and read as a script: where `source` or `.` reads
  `/dev/stdin` or `-`, where a substitution that holds the heredoc is `eval`'s argument or
  follows a shell's `-c`, as in `eval "$(cat <<EOF …)"`, and where a shell or `source`
  reads it through a `<( )`. A substitution anywhere else keeps its heredoc data, so
  `gh pr create --draft --body "$(cat <<'EOF' …)"` and `git commit -m "$(cat <<EOF …)"`
  read the body as the text it is. A pipe into `source /dev/stdin` asks, as a pipe into a
  shell does.
- **The directory walk follows only a plain `cd`.** A `cd` in a subshell, `(cd /x)` or a
  pipeline's `cd /x | …`, does not last, and one after a keyword, `if false; then cd /x; fi`,
  may not run. Following
  either could judge a repo other than the one the commit lands in, which is weaker than
  not following it. The same holds for the `cd` in an `eval` behind a keyword. A `cd`
  behind any other word the lookup skips, a redirect included, is not followed either. A
  quoted `"cd"` or `"eval"` is, as the shell runs it, but not one piece of a quoted argument,
  such as `"cd /x"`, which the shell would run as a command of that whole name (#150).
  A `cd` inside a `( … )` or `{ …; }` group is followed for the commands after it in the group,
  so `(cd /wt && git commit)` is judged in `/wt`. The walk drops the openers at a segment's start
  and restores the directory the group opened in after the first segment that holds a `)` or
  `}`. A `)` that closes nothing, as in a quoted message, ends the group early, which judges the
  rest where the group started, as before groups were followed, never late. A brace group runs
  in the current shell, so its `cd` lasts past it, but the walk follows it inside the group only,
  as the user chose: `{ cd /x; }; git commit` is judged where the shell sits, as before.

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
| `pushd <path> && git commit` | As `cd`; `popd` returns to the directory before it. `pushd` alone, or with `+N`, `-N` or `-n`, is not guessed at. |
| `git -C <path> commit` | Cumulative — each `-C` is relative to the previous one. |
| `env -C <path> git commit` | `env -C`, `sudo -D` and their `--chdir` run that one command there, before git's own `-C` (#112). |

Every matching command is judged, not only the first, so `git -C a push && git -C b push` has
both directories judged, each once. A command with none, such as a pipe into a shell, has the
directory it ends in judged. Each directory costs `guard-default-branch` some 33 ms of git
calls at load 10, and a command within the length cap can name 6,500 of them, which would
time the hook out. So past 64 directories it asks.

A directory that does not exist when the hook runs, as one the command makes first or names
through a variable, as in `mkdir d && env -C d git commit` or `cd "$WT"`, used to be skipped,
which let the commit through. `guard-default-branch` now judges it at its nearest existing
ancestor, where git would find its repo, as main did for `env -C`, whose directory it did not
read. A prefix of a path exists if a longer one does, so it finds that ancestor by halving the
path's components, as climbing one at a time is quadratic in a deep path: 16,000 `env -Cx`
wrappers before a commit took it 14 s that way, and take 4.4 s.

A command substitution runs before the command that holds it, in a child shell of its own, but
the carried split writes its commands after all the rest (#87). So the walk reads that split in
tag mode, `_guardrails_split_awk 1 <cmd> 0 1`, where a line before each segment says where it
runs (#114). A line in place is tagged `T`, and `T1` when it starts inside a substitution: a
piece of one cut at an operator inside it, such as ` cd /x)` from `echo $(true && cd /x)`. Its
commands are in the substitution's own segments, so the walk skips it, where it used to follow
that `cd` to `/x)`, a path that does not exist, and skip the check. Each instance of a
substitution opens with a line `O` naming its parent instance, or the line in place that holds
it, and its segments are tagged `S`. So the walk starts each one where the line that holds it,
or its parent at the point it opens, stands, and a `cd` in one reaches neither another nor the
commands after it. A heredoc body's substitutions are held by the line that opened it, a shell's
too when its heredoc is unquoted, as the shell expands them before the shell it feeds starts.
That shell drops the backslash of an escaped `\$(` or `` \` `` there, so the script runs the
substitution itself: the split reads it as the script's, held by its own line. A shell's
heredoc is the script that shell runs, so its lines are tagged `B` with the line that opened it,
and the walk reads them as a script of their own, started where that line stands: a `cd` in it
reaches nothing past its delimiter, nor does one after its opener, as in `bash <<EOF; cd /y`,
reach it. Each tag also names the operator before its segment, so the walk knows a `cd` piped
into the next command, which runs in the pipeline's subshell and does not last (#115). bash runs
the last command of a pipeline in a subshell too, but zsh runs it in the current shell, so a
`cd` there is followed, as before. Only the walk reads tags; the guards' other passes read the
split as before, byte for byte.

## A branch switched to before the commit

A commit after a switch to a branch, in one `&&` chain, lands on that branch, as in
`git switch -c fix/x && git commit -am x`, the natural recovery after a refusal (#81). So the
walk names that branch in the commit's record, `local:fix/x <dir>`, and `guard-default-branch`
judges it rather than HEAD as it stands before the command runs. Only a switch whose target
it knows counts: `git switch <branch>`, `-c`, `-C`, `--create`, `--orphan`, and `git checkout
-b`, `-B` or `--orphan`. It counts only where the switch must succeed for the commit to run:
in the walk's top chain, run here, unwrapped, in the commit's directory, not after `||` nor
piped into the next command, and every link from it to the commit an `&&`. Anything that may
leave HEAD elsewhere drops the branch from every record, so the commit is judged at HEAD as
before: a `checkout` without `-b`, which may restore a file, `switch -` or `--detach`, a switch
in a substitution, a payload, or any git subcommand but those that cannot move HEAD to another
branch, such as `add`, `status` or `push`. So `git switch main && git commit` is judged on
`main`, which is stronger than main, where HEAD was judged.

The per-line split sees no `&&`, so it names no branch. Its records count only where it reads
more commands in a directory than the carried split, as where that split misreads a quote and
hides a commit; there they are judged at HEAD. So a quote misread never lets a commit through
that main refused.

## Two splits, never weaker than one

The splitter carries quote state across lines, so a quoted argument spanning lines
stays data. A shell construct it misreads can leave it inside a quote the shell has
already closed, hiding the lines that follow. So every guard also reads the per-line
split it replaced (`_GUARDRAILS_SPLIT_PER_LINE=1`), and git counts as run if either split
sees it. Each split's lines are read by that split's own rule for a here-string, and a script
a line runs is split both ways again, whichever split it came from (#152). `_guardrails_git_effective_cwd` prints the
directories of both, and `guard-default-branch`, `test-gate` and `lint-warn` judge every one. The cost is
that the per-line split's false positives remain for the git guards.

Where the carried split's quotes never close, bash still runs the lines before them, so the
carried split also splits every line on its own and the guards read those lines in the same
pass. It splits them as the per-line split does, but reads a here-string as one word, as the
shell does. The per-line split reads the `<<` in `<<<"$PWD"` as a heredoc opener, which hides
every line after it, and drops the here-string's word, so the carried split's rule for a
here-string would take the next word as its target (#61, #152). Those lines count against
the segment cap with the carried split. The per-line split itself stays as it was.

## Reading in time

A hook that runs past its 10 s timeout lets the command through, so `_guardrails_unreadable`
asks about a command the guards could not read in time. It has three caps: 128 KiB of text,
10,000 segments, and 16 shells and evals. The text is counted in bytes, as the split reads
it: a UTF-8 locale counts characters, which let in up to four times as many bytes (#151).
A guard whose library does not load, as with a syntax error or a missing file, checks
nothing, so it asks too. `publish-cmd.sh` and `git-cmd.sh` return the status of their own
source of `shell-split.sh`, and each guard checks that the functions it calls are defined,
as a syntax error stops a source partway.

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
and `ssh` always, and `sh`, `bash`, `zsh`, `dash` or `ksh` when a `-c`, alone or in a cluster such
as `-lc`, or a `<<<` follows it in its line. That payload is always text after the word in
the same segment, so these are bounds. A nested payload is counted again through its own
word. Neither depends on which word is the command, so a wrapper before the shell cannot
hide one.

They over-count a shell's name in prose that a `-c` or `<<<` follows, and `eval` and `ssh` in
any prose, so a command running ssh 17 times asks (#113).
In the suites, a 300-line commit message naming shells 12 times counts 306 segments and no
text read again. A 5,000-line script fed to bash counts 5,004 segments and 23 characters, a
`bash -c` over a 100 KiB script reads 102,000 characters again, and every other command
counts at most 140 characters. A shell in a shell over more than 64 KiB asks.

The publish guard checks `curl`, `wget`, `http` and `gh api` lines without starting a process
(#126). It started about seven for each `curl` line, so 4,990 of them took it 180 s. Its URL
scan now costs a regex per URL. So past 32 URLs in one segment a write is read as remote,
which bounds a segment, while the length cap bounds the URLs in a command.

Within the caps, the slowest input measured takes guard-default-branch 6.3 s of the 10 s
budget on macOS, on an M4 Max at load 13 to 17: 25,000 options with a redirect fused to each
between `git` and `commit` (#91), as described below. It took 5.9 s at load 6 to 30 before a
redirect's target was read for an open quote. Before #91, the slowest took 4.1 s,
when re-measured for #131: 32,000 `env` wrappers before a `git commit`,
read by guard-default-branch, and one `eval` re-reading 480 `curl -d` lines of 32 local hosts
each, read by guard-publish (3.4 s on Linux, when last measured there). The words the lookup
skips since #109, #110, #111 and #116 come next, at 2.7 to 4.0 s for 26,000 escaped
wrappers, 32,000 redirects, 13,100 `timeout 1` wrappers or 7,700 `sudo --user root` before a
commit. Each word before a command costs the lookup a few checks, so a word holding none of
`<`, `>`, `(` and `)` skips the redirect and function checks; that kept 32,000 `env`
wrappers at 4.0 s rather than 4.8 s.

The words after a command are read the same way since #131, so they are on the slow path
too: 32,000 redirects or escaped options between `git` and `commit` take guard-default-branch
3.0 to 3.7 s. A call to the shared redirect or unquote helper costs a few microseconds a word,
so 32,000 redirects before a commit went from 2.8 to 3.4 s. The pipe check drops quotes as
bytes (#134): in a UTF-8 locale the substitution took guard-publish 19 s on 126 KB of quoted
multibyte words, and as bytes it takes 1.1 s. The host check drops the quotes of each
word that holds one, as bytes, and reads each host past its userinfo with two more
regexes (#148, #149). At load 13 to 15, one `eval` re-reading 480 lines of 32 bare
local hosts takes guard-publish 4.7 s (4.2 s before), 4,990 lines that each write to a
quoted local host 3.5 s (2.2 s), and 32,000 words with a backslash in one write 3.8 s
(1.4 s). See [url-hosts.md](url-hosts.md).

An HTTP write is read as its client reads it, a word at a time (see
[url-hosts.md](url-hosts.md)): a word that starts with `-`, a quote, `$` or a backtick
costs an unquote, and an option a regex. Each URL is then sorted into local, not proven
local or remote, and the scan also finds a URL with no slashes after its scheme and an
address with no scheme. At load 8 to 22, one curl write of 32,000 quoted words takes
guard-publish 3.3 s (1.8 s before), 30,000 clusters of flags 2.8 s (1.5 s), 10,000
headers whose quoted values run over three words 3.3 s (1.5 s), 30,000 httpie items
3.0 s (1.5 s), and one `eval` re-reading 480 lines of 32 bare local hosts 5.8 s
(4.6 s), its slowest input. The reader first kept its words with a slice of the toks
array, which bash walks from its start, so 32,000 quoted words took it past 30 s; it
keeps them by index.

A word with a redirect fused to it, as in `git>/dev/null` or `-p>x`, is split since #91, so the
lookup and git's skip read on past it where they stopped at it before. Each such word costs a
regex and a second look at what is left, where an escaped option costs one unquote: 25,000
options with a redirect fused to each between `git` and `commit` take guard-default-branch
5.9 s, against 4.0 s before #91, 14,000 `sudo> x` wrappers before a commit 5.7 s, and 16,000
`sudo>x` 4.9 s. Before #91 the lookup stopped at the first of those wrappers, in 1.3 s. A
plain chain of 25,000 `sudo` wrappers takes 3.7 s, as before. The split is made in the call
that checks for a redirect, and a redirect fused to its target needs no second check; together
they took the slowest shape from 6.6 s to 5.9 s.

The heredoc queue (#108, #132) costs little: within the caps, 9,900 heredocs opened on one
line take at most 1.0 s, 1,600 lines that each open two 0.8 s, and 16 shells' heredocs nested
around 4,900 lines of commands 1.4 s, as before. A command whose quotes never close has every
line read again on its own in the carried split's pass, and those lines are no longer hidden
after a here-string (#61), so 4,990 lines after one take guard-publish 2.1 s, where they took
1.3 s.

The guards read a segment several times. guard-default-branch reads it in its git check, in
each split's directory walk and in its stdin check, and reads the per-line split's copy too
where the splits differ. Each read of the words before the command is linear, so 14,000
wrappers with an operator fused to each, `sudo> x`, before a pipe into bash took it 8.8 s at
load 15, where a quote spanning lines made the splits differ: five reads. So the lookup's
result for a segment of 64 words or more is kept, keyed by the split and the words, and the
subshells the later passes run in inherit it. Callers read a segment's words only past its
command, which the lookup's splitting of fused redirects leaves as they were, so a kept
result reads the same. guard-default-branch now reads that segment once for each split, in
4.4 s. guard-publish runs its stdin check in its publish check's subshell, which prints nothing
when it finds nothing, so the two share the kept lookup and it reads that segment twice: 4.3 s
before a pipe into python3, where three reads took 5.6 s, at load 17 to 24. The lookup also reads a word whose redirect it
splits off at the redirect's target, where it reads next, rather than moving the redirect
there, which took a read of 14,000 such wrappers from 1.2 s to 1.0 s.

The checks added with the kept lookup cost less than the slowest input. The stdin check now
reads a segment that names `sudo`, `doas`, `chroot`, `ssh`, `/dev/stdin` or another
interpreter (#92, #113, #133), so guard-publish reads 14,000 `sudo> x` wrappers before a
commit a third time, in 5.8 s where it took 3.9 s, and in 5.5 to 5.6 s before a pipe into
bash, python3 or `sudo -s`. A redirect's target holding a quote costs a regex: 16,000
`> 'a b'` before a commit take guard-default-branch 4.4 s. 30,000 options after `ssh h` take
guard-publish 2.1 s, one `ssh` over 128 KiB of words 3.0 s, and `gh api` with 30,000
redirects among its flags 3.5 s (#146). These were measured at load 13 to 17.

The walk's tags, the runners and the branch a chain switches to leave the slowest input where
it was: 25,000 options with a redirect fused to each between `git` and `commit` take
guard-default-branch 5.9 to 6.0 s at load 3 to 5, before and after them. The slowest of their own
paths, at that load, are 16 ssh commands that each commit on another host, over 7 KiB of words
each, which guard-default-branch reads and asks about in 4.5 s; 16,000 `env -Cx` wrappers before
a commit, 4.3 s; 9,000 nested `docker exec`, `kubectl exec` and `nsenter` before one, 3.0 s; and
1,600 lines of a switch, an add and a commit in one chain, 2.4 s. guard-publish reads 4,400
lines of prose naming `su` and `script` in 2.6 s, where it took 1.4 s.

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

Tokens are split on whitespace, so a quoted argument of several words is several words of the
split. A directory is read as one shell word, joined across the words its quotes or escaped
blanks span and without its quotes, so `git -C '/path with spaces' commit` and `cd "/x"` are
judged where they run, as is a value of git's that holds a blank, as in `-c "user.name=a b"`
(#150). A leading `~` or `~/` outside quotes is `$HOME`, as the shell expands it, so `cd ~/wt`
is judged in the worktree rather than skipped as a path that does not exist; another user's
`~u` is not guessed at. Joined words keep one blank between them, where the command may have had several. A
long option that takes a separate value but is not in its wrapper's list reads its value as
the command word, which fails open: the guard lets the command through rather than blocking
it wrongly.

A quoted argument of several words is read as several words, as it always was. Its middle
words hold no quote, so a verb among them blocks, as before: `python3 x.py "a post here"`. Its
first and last words, such as `"post` and `it"` in `say "post it"`, are pieces that the split
on blanks cut, whose quotes do not close within them (`_guardrails_whole_word`). The shell
passes the argument whole, so a verb read from a piece may not be the command's: the publish
guard asks rather than blocks, and names the piece (#131). So `claude "review this"` costs a
question. `ssh host 'npm publish'` publishes from another host, and is refused, as ssh's
command is read as a command line (#113). The
per-line split cuts every quoted line into pieces, so a piece read there asks nothing, as
before. Git's skip leaves a piece as written, as before, so `git "commit -m x"` is not a
commit.

## Commits elsewhere

A git command that ssh, `docker exec`, `kubectl exec` or `nsenter` runs is read like a local
one, as is the script of a shell they run, its heredoc included, but its repo is on another
host or in a container, whose branch no guard here can see. So `_guardrails_invokes_git`
returns 2 for a command run only there, which `test-gate` and `lint-warn` count as no command,
as main did. The walk reports such a command as `remote`, and `guard-default-branch` asks
about it, on any branch, rather than judge the local checkout, which it used to refuse a
commit on when that checkout was on its default branch. Main let these through, so asking is
still stronger. The local shell expands a substitution in ssh's double-quoted command line,
or in an unquoted heredoc fed to ssh, before ssh runs, so that runs here and is judged here.

A script in double quotes, as `bash -c "…"`, `eval "…"` or ssh's command line, is read as the
shell passes it on (`_guardrails_dq_payload`): an escaped `\$`, `` \` ``, `\"` or `\\` loses its
backslash, so `bash -c "echo \$(git commit)"` commits in that shell, and a substitution the shell
expands here first is made inert (`$(` becomes `$_(`, and a backtick `_`), as the split has read
it where it runs. So `ssh h "echo $(git commit)"` is judged here only, where it used to be read
again as ssh's and add a question. A script that is not one string in double quotes, as `"a"' $(b)'`, is
read as written, as before, since its single-quoted piece passes `$(b)` on to run there.

## Failure mode if you change this

Tightening the matcher so it blocks more aggressively will start blocking benign
`gh` and `grep` invocations. Keep new matching rules fail-open, and add a
regression case to `tests/test_guard_default_branch.sh` naming the command line
that motivated them.
