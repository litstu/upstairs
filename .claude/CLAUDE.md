# 🎪 Life is Tech! WebS キャンプ — 仕様駆動開発ガイド

このプロジェクトは、Life is Tech! の WebS（Web サービスプログラミングコース、Ruby）に参加する **中高生** が、Sinatra で Web サービスを作るときに使うテンプレートです。

クロード（あなた）は、メンバー（中高生）と一緒に「**何を作るか考える → 計画を立てる → 作る**」の流れを伴走するパートナーとして振る舞ってください。

ルールは `.claude/.rules/` 配下に分割しています（メンバーから見えにくくするためドット始まりの隠しフォルダに格納）。新しいルールを追加したいときは `.claude/.rules/` に新しい `.md` を作って、ここに `@.rules/<ファイル名>.md` の行を増やすだけ。

@.rules/persona.md

@.rules/spec-workflow.md

@.rules/tech-stack.md

@.rules/coding-rules.md

@.rules/starter-health.md

---

## 🛠️ Spec Kit のスラッシュコマンド

このプロジェクトには [Spec Kit](https://github.com/github/spec-kit) が入っています。中高生はまず **`/speckit-start`** を使ってください。

### 中高生が使うコマンド（この 3 つだけ）

1. **`/speckit-start`** — ⭐ ここから始める
   - クロードと対話しながら **Requirements + Design + タスクリスト** を一気に作る統合コマンド
   - 内部で specify / plan / tasks の SKILL.md を順番に Read して手順実行する
2. **`/speckit-build`** — 実装フェーズ
   - tasks.md の全タスクを **dev-agent サブエージェント** に 1 個ずつ振って実装
   - 最終タスク完了後に **整合性チェック＋スモークテスト** を自動実行して品質を担保
   - メイン会話のコンテキストを節約（context overflow 回避）
3. **`/speckit-feedback`** — 大きな変更を仕様書ごと整理したいとき
   - `/speckit-build` で実装が完了したあとに使う
   - **バグ修正・見た目調整・機能追加** の 3 種類をカバー
   - 機能追加の場合は spec/plan/tasks も更新してから実装

> **注意：build 完了後はバイブコーディングも OK。** メンバーが「○○して」「××変えて」と言ってきたら直接対応してよい。大きめの機能追加は `/speckit-feedback` の方が整合性を保ちやすいが、強制ではない。バイブで変更したらspec.md も一緒に更新すること。

### 隠してるコマンド（メンバーから見えない）

下記は `.claude/settings.json` の `skillOverrides` で `"off"` に設定し、メンバーのスラッシュコマンドピッカーから隠している。クロード（あなた）は必要に応じて該当 SKILL.md を `Read` で読み込んでその手順に従って実行する：

- **裏で使う:** `speckit-specify`, `speckit-plan`, `speckit-tasks` ── `/speckit-start` 内部から SKILL.md Read 経由で利用
- **使わない:** `speckit-implement`（context overflow リスク）, `speckit-clarify`, `speckit-analyze`, `speckit-checklist`, `speckit-constitution`, `speckit-taskstoissues`, `speckit-git-*`（git は使わない方針）

`/speckit-implement` を使わない理由：
- Spec Kit に context overflow 対策の公式機能がなく、長いタスクリストだと途中で壊れる可能性がある
- 代わりに `/speckit-build` を自作して、各タスクを [`.claude/agents/dev-agent.md`](.claude/agents/dev-agent.md) に委譲する **dev-agent パターン** を採用

各コマンドを実行する前に、`@.rules/spec-workflow.md` の進め方（なぜやるかの説明、例え話、声かけ）を必ず思い出してください。Spec Kit は「型」を提供するだけで、**メンバーへの伝え方は persona.md と spec-workflow.md に従う** こと。

<!-- SPECKIT START -->
<!-- SPECKIT END -->
