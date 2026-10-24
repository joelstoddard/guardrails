#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
HOOK="$DIR/../plugins/recording/hooks/scripts/lessons-nudge.sh"

old="$(date -v-30d +%F 2>/dev/null || date -d '30 days ago' +%F)"
new="$(date -v-1d  +%F 2>/dev/null || date -d '1 day ago'   +%F)"

run() { GUARDRAILS_LESSONS_JOURNAL="$1" bash "$HOOK" 2>/dev/null; }

# --- silent when the journal is missing
out="$(run /nonexistent/journal.jsonl)"
[ -z "$out" ] || { echo "  FAIL: spoke with no journal"; FAILS=1; }

# --- silent when every unpromoted entry is recent
j="$(scratch_file)"; printf '{"date":"%s","skill":"a","promoted":false}\n' "$new" > "$j"
out="$(run "$j")"
[ -z "$out" ] || { echo "  FAIL: nudged on a fresh entry: $out"; FAILS=1; }

# --- reports a count when an unpromoted entry is older than 7 days
j="$(scratch_file)"
printf '{"date":"%s","skill":"a","promoted":false}\n' "$old" >> "$j"
printf '{"date":"%s","skill":"b","promoted":false}\n' "$new" >> "$j"
out="$(run "$j")"
case "$out" in
  *"2 lesson"*) ;;
  *) echo "  FAIL: expected a count of 2, got: $out"; FAILS=1 ;;
esac

# --- entries already promoted do not count
j="$(scratch_file)"; printf '{"date":"%s","skill":"a","promoted":true}\n' "$old" > "$j"
out="$(run "$j")"
[ -z "$out" ] || { echo "  FAIL: counted a promoted entry: $out"; FAILS=1; }

# --- malformed lines are skipped, not fatal
j="$(scratch_file)"
echo 'not json at all' >> "$j"
printf '{"date":"%s","skill":"a","promoted":false}\n' "$old" >> "$j"
out="$(run "$j")"
case "$out" in
  *"1 lesson"*) ;;
  *) echo "  FAIL: malformed line broke the read, got: $out"; FAILS=1 ;;
esac
run "$j" >/dev/null || { echo "  FAIL: nonzero exit on malformed input"; FAILS=1; }

# --- with no override, the journal is in the Claude config directory, which defaults to ~/.claude (#120)
cfg="$(scratch_dir)"
printf '{"date":"%s","skill":"a","promoted":false}\n' "$old" > "$cfg/skill-lessons.jsonl"
out="$(env -u GUARDRAILS_LESSONS_JOURNAL CLAUDE_CONFIG_DIR="$cfg" HOME=/nonexistent bash "$HOOK" 2>/dev/null)"
case "$out" in *"1 lesson"*) ;; *) echo "  FAIL: missed the journal in CLAUDE_CONFIG_DIR, got: $out"; FAILS=1 ;; esac
home="$(scratch_dir)"; mkdir "$home/.claude"; cp "$cfg/skill-lessons.jsonl" "$home/.claude/"
out="$(env -u GUARDRAILS_LESSONS_JOURNAL -u CLAUDE_CONFIG_DIR HOME="$home" bash "$HOOK" 2>/dev/null)"
case "$out" in *"1 lesson"*) ;; *) echo "  FAIL: missed the journal in ~/.claude, got: $out"; FAILS=1 ;; esac

# --- the self-improvement skill writes the journal the hook reads
SKILL="$DIR/../plugins/recording/skills/self-improvement/SKILL.md"
hook_line="$(grep '^journal=' "$HOOK")"
[ -n "$hook_line" ] || { echo "  FAIL: no journal= line in the hook"; FAILS=1; }
assert_eq "$hook_line" "$(grep '^journal=' "$SKILL")" "the skill resolves the journal as the hook does"

finish "lessons-nudge"
