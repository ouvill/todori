# task-61: 日付・時刻表記のロケール準拠リファクタ

## 1. 背景とコンテキスト

2026-07-06の人間指示により、日付・時刻の表記はホストOSの言語・ロケール設定に従うことが `docs/design/ui-spec.md` に明記された。固定パターン文字列やISO風の手組み表示は、英語では自然に見えても日本語で「月, 7月 6」のような不自然な語順を生む。

本タスクでは、`app/lib/` 内の日付表示を棚卸しし、固定パターンや手組み整形を `DateFormat` の skeleton API へ統一する。相対表記（Today/Tomorrow/今日/明日）は既存のl10n文言を維持し、絶対日付だけをロケール準拠へ寄せる。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`（共通規約・共通受け入れ基準）
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md` セクション1（親しみやすい、日付・時刻表記）
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`

## 3. ゴール

- `app/lib/` の日付表示を `DateFormat.MMMEd` / `DateFormat.yMMMd` / `DateFormat.MMMd` などの skeleton API へ統一する。
- Home見出しの日付、詳細画面のCreated at、期日pill、タスク作成シートの期日表示がホストロケールへ追従する。
- jaでは `7月8日(水)` 相当、enでは `Wed, Jul 8` 相当の自然なHome見出しになることをテストとvisual QAで確認する。
- `Today` / `Tomorrow` / `今日` / `明日` などの相対表記は既存l10n文言のまま維持する。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-61-locale-date-format.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### やること

1. `app/lib/` の `DateFormat` 利用箇所と手組み日付整形を棚卸しする。
2. 固定パターン文字列や `yyyy-MM-dd` 相当の手組み整形があれば skeleton API へ置換する。
3. Home日付見出しを共通ヘルパー化し、画面・テスト・visual QAで同じ整形を参照できるようにする。
4. Created atや期日表示がロケール引数を渡していることを確認し、不足があれば修正する。
5. widget testで英日Home見出し、詳細Created at、期日表示のロケール差を検証する。
6. `home_tasks.png` / `home_tasks_ja.png` をvisual QAで生成し、英日見出し日付が自然な表記であることを目視確認する。
7. 完了時に `docs/tasks/README.md` と `docs/tasks/BACKLOG.md` を更新し、指示書へ `## 9. 完了報告` を追記する。

### やらないこと

- 相対表記（Today/Tomorrow/今日/明日）の文言変更。
- 期日ピッカー自体の挙動変更。
- DB上のepoch millisecondsやタイムゾーン保存方針の変更。
- ARB文言の追加・変更（必要が出た場合のみ最小限にする）。
- 新規pub/crate依存の追加。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. `app/lib/` と `app/test/` の `DateFormat`、固定パターン、`yyyy-MM-dd` 相当の手組み整形を検索する。
3. Home見出し用の整形を `DateFormat.MMMEd(locale)` ベースのヘルパーへ寄せる。
4. 未使用でもUI用に残っている日付整形関数が固定表示を返している場合は、`DateFormat.yMMMd(l10n.localeName)` 等へ変更する。
5. `task_components.dart`、`tasks_screen.dart`、`task_detail_screen.dart` の表示経路が `Localizations.localeOf(context).toLanguageTag()` または `l10n.localeName` を渡していることを確認する。
6. widget testで `en` / `ja` のHome見出し、Created at、相対表記例外を検証する。
7. visual QAで `home_tasks.png` / `home_tasks_ja.png` を生成し、見出し日付を目視する。
8. 品質ゲートを実行し、結果を完了報告へ記録する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準を満たすこと。

タスク固有の受け入れ基準:

- [ ] `app/lib/` に `DateFormat('...')` 形式の固定パターン文字列と `yyyy-MM-dd` 相当の手組み日付表示が残っていない。
- [ ] Home見出しの日付が `DateFormat.MMMEd` 相当の skeleton API で表示され、en/jaのwidget testで期待値を確認している。
- [ ] 詳細画面のCreated atが `DateFormat.yMMMd` 相当の skeleton API で表示され、jaロケールでも自然な表記になることを確認している。
- [ ] 期日pillとタスク作成シートの期日表示が `DateFormat.MMMd` 相当の skeleton API または既存相対l10n文言で表示される。
- [ ] Today/Tomorrow/今日/明日などの相対表記は現状維持され、絶対日付だけがロケール準拠になっている。
- [ ] `home_tasks.png` / `home_tasks_ja.png` をvisual QAで生成し、英日見出し日付が自然な表記であることを目視確認している。
- [ ] 完了報告に、置換箇所一覧、DateFormat検索結果、追加・更新したテスト名、スクショ目視結果を記録している。

## 7. 制約・注意事項

- `docs/design/ui-spec.md` セクション1の「日付・時刻の表記はホストOSの言語・ロケール設定に従う」を正とする。
- intlの固定パターン文字列を使わず、skeleton APIへ委ねる。
- `Localizations.localeOf(context).toLanguageTag()` または `AppLocalizations.localeName` を使い、Dart VMのデフォルトロケールに暗黙依存しない。
- 相対表記はl10n文言として維持する。これはui-specの例外である。
- UI文字列を追加する場合はARB化する。ただし本タスクは原則として新規表示文言を追加しない。
- 新規依存は追加しない。
- 生成物ではない `app/lib/src/generated/l10n/` はARB変更がない限り触らない。

## 8. 完了報告に含めるべき内容

完了報告は事実のみを記録する。以下を含めること。

- 作業日、読んだファイル
- `app/lib/` のDateFormat/固定パターン棚卸し結果
- 置換箇所一覧と、各箇所で使ったskeleton API
- 相対表記を維持した箇所
- 追加・更新したwidget test名と検証対象
- visual QAの退避先、出力先、`home_tasks.png` / `home_tasks_ja.png` の目視結果
- 品質ゲートの実行結果
- 変更ファイル一覧
- 未解決事項（なければ「なし」）
