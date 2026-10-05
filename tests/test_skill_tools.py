"""A skill's allowed-tools skips the permission prompt, so a wildcard over a write-capable command must be deliberate."""

import unittest
from pathlib import Path

import yaml

PLUGINS = Path(__file__).resolve().parent.parent / "plugins"

# Commands whose subcommands can write: delete branches, rewrite remotes or history, edit issues, labels or PRs, call the API.
WRITE_CAPABLE = {
    "", "git", "git branch", "git remote", "git push", "git reset", "git tag", "git config",
    "gh", "gh issue", "gh label", "gh pr", "gh api", "gh repo", "gh release",
}

# The broad grants a skill needs to do its job, each with the reason.
DELIBERATE = {
    ("commit", "Bash(git *)"): "stages and commits",
    ("draft-pr", "Bash(git *)"): "pushes the branch before opening the PR",
    ("rebase", "Bash(git *)"): "rewrites the branch's history",
    ("rebase", "Bash(gh repo *)"): "reads the default branch",
    ("rebase", "Bash(gh pr *)"): "reads and retargets the PR",
    ("stacked-diffs", "Bash(git *)"): "creates and rebases the stack's branches",
    ("stacked-diffs", "Bash(gh pr *)"): "opens and retargets the stack's PRs",
    ("stacked-diffs", "Bash(gh api *)"): "reads PR state the gh subcommands do not expose",
    ("stacked-diffs", "Bash(gh repo *)"): "reads the default branch",
    ("ci-watch", "Bash(git push:*)"): "pushes the CI fixes it commits",
    ("pre-pr-check", "Bash"): "runs the repo's own lint and test commands, which cannot be listed in advance",
}


def skills():
    for path in sorted(PLUGINS.glob("*/skills/*/SKILL.md")):
        text = path.read_text()
        meta = yaml.safe_load(text[4 : text.index("\n---\n", 4)]) if text.startswith("---\n") else {}
        tools = meta.get("allowed-tools") or ""
        entries = tools if isinstance(tools, list) else tools.split(",")
        yield path.parent.name, [e.strip() for e in entries if e.strip()]


def wildcard_command(entry):
    """The command a wildcard entry grants every subcommand of, or None for an exact or non-Bash entry."""
    if entry == "Bash":
        return ""
    if not (entry.startswith("Bash(") and entry.endswith(")")):
        return None
    command = entry[5:-1]
    for suffix in (":*", " *"):
        if command.endswith(suffix):
            return command[: -len(suffix)]
    return None


class SkillTools(unittest.TestCase):
    def test_no_skill_grants_a_write_capable_wildcard_by_accident(self):
        for skill, entries in skills():
            for entry in entries:
                if wildcard_command(entry) in WRITE_CAPABLE:
                    with self.subTest(skill=skill, entry=entry):
                        self.assertIn((skill, entry), DELIBERATE, "narrow it, or add it to DELIBERATE with the reason")

    def test_every_deliberate_grant_still_exists(self):
        granted = {(skill, entry) for skill, entries in skills() for entry in entries}
        for key in DELIBERATE:
            with self.subTest(grant=key):
                self.assertIn(key, granted, "the skill no longer grants this; remove it from DELIBERATE")


if __name__ == "__main__":
    unittest.main()
