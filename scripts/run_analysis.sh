#!/usr/bin/env bash
# Run Knip and similarity-ts against the checked-out target repository
# and assemble a Markdown report under reports/.
set -uo pipefail

: "${TARGET_DIR:?TARGET_DIR is required}"

mkdir -p reports
abs_reports=$(cd reports && pwd)
knip_md="$abs_reports/knip.md"
sim_md="$abs_reports/similarity.md"
report_md="$abs_reports/report.md"

pushd "$TARGET_DIR" >/dev/null

# --- Install target dependencies (best-effort) ---------------------------
echo "::group::Install target dependencies"
install_log="$abs_reports/install.log"
: >"$install_log"
if [[ -f package-lock.json ]]; then
  npm ci  --ignore-scripts >>"$install_log" 2>&1 \
    || npm install --ignore-scripts >>"$install_log" 2>&1 \
    || true
elif [[ -f pnpm-lock.yaml ]]; then
  corepack enable >/dev/null 2>&1 || true
  pnpm install --ignore-scripts >>"$install_log" 2>&1 || true
elif [[ -f yarn.lock ]]; then
  corepack enable >/dev/null 2>&1 || true
  yarn install --ignore-scripts >>"$install_log" 2>&1 || true
elif [[ -f package.json ]]; then
  npm install --ignore-scripts >>"$install_log" 2>&1 || true
fi
echo "::endgroup::"

# --- Knip ----------------------------------------------------------------
echo "::group::Knip"
{
  echo "## Knip"
  echo
  if [[ -f package.json ]]; then
    echo '```'
    npx --yes knip \
      --reporter markdown \
      --no-progress \
      --no-exit-code \
      2> "$abs_reports/knip.err" \
      || echo "(knip failed — see knip.err in the artifact)"
    echo '```'
  else
    echo "_No package.json detected; skipping Knip._"
  fi
} > "$knip_md"
echo "::endgroup::"

# --- similarity-ts -------------------------------------------------------
echo "::group::similarity-ts"
src_dir="."
[[ -d src ]] && src_dir="src"
{
  echo "## similarity-ts"
  echo
  echo "Scanned: \`$src_dir\` (threshold 0.85, min-lines 5)"
  echo
  echo '```'
  similarity-ts "$src_dir" \
    --threshold 0.85 \
    --min-lines 5 \
    --extensions ts,tsx,js,jsx \
    2>&1 \
    || echo "(similarity-ts failed)"
  echo '```'
} > "$sim_md"
echo "::endgroup::"

popd >/dev/null

# --- Combined report -----------------------------------------------------
{
  echo "# Re-NNDD analysis report"
  echo
  echo "- **Commit:** [\`${COMMIT_SHORT:-?}\`](${COMMIT_URL:-#}) by **${COMMIT_AUTHOR:-unknown}**"
  echo "- **Message:** ${COMMIT_MSG:-}"
  echo "- **Generated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo
  cat "$knip_md"
  echo
  cat "$sim_md"
} > "$report_md"

# --- Quick counts for Discord embed --------------------------------------
sim_count=$(grep -c -E '^[[:space:]]*Similarity:' "$sim_md" || true)
knip_unused=$(grep -cE '^\| ' "$knip_md" || true)   # rough: count table rows
{
  echo "REPORT_FILE=$report_md"
  echo "SIM_COUNT=$sim_count"
  echo "KNIP_ROWS=$knip_unused"
} >>"$GITHUB_ENV"

echo "report written to $report_md (similarity hits=$sim_count, knip table rows=$knip_unused)"
