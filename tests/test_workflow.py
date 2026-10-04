"""CI runs with a read-only token: main auto-updates every installed machine, so a write token is a supply-chain risk."""

import unittest
from pathlib import Path

import yaml

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"


class Workflows(unittest.TestCase):
    def test_every_workflow_grants_only_read_access(self):
        files = sorted(WORKFLOWS.glob("*.yml"))
        self.assertTrue(files, "no workflows")
        for path in files:
            with self.subTest(workflow=path.name):
                self.assertEqual(yaml.safe_load(path.read_text()).get("permissions"), {"contents": "read"})


if __name__ == "__main__":
    unittest.main()
