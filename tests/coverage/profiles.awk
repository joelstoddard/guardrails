# Reads "path<TAB>profile" lines, one for each awk run a gawk profile recorded, and prints "path<TAB>ran<TAB>statements"
# for each path: the statements of every distinct program it ran, and how many of them any run of that program reached.
# With -v missed=FILE, writes "path<TAB>statement" there for each statement no run reached. See docs/design/coverage.md
BEGIN { FS = "\t" }
{
  path = $1; file = $2; n = 0; key = path; header = 1
  while ((getline line < file) > 0) {
    if (header) { header = 0; continue }   # "# gawk profile, created" and the time
    ran = match(line, /^ *[0-9]+  /)        # a count, then two spaces: the statement ran that many times
    code = ran ? substr(line, RLENGTH + 1) : line
    sub(/^[ \t]+/, "", code); sub(/[ \t]*# [0-9]+$/, "", code)
    # Braces, an else, rule and function headers and gawk's section comments are no statement of their own.
    if (code == "" || code ~ /^#/ || code ~ /^[{}]$/ || code == "} else {" || code ~ /^(BEGIN|END|BEGINFILE|ENDFILE) [{]$/ || code ~ /^function /) continue
    n++; text[n] = code; reached[n] = ran
    key = key SUBSEP code
  }
  close(file)
  if (!(key in size)) { size[key] = n; owner[key] = path; for (j = 1; j <= n; j++) stmt[key, j] = text[j] }
  for (j = 1; j <= n; j++) if (reached[j]) hit[key, j] = 1
}
END {
  for (key in size) {
    p = owner[key]; total[p] += size[key]
    for (j = 1; j <= size[key]; j++) {
      if ((key, j) in hit) covered[p]++
      else if (missed != "") print p "\t" stmt[key, j] > missed
    }
  }
  for (p in total) print p "\t" (covered[p] + 0) "\t" total[p]
}
