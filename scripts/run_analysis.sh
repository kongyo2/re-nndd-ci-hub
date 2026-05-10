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

# --- similarity-ts (frontend / SvelteKit src/) ---------------------------
# Re-NNDD's frontend lives in `src/` and uses .ts + .svelte. similarity-ts
# does not parse .svelte, so we scope to the TS-flavored extensions.
echo "::group::similarity-ts"
ts_dir=""
if   [[ -d src ]]; then ts_dir="src"
elif [[ -d packages || -d apps ]]; then ts_dir="."
elif compgen -G "*.ts" >/dev/null || compgen -G "*.tsx" >/dev/null; then ts_dir="."
fi
{
  echo "## similarity-ts"
  echo
  if [[ -z "$ts_dir" ]]; then
    echo "_No TypeScript sources detected; skipping._"
  else
    echo "Scanned: \`$ts_dir\` (threshold 0.85, min-lines 5, extensions ts,tsx,mts,cts)"
    echo
    echo '```'
    similarity-ts "$ts_dir" \
      --threshold 0.85 \
      --min-lines 5 \
      --extensions ts,tsx,mts,cts \
      2>&1 \
      || echo "(similarity-ts failed)"
    echo '```'
  fi
} > "$sim_md"
echo "::endgroup::"

# --- similarity-rs (Tauri backend / src-tauri/) --------------------------
sim_rs_md="$abs_reports/similarity-rs.md"
echo "::group::similarity-rs"
rs_dir=""
if   [[ -d src-tauri/src ]]; then rs_dir="src-tauri/src"
elif [[ -d src-tauri ]];     then rs_dir="src-tauri"
elif [[ -f Cargo.toml && -d src ]]; then rs_dir="src"
fi
{
  echo "## similarity-rs"
  echo
  if [[ -z "$rs_dir" ]]; then
    echo "_No Rust sources detected; skipping._"
  else
    echo "Scanned: \`$rs_dir\` (threshold 0.85, min-lines 5)"
    echo
    echo '```'
    similarity-rs "$rs_dir" \
      --threshold 0.85 \
      --min-lines 5 \
      2>&1 \
      || echo "(similarity-rs failed)"
    echo '```'
  fi
} > "$sim_rs_md"
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
  echo
  cat "$sim_rs_md"
} > "$report_md"

# --- Quick counts for Discord embed --------------------------------------
sim_ts_count=$(grep -c -E '^[[:space:]]*Similarity:' "$sim_md"    || true)
sim_rs_count=$(grep -c -E '^[[:space:]]*Similarity:' "$sim_rs_md" || true)
knip_unused=$(grep -cE '^\| ' "$knip_md" || true)   # rough: count table rows
{
  echo "REPORT_FILE=$report_md"
  echo "SIM_TS_COUNT=$sim_ts_count"
  echo "SIM_RS_COUNT=$sim_rs_count"
  echo "SIM_COUNT=$((sim_ts_count + sim_rs_count))"
  echo "KNIP_ROWS=$knip_unused"
} >>"$GITHUB_ENV"

echo "report written to $report_md (similarity-ts=$sim_ts_count, similarity-rs=$sim_rs_count, knip rows=$knip_unused)"
