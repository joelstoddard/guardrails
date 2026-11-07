"""Consistency checks between the persona agents and the hook that holds their reports to format."""

import json
import os
import subprocess
import unittest
from pathlib import Path

import yaml

PERSONAS = Path(__file__).resolve().parent.parent / "plugins" / "personas"


def frontmatter(path):
    text = path.read_text()
    if not text.startswith("---\n"):
        return None
    return yaml.safe_load(text[4 : text.index("\n---\n", 4)])


def agents():
    return sorted((PERSONAS / "agents").glob("*.md"))


def hook_context(event, **env):
    """Run the personas rules hook for <event> as Claude Code would, and return the context it adds."""
    hooks = json.loads((PERSONAS / "hooks" / "hooks.json").read_text())["hooks"]
    [command] = [h["command"] for entry in hooks[event] for h in entry["hooks"] if "/rules/" in h["command"]]
    env = {"PATH": os.environ["PATH"], "CLAUDE_PLUGIN_ROOT": str(PERSONAS), **env}
    out = subprocess.run(["bash", "-c", command], env=env, capture_output=True, text=True, check=True).stdout
    return json.loads(out)["hookSpecificOutput"]["additionalContext"]


class Agents(unittest.TestCase):
    def test_agents_exist(self):
        self.assertTrue(agents(), "no agent files")

    def test_every_agent_declares_name_description_and_tools(self):
        for path in agents():
            with self.subTest(agent=path.name):
                meta = frontmatter(path)
                self.assertIsNotNone(meta, "missing frontmatter")
                self.assertEqual(meta.get("name"), path.stem)
                self.assertTrue(meta.get("description"))
                tools = meta.get("tools") or ""
                if isinstance(tools, str):
                    tools = tools.split(",")
                self.assertIn("Skill", [t.strip() for t in tools])

    def test_report_hook_matcher_lists_exactly_the_agents(self):
        hooks = json.loads((PERSONAS / "hooks" / "hooks.json").read_text())["hooks"]
        matchers = [
            entry["matcher"]
            for entry in hooks.get("SubagentStop", [])
            if any("persona-report.sh" in h["command"] for h in entry["hooks"])
        ]
        self.assertEqual(len(matchers), 1)
        alternatives = matchers[0].split("|")
        # Plugin agents report as personas:<name>. A bare name never matches, so the hook does not run.
        self.assertTrue(all(alt.startswith("personas:") for alt in alternatives), matchers[0])
        self.assertEqual({alt.split(":", 1)[1] for alt in alternatives}, {p.stem for p in agents()})

    def test_delegation_names_every_tool_beyond_the_shared_allowlist(self):
        # delegation.md tells the orchestrator what a persona can do; a tool it omits is one it plans without.
        shared = {"Read", "Grep", "Glob", "Edit", "Write", "Bash", "Skill"}
        lines = (PERSONAS / "rules" / "delegation.md").read_text().splitlines()
        for path in agents():
            tools = frontmatter(path).get("tools") or ""
            names = tools if isinstance(tools, list) else tools.split(",")
            for tool in {t.strip() for t in names} - shared:
                with self.subTest(agent=path.stem, tool=tool):
                    self.assertTrue(any(tool in line and path.stem in line for line in lines))


class ConfigDir(unittest.TestCase):
    """Claude Code reads user files from CLAUDE_CONFIG_DIR when it is set, so no persona path assumes ~/.claude (#120)."""

    def test_agents_name_no_home_config_path(self):
        for path in agents():
            with self.subTest(agent=path.name):
                self.assertNotIn("~/.claude", path.read_text())

    def test_rules_hooks_name_the_config_dir(self):
        for event in ("SessionStart", "SubagentStart"):
            with self.subTest(event=event):
                context = hook_context(event, HOME="/home/u", CLAUDE_CONFIG_DIR="/etc/claude")
                self.assertIn("`/etc/claude`", context)
                self.assertNotIn("${CLAUDE_", context)

    def test_config_dir_defaults_to_home(self):
        for event in ("SessionStart", "SubagentStart"):
            with self.subTest(event=event):
                self.assertIn("`/home/u/.claude`", hook_context(event, HOME="/home/u"))


if __name__ == "__main__":
    unittest.main()
