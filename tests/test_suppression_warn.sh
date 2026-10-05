#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/building/hooks/scripts/suppression-warn.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write() {
  printf '%s' "$2" > "$TMP/$1"
  jq -n --arg f "$TMP/$1" --arg c "$2" '{tool_input:{file_path:$f,content:$c}}'
}

for line in 'it.skip("slow", () => {})' 'xit("flaky", () => {})' '@pytest.mark.skip(reason="x")' \
  '  t.Skip("later")' 'x = 1  # noqa: E501' '// eslint-disable-next-line' '// @ts-ignore' \
  'y = f()  # type: ignore' 'const z = w as any;' 'v := g() //nolint' \
  '// @ts-expect-error' '// @ts-nocheck' '# pylint: disable=invalid-name' '# shellcheck disable=SC2086' \
  '@unittest.skip("later")' '    pytest.skip("later")' 'xdescribe("suite", () => {})' '  t.Skipf("later %d", n)' \
  '#[allow(dead_code)]' '@SuppressWarnings("unchecked")' 'out = run(cmd)  # nosec' 'const u = x as any as Foo;'; do
  run_hook "$S" "$(write case.txt.js "$line")"
  assert_rc 0 "never blocks: $line"
  assert_out "additionalContext" "warns: $line"
done

run_hook "$S" "$(write iter.rs 'let rest = it.iter().skip(1);')"
assert_eq "" "$OUT" "iterator skip is not a test skip"

run_hook "$S" "$(write words.js 'var cannolintx = 1;')"
assert_eq "" "$OUT" "nolint inside a word is not a suppression"

run_hook "$S" "$(write prose.py '# same as any other value')"
assert_eq "" "$OUT" "as any other is prose"

run_hook "$S" "$(write notes.md 'it.skip(')"
assert_eq "" "$OUT" "markdown ignored"

finish "suppression-warn"
