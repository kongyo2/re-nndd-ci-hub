# re-nndd-ci-hub

[`abeshinzo78/Re-NNDD`](https://github.com/abeshinzo78/Re-NNDD) を外部から監視し、
プッシュの度に [Knip](https://knip.dev) と
[`mizchi/similarity`](https://github.com/mizchi/similarity)
(`similarity-ts`) を走らせて Discord にレポートを送る GitHub Actions です。

対象リポジトリのワークフローを書き換えられない (= 自分のリポジトリではない) ため、
このハブ側で **schedule (10分ごと polling) + workflow_dispatch** で新しい
コミットを検出して解析します。最後に処理した SHA は `state/last_sha.txt` に
保存され、ワークフロー自身が commit-back します。

## セットアップ

1. このリポジトリの **Settings → Secrets and variables → Actions** で
   `DISCORD_WEBHOOK_URL` シークレットに Discord Webhook の URL を登録します。
   - Webhook の作り方は
     [Discord Webhook ガイド](https://zenn.dev/discorders/articles/discord-webhook-guide)
     を参照。
2. このブランチ (`claude/github-actions-monitoring-oVmVo`) を **default branch
   にマージ**します。GitHub Actions の `schedule` トリガーは default branch
   に存在するワークフローのみを起動するためです。
3. 動作確認は **Actions → Monitor Re-NNDD → Run workflow**
   (`force=true` を入れると state に関係なく走ります) でできます。

## 構成

| ファイル | 役割 |
| --- | --- |
| `.github/workflows/monitor.yml` | スケジュール／手動トリガーで全体を駆動 |
| `scripts/check_new_commit.sh`   | 対象リポジトリ default branch の最新 SHA を取得し state と比較 |
| `scripts/run_analysis.sh`       | 対象を clone, deps を install, Knip + similarity-ts を実行しレポート組立 |
| `scripts/notify_discord.sh`     | Discord Webhook へ embed + `report.md` 添付で POST |
| `state/last_sha.txt`            | 最後に処理した commit SHA |

## 実行内容

- **Knip**: `npx --yes knip --reporter markdown --no-progress --no-exit-code`
  ([CI ガイド](https://knip.dev/guides/using-knip-in-ci) 準拠)。設定が無い
  リポジトリでも動くよう `--no-exit-code` で常に成果物を得ます。
- **similarity-ts / similarity-rs**: 上流の
  [`mizchi/similarity`](https://github.com/mizchi/similarity) を
  `actions/checkout` で `similarity/` 配下にクローンし、
  `cargo install --path similarity/crates/similarity-{ts,rs}` でソースから
  ビルドします (`Swatinem/rust-cache@v2` で `target/` をキャッシュ)。
  実行内容は上流リポジトリ同梱の
  [`check-similarity-ts`](https://github.com/mizchi/similarity/blob/main/.claude/skills/check-similarity-ts/SKILL.md) /
  [`check-similarity-rs`](https://github.com/mizchi/similarity/blob/main/.claude/skills/check-similarity-rs/SKILL.md)
  skill に準拠し、各言語につき 2 パスで走らせます:
  - `similarity-ts src --threshold 0.85 --min-tokens 25 --print` (関数)
  - `similarity-ts src --threshold 0.85 --experimental-types --print` (型/interface)
  - `similarity-rs src-tauri/src --threshold 0.85 --min-lines 5 --print` (関数)
  - `similarity-rs src-tauri/src --threshold 0.85 --experimental-types --print` (struct/enum)

  Re-NNDD は Tauri 2 + SvelteKit 構成のため `.svelte` は両ツール非対応 →
  Knip 側 (svelte plugin auto-detect) でカバー。
- 結果は `reports/report.md` にまとめ、Actions のアーティファクトと
  Discord 添付ファイルの両方に出します。

## 注意

- スケジュール (`*/10 * * * *`) は GitHub のベストエフォート。混雑時には
  数十分遅延することがあります。即時通知が必須なら、対象リポ側に
  `repository_dispatch` を投げる workflow を追加するか、
  [`Smee`](https://smee.io/) などで webhook をリレーする構成に切り替えます。
- 対象リポジトリが private になった場合は `actions/checkout` の `token`
  と `check_new_commit.sh` の API 呼び出しに read 権限のある PAT を
  別途 secret として渡してください。
- ワークフローは自リポジトリへ state を push するため、`contents: write`
  権限を要求しています。push されるのは `state/last_sha.txt` のみです。
