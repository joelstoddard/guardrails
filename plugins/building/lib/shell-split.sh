#!/usr/bin/env bash
# shell-split.sh — split a command line into segments on shell operators, ignoring
# operators that appear inside quotes.
#
# Splitting blindly does not merely over-split a real command, it fabricates one that
# was never run: the pipes in `grep -E 'a|cd /evil' f` yield a segment whose first word
# is `cd`, which is enough to send a guard looking at the wrong directory. Shared by
# git-cmd.sh and publish-cmd.sh so the two hooks cannot drift apart on it.
#
# Heredoc bodies are dropped for the same reason: a `<<EOF` body is data the command
# writes, not commands the shell runs, and prose routinely starts a line with a word
# a guard would read as a tool and a verb. Detection errs toward keeping lines —
# anything not recognised as an opener is still scanned, so a miss costs a false
# positive, never a missed command. The shell does run the $( ) and backticks in the
# body of an unquoted <<EOF, so the split that carries quotes writes those as segments.
#
# A quoted argument can span lines, so quote state carries across them, with the
# shell's escapes, comments and $'...' strings, and a backslash-newline joins two lines.
# If the quotes never close, bash still runs the lines before them, so every line is then
# also split on its own, with quotes reset, and no command can hide behind a false quote.
#
# Usage: _guardrails_split_segments "<cmdline>" → one segment per line.
#        _GUARDRAILS_SPLIT_PER_LINE=1 resets quotes on every line, the split from before they carried,
#        which the guards keep as a cross-check so that carrying never weakens them.

# carry=1 carries quotes across lines and exits 3 if they never close; carry=0 resets them per line. here=1, for the
# lines read on their own when quotes never close, reads a here-string as one word, which opens no heredoc (#61, #152).
_guardrails_split_awk() {
  printf '%s' "$2" | awk -v carry="$1" -v here="${3:-0}" '
    # Carry mode also writes each command inside a $( ), <( ) or >( ) as a segment of its own, after the
    # rest, as backticks are written as sh -c "...". Level k of nesting holds its text from cs[k] on this
    # line, after pieces lp[k, 1..ln[k]] from earlier lines; a nested level leaves its opener and closer.
    # Levels at or below hb enclose an unquoted heredoc body being read, whose text is data, not theirs.
    function subopen(k, start) {
      if (k > hb + 1) lp[k - 1, ++ln[k - 1]] = substr($0, cs[k - 1], start - cs[k - 1])
      cs[k] = start; ln[k] = 0; seal(sf[k] == 1 || ev[k - 1])
    }
    function subemit(k, e,   j, t) {
      t = substr($0, cs[k], e - cs[k])
      if (t == "" && !ln[k]) return
      if (kind[k] == "`") xp[++nxp] = "sh -c \""
      for (j = 1; j <= ln[k]; j++) xp[++nxp] = lp[k, j]
      xp[++nxp] = t
      if (kind[k] == "`") xp[++nxp] = "\""
      xp[++nxp] = "\n"; ln[k] = 0
    }
    function subclose(k, e) {
      wordend(); seal(fsh == 1 || ev[k])
      subemit(k, e)
      if (k > hb + 1) cs[k - 1] = e
    }
    # A shell word anywhere in a segment makes the body of a heredoc opened in it its script, so no wrapper hides one
    # (#90), nor a redirect before the shell, as in <<EOF bash (#132). So do chroot and ssh, or an option with s or i
    # after sudo or doas, as each starts a shell with no command (#113, #133); fsh is 2 after sudo or doas. seal decides for the
    # heredocs opened from pseg on once their segment ends, or a substitution opens in it, whose own heredocs it decides
    # for when it closes. So does source or . of /dev/stdin or -, which ps notes the first word of. fev notes eval, or a
    # -c after a shell, which runs a substitution in its words as a script, so ev[k] marks level k as one, and a heredoc
    # opened in it as its script; so does a shell or source before a <( ).
    function wordend() {
      if (index(" sh bash zsh dash ksh chroo ssh ", " " cw " ")) fsh = 1
      else if (cw == "sudo" || cw == "doas") { if (!fsh) fsh = 2 }
      else if (fsh == 2 && (cw ~ /^-[^-]*[si]/ || cw == "--she" || cw == "--log")) fsh = 1
      if (cw == "eval" || (fsh == 1 && cw ~ /^-[^-]*c/)) fev = 1
      if (ps && (cw == "stdin" || cw == "-")) fsh = 1
      if (cw != "") ps = (cw == "sourc" || cw == ".")
      cw = ""; qd = 0
    }
    function seal(f, k) { f = (f == 1); for (k = pseg; k <= en; k++) if (es[k] < 0) es[k] = f; pseg = en + 1 }
    # Level l reads the body at lh[l], and act maps the delimiter of each script being read to the outermost level
    # reading it.
    function head(l, e) { e = lh[l]; if (es[e] && !(ed[e] in act)) act[ed[e]] = l }
    function drop(e) { e = lh[lv]; if (es[e] && (ed[e] in act) && act[ed[e]] == lv) delete act[ed[e]]; en = pb = la[lv] - 1; pseg = en + 1; lv-- }
    function nexthead(e) {
      e = lh[lv]
      if (lh[lv] == en) { drop(); return }
      if (es[e] && (ed[e] in act) && act[ed[e]] == lv) delete act[ed[e]]
      lh[lv]++; head(lv)
    }
    # The shell ends a body at its delimiter line, even inside a substitution, which is then never closed.
    function bodyend() {
      for (; d > hb; d--) subemit(d, cs[d])
      q = hq; inb = 0; hb = 0; cont = 0
    }
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92); hd = ""; d = 0; q = ""; out = ""; cont = 0; wb = 1; cw = ""; fsh = 0 }
    {
      # A heredoc body starts once its opening line ends, and a backslash-newline has not ended it.
      if (!carry && hd != "") { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); if (t == hd) hd = ""; next }
      # The carried split reads the body of every heredoc a line opens, in turn (#108). Entries pb+1..en are opened
      # on a line not yet ended, and level lv holds those of one line, from la[lv], with its body read at lh[lv]. The
      # bodies start once the command that opened them ends: not inside a quote, backtick or substitution opened
      # after them on its line, whose text the shell reads first, at depth pd or less.
      if (carry && !cont) {
        if (q == "") wordend()
        seal(fsh == 1 || ev[d])
        if (en > pb && q == "" && d <= pd) { la[++lv] = pb + 1; lh[lv] = pb + 1; pb = en; lq[lv] = q; ld[lv] = d; head(lv) }
      }
      if (lv) {
        t = $0
        sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        # A shell reads the heredoc its script came from to the delimiter, whatever the script left open, so the
        # outermost script with this delimiter ends here, and all it opened with it. Its delimiter line is still read.
        if (t in act) {
          if (inb) bodyend()
          for (al = act[t]; lv > al; ) drop()
          for (; d > ld[al]; d--) subemit(d, cs[d])
          q = lq[al]; cont = 0; nexthead()
        } else if (!es[h = lh[lv]] && (!cont || inb)) {
          if (t == ed[h]) { nexthead(); if (inb) bodyend(); next }
          # The shell runs the $( ) and backticks of an unquoted body, where quotes are text, as in q = "hd".
          if (!ex[h]) next
          if (!inb) { inb = 1; hb = d; hq = q; q = "hd" }
        }
      }
      if (!carry) q = ""
      if (!cont) wb = 1
      # cw is the end of the word being read, and fsh notes a shell word before it in the segment.
      if (carry && q == "" && !cont) { cw = ""; fsh = 0; qd = 0; fev = 0; ps = 0 }
      # Indexing the line split into characters keeps the scan linear: substr rescans the line on each call.
      cont = 0; ar = 0; n = split($0, chars, "")
      for (i = 1; i <= n; i++) {
        # Appending to one ever longer string is quadratic, so every 256 characters it moves into piece.
        if (++appended > 256) { piece[++np] = out; out = ""; appended = 0 }
        c = chars[i]

        # A backslash makes the next character literal, except inside single quotes.
        # At the end of an unquoted line it joins the next line to this one.
        if (carry && c == bs && q != sq) {
          if (i == n) { if (q == "") cont = 1; else out = out c; break }
          # The shell drops the backslash, so the character is part of the word, as in ba\sh (#111).
          if (!qd) { if (chars[i + 1] == "/") cw = ""; else if (length(cw) < 5) cw = cw chars[i + 1] }
          out = out c chars[i + 1]; i++; wb = 0; continue
        }

        # An enclosing quote does not reach inside $( ), where quoting restarts and
        # a <<WORD is a real opener. Depth outlives the line because the closing )
        # of a `-m "$(cat <<EOF ...)"` body lands on a later one.
        if (q != sq && q != "ansi" && q != "bt" && c == "$" && chars[i + 1] == "(" && chars[i + 2] != "(") {
          st[++d] = q; sw[d] = cw; sf[d] = fsh; sv[d] = fev; ev[d] = fev; q = ""; cw = ""; fsh = 0; fev = 0; ps = 0; qd = 0; out = out "$("
          if (carry) { kind[d] = "$"; subopen(d, i + 2) }
          i++; wb = 1; continue
        }
        # A backtick substitution ends at the next unescaped backtick, whatever quotes it holds.
        if (carry && c == "`" && q == "bt") { subclose(d, i); cw = sw[d]; fsh = sf[d]; fev = sv[d]; qd = 1; q = st[d--]; out = out c; wb = 0; continue }
        if (carry && c == "`" && (q == "" || q == dq || q == "hd")) {
          st[++d] = q; sw[d] = cw; sf[d] = fsh; sv[d] = fev; ev[d] = fev; kind[d] = "`"; subopen(d, i + 1); q = "bt"; out = out c; continue
        }
        # An ANSI-C string ends only at a single quote, so its marker is longer than any character.
        if (q != "") {
          out = out c; wb = 0
          if (c == q || (q == "ansi" && c == sq)) q = ""
          else if (carry && !qd && q != "bt" && q != "hd") {
            # A quoted first word is a shell when the quote ends with it or an option follows it, as when ssh
            # is given bash -s in quotes (#111); a later word in the quote is prose, as in --title "bash fix".
            if (c == " " || c == "\t") { if (chars[i + 1] == "-") wordend(); cw = ""; qd = 1 }
            else if (c == "/") cw = ""; else if (length(cw) < 5) cw = cw c
          }
          continue
        }
        if (carry && c == "$" && chars[i + 1] == sq) { q = "ansi"; out = out c sq; i++; continue }
        if (c == sq || c == dq) { q = c; out = out c; continue }
        if (carry && (c == "<" || c == ">") && chars[i + 1] == "(") {
          wordend(); st[++d] = q; sw[d] = cw; sf[d] = fsh; sv[d] = fev; ev[d] = (fsh == 1 || ps)
          cw = ""; fsh = 0; fev = 0; ps = 0; qd = 0; kind[d] = "$"; subopen(d, i + 2); out = out c "("; i++; wb = 1; continue
        }

        # A word that starts with # comments out the rest of the line. wb marks a word start: after a
        # blank or an operator, but not after an escape, or the ) closing a $( ), <( ) or $(( )).
        if (carry && c == "#" && wb) break

        # (( )) is arithmetic, where << is a bit shift rather than a redirect.
        # Miscounting only suppresses heredoc detection, which is the safe way to err.
        if (c == "(" && chars[i + 1] == "(") { ad[++ar] = (chars[i - 1] == "$"); out = out "(("; i++; wb = 0; continue }
        if (c == ")" && chars[i + 1] == ")" && ar > 0) { wb = !ad[ar--]; out = out "))"; i++; continue }
        if (c == ")" && d > 0) { if (carry) subclose(d, i); cw = sw[d]; fsh = sf[d]; fev = sv[d]; qd = 1; q = st[d--]; out = out c; wb = 0; continue }

        # <<WORD / <<-WORD / <<"WORD" opens a heredoc; <<< is a here-string.
        if (carry && c == "<" && (chars[i + 1] chars[i + 2]) == "<<") { out = out "<<<"; i += 2; wb = 1; continue }
        # A body is read to its delimiter alone, so a heredoc opened in its substitution opens no other.
        if (c == "<" && chars[i + 1] == "<" && chars[i + 2] != "<" && ar == 0 && !inb) {
          j = i + 2
          if (chars[j] == "-") j++
          while (chars[j] == " " || chars[j] == "\t") j++
          dl = ""; qc = chars[j]
          if (carry) {
            # The delimiter is a whole shell word, as the shell reads it: quotes and backslashes removed.
            # A delimiter is a short word: past 1024 characters this opens no heredoc, which errs toward
            # scanning and keeps a long word from making the read quadratic.
            qd = ""; quoted = 0; dn = 0
            for (; j <= n; j++) {
              if (++dn > 1024) { dl = ""; break }
              ch = chars[j]
              if (qd != "") { if (ch == qd) qd = ""; else dl = dl ch; continue }
              if (ch == sq || ch == dq) { qd = ch; quoted = 1; continue }
              if (ch == bs) { dl = dl chars[++j]; quoted = 1; continue }
              if (index(" \t;&|<>()", ch)) break
              dl = dl ch
            }
            if (!quoted && index("0123456789", substr(dl, 1, 1))) dl = ""   # 1<<2 inside $[ ] or a split (( )) is a shift
          } else if (qc == sq || qc == dq) {
            s0 = ++j
            while (j <= n && chars[j] != qc) j++
            dl = substr($0, s0, j - s0); j++
          } else {
            s0 = j
            while (j <= n && chars[j] ~ /[A-Za-z0-9_]/) j++
            dl = substr($0, s0, j - s0)
            if (dl ~ /^[0-9]+$/) dl = ""   # a bare number is a shift operand, not a delimiter
          }
          if (dl != "") {
            wordend()
            if (here && chars[i - 1] == "<") { out = out substr($0, i, j - i); i = j - 1; continue }
            if (!carry) hd = dl; else { ed[++en] = dl; ex[en] = !quoted; es[en] = -1; if (en == pb + 1 || d < pd) pd = d }
            out = out "<<"; i = j - 1; wb = 0; continue
          }
        }

        if ((c == "&" && chars[i + 1] == "&") ||
            (c == "|" && chars[i + 1] == "|")) {
          if (carry && d > 0) { subemit(d, i); cs[d] = i + 2 }
          if (carry) { wordend(); seal(fsh == 1 || ev[d]) }
          out = out "\n"; i++; wb = 1; cw = ""; fsh = 0; fev = 0; ps = 0; qd = 0; continue
        }
        # A lone & ends a command as ; does, but the & in >&, <&, &> and |& belongs to a redirect or pipe.
        if (carry && ((index("<>", c) && chars[i + 1] == "&") || (c == "&" && chars[i + 1] == ">"))) {
          wordend(); out = out c chars[i + 1]; i++; wb = 1; continue
        }
        if (c == "|" || c == ";" || (carry && c == "&")) {
          j = (carry && c == "|" && chars[i + 1] == "&")
          if (carry && d > 0) { subemit(d, i); cs[d] = i + 1 + j }
          if (carry) { wordend(); seal(fsh == 1 || ev[d]) }
          i += j
          out = out "\n"; wb = 1; cw = ""; fsh = 0; fev = 0; ps = 0; qd = 0; continue
        }
        if (carry) wb = (index(" \t<>&(", c) > 0 || (c == ")" && d == 0))
        # cw keeps only what a shell name needs, five characters after the last slash, so a long word stays linear.
        if (carry) { if (index(" \t<>&()", c)) wordend(); else if (c == "/") cw = ""; else if (length(cw) < 5) cw = cw c }
        out = out c
      }
      # Inside a substitution a line break ends a command too, unless quoted, escaped or in backticks.
      if (carry && d > hb) {
        if (kind[d] == "$" && q == "" && !cont) subemit(d, i)
        else lp[d, ++ln[d]] = substr($0, cs[d], i - cs[d]) (cont ? "" : ";")
        cs[d] = 1
      }
      if (inb) { out = ""; np = 0; appended = 0; next }
      # A line is written only once read whole, so an awk that aborts mid-line writes none of it, as
      # before. A line break inside a quote is data here, but a separator to the sh -c or eval that
      # re-splits the quote, so it is written as a semicolon.
      for (k = 1; k <= np; k++) printf "%s", piece[k]
      printf "%s", out; out = ""; np = 0; appended = 0
      if (carry && q != "") { printf ";"; next }
      if (cont) next
      print ""
    }
    END {
      if (inb) bodyend()
      if (nxp && (q != "" || cont)) printf "\n"
      for (j = 1; j <= nxp; j++) printf "%s", xp[j]
      if (carry && (q != "" || cont)) exit 3
    }'
}

# A hook that times out lets the command through, so the guards do not read a command past these limits:
# its length, the segments in its two splits, and the shells and evals it could make them re-read. Within
# them, the slowest guard measured 6.3 s of its 10 s budget (macOS on an M4 Max, load 13 to 17), on 25,000 options with
# a redirect fused to each between git and commit (#91). See docs/design/git-command-parsing.md
_GUARDRAILS_SPLIT_MAX=131072
_GUARDRAILS_SPLIT_MAX_SEGMENTS=10000
_GUARDRAILS_SPLIT_MAX_SHELLS=16

# _guardrails_unreadable <cmdline> → rc 0 and a reason if a guard cannot read the command in full:
# too much to read in time, or a split whose awk aborted, as BSD awk does on invalid bytes (#76).
_guardrails_unreadable() {
  local rc carried per_line n s r
  # Bytes bound what the split reads, where a UTF-8 locale counts characters (#151).
  n="$(LC_ALL=C; printf '%s' "${#1}")"
  if [ "$n" -gt "$_GUARDRAILS_SPLIT_MAX" ]; then
    printf '%s bytes is too long to read in time' "$n"; return 0
  fi
  carried="$(_guardrails_split_awk 1 "$1" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 3 ] || { printf 'splitting it failed (awk exit %s)' "$rc"; return 0; }
  # Where quotes never close, the guards read every line on its own as well, in the same pass.
  [ "$rc" = 0 ] || carried="$carried"$'\n'"$(_guardrails_split_awk 0 "$1" 1 2>/dev/null)" ||
    { printf 'splitting it line by line failed (awk exit %s)' "$?"; return 0; }
  per_line="$(_guardrails_split_awk 0 "$1" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || { printf 'splitting it line by line failed (awk exit %s)' "$rc"; return 0; }
  # n counts the segments of both splits, s the shells and evals in the carried split, which drops heredoc bodies as
  # data, and r the characters the larger split reads again. See docs/design/git-command-parsing.md
  read -r n s r < <(LC_ALL=C awk '
    FNR == 1 { f++ }
    {
      # A shell reads what follows its -c or <<< as a script, and eval and ssh what follow them, so each place after one
      # where a split could cut is a segment, and each character after one is read again (#107, #113).
      L = length($0); np = split($0, part, /[;|&`]|[$<>][(]/)
      for (last = np; last > 0 && part[last] !~ /(^|[ \t])-([^ \t-][^ \t]*)?c|<<</; last--) ;
      n++; k = 0; pre = 0
      for (i = 1; i <= np; i++) {
        t = part[i]; gsub(/["\047\\]/, "", t); nw = split(t, w, /[^A-Za-z0-9_.-]+/); at = pre
        for (j = 1; j <= nw; j++) {
          at += length(w[j]); sh = (w[j] == "sh" || w[j] == "bash" || w[j] == "zsh" || w[j] == "dash" || w[j] == "ksh")
          ev = (w[j] == "eval" || w[j] == "ssh")
          if (f == 1 && (sh || ev)) s++
          if (ev || (sh && i <= last)) { k++; r[f] += L - at }
        }
        n += k; pre += length(part[i]) + 1
      }
    }
    END { print n + 0, s + 0, (r[1] > r[2] ? r[1] : r[2]) + 0 }' <(printf '%s\n' "$carried") <(printf '%s\n' "$per_line"))
  # A count the awk could not make compares as unreadable, as test fails on an empty number.
  [ "$n" -le "$_GUARDRAILS_SPLIT_MAX_SEGMENTS" ] 2>/dev/null || { printf '%s segments are too many to read in time' "$n"; return 0; }
  [ "$s" -le "$_GUARDRAILS_SPLIT_MAX_SHELLS" ] 2>/dev/null || { printf '%s shells and evals are too many to re-read in time' "$s"; return 0; }
  [ "$r" -le "$_GUARDRAILS_SPLIT_MAX" ] 2>/dev/null || { printf '%s characters its shells and evals would read again are too many to read in time' "$r"; return 0; }
  return 1
}

_guardrails_split_segments() {
  local segs closed=1
  if [ "${_GUARDRAILS_SPLIT_PER_LINE:-}" = 1 ]; then _guardrails_split_awk 0 "$1"; return; fi
  segs="$(_guardrails_split_awk 1 "$1")" || closed=0
  [ -z "$segs" ] || printf '%s\n' "$segs"
  [ "$closed" = 1 ] || _guardrails_split_awk 0 "$1" 1
}

# _guardrails_command_at → reads the caller's toks, one segment's words, and sets _GUARDRAILS_CMD_AT to the index of
# the command they run and _GUARDRAILS_CMD to its name, past assignments, keywords, a ( and wrappers with their options.
# _GUARDRAILS_CMD_WRAPPED is 1 when a keyword, ( or wrapper came first. See docs/design/git-command-parsing.md
_guardrails_command_at() {
  _GUARDRAILS_CMD_AT=0; _GUARDRAILS_CMD="${toks[0]:-}"; _GUARDRAILS_CMD_WRAPPED=0
  # Every segment pays for this call, and bash calls a small function faster, so only a word that can come before
  # the command goes on to the loop, which must skip each word named here.
  case "$_GUARDRAILS_CMD" in
    *[=/\(\)\<\>\"\'\\]* | '' | '!' | '{' | if | then | elif | else | while | until | do | in) _guardrails_command_skip ;;
    function | coproc | case) _guardrails_command_skip ;;
    sudo | env | exec | time | xargs | ssh | nohup | command) _guardrails_command_skip ;;
    timeout | nice | stdbuf | doas | setsid | chroot | docker | kubectl) _guardrails_command_skip ;;
    *) [ "${toks[1]:-}" != '()' ] || _guardrails_command_skip ;;   # f () { ...; }
  esac
}

# _guardrails_skip_redirect → rc 0 if the caller's word w, at its index i, is a redirect (#109), with i past it, and past
# its target when the operator stands alone, or a word with a redirect fused to it, split for the caller to read index i
# again (#91). Callers pass only a word that holds < or >.
_guardrails_skip_redirect() {
  local t
  # Patterns sort the usual forms, as a regex per word costs more; a longer fd goes to the regex. An operator alone takes
  # the next word as its target, t=2, and one fused to its target takes none, t=1.
  case "$w" in
    \< | \> | \>\> | \>\| | \<\> | \>\& | \<\& | \&\> | \&\>\> | [0-9]\< | [0-9]\> | [0-9]\>\> | [0-9]\>\| | \
      [0-9]\<\> | [0-9]\>\& | [0-9]\<\&) t=2 ;;
    \<\< | \<\<- | \<\<\< | [0-9]\<\< | [0-9]\<\<- | [0-9]\<\<\<) t=h ;;
    \<* | \>* | \&\>* | [0-9]\<* | [0-9]\>*) t=1 ;;
    [0-9]*[\<\>]* | \{*[\<\>]*)
      local redirect='^([0-9]+|\{[A-Za-z_][A-Za-z0-9_]*\})?(&>>|&>|>>|>&|>\||<<<|<<-|<<|<>|<&|>|<)(.*)$'
      [[ $w =~ $redirect ]] || { _guardrails_split_fused; return; }
      t=1; [ -n "${BASH_REMATCH[3]}" ] || case "${BASH_REMATCH[2]}" in \<\< | \<\<- | \<\<\<) t=h ;; *) t=2 ;; esac ;;
    *) _guardrails_split_fused; return ;;
  esac
  case "$t" in
    1) i=$((i + 1)); t="$w" ;;
    2) i=$((i + 2)); t="${toks[$((i - 1))]:-}" ;;
    *)
      # The split drops a heredoc's delimiter, as the per-line split does a here-string's word, unless the word starts
      # with a digit, which they read as a shift.
      i=$((i + 1)); t=""
      case "$w" in *\<\<\<) [ "${_GUARDRAILS_SPLIT_PER_LINE:-}" = 1 ] || { i=$((i + 1)); t="${toks[$((i - 1))]:-}"; } ;; esac
      [ -n "$t" ] || case "${toks[$i]:-}" in [0-9]*) i=$((i + 1)) ;; esac ;;
  esac
  case "$t" in *[\"\'\\]*) _guardrails_skip_quoted "$t" ;; esac
  return 0
}

# _guardrails_skip_quoted <target> → moves the caller's i past the words that a redirect's target, which ends before i,
# joins to itself with a quote it opens or an escaped blank, as the shell reads them as one word. A quote opened later in
# the target, as in >out", may close a quote opened before it, in a piece of a quoted argument, so it joins nothing. If
# the quote does not close in the caller's toks, as in a line cut from a quote spanning lines, i stays.
_GUARDRAILS_OPEN_QUOTE='^(([0-9]+|\{[A-Za-z_][A-Za-z0-9_]*\})?[<>&|-]*)('"'"'[^'"'"']*|"([^"\\]|\\.)*\\?)$|^([^"'"'"'\\]|\\.|"([^"\\]|\\.)*"|'"'"'[^'"'"']*'"'"')*\\$'
_GUARDRAILS_SQ_REST="^[^']*'(.*)$"
_GUARDRAILS_DQ_REST='^([^"\\]|\\.)*"(.*)$'
_guardrails_skip_quoted() {
  local t="$1" k="$i" q
  while [[ $t =~ $_GUARDRAILS_OPEN_QUOTE ]]; do
    q="${BASH_REMATCH[3]:0:1}"; q="${q:-\\}"
    # An escaped blank joins the next word, read from its start; a quote, the words up to the one that closes it, read
    # from after the quote.
    while :; do
      [ "$k" -lt "${#toks[@]}" ] || return 0
      t="${toks[$k]}"; k=$((k + 1))
      case "$q" in
        \\) break ;;
        \') [[ $t =~ $_GUARDRAILS_SQ_REST ]] && { t="${BASH_REMATCH[1]}"; break; } ;;
        *) [[ $t =~ $_GUARDRAILS_DQ_REST ]] && { t="${BASH_REMATCH[2]}"; break; } ;;
      esac
    done
  done
  i="$k"
}

# _guardrails_split_fused → rc 0 if the caller's word w, at its index i, is a word with a redirect after it and no blank
# between, as in bash<<<'…' or git>out (#91). toks[i] is then that word, for the caller to read next, at the redirect's
# target when an operator alone takes the next word. _guardrails_skip_redirect calls it on a word that is no redirect.
_GUARDRAILS_FUSED='^(([^<>"'"'"'\\]|\\.|"[^"]*"|'"'"'[^'"'"']*'"'"')+)([<>].*)$'
_guardrails_split_fused() {
  local j="$i" p
  [[ $w =~ $_GUARDRAILS_FUSED ]] || return 1
  p="${BASH_REMATCH[1]}"; w="${BASH_REMATCH[3]}"; toks[j]="$p"
  case "$w" in
    \< | \> | \>\> | \>\| | \<\> | \>\& | \<\& | \<\< | \<\<- | \<\<\<) ;;
    # A target whose quote stays open joins the words after it, so the word goes in place of the last of them.
    *[\"\'\\]*) i=$((j + 1)); _guardrails_skip_quoted "$w"; [ "$i" -gt "$((j + 1))" ] && { i=$((i - 1)); toks[i]="$p"; return 0; }
      i="$j"; return 0 ;;
    *) return 0 ;;
  esac
  _guardrails_skip_redirect
  [ "$i" -gt "$((j + 1))" ] && { i=$((i - 1)); toks[i]="$p"; return 0; }
  i="$j"; return 0
}

# _guardrails_unquote → rc 0 with the quotes and backslashes the shell drops removed from the caller's word w, if it is
# short (#111). Callers pass only a word that holds a quote or backslash.
_guardrails_unquote() {
  # A name is short, and a long word would make the substitution slow.
  [ "${#w}" -le 64 ] || return 1
  w="${w#\$}"; w="${w//[\"\'\\]/}"
}

# _guardrails_whole_word → rc 0 if every quote and backslash in the caller's word w closes within it, so the word is
# whole and not one piece of a quoted argument that the split on blanks cut (#131). A word too long to unquote is not.
_GUARDRAILS_WHOLE_WORD='^([^"'"'"'\\]|\\.|"([^"\\]|\\.)*"|'"'"'[^'"'"']*'"'"')*$'
_guardrails_whole_word() {
  [ "${#w}" -le 64 ] || return 1
  case "$w" in *[\"\']* | *\\) [[ $w =~ $_GUARDRAILS_WHOLE_WORD ]] ;; esac
}

# The guards' passes read a segment up to five times, and the loop is linear in the words before the command, so a long
# segment's lookup is kept, keyed by the split and its words; a subshell inherits it. Callers read toks only past the
# command, which the loop's splitting of fused redirects leaves as they were. See docs/design/git-command-parsing.md
declare -A _GUARDRAILS_CMD_CACHE
_guardrails_command_skip() {
  local i=0 w b="" vals longs o start ops sub remote=-1 rb ra so no ws="" key=""
  if [ "${#toks[@]}" -ge 64 ]; then
    key="${_GUARDRAILS_SPLIT_PER_LINE:-} ${toks[*]}"
    if [ -n "${_GUARDRAILS_CMD_CACHE[$key]+x}" ]; then
      IFS=/ read -r _GUARDRAILS_CMD_AT _GUARDRAILS_CMD_WRAPPED _GUARDRAILS_CMD_SHELL _GUARDRAILS_CMD_ARGS _GUARDRAILS_CMD \
        <<<"${_GUARDRAILS_CMD_CACHE[$key]}"
      return
    fi
  fi
  while [ "$i" -lt "${#toks[@]}" ]; do
    w="${toks[$i]}"; b=""
    # Most words hold none of < > ( ), so they skip these checks, which every word before the command pays for.
    # A ( opens a subshell, fused to the word after it or not; (( is arithmetic.
    case "$w" in
      *[\<\>\(\)]*) case "$w" in '(('*) ;; '('*) w="${w#(}"; _GUARDRAILS_CMD_WRAPPED=1 ;; esac
        # A redirect can come before the command (#109).
        _guardrails_skip_redirect && { _GUARDRAILS_CMD_WRAPPED=1; continue; }
        # A function's header and a case arm's pattern come before the command they run (#110).
        case "$w" in
          *'()'*) [[ $w =~ \(\)(.*)$ ]]; w="${BASH_REMATCH[1]}"; w="${w#[{(]}"; _GUARDRAILS_CMD_WRAPPED=1 ;;
          *')') _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1)); continue ;;
        esac ;;
    esac
    case "$w" in
      [A-Za-z_]*=*) i=$((i + 1)); continue ;;
      # The shell drops a command word's quotes and backslashes (#111).
      *[\"\'\\]*) _guardrails_unquote && _GUARDRAILS_CMD_WRAPPED=1 ;;
    esac
    case "$w" in
      '' | '!' | '{' | if | then | elif | else | while | until | do | in) _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1)); continue ;;
      function) _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 2)); continue ;;
      # A coproc's name comes only before a compound command, and a case's word before its in.
      coproc) _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1)); case "${toks[$((i + 1))]:-}" in '{' | '('*) i=$((i + 1)) ;; esac; continue ;;
      case) _GUARDRAILS_CMD_WRAPPED=1; for ((i = i + 1; i < ${#toks[@]}; i++)); do [ "${toks[$i]}" = in ] && break; done; continue ;;
    esac
    # ${w##*/} is quadratic on a long word, enough to time the hook out; this regex is linear.
    b="$w"; [[ $b == */* && $b =~ /([^/]*)$ ]] && b="${BASH_REMATCH[1]}"
    # A wrapper runs the command after its options and its operand, if it has one: a duration, root, host or
    # container. vals are its short options that take a value, and longs its long ones (#116). ws names it if, with no
    # command, it starts a shell that reads stdin, as chroot and ssh do, and sudo or doas with an option in so (#113, #133).
    ops=0; sub=0; longs=""; so=""; no=""; ws=""
    case "$b" in
      sudo)
        vals=CDghpRrTtUu; so='^-[^CDghpRrTtUu]*[si]'
        longs='--user --group --chdir --close-from --host --prompt --role --type --command-timeout --other-user --chroot' ;;
      env) vals=CPSu; longs='--unset --chdir --split-string' ;;
      exec) vals=a ;;
      time) vals=fo; longs='--output --format' ;;
      xargs) vals=adEIJLnPRSs; longs='--arg-file --delimiter --max-args --max-procs --max-chars --process-slot-var' ;;
      timeout) vals=ks; ops=1; longs='--signal --kill-after' ;;
      nice) vals=n; longs='--adjustment' ;;
      stdbuf) vals=ioe; longs='--input --output --error' ;;
      doas) vals=Cu; so='^-[^Cu]*s' ;;
      chroot) vals=ugG; ops=1; longs='--userspec --groups'; ws="$b" ;;
      nohup | command | setsid) vals="" ;;
      # These run their command elsewhere, as you, so only a shell there is the command word, read like a shell here.
      # ssh takes options after its host as well, and its command is read as a payload (#113).
      # With -N, -W, -O, -G, -Q or -V it starts no shell.
      ssh) vals=BbcDEeFIiJLlmOoPpQRSWw; no='^-[^BbcDEeFIiJLlmOoPpQRSWw]*[NWOGQV]'; ops=1; remote="$i"; rb="$b"; ws="$b" ;;
      docker)
        [ "${toks[$((i + 1))]:-}" = exec ] || break
        vals=euw; ops=1; sub=1; remote="$i"; rb="$b"; longs='--env --env-file --user --workdir --detach-keys' ;;
      kubectl)
        [ "${toks[$((i + 1))]:-}" = exec ] || break
        vals=cfn; ops=1; sub=1; remote="$i"; rb="$b"; longs='--container --filename --namespace --pod-running-timeout' ;;
      # f () { ...; } names a function before its body.
      *) [ "${toks[$((i + 1))]:-}" != '()' ] || { _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 2)); continue; }; break ;;
    esac
    start="$i"; _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1 + sub))
    while :; do
      for (( ; i < ${#toks[@]}; i++)); do
        o="${toks[$i]}"
        case "$o" in
          --) i=$((i + 1)); break ;;
          # A long option written with = holds its value.
          --*)
            case " $longs " in *" $o "*) i=$((i + 1)) ;; esac
            case "$o" in --shell | --login) [ -z "$so" ] || ws="$b" ;; esac ;;
          -?*)
            # command -v and -V name a command without running it.
            [[ $b == command && $o == -*[vV]* ]] && { i="$start"; break 3; }
            # A shell option counts before the first option in its cluster that takes a value, which takes the rest.
            [[ -n $so && $o == *[si]* && $o =~ $so ]] && ws="$b"
            [[ -n $no && $o == *[NWOGQV]* && $o =~ $no ]] && ws=""
            # In a cluster, the first option taking a value takes the rest of the word, or the next word if none is left.
            [[ -n $vals && -z ${o#-*[$vals]} ]] && i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      [ "$ops" -gt 0 ] || break
      # kubectl and ssh take options after their pod or host as well.
      ops=0; i=$((i + 1)); case "$b" in kubectl | ssh) ;; *) break ;; esac
    done
    ((start != remote)) || ra="$i"
  done
  _GUARDRAILS_CMD_SHELL=""; [ "$i" -lt "${#toks[@]}" ] || { b=""; _GUARDRAILS_CMD_SHELL="$ws"; }
  # _GUARDRAILS_CMD_ARGS is where the command that ssh runs starts.
  if [ "$remote" -ge 0 ]; then
    case "$b" in sh | bash | zsh | dash | ksh) ;; *) i="$remote"; b="$rb"; _GUARDRAILS_CMD_ARGS="$ra" ;; esac
  fi
  _GUARDRAILS_CMD_AT="$i"; _GUARDRAILS_CMD="$b"
  # A name holds no /, as the loop reads it from the last one.
  [ -z "$key" ] || _GUARDRAILS_CMD_CACHE[$key]="$i/$_GUARDRAILS_CMD_WRAPPED/$_GUARDRAILS_CMD_SHELL/${_GUARDRAILS_CMD_ARGS:-}/$b"
}

# _guardrails_shell_payload <segment> → rc 0 with _GUARDRAILS_PAYLOAD set to the script a shell runs from
# its command line (a -c argument, alone or in a cluster such as -lc, or a here-string), eval runs, or ssh runs on its
# host (#113), else rc 1. It sets a variable rather than printing, since a subshell for every segment is slow.
_guardrails_shell_payload() {
  local seg="$1" i k inner="" here='<<<[[:space:]]*(.*)$'
  local -a toks
  case "$seg" in *eval* | *'<<<'* | *-*c* | *[\"\'\\]* | *ssh*) ;; *) return 1 ;; esac
  read -r -a toks <<<"$seg" || return 1
  _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"
  case "$_GUARDRAILS_CMD" in
    eval) inner="${toks[*]:$((i + 1))}" ;;
    # With no command, ssh has none, though a redirect may follow its host.
    ssh) [ -z "$_GUARDRAILS_CMD_SHELL" ] || return 1; inner="${toks[*]:$_GUARDRAILS_CMD_ARGS}" ;;
    sh | bash | zsh | dash | ksh)
      for ((k = i + 1; k < ${#toks[@]}; k++)); do
        case "${toks[$k]}" in
          --*) ;;
          -*c*) inner="${toks[*]:$((k + 1))}"; break ;;
        esac
      done
      # Words and a regex, as searching with ${seg#*<<<} is quadratic on a long segment.
      [ -n "$inner" ] || { [[ $seg =~ $here ]] && inner="${BASH_REMATCH[1]}"; } ;;
    *) return 1 ;;
  esac
  # Slices, as ${inner#["']} and ${inner%["']} are quadratic on a long payload in a UTF-8 locale (#107).
  case "${inner:0:1}" in [\"\']) inner="${inner:1}" ;; esac
  case "${inner: -1}" in [\"\']) inner="${inner:0:${#inner}-1}" ;; esac
  [ -n "$inner" ] && [ "$inner" != "$seg" ] || return 1
  _GUARDRAILS_PAYLOAD="$inner"
}

# _guardrails_shell_reads_stdin <segment> → rc 0 and a reason if the segment is a shell or another interpreter reading
# commands from a stdin the command line does not show, such as a pipe; not a heredoc, here-string, file or script.
_guardrails_shell_reads_stdin() {
  local i shell w
  local -a toks
  # The splits read a here-string as a script only when a shell is the command, so it falls through.
  case "$1" in *'<<<'*) ;; *'<'*) return 1 ;; esac
  read -r -a toks <<<"$1" || return 1
  _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"; shell="$_GUARDRAILS_CMD"
  case "$shell" in
    sh | bash | zsh | dash | ksh)
      for ((i = i + 1; i < ${#toks[@]}; i++)); do
        w="${toks[$i]}"
        # A redirect after the shell is not its script; i is left on its last word.
        case "$w" in *[\<\>]*) _guardrails_skip_redirect && { i=$((i - 1)); continue; } ;; esac
        case "$w" in
          -o | +o | -O | +O | --rcfile | --init-file) i=$((i + 1)) ;;
          --*) ;;
          - | -*s*) break ;;
          -* | +*) ;;
          *) return 1 ;;
        esac
      done ;;
    python | python[23] | python[23].[0-9]* | node | nodejs | perl | ruby | php | lua | deno | bun)
      _guardrails_interp_reads_stdin || return 1 ;;
    source | .) case "${toks[$((i + 1))]:-}" in /dev/stdin | -) ;; *) return 1 ;; esac ;;
    '' | ssh)
      [ -n "$_GUARDRAILS_CMD_SHELL" ] || return 1
      printf '%s with no command starts a shell that reads commands from stdin, which the command line does not show' \
        "$_GUARDRAILS_CMD_SHELL"
      return 0 ;;
    *) return 1 ;;
  esac
  printf '%s reads commands from stdin, which the command line does not show' "$shell"
}

# _guardrails_interp_reads_stdin → rc 0 if the interpreter at the caller's index i, named by its shell, reads its script
# from stdin: there is no script file, no code or module on its command line, and no option that exits first (#92). In a
# cluster of short options, stop ends the reading, and the first of rest takes the rest of the word as its value, or
# the next word if it is in next and last. Reads the caller's toks.
_guardrails_interp_reads_stdin() {
  local w stop rest next lstop="--version --help" lnext=""
  case "$shell" in
    python*) stop=cmVh; rest=WX; next=WX; lnext=--check-hash-based-pycs ;;
    node*)
      stop=epcvh; rest=rC; next=rC; lstop="$lstop --eval --print --check --test --run --v8-options"
      lnext='--require --import --loader --experimental-loader --conditions --env-file --title' ;;
    perl) stop=eEvhV; rest=ilx0CdDMmIF; next=I ;;
    ruby) stop=evh; rest=0CEFIKrTWx; next=CEIr ;;
    php)
      stop=rfBREFSlswimvh; rest=cdzt; next=cdzt; lnext='--php-ini --define --zend-extension --docroot'
      lstop="$lstop --run --file --process-begin --process-code --process-file --process-end --server --lint --info --modules" ;;
    lua) stop=ev; rest=l; next=l ;;
    # deno and bun read one from stdin only when it is named -, as in deno run -.
    *) for w in "${toks[@]:$((i + 1))}"; do [ "$w" != - ] || return 0; done; return 1 ;;
  esac
  for ((i = i + 1; i < ${#toks[@]}; i++)); do
    w="${toks[$i]}"
    case "$w" in *[\<\>]*) _guardrails_skip_redirect && { i=$((i - 1)); continue; } ;; esac
    case "$w" in *[\"\'\\]*) _guardrails_unquote ;; esac
    case "$w" in
      -) return 0 ;;
      # A script file follows --, if anything does.
      --) [ "$((i + 1))" -ge "${#toks[@]}" ]; return ;;
      --*=*) ;;
      --*)
        case " $lstop " in *" $w "*) return 1 ;; esac
        case " $lnext " in *" $w "*) i=$((i + 1)) ;; esac ;;
      -*)
        [[ $w =~ ^-[^$rest]*[$stop] ]] && return 1
        [[ $w =~ ^-[^$rest]*[$next]$ ]] && i=$((i + 1)) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# _guardrails_names_shell <text> → rc 0 if a shell, eval, another interpreter or a wrapper that can start a shell appears in
# it as a word, as it must to run, or /dev/stdin, which source can run.
_guardrails_names_shell() {
  local w t="$1"
  # The shell drops quotes, backslashes and a backslash-newline inside a word, so b"as"h is bash (#134). As bytes, as the
  # substitution is quadratic on long text in a UTF-8 locale.
  case "$t" in *[\"\'\\]*) local LC_ALL=C; t="${t//\\$'\n'/}"; t="${t//[\"\'\\]/}" ;; esac
  case "$t" in
    */dev/stdin*) return 0 ;;
    *sh* | *eval* | *sudo* | *doas* | *chroot* | *python* | *node* | *perl* | *ruby* | *php* | *lua* | *deno* | *bun*) ;;
    *) return 1 ;;
  esac
  for w in sh bash zsh dash ksh eval sudo doas chroot ssh python python2 python3 node nodejs perl ruby php lua deno bun; do
    case " $t " in *[!A-Za-z0-9_.-]"$w"[!A-Za-z0-9_.-]*) return 0 ;; esac
  done
  # A python by version, such as python3.12.
  case " $t " in *[!A-Za-z0-9_.-]python[23].[0-9]*) return 0 ;; esac
  return 1
}

# _guardrails_unseen_shell_stdin <cmdline> → rc 0 and a reason if a shell in it, or in a script it runs,
# reads commands from stdin that the command line does not show, or it nests a script deeper than the guards read (#102).
_guardrails_unseen_shell_stdin() {
  local depth="${2:-0}" seg
  [ "$depth" -le 4 ] || { printf 'it nests a script more than four shells or evals deep, past what the guards read'; return 0; }
  # This pass runs on every command, so only text naming a shell or eval as a word is looked at closely.
  _guardrails_names_shell "$1" || return 1
  while IFS= read -r seg; do
    _guardrails_names_shell "$seg" || continue
    if _guardrails_shell_payload "$seg"; then
      _guardrails_unseen_shell_stdin "$_GUARDRAILS_PAYLOAD" "$((depth + 1))" && return 0
    else
      _guardrails_shell_reads_stdin "$seg" && return 0
    fi
  done < <(_guardrails_split_segments "$1")
  return 1
}
