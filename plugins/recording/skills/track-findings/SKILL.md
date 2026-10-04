---
name: track-findings
description: File every finding outside scope as a tracked issue, so nothing you noticed is left only in chat. Follow this skill BEFORE ending a turn that lists findings — yours or a persona's — and whenever the user says "track this", "add a todo", or "file an issue". Uses the tracker the session context names (a work project), otherwise GitHub issues.
allowed-tools: Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh repo view:*), Bash(gh label list:*), Bash(git remote:*), Bash(git branch:*), Read, Grep, Skill
---

# Track findings

A finding is anything outside the task's scope that you noticed AND did not change. It is NEVER left only in chat: it becomes an issue, OR the user declines it.

## Which tracker

* IF the session context names a tracker skill (a work project does), use that skill. It is a shared tracker, so the "Shared" rule below applies.
* OTHERWISE use GitHub issues, in the repo the finding belongs to. That is NOT always the current repo.
* NEVER route a finding to the user's personal Notion. There is no integration.

## Personal OR shared

Other developers may not want AI-filed issues, so ask BEFORE filing anywhere that is NOT the user's own.

* Run `gh repo view <owner>/<repo> --json nameWithOwner,isInOrganization,viewerPermission`.
* **Personal**: `isInOrganization` is `false` AND `viewerPermission` is `ADMIN`. The user owns it. File it (step 2 onward); the permission prompt is the approval.
* **Shared**: anything else, including every work tracker. Show the user the drafted issue in chat AND ask whether to file it there. End the finding's line with `(asked)` until they answer. File ONLY on an explicit yes for that issue; on a no, mark it `(declined)`.

## Protocol (GitHub issues)

1. **Pick the repo.** IF the finding's repo is NOT one the user can write to, ask the user which repo to use.
2. **Look for a duplicate.** Run `gh issue list --repo <owner>/<repo> --state open --search "<key words>"`. IF an open issue already covers it, use that issue's URL AND do NOT file another.
3. **Ensure the label.** IF `gh label list --repo <owner>/<repo> --search finding` shows no `finding` label, ask the user to approve `gh label create finding --repo <owner>/<repo> --description "Noticed outside a task's scope"`.
4. **File it**, one issue per finding. The permission prompt is the user's approval:

   ```bash
   gh issue create --repo <owner>/<repo> --label finding --title "<imperative summary, under 70 characters>" --body-file - <<'EOF'
   ## Finding
   What is wrong, in one or two sentences.

   ## Evidence
   `path/to/file:line`, the command and its output, or the doc it contradicts.

   ## Suggested fix
   The smallest change that would resolve it.

   ## Where it was noticed
   Branch `<branch>` (PR #<n> if one exists), while working on <task>.

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   ```

5. **Record the reference.** In your findings list, end the finding's line with the issue URL.
6. **IF the user declines** at the prompt OR in chat, end the line with `(declined)` instead. NEVER retry a declined finding.

## Rules

* ALWAYS end the issue body with the `🤖 Generated with [Claude Code]` footer. An issue without it reads as written by the user.
* NEVER comment on, edit, OR close an issue. Filing is the ONE exception to never publishing as the user: in a personal repo it needs the user's approval at the prompt, AND anywhere else an explicit yes in chat first.
* ALWAYS list findings under a heading containing "Findings outside scope", one list item each, each line ending with the issue URL, `(asked)`, OR `(declined)`.
