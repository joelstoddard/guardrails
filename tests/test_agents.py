"""Consistency checks between the persona agents and the hook that holds their reports to format."""

import json
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
                tools = [t.strip() for t in meta.get("tools", "").split(",")]
                self.assertIn("Skill", tools)

    def test_report_hook_matcher_lists_exactly_the_agents(self):
        hooks = json.loads((PERSONAS / "hooks" / "hooks.json").read_text())["hooks"]
        matchers = [
            entry["matcher"]
            for entry in hooks.get("SubagentStop", [])
            if any("persona-report.sh" in h["command"] for h in entry["hooks"])
        ]
        self.assertEqual(len(matchers), 1)
        names = {alt.split(":")[-1] for alt in matchers[0].split("|")}
        self.assertEqual(names, {p.stem for p in agents()})


if __name__ == "__main__":
    unittest.main()
