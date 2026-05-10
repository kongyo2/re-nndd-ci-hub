#!/usr/bin/env bash
# Resolve the latest commit on the target repository's default branch
# (or a SHA passed via workflow_dispatch input) and compare it to the
# state file. Emits step outputs: sha, short_sha, message, author, url, changed.
set -euo pipefail

: "${TARGET_REPO:?TARGET_REPO is required}"
: "${STATE_FILE:?STATE_FILE is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

api="https://api.github.com/repos/${TARGET_REPO}"
auth=()
if [[ -n "${GH_TOKEN:-}" ]]; then
  auth=(-H "Authorization: Bearer ${GH_TOKEN}")
fi
auth+=(-H "Accept: application/vnd.github+json")

override="${INPUT_SHA:-}"
force="${INPUT_FORCE:-false}"

if [[ -n "$override" ]]; then
  sha="$override"
else
  default_branch=$(curl -fsSL "${auth[@]}" "$api" | jq -r '.default_branch')
  sha=$(curl -fsSL "${auth[@]}" "$api/commits/${default_branch}" | jq -r '.sha')
fi

commit_json=$(curl -fsSL "${auth[@]}" "$api/commits/${sha}")
# Canonicalize: when the operator passes a branch name, tag, or short SHA
# via workflow_dispatch, the GitHub API resolves it to the immutable
# commit. Always use that resolved SHA downstream so reports stay
# reproducible and short_sha is derived from a real 40-char hash.
sha=$(jq -r '.sha' <<<"$commit_json")
short_sha="${sha:0:7}"
message=$(jq -r '.commit.message' <<<"$commit_json" | head -n1)
author=$(jq -r '.commit.author.name // .author.login // "unknown"' <<<"$commit_json")
url=$(jq -r '.html_url' <<<"$commit_json")

last=""
if [[ -f "$STATE_FILE" ]]; then
  last=$(tr -d '[:space:]' <"$STATE_FILE")
fi

changed=true
if [[ "$sha" == "$last" && "$force" != "true" && -z "$override" ]]; then
  changed=false
fi

{
  echo "sha=$sha"
  echo "short_sha=$short_sha"
  echo "author=$author"
  echo "url=$url"
  echo "changed=$changed"
  # multiline-safe heredoc form for commit message
  delim="EOF_$(date +%s%N)"
  echo "message<<$delim"
  echo "$message"
  echo "$delim"
} >>"$GITHUB_OUTPUT"

echo "target=$TARGET_REPO sha=$short_sha changed=$changed"
