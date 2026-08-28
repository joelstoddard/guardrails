#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../lib/publish-cmd.sh"

# blocks <cmdline> <label> — expects the command to be judged as publishing
blocks() {
  if _guardrails_publishes_as_user "$1" >/dev/null; then :; else
    echo "  FAIL [$2]: expected BLOCK, got allow — '$1'"; FAILS=1
  fi
}
# allows <cmdline> <label> — expects the command to pass through
allows() {
  if _guardrails_publishes_as_user "$1" >/dev/null; then
    echo "  FAIL [$2]: expected ALLOW, got block — '$1'"; FAILS=1
  fi
}

# ---------------------------------------------------------------------------
# A publish verb as a subcommand of ANY tool. No platform list: a tool this
# guard has never heard of must be caught on the shape of the invocation.
# ---------------------------------------------------------------------------
blocks 'gh pr comment 12 --body hi'              "gh pr comment"
blocks 'gh issue comment 12 --body hi'           "gh issue comment"
blocks 'gh pr review 12 --approve'               "gh pr review"
blocks 'glab mr note 5 --message hi'             "glab mr note"
blocks 'jira issue comment ABC-1 --body x'       "jira issue comment"
blocks 'linear comment ENG-1 "text"'             "linear comment"
blocks 'discord-cli send general hi'             "an unknown tool, send verb"
blocks 'some-future-tool post --text hi'         "a tool that does not exist yet"
blocks 'npm publish'                             "npm publish"
blocks 'cargo publish'                           "cargo publish"
blocks 'git send-email --to a@b.c patch.eml'     "git send-email"
blocks '/opt/homebrew/bin/gh pr comment 1 -b x'  "tool via absolute path"

# Mail transports publish as the user by definition.
blocks 'mail -s subject someone@example.com'     "mail"
blocks 'sendmail -t < msg.txt'                   "sendmail"
blocks 'msmtp someone@example.com'               "msmtp"

# ---------------------------------------------------------------------------
# Any authenticated/bodied HTTP write to a remote host — regardless of vendor.
# The host list is gone: what matters is "write" + "not local".
# ---------------------------------------------------------------------------
blocks 'curl -X POST https://api.github.com/repos/o/r/issues/1/comments -d "{}"' "curl POST github"
blocks 'curl -d "text=hi" https://slack.com/api/chat.postMessage'                "curl POST slack"
blocks 'curl -X POST https://api.some-vendor-we-never-heard-of.io/v2/messages -d x' "curl POST unknown vendor"
blocks 'curl -d hi https://mastodon.social/api/v1/statuses'                      "curl POST fediverse"
blocks 'curl -X PATCH https://example.com/api/thing -d x'                        "curl PATCH"
blocks 'curl -X DELETE https://example.com/api/thing'                            "curl DELETE"
blocks 'curl --json {} https://example.com/hook'                                 "curl --json"
blocks 'wget --post-data=x https://example.com/api'                              "wget post"
blocks 'http POST example.com/api text=hi'                                       "httpie"

# ...but reads are untouched, and local development is not publishing.
allows 'curl https://api.github.com/repos/o/r'      "curl GET remote"
allows 'curl -O https://example.com/archive.tar.gz' "curl download"
allows 'curl -fsSL https://example.com/install.sh'  "curl fetch script"
allows 'curl -X POST http://localhost:8080/api -d x'   "POST to localhost"
allows 'curl -d x http://127.0.0.1:3000/api'           "POST to loopback ip"
allows 'curl -X POST http://[::1]:9000/api -d x'       "POST to ipv6 loopback"

# ---------------------------------------------------------------------------
# gh api: a method or body flag silently promotes it to a write.
# ---------------------------------------------------------------------------
blocks 'gh api -X POST repos/o/r/issues/1/comments -f body=hi' "gh api -X POST"
blocks 'gh api --method PATCH repos/o/r/issues/1'              "gh api --method PATCH"
blocks 'gh api repos/o/r/issues/1/comments -f body=x'          "gh api -f implies POST"
allows 'gh api repos/o/r/pulls/1'                              "gh api GET"
allows 'gh api --method GET repos/o/r/issues'                  "gh api explicit GET"

# ---------------------------------------------------------------------------
# Opening a review request is hands-off, but only as a draft: a ready PR pings
# reviewers, and promotion is the human's call. Flag position must not matter.
# ---------------------------------------------------------------------------
allows 'gh pr create --draft --title x --body y'  "draft PR, flag first"
allows 'gh pr create --title x --draft --body y'  "draft PR, flag in the middle"
allows 'gh pr create --title x --body y --draft'  "draft PR, flag last"
allows 'glab mr create --draft --title x'         "draft MR on another forge"
blocks 'gh pr create --title x --body y'          "ready PR blocked"
blocks 'gh pr create --fill'                      "ready PR via --fill blocked"
blocks 'glab mr create --title x'                 "ready MR on another forge"
# -d is --draft in gh but --description in glab, so it is not proof of a draft.
blocks 'glab mr create -d "some description" --title x' "-d is not a draft flag"

# ---------------------------------------------------------------------------
# Composition must not hide the call.
# ---------------------------------------------------------------------------
blocks "sh -c 'gh pr comment 1 --body hi'"       "sh -c wrapper"
blocks 'bash -c "jira issue comment X --body y"' "bash -c wrapper, unknown tool"
blocks 'git add -A && npm publish'               "chained after git"
blocks 'true; gh pr review 1 --approve'          "chained after semicolon"

# The hatch is not self-grantable: an assistant can prefix anything it writes.
blocks 'ALLOW_PUBLISH_AS_ME=1 gh pr comment 1 --body x' "inline hatch, gh"
blocks 'ALLOW_PUBLISH_AS_ME=1 npm publish'              "inline hatch, npm"

# ---------------------------------------------------------------------------
# No false positives: a word in an argument is not an invocation.
# ---------------------------------------------------------------------------
allows 'git commit -m "wire up gh pr comment"'  "publish verb in a commit message"
allows 'git commit -m "post the release notes"' "post in a commit message"
allows 'git log --grep post'                    "verb as a flag value"
allows 'git log --oneline'                      "ordinary git read"
allows "grep -r 'gh pr comment' ."              "grep for the string"
allows 'rg publish src/'                        "ripgrep for the word"
allows 'echo "do not send this"'                "echo mentioning a verb"
allows 'cat notes-about-publishing.md'          "filename containing a verb"
allows 'gh pr view 12'                          "gh pr view"
allows 'gh pr list'                             "gh pr list"
allows 'npm install'                            "npm install"
allows 'npm run build'                          "npm run build"
allows 'git status'                             "unrelated command"

finish "publish-cmd"
