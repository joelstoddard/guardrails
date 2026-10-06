"""Eval runs cost real usage, so the graders and scaffolds are pinned here, where a pattern edit fails for free."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

EVALS = Path(__file__).resolve().parent.parent / "plugins" / "building" / "evals"
RUNNER = Path(__file__).resolve().parent / "evals.sh"
CONVENTIONAL = re.compile(r"^(feat|fix|refactor|chore|docs|style|test|build|ci|perf)(\(.+\))?!?: ", re.M)


def grader(case, name, key="pattern"):
    """The grader's regex as the eval tool reads it. The tool runs JavaScript regexes; these mean the same under re.ASCII."""
    text = (EVALS / case / "graders" / f"{name}.md").read_text()
    return re.compile(yaml.safe_load(text.split("---")[1])[key], re.ASCII)


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

    def __init__(self, case):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name) / "cwd"
        self.dir.mkdir()
        home = Path(self._tmp.name) / "home"
        home.mkdir()
        self.env = {**os.environ, "HOME": str(home), "GIT_CONFIG_NOSYSTEM": "1"}
        subprocess.run(["bash", str(EVALS / case / "scaffold.sh")], cwd=self.dir, env=self.env, check=True)

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


class Scaffolds(unittest.TestCase):
    def workspace(self, case):
        ws = Workspace(case)
        self.addCleanup(ws.close)
        return ws


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


class Runner(unittest.TestCase):
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
