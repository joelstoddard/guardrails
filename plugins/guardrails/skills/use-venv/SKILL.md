---
name: use-venv
description: Use when about to run a language install command (pip, pipx, npm install -g, uv pip install, etc.) OR entering a project directory containing pyproject.toml / requirements.txt / package.json / .nvmrc — verifies virtual-environment isolation exists and is active before proceeding, and prompts to create one if missing.
allowed-tools: Bash(ls *), Bash(cat *), Bash(test *), Bash(command *), Bash(echo *), Bash(uv *), Bash(python *), Bash(python3 *), Bash(pip *), Bash(nvm *), Bash(node *), Bash(npm *), Bash(env)
---

## Purpose

Prevent pollution of the user's system Python and global Node installs. Verify virtual-environment isolation is present and active before running any language install command, and prompt to set one up when entering a project directory that has a dependency manifest but no isolation.

## Rules

1. **Never install into system/global.** Refuse `pip install X` outside a venv, `sudo pip install`, or `npm install -g X` without explicit user confirmation. Always offer the isolated equivalent first.
2. **Existence ≠ activation.** A `.venv/` directory is not sufficient. Either `$VIRTUAL_ENV` must be set, or the command must be prefixed with `uv run` / `uv pip` (which target `.venv/` without activation).
3. **Detect before recommending.** Use existing project markers to pick the right tool, not a hard-coded default:

   | Marker | Recommend |
   |--------|-----------|
   | `uv.lock` | `uv sync` / `uv pip install …` |
   | `poetry.lock` or `[tool.poetry]` in `pyproject.toml` | `poetry install` |
   | `Pipfile` | `pipenv install` |
   | `requirements.txt` only | `uv venv && uv pip install -r requirements.txt` |
   | `pyproject.toml` with no lock | `uv venv && uv pip install -e .` |
   | `.nvmrc` or `package.json#engines.node` | `nvm use` (fall back to `fnm use` if `fnm` is on PATH and `nvm` is not) |
   | `package.json` with no engine pin | prompt for Node version |

4. **Ask once per decision.** When the user confirms "create `.venv` with uv", don't re-prompt for subsequent installs in the same Claude conversation. Same for declines — remember them for the rest of the conversation. (No cross-conversation memory; each new conversation starts fresh.)
5. **Never auto-run destructive env changes.** Creating a new venv is additive and fine to run after confirmation. Deleting an existing venv, switching Python versions in place, or `rm -rf node_modules` always requires a separate explicit confirmation.

## Triggers

**Trigger A — about to run a language install command.** Examples that fire the skill:

- `pip install …`, `pip3 install …`, `sudo pip install …`
- `uv pip install …` (verifies `.venv/` exists and is the target)
- `pipx install …` (no-op — pipx isolates by design)
- `npm install -g …`, `yarn global add …`, `pnpm add -g …`

**Trigger B — entering a project directory with a manifest.** Manifest markers:

- Python: `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py`, `setup.cfg`
- Node: `package.json`, `.nvmrc`, `.node-version`

If none of these exist in the current directory (walking up to the git root), Trigger B does not fire.

## Workflow

### Trigger A — install command

1. If the install type is isolated by design (`pipx install`, `npm install` without `-g`, `cargo install`, `brew install`), proceed. Skill is a no-op.
2. For Python install into an env: check `$VIRTUAL_ENV`. If set, proceed.
3. If `$VIRTUAL_ENV` is unset, look for `.venv/` (or `.env/`, `venv/`) in the current directory, walking up to the git root:
   - **Found:** `source .venv/bin/activate` does not persist across separate Bash subprocess calls, so do not "activate then install" in two steps. Default to `uv pip install …` (which targets `.venv/` without activation). If `uv` is not on PATH, chain activation and install in one bash call: `source .venv/bin/activate && pip install …`. Tell the user which path was taken.
   - **Not found:** continue with Trigger B flow from step 2.
4. For `npm install -g X`: always refuse. Offer alternatives — `npx <pkg>` for one-shot use, project-local `npm install <pkg>`, or a user-managed global via `volta` / `pnpm` / `nvm`-scoped global.

### Trigger B — entering a manifest directory

1. Detect project type using the marker table in Rule 3.
2. Check existing env state:
   - **Python:** does `.venv/` (or `.env/`, `venv/`) exist? Does `$VIRTUAL_ENV` point at it?
   - **Node:** does `node_modules/` exist? Does `node -v` match `.nvmrc` or `engines.node`?
3. **All satisfied:** stay silent. No interruption.
4. **Missing:** propose the appropriate command (one line, exact — not pseudo-commands) and ask for confirmation. On yes, run it. On no, remember that decision for the conversation and do not re-ask for this project.

### Shared principles

- Single confirmation per decision, conversation-scoped.
- Commands shown exactly as they will run.
- On tool-missing failure (e.g. `uv` not on PATH), fall back to `python -m venv .venv` for Python or prompt the user for the Node version manager. Always tell the user what fallback was taken.
