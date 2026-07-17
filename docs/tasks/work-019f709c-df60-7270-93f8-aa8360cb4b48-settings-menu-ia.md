---
id: 019f709c-df60-7270-93f8-aa8360cb4b48
title: Menu-first account information architecture
status: done
lane: standard
milestone: maintenance
---

## 1. 背景とコンテキスト

2026-07-18のプロダクトオーナー指示により、グローバルナビゲーションからAccountへ直接遷移する構造をやめ、メニュー一覧を経由してAccountへ進む情報設計へ変更する。Account画面の視覚改善差分はmainから専用worktreeへ移して継続する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/design/ui-spec.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `app/lib/src/router.dart`
- `app/lib/src/ui/app_navigation_shell.dart`
- `app/lib/src/screens/account_screen.dart`

## 3. ゴール

- mobile / wide navigationの最終destinationをMenuにする。
- Menuに実在する遷移先だけを連続rowで表示し、AccountとCalendar settingsへ1操作で進めるようにする。
- AccountをMenu配下の戻れる画面として扱い、既存の認証、同期、課金、Security、Server URL操作を維持する。

## 4. スコープ

### やること

- `/menu` と `/menu/account` routeの追加、旧トップレベル`/account` routeの置換。
- Account、Calendar settings、Templatesへ進めるMenu画面の追加。
- Calendarの週開始曜日を地域の既定 / 月曜 / 日曜から選択し、暗号化ローカル設定へ保存する。
- bottom navigation / railのYouをMenuへ変更。
- Accountの戻る導線、英日ARB、widget / route / visual QA testの更新。
- `docs/design/ui-spec.md`へ2026-07-18のMenu-first裁定を反映。

### やらないこと

- 実体のない通知、外観、言語、法務ページへのdead-end row追加。
- Accountの認証、同期、課金、暗号境界の変更。
- 新規依存、schema、protocol、FRB APIの変更。

## 5. 実装手順

1. Menu画面と英日文言を追加する。
2. shell destinationとrouterをMenu-first構造へ変更する。
3. Accountへ戻る導線を追加し、既存Account改善差分を統合する。
4. widget testとvisual QAを更新し、狭幅・日本語・大文字サイズを確認する。
5. Flutter品質ゲートとboundary checkを実行する。

## 6. 受け入れ基準

- [x] bottom navigation / railにMenuが表示され、選択するとAccountではなくMenu一覧を開く。
- [x] MenuからAccountを開き、戻る操作でMenuへ戻れる。
- [x] Menuには実在するAccount / Calendar settings / Templatesだけが表示され、dead-end rowがない。
- [x] Calendar settingsで地域の既定 / 月曜 / 日曜を保存でき、Week / Month表示と取得範囲へ反映される。
- [x] Accountのログイン、登録、ログアウト、同期、課金、Safety number、Server URL操作が回帰していない。
- [x] 390px通常表示と320px日本語text scale 2.0でoverflowせず、主要操作へスクロール到達できる。
- [x] `flutter analyze`、`flutter test`、hardcoded strings、client boundary、`git diff --check`が成功する。

## 7. 制約・注意事項

- warm single canvas、Inter、hairline中心とし、Menu rowへ外周cardや情報pillを追加しない。
- top-level destinationの意味が変わるため、route、shell selection、test、UI specを同時に更新する。
- public/private境界へ触れず、秘密情報を表示・記録しない。

## 8. 完了報告に含めるべき内容

- worktree / branch、変更route、Menu row一覧。
- Accountの既存操作を維持したtest結果。
- Menu / Accountのvisual QA画像と狭幅確認結果。
- 独立検証の判定、未解決事項、commit。

## 9. 実装・検証結果

- `/menu`をトップレベルdestination、`/menu/account`と`/menu/calendar`を戻れる子routeとして実装した。Menu rowはAccount、Calendar settings、Templatesのみ。
- Calendar settingsで地域の既定 / 月曜 / 日曜を選択できる。暗号化ローカル設定の`calendar_week_start`へ保存し、Week / Monthの先頭列とoccurrence取得範囲に同じ値を適用した。
- Accountへsubtitle、privacy intro、signed-in identity、同期状態、用途別sectionを追加した。既存操作と境界は変更していない。
- 390px通常表示と320px日本語text scale 2.0のMenu / Account / Calendar settingsをvisual QAし、狭幅では戻る操作を独立route barへ配置してoverflowを解消した。戻る矢印は48pxのtap targetを維持しつつ、見出しと同じ左端へ揃えた。
- `cargo build --release`、`flutter analyze`、`flutter test`（266件成功、visual QA harness 1件skip）、hardcoded strings、client boundary check / test、`git diff --check`が成功した。
- 全体テストで既存カレンダーテストの日曜始まり週における土曜→翌日仮定を検出したため、表示中の別日をdrag targetに使う曜日非依存テストへ修正し、単独・全体の両方で再検証した。
- 初回独立レビューでMenu→Templatesの戻り履歴欠落（P1）とCalendar設定保存失敗時の直前値・再試行手段喪失（P2）を検出した。`push`遷移、往復test、直前値保持、失敗通知、再試行testを追加して修正した。
- 修正後の独立再レビューは元P1 / P2解消、新規P0〜P3なし、重大・中程度の指摘なしでPASSした。独立側でも対象12件と`git diff --check`が成功した。
- 非blocking残存リスクは、初回設定read失敗時の画面内retry未実装と、保存中disabled状態のscreen-reader専用assert未追加。実装差分はDraft PR #34として公開した。
