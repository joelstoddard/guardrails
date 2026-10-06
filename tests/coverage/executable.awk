# Prints the numbers of the lines in a shell file that count as executable.
# Consistent rather than exact: floors start at measured values. See docs/design/coverage.md
BEGIN { sq = 0; dq = 0; here = ""; cont = 0; ar = 0 }
{
  line = $0
  if (here != "") {                          # heredoc body
    t = line; sub(/^\t+/, "", t)
    if (t == here) here = ""
    next
  }
  in_string = sq || dq
  was_cont = cont
  code = ""; opens = ""
  n = length(line)
  for (i = 1; i <= n; i++) {                 # drop string contents and comments, track open quotes
    c = substr(line, i, 1)
    if (sq) { if (c == "'") { sq = 0; code = code "'" }; continue }
    if (dq) {
      if (c == "\\") { i++; continue }
      if (c == "\"") { dq = 0; code = code "\"" }
      continue
    }
    if (c == "\\") { code = code c substr(line, i + 1, 1); i++; continue }
    if (c == "'") { sq = 1; code = code c; continue }
    if (c == "\"") { dq = 1; code = code c; continue }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;]/)) break
    if (c == "(" && substr(line, i + 1, 1) == "(") { ar++; code = code "(("; i++; continue }   # inside (( )) or $(( )), even across lines, << is a shift
    if (c == ")" && substr(line, i + 1, 1) == ")" && ar) { ar--; code = code "))"; i++; continue }
    if (!ar && c == "<" && substr(line, i + 1, 1) == "<" && substr(line, i + 2, 1) != "<" && (i == 1 || substr(line, i - 1, 1) != "<")) {
      rest = substr(line, i + 2); sub(/^-/, "", rest); sub(/^[ \t]*/, "", rest); sub(/^["']/, "", rest)
      if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) opens = substr(rest, 1, RLENGTH)
      code = code "<<"; i++; continue
    }
    code = code c
  }
  cont = (!sq && !dq && code ~ /\\$/)
  if (opens != "") here = opens              # the body starts on the next line
  if (in_string || was_cont) next            # continuation of a string or a backslash line
  if (line ~ /# coverage: ignore [^ ]/) next
  gsub(/^[ \t]+|[ \t]+$/, "", code)
  if (code == "") next
  if (code ~ /^(then|else|fi|do|done|esac|in|;;|;&|;;&|\{|\}|\))([ \t;|&<>].*)?$/) next
  if (code ~ /^(function[ \t]+)?[A-Za-z_][A-Za-z0-9_:-]*[ \t]*\(\)[ \t]*\{?$/) next
  if (code ~ /^[^ \t()]+([ \t]*\|[ \t]*[^ \t()]+)*[ \t]*\)([ \t]*(;;&|;;|;&))?$/) next   # a case label, with or without an empty arm
  print NR
}
