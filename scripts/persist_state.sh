#!/usr/bin/env bash
# Persist the latest processed commit SHA to state/last_sha.txt on the
# *default branch* of the hub repository, regardless of which ref the
# workflow was triggered on. Uses a temporary fresh clone with the token
# scoped only to this step, and retries on non-fast-forward rejection so
# concurrent commits do not leave the state stuck.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${DEFAULT_BRANCH:?DEFAULT_BRANCH is required}"
: "${NEW_SHA:?NEW_SHA is required}"
: "${SHORT_SHA:?SHORT_SHA is required}"
: "${STATE_FILE:?STATE_FILE is required}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

clone_url="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
git clone --quiet --depth=1 --branch "$DEFAULT_BRANCH" "$clone_url" "$tmp/repo"
cd "$tmp/repo"

git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

mkdir -p "$(dirname "$STATE_FILE")"
echo "$NEW_SHA" >"$STATE_FILE"
git add "$STATE_FILE"

if git diff --cached --quiet; then
  echo "state already at ${SHORT_SHA}; nothing to push"
  exit 0
fi

git commit --quiet -m "chore(state): bump last seen SHA to ${SHORT_SHA}"

for attempt in 1 2 3 4; do
  if git push --quiet origin "HEAD:${DEFAULT_BRANCH}"; then
    echo "state pushed (attempt ${attempt})"
    exit 0
  fi
  echo "push rejected on attempt ${attempt}; rebasing..." >&2
  git fetch --quiet origin "$DEFAULT_BRANCH"
  # If someone else already advanced state to NEW_SHA, our diff disappears
  # after rebase and the next push becomes a no-op (handled above).
  if ! git rebase --quiet "origin/${DEFAULT_BRANCH}"; then
    git rebase --abort || true
    echo "rebase failed on attempt ${attempt}" >&2
  fi
  sleep $((attempt * 2))
done

echo "failed to push state after retries" >&2
exit 1
