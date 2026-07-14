# task-107: Integrated Product Finish

> ステータス: 完了（production contract・runtime・motion・Visual QAを統合し独立検証済み）
> 作業日: 2026-07-13

## 1. 背景とコンテキスト

task-100〜106でsingle-canvas production UI、計画属性付きCapture、Search、Calendar、Timer同期、Pomodoro / Stopwatch / Focusを順に実装した。本taskは新機能を追加するのではなく、実装済みの全体を単一のプロダクト体験として整合させる最終統合である。

`docs/design/ui-spec.md`にはCalendar完成前、Focus実装前、task-100移行中の記述が残っている。実装を正しく監査したうえで現在の拘束仕様へ再canon化し、navigation、route復帰、provider invalidation、sheet、task row、完了motion、全状態の視覚品質を統合HEADで検証する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md` / `DESIGN_PLAYBOOK.md` / `STATUS.md` / `BACKLOG.md`
- `docs/tasks/task-100-production-design-foundation.md`〜`task-106-pomodoro-stopwatch-focus.md`
- `docs/design/ui-spec.md` / `visual-direction.md`
- `app/lib/src/router.dart` / `main.dart` / `core/providers.dart` / `core/bridge_service.dart`
- Home / Lists / Task detail / Capture / Search / Calendar / Focusのproduction widget
- `app/test/visual_qa/visual_qa_screenshots_test.dart`と関連widget / provider tests

## 3. ゴール

- `ui-spec.md`をtask-106完了後のproduction実装と裁定へ一致させ、古い暫定規則と既知逸脱を解消する。
- Home / Calendar / Lists / You / Capture / Search / Task detail / Focusの遷移と復帰を一貫させる。
- create / update / complete / reopen / sync / timer finish後に、同じtaskを表示する全surfaceが適切に再取得されることを固定する。
- productionの主要画面・system state・sheet・motionを狭幅、ワイド、日本語、text scale、RTL、Reduce Motionで視覚・操作の両面から検証する。
- Design Labをfake data専用の独立環境として維持し、productionからimportしない。

## 4. スコープ

### やること

- `ui-spec.md`のHomeをToday + Overdue統合 + 控えめなCompletedへ更新する。
- CalendarをHome / Calendar / Lists / Youのトップレベルnavigationとして確定し、Week / Month / Completed / occurrence移動の規則を記録する。
- CaptureのList / Due / Plan / Priority、Searchのimmersive全状態、Focusのsetup / dark running-paused / finish-discard / status直交を拘束仕様へ反映する。
- trailing swipe Focus、Task detailのpriority / due / plan / estimate / actual、root navigator sheet、home indicatorまで連続するwarm surfaceをcanon化する。
- routerとnavigation stackを監査し、deep link、detail、Search、Focusから安全かつ予測可能に復帰させる。
- task mutationとsync後のHome / List / Search / Calendar / detail / actual total cache invalidationを監査・修正し、回帰テストを追加する。
- 完了motionをpress → fill → check → halo → strike → 500ms hold → 420ms collapseへ統一し、Reduce Motionでは即時確定する。
- stale comment、暫定名、実装済み機能をfuture扱いするtest / docsを整理する。
- production Visual QA harnessを主要routeとempty / loading / error / completed disclosure / completion midframeへ拡張し、全PNGを目視する。

### やらないこと

- 新しいdomain属性、同期collection、schema / protocol変更。
- Timerからのtask status自動変更。`in_progress`はKanbanまたは明示操作専用のまま維持する。
- 通常画面のdark mode、active session同期、break実績同期、設定同期。
- recurrence / template、analytics dashboard、Live Activity、exact alarm、background worker。
- Design Lab componentをproductionへimportすること、Design Labのfake dataをproductionへ接続すること。
- 新規package / font追加、`docs/01_企画書.md` / `docs/02_機能仕様書.md`変更。

## 5. 実装手順

1. 監督者がtask契約、shared file owner、統合順序を確定する。read-onlyのspec、runtime/cache、visual/accessibility監査を並列で行う。
2. **spec owner**が`ui-spec.md`を実装済みproduction契約へ再canon化する。過去裁定履歴は保持し、現在規範から暫定文言を除く。
3. **integration owner**がrouter / providers / production screensを単独所有し、監査で確認した遷移・invalidation・状態欠落だけを最小修正する。
4. **visual test owner**がproduction Visual QA harnessと非重複testを拡張する。Design Labは編集・importしない。
5. 統合HEADでfocused tests、Flutter full gate、Rust / boundary gate、Visual QAを実行する。
6. 実装不参加のverifierがtask-100〜106との整合、全受け入れ基準、全PNGを独立検証する。不合格は画面名・状態・具体差分でfix ownerへ戻す。

## 6. 受け入れ基準

- [x] `ui-spec.md`の現在規範にCalendar完成前、Focus実装前、task-100移行中の暫定記述が残っていない。
- [x] HomeがToday + Overdue統合 + 小さなCompleted、CalendarがWeek / Month + day agendaとして仕様・実装・Visual QAで一致する。
- [x] mobileはHome / Calendar / 中央Capture / Lists / You、wideは同じIAのcompact railとなり、専用routeではglobal navigationを隠す。
- [x] Capture / Search / Calendar / Focusのopen・detail遷移・back / close・deep-link exitが予測可能で、sheet下端に未着色領域がない。
- [x] create / update / complete / reopen / date move / sync / timer finish後、Home / List / Search / Calendar / detail / actual totalの該当表示がstaleにならない。
- [x] Focus開始・pause・resume・通常finishでtask status不変、Focus内task completeはsession保存成功後だけdone、UndoでTimer非再開を維持する。
- [x] open task trailing swipeはFocus、Due / Plan / Priority / EstimateはCaptureまたはTask detail propertyから編集できる。
- [x] priorityは一覧の小さなdotで、due / plan / estimate / actualはplain metadataまたはproperty rowで伝わり、card / pillを増やさない。
- [x] completion motionがpress → fill → check → halo → strike → 500ms hold → 420ms collapseで、halo中心がcheckboxと一致し、Reduce Motionは即時確定する。
- [x] productionからDesign Lab / fake data importがなく、Design Labは独立して動作する。
- [x] semantics、44px以上のtap target、keyboard / accessible date move、色以外の情報伝達、RTLを維持する。
- [x] Visual QAで390×844、320px日本語text scale 2.0、720 / 1024px、empty / loading / error、Completed開閉、completion midframe、Focus各状態を確認する。
- [x] Cargo / release bridge / Flutter / hardcoded strings / boundary / `git diff --check`が成功し、独立検証が合格する。

## 7. 制約・注意事項

- 本taskは統合仕上げであり、監査で見つけた隣接featureを無制限に追加しない。scope外は完了報告へ具体的に残す。
- specは願望ではなくproduction実装と人間裁定の拘束契約にする。実装と矛盾する場合はどちらが誤りかをtask契約から判定して同じcommitで整合させる。
- router、providers、theme、task components、ARB、Visual QA harnessには同時に複数ownerを置かない。
- visual変更は生成PNGを必ず目視し、debug bannerとproduct描画異常を区別する。
- FRB生成物は手編集しない。新規依存が必要になった場合は作業を止める。
- public/private境界を守り、秘密情報と復号済みplaintextをログや報告へ含めない。

## 8. 完了報告に含めるべき内容

- `ui-spec.md`から解消した暫定規則と、現在のHome / Calendar / Search / Capture / Focus契約。
- 遷移、route復帰、cache invalidationで修正した具体箇所と回帰テスト。
- completion motion、Reduce Motion、Design Lab境界の検証結果。
- Visual QAのcase一覧、PNG保存先、目視結果。
- Cargo / Flutter / boundary / full gate / 独立検証結果とcommit hash。
- intentional skip、OS制約、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-13
- 結果: `ui-spec.md`をtask-106後のHome / Capture / Search / Calendar / Focus契約へ再canon化した。Search queryを保持するmutation / sync refresh、list lifecycle後のHome refresh、削除後のTimer refresh、sync single-flightと失敗復帰、foreground Timer restore retryを統合した。
- 完了順序: Home / List / Calendar / Detailの全経路を共有completion coordinatorへ集約した。matching workは実績保存、active breakはlocal終了に成功してからだけtaskを`done`とし、失敗時はstatusを維持する。UndoはTimerを再開しない。
- UI / motion: OnboardingをLucideへ統一し、Focus inverse error / conflict色をtoken化、task rowのdatetimeをcompact表示、Search metadataをmiddle-dot grammarへ統一した。Homeと通常List rootは同じlogical rowでcheck / halo / strikeを描き、500ms hold後420ms collapseする。nested taskは階層内motion、Reduce Motionは即時確定とした。
- 境界: productionからDesign Lab / visual QA / fake bridgeへのimportを静的検査で禁止した。Visual harnessはDEBUG bannerを抑止し、全画面captureをwarm / inverse surfaceへ正規化、毎回生成物をcleanしてmanifest件数を検証する。
- 証拠: Rust workspace 290件成功 / intentional ignored 2件。Flutter 221件成功 / Visual harness通常gate intentional skip 1件。専用Visual QA 120 / 120成功、`app/build/visual_qa/`の128 PNGとmanifest 128行が一致し、全PNGを目視した。
- Commit: `9a03562`, `8d49d3c`, `cf6b028`, `73f3c16`, `f5a3393`, `a5dd87a`, `cfa2d97`, `b6f22bd`, `48fd7c3`, `a9a8570`, `83c88cb`, `2b986b8`, `dd92638`, `cf62d7f`
- 未解決: exact alarm、background worker、Live Activity、通常画面dark modeは既定scope外。iOS / Android実機確認は人間作業として継続する。

### 独立検証

- 判定: 合格（P0〜P2 findingなし）
- 根拠: 実装不参加のverifierがHEAD `cf62d7f`でCargo fmt / clippy / workspace、Docker server auth / RLS / sync、release bridge、Flutter analyze / full test、hardcoded strings、client boundary / negative self-test、diffを再実行した。初回fullでclosed `wont_do` subtaskのdisabled reorder shellを検出し、`cf62d7f`修正後にfocused、motion 4件、Flutter fullを再実行して合格した。Visual QAも120 / 120と主要PNGを独立再確認した。
- 検証者: `/root/task107_independent_verify`（read-only）
