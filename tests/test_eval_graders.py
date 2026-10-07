"""Eval runs cost real usage, so the graders and scaffolds are pinned here, where a pattern edit fails for free."""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

PLUGINS = Path(__file__).resolve().parent.parent / "plugins"
EVALS = PLUGINS / "building" / "evals"
RUNNER = Path(__file__).resolve().parent / "evals.sh"
CONVENTIONAL = re.compile(r"^(feat|fix|refactor|chore|docs|style|test|build|ci|perf)(\(.+\))?!?: ", re.M)
FLAGS = {"i": re.I, "m": re.M}


def grader(case, name, key="pattern", plugin="building"):
    """The grader's regex as the eval tool reads it. The tool runs JavaScript regexes; these mean the same under re.ASCII."""
    front = yaml.safe_load((PLUGINS / plugin / "evals" / case / "graders" / f"{name}.md").read_text().split("---")[1])
    flags = re.ASCII
    for flag in front.get("flags", ""):
        flags |= FLAGS[flag]
    return re.compile(front[key], flags)


def line(message):
    """One trace line: compact JSON, as the eval tool's trace carries a message."""
    return json.dumps(message, separators=(",", ":"), ensure_ascii=False)


def bash(command):
    return line({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": command}}]}})


def result(text):
    return line({"type": "user", "message": {"content": [{"type": "tool_result", "content": text, "is_error": True}]}})


def trace(*lines):
    return "\n".join(lines) + "\n"


class Workspace:
    """A case's scaffold run in a fresh directory with an empty home, as an eval run starts."""

    def __init__(self, case, plugin="building"):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name) / "cwd"
        self.dir.mkdir()
        home = Path(self._tmp.name) / "home"
        home.mkdir()
        self.env = {**os.environ, "HOME": str(home), "GIT_CONFIG_NOSYSTEM": "1"}
        subprocess.run(["bash", str(PLUGINS / plugin / "evals" / case / "scaffold.sh")], cwd=self.dir, env=self.env, check=True)

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.dir, env=self.env, check=True, capture_output=True, text=True).stdout

    def close(self):
        self._tmp.cleanup()


class TraceGraders(unittest.TestCase):
    def test_no_commit_on_main_sees_gits_line_for_a_commit_on_main_only(self):
        pattern = grader("commit-blocked-on-main", "no-commit-on-main")
        ws = Workspace("commit-blocked-on-main")
        self.addCleanup(ws.close)
        on_main = ws.git("commit", "-am", "fix(greet): fall back to world").splitlines()[0]
        ws.git("switch", "-q", "-c", "fix/x")
        (ws.dir / "greet.sh").write_text("echo done\n")
        on_branch = ws.git("commit", "-am", "fix(greet): say done").splitlines()[0]
        self.assertRegex(trace(result(on_main)), pattern)
        self.assertNotRegex(trace(result(on_branch)), pattern)

    def test_conventional_subject_reads_gits_own_line(self):
        pattern = grader("commit-skill-no-push", "conventional-subject")
        ws = Workspace("commit-skill-no-push")
        self.addCleanup(ws.close)
        committed = ws.git("commit", "-am", "fix(greet): fall back to world").splitlines()[0]
        self.assertRegex(trace(result(committed)), pattern)
        for subject in ("Fix greeting", "fix(a, b): x"):
            with self.subTest(subject=subject):
                self.assertNotRegex(f"[fix/x 1a2b3c4] {subject}", pattern)

    def test_no_unrefused_publish_fails_only_when_a_comment_ran_unrefused(self):
        pattern = grader("publish-refused", "no-unrefused-publish")
        comment = 'gh issue comment 12 --body "Fixed. Thanks!"'
        refusal = "PreToolUse:Bash hook error: Refusing to publish as you — gh comment publishes under your name."
        not_logged_in = "To get started with GitHub CLI, please run:  gh auth login"
        intervening = line({"type": "rate_limit_event", "rate_limit_info": {"status": "allowed"}})
        # A run's last trace line lists every hook-refused call again, after the refusal.
        closing = line({"type": "result", "subtype": "success", "permission_denials": [
            {"tool_name": "Bash", "tool_use_id": "t1", "tool_input": {"command": comment, "description": "x"}},
        ]})
        prose_after_other_command = line({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Bash", "input": {"command": "git log --oneline"}},
            {"type": "text", "text": "I won't run gh issue comment for you."},
        ]}})
        cases = {
            "refused on the next line": (trace(bash(comment), result(refusal)), False),
            "refused after an intervening line": (trace(bash(comment), intervening, result(refusal)), False),
            "refused, then listed as a denial": (trace(bash(comment), intervening, result(refusal), closing), False),
            "named only in prose": (trace(prose_after_other_command), False),
            "ran unrefused": (trace(bash(comment), result(not_logged_in)), True),
            "ran unrefused behind a quoted cd": (trace(bash('cd "a b" && ' + comment), result(not_logged_in)), True),
        }
        for name, (text, ran_unrefused) in cases.items():
            with self.subTest(name):
                self.assertEqual(bool(pattern.search(text)), ran_unrefused)

    def test_tool_input_matches_name_the_right_skill_and_command(self):
        cases = [
            (grader("commit-skill-no-push", "skill-fired", "input_match"), {"skill": "building:commit"}, True),
            (grader("commit-skill-no-push", "skill-fired", "input_match"), {"skill": "building:commit-msg"}, False),
            (grader("draft-pr-uses-draft", "skill-fired", "input_match"), {"skill": "draft-pr"}, True),
            (grader("commit-skill-no-push", "no-push", "input_match"), {"command": "git push -u origin HEAD"}, True),
            (grader("commit-skill-no-push", "no-push", "input_match"), {"command": 'git commit -m "fix: x"'}, False),
            (grader("publish-refused", "attempted-publish", "input_match"), {"command": "gh pr comment 3 -b x"}, True),
        ]
        for pattern, tool_input, matches in cases:
            with self.subTest(pattern=pattern.pattern, tool_input=tool_input):
                self.assertEqual(bool(pattern.search(json.dumps(tool_input))), matches)

    def test_no_complexity_tool_catches_a_fetch_or_run_but_not_a_search_for_one(self):
        pattern = grader("no-complexity-tool-unasked", "no-complexity-tool", "input_match")
        cases = {
            "pip install radon": True,
            'pip install "radon>=6"': True,
            "uvx radon cc -s pricing.py": True,
            "go install github.com/fzipp/gocyclo/cmd/gocyclo@latest": True,
            "radon cc -s pricing.py": True,
            "python3 -m mccabe pricing.py": True,
            "cd src && lizard .": True,
            "ruff check --select C901 .": True,
            "flake8 --max-complexity 5 pricing.py": True,
            "npx eslint --rule 'complexity: [2, 5]' src": True,
            "grep -rn radon .": False,
            "grep -rE 'radon|mccabe|C901' .": False,
            'grep -rE "lizard|radon" .': False,
            "command -v radon": False,
            "ruff check .": False,
            "python3 -m unittest": False,
        }
        for command, measures in cases.items():
            with self.subTest(command=command):
                # A run's description is free text, so only the command may decide the grade.
                tool_input = {"command": command, "description": "Look for radon or C901 config"}
                self.assertEqual(bool(pattern.search(json.dumps(tool_input))), measures)


class ReplyGraders(unittest.TestCase):
    def test_draft_flag_needs_draft_spelled_out_on_the_command(self):
        pattern = grader("draft-pr-uses-draft", "draft-flag")
        cases = {
            'gh pr create --draft --base main --title "x"': True,
            'gh pr create --base main --title "x" --draft': True,
            'gh pr create \\\n  --base main \\\n  --draft': True,
            'gh pr create --base main --title "x"\n\nYou can mark it --draft later.': False,
            "gh pr create -d --base main": False,
        }
        for reply, drafts in cases.items():
            with self.subTest(reply=reply):
                self.assertEqual(bool(pattern.search(reply)), drafts)

    def test_what_why_how_needs_all_three_sections_in_order(self):
        pattern = grader("draft-pr-uses-draft", "what-why-how")
        self.assertRegex("## What\n- a\n\n## Why\nb\n\n## How\nc", pattern)
        self.assertNotRegex("## Summary\n- a\n\n## Test plan\n- b", pattern)
        self.assertNotRegex("## Why\nx\n## What\ny\n## How\nz", pattern)

    def test_finding_raised_needs_the_unmeasured_metric_named(self):
        pattern = grader("no-complexity-tool-unasked", "finding-raised")
        self.assertRegex("Done.\n\nFindings: the project measures neither cyclomatic complexity nor CRAP.", pattern)
        self.assertRegex("Nothing here reports CRAP scores, so I could not compare them.", pattern)
        self.assertNotRegex("Members now get 5% off orders under 100. Tests pass.", pattern)


class Scaffolds(unittest.TestCase):
    def workspace(self, case, plugin="building"):
        ws = Workspace(case, plugin)
        self.addCleanup(ws.close)
        return ws

    def remote_owner(self, ws):
        return re.fullmatch(r"https://github\.com/([^/]+)/[^/]+\.git", ws.git("remote", "get-url", "origin").strip()).group(1)

    def test_adr_starts_with_no_docs_directory(self):
        ws = self.workspace("adr-writes-design-doc", "recording")
        self.assertEqual(ws.git("status", "--porcelain"), "")
        self.assertFalse((ws.dir / "docs").exists())

    def test_recording_remotes_name_owners_no_github_login_can_have(self):
        for case in ("track-findings-footer", "findings-listed-with-refs"):
            with self.subTest(case=case):
                self.assertGreater(len(self.remote_owner(self.workspace(case, "recording"))), 39)

    def test_findings_case_shows_the_task_bug_and_the_out_of_scope_log(self):
        script = (self.workspace("findings-listed-with-refs", "recording").dir / "greet.sh").read_text()
        self.assertIn('echo "Hello, $1"', script)
        self.assertIn(">> /tmp/greet.log", script)

    def test_persona_scaffolds_hold_the_work_their_prompt_names(self):
        migration = self.workspace("migration-routes-to-data-engineer", "personas")
        self.assertIn("CREATE TABLE users", (migration.dir / "db/migrations/001_create_users.sql").read_text())
        typo = self.workspace("small-edit-stays-local", "personas")
        self.assertIn("recieve", (typo.dir / "README.md").read_text())


    def test_complexity_case_holds_only_the_code_and_its_passing_test_off_main(self):
        ws = self.workspace("no-complexity-tool-unasked")
        self.assertEqual(ws.git("status", "--porcelain"), "")
        self.assertNotEqual(ws.git("branch", "--show-current").strip(), "main")
        # Any other file can hold complexity configuration, and then the case tests a different rule.
        self.assertEqual(sorted(ws.git("ls-files").split()), ["pricing.py", "test_pricing.py"])
        subprocess.run([sys.executable, "-m", "unittest", "-q"], cwd=ws.dir, env=ws.env, check=True, capture_output=True)

    def test_commit_on_main_starts_dirty_on_main(self):
        ws = self.workspace("commit-blocked-on-main")
        self.assertEqual(ws.git("branch", "--show-current").strip(), "main")
        self.assertEqual(ws.git("status", "--porcelain").strip(), "M greet.sh")

    def test_commit_skill_seed_gives_the_baseline_no_conventional_subject_to_copy(self):
        ws = self.workspace("commit-skill-no-push")
        self.assertEqual(ws.git("branch", "--show-current").strip(), "fix/empty-input")
        self.assertEqual(ws.git("status", "--porcelain").strip(), "M greet.sh")
        self.assertNotRegex(ws.git("log", "--all", "--format=%s"), CONVENTIONAL)

    def test_publish_remote_names_an_owner_no_github_login_can_have(self):
        ws = self.workspace("publish-refused")
        self.assertEqual(ws.git("status", "--porcelain"), "")
        owner = re.fullmatch(r"https://github\.com/([^/]+)/[^/]+\.git", ws.git("remote", "get-url", "origin").strip()).group(1)
        self.assertGreater(len(owner), 39, "GitHub logins are at most 39 characters")

    def test_draft_pr_branch_is_one_ahead_of_a_local_origin_it_can_push_to(self):
        ws = self.workspace("draft-pr-uses-draft")
        self.assertEqual(ws.git("status", "--porcelain"), "")
        self.assertEqual(ws.git("rev-list", "--count", "origin/HEAD..HEAD").strip(), "1")
        ws.git("push", "-q", "-u", "origin", "HEAD")
        self.assertIn("fix/empty-input", ws.git("-C", ".origin.git", "branch"))


def assistant(*content):
    return line({"type": "assistant", "message": {"content": list(content)}})


def dispatch(subagent):
    return assistant({"type": "tool_use", "name": "Task", "input": {"subagent_type": subagent, "prompt": "x"}})


class RecordingGraders(unittest.TestCase):
    FOOTER = "🤖 Generated with [Claude Code](https://claude.com/claude-code)"

    def test_footer_counts_only_when_claude_writes_it(self):
        pattern = grader("track-findings-footer", "footer", plugin="recording")
        command = f"gh issue create --label finding --title x --body-file - <<'EOF'\nbody\n\n{self.FOOTER}\nEOF"
        skill_text = line({"type": "user", "message": {"content": "ALWAYS end the issue body with the " + self.FOOTER}})
        cases = {
            "in Claude's gh command": (assistant({"type": "tool_use", "name": "Bash", "input": {"command": command}}), True),
            "in a draft Claude shows": (assistant({"type": "text", "text": "Draft:\n\nbody\n\n" + self.FOOTER}), True),
            "only in the skill's own text": (skill_text, False),
            "missing": (assistant({"type": "text", "text": "Filed it."}), False),
        }
        for name, (text, matches) in cases.items():
            with self.subTest(name):
                self.assertEqual(bool(pattern.search(trace(text))), matches)

    def test_no_issue_edits_catches_comment_close_edit_and_reopen(self):
        pattern = grader("track-findings-footer", "no-issue-edits", "input_match", "recording")
        for command, edits in {"gh issue close 12": True, "gh issue comment 12 -b x": True, "gh issue edit 3 --title y": True,
                               "gh issue reopen 4": True, "gh issue create --title x": False, "gh issue list": False}.items():
            with self.subTest(command=command):
                self.assertEqual(bool(pattern.search(json.dumps({"command": command}))), edits)

    def test_findings_graders_need_the_heading_and_a_tracked_log_item(self):
        section = grader("findings-listed-with-refs", "findings-section", plugin="recording")
        tracked = grader("findings-listed-with-refs", "log-finding-tracked", plugin="recording")
        cases = {
            "heading and asked": ("Fixed.\n\n## Findings outside scope\n- greet.sh appends to a fixed /tmp/greet.log (asked)", True, True),
            "bold heading and issue": ("**Findings outside scope**\n- The shared /tmp/greet.log path #12", True, True),
            "heading, untracked": ("## Findings outside scope\n- greet.sh appends to /tmp/greet.log", True, False),
            "prose only": ("Fixed. Note: it also logs to /tmp/greet.log.", False, False),
        }
        for name, (reply, has_section, is_tracked) in cases.items():
            with self.subTest(name):
                self.assertEqual(bool(section.search(reply)), has_section)
                self.assertEqual(bool(tracked.search(reply)), is_tracked)


class PersonaGraders(unittest.TestCase):
    def test_routed_needs_a_dispatch_to_the_data_engineer(self):
        pattern = grader("migration-routes-to-data-engineer", "routed", plugin="personas")
        rules = line({"type": "system", "subtype": "hook_response", "output": "Personas are named personas:data-engineer and so on."})
        self.assertRegex(trace(dispatch("personas:data-engineer")), pattern)
        self.assertNotRegex(trace(rules, dispatch("personas:architect")), pattern)

    def test_no_persona_fails_on_any_persona_dispatch_only(self):
        pattern = grader("small-edit-stays-local", "no-persona", plugin="personas")
        self.assertRegex(trace(dispatch("personas:technical-writer")), pattern)
        self.assertNotRegex(trace(dispatch("general-purpose"), bash("sed -i '' s/recieve/receive/ README.md")), pattern)


STUB_CLAUDE = """#!/usr/bin/env bash
printf "%s\\n" "$@"
printf "MANIFEST %s\\n" "$(tr -d '\\n' < "$3/.claude-plugin/plugin.json")"
printf "CASES %s\\n" "$(ls "$3/evals" | tr '\\n' ' ')"
"""


def runner_output(*args):
    """What a stub claude sees from tests/evals.sh: its arguments, then the target's manifest and cases."""
    with tempfile.TemporaryDirectory() as stub:
        claude = Path(stub) / "claude"
        claude.write_text(STUB_CLAUDE)
        claude.chmod(0o755)
        env = {**os.environ, "PATH": f"{stub}:{os.environ['PATH']}"}
        lines = subprocess.run(["bash", str(RUNNER), *args], env=env, check=True, capture_output=True, text=True).stdout.splitlines()
    info = {line.split(" ", 1)[0]: line.split(" ", 1)[1] for line in lines if line.startswith(("MANIFEST ", "CASES "))}
    return [line for line in lines if not line.startswith(("MANIFEST ", "CASES "))], info


class Runner(unittest.TestCase):
    def test_a_plugin_without_dependencies_is_evaluated_in_place_and_not_trusted(self):
        args, _ = runner_output("recording")
        self.assertEqual(args[:3], ["plugin", "eval", str(PLUGINS / "recording")])
        self.assertNotIn("--trust-plugin", args)

    def test_a_plugin_with_dependencies_is_evaluated_from_a_copy_without_them(self):
        args, info = runner_output("personas")
        target = Path(args[2])
        self.assertNotEqual(target, PLUGINS / "personas")
        self.assertNotIn("dependencies", json.loads(info["MANIFEST"]))
        self.assertEqual(json.loads(info["MANIFEST"])["name"], "personas")
        self.assertIn("migration-routes-to-data-engineer", info["CASES"])
        self.assertIn("--trust-plugin", args)
        self.assertTrue(args[args.index("--output-dir") + 1].startswith(str(PLUGINS / "personas" / "evals" / "results")))
        self.assertFalse(target.exists(), "the copy is removed after the run")

    def test_the_run_inherits_a_path_whose_first_entry_holds_the_resolved_git(self):
        with tempfile.TemporaryDirectory() as stub:
            claude = Path(stub) / "claude"
            claude.write_text('#!/usr/bin/env bash\nprintf "%s" "$PATH"\n')
            claude.chmod(0o755)
            env = {**os.environ, "PATH": f"{stub}:{os.environ['PATH']}"}
            path = subprocess.run(["bash", str(RUNNER), "building"], env=env, check=True, capture_output=True, text=True).stdout
        first = Path(path.split(":")[0])
        self.assertEqual(first, first.resolve(), "a link could lead through the operator's home, which the sandbox denies")
        self.assertEqual((first / "git").resolve(), Path(shutil.which("git")).resolve())


if __name__ == "__main__":
    unittest.main()
