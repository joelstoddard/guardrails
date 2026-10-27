# Prints one mutant per operator match on the given lines: line \034 operator \034 mutated line.
# Usage: awk -v lines=",3,7," -f mutants.awk FILE. See docs/design/coverage.md
function emit(op, at, len, new) {
  printf "%d\034%s\034%s\n", NR, op, substr(line, 1, at - 1) new substr(line, at + len)
}
function word_at(i, w) { # w starts at i and is a whole word
  return substr(line, i, length(w)) == w && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;&|(!]/) &&
    (i + length(w) > length(line) || substr(line, i + length(w), 1) ~ /[ \t;&|)]/)
}
BEGIN {
  swap["-eq"] = "-ne"; swap["-ne"] = "-eq"; swap["-lt"] = "-ge"; swap["-ge"] = "-lt"
  swap["-gt"] = "-le"; swap["-le"] = "-gt"; swap["-z"] = "-n"; swap["-n"] = "-z"
}
index(lines, "," NR ",") {
  line = $0; sq = 0; dq = 0; n = length(line); code = ""
  for (i = 1; i <= n; i++) {
    c = substr(line, i, 1)
    if (sq) { if (c == "'") sq = 0; continue }
    if (dq) { if (c == "\\") { i++; continue } if (c == "\"") dq = 0; continue }
    if (c == "\\") { i++; continue }
    if (c == "'") { sq = 1; continue }
    if (c == "\"") { dq = 1; continue }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;]/)) break
    code = code c
    two = substr(line, i, 2)
    if (two == "==" && substr(line, i + 2, 1) != "=") emit("==", i, 2, "!=")
    else if (two == "!=") emit("!=", i, 2, "==")
    else if (two == "&&") emit("&&", i, 2, "||")
    else if (two == "||") emit("||", i, 2, "&&")
    # Test operators only inside [[ ]], [ ] or test, so options such as `head -n` are left alone.
    if (c == "-" && (index(code, "[[") || index(code, "[ ") || index(code, "test ")))
      for (w in swap) if (word_at(i, w)) emit(w, i, length(w), swap[w])
    if (c == "!" && substr(line, i + 1, 1) == " " && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) emit("!", i, 2, "")
    if (word_at(i, "exit") || word_at(i, "return")) {
      k = substr(line, i, 1) == "e" ? 4 : 6
      if (substr(line, i + k, 1) == " " && substr(line, i + k + 1, 1) ~ /[0-2]/ && substr(line, i + k + 2, 1) !~ /[0-9]/) {
        d = substr(line, i + k + 1, 1)
        to = d == "0" ? "1" : "0"
        if (!(k == 6 && d == "2")) emit(k == 4 ? "exit" : "return", i + k + 1, 1, to)
      }
    }
    if (word_at(i, "true")) emit("true", i, 4, "false")
    if (word_at(i, "false")) emit("false", i, 5, "true")
  }
  # Deleting a simple command or assignment keeps the syntax valid; control lines are left alone.
  t = code; gsub(/^[ \t]+|[ \t]+$/, "", t)
  if (t ~ /^[A-Za-z_][A-Za-z0-9_.\/-]*([= \t]|$)/ && t !~ /^(if|elif|while|until|for|case|function|then|do|else|local|declare|export|readonly)([ \t]|$)/ &&
      t !~ /(\{|\(|\\|\||&&|;;)$/ && t !~ /<</) {
    match(line, /^[ \t]*/); emit("delete", RLENGTH + 1, length(line) - RLENGTH, ":")
  }
}
