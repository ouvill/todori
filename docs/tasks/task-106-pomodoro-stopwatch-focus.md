# task-106: Pomodoro / Stopwatch / Focus Experience

> ステータス: 進行中（engine・lifecycle・production Focus UIを実装中）
> 作業日: 2026-07-13

## 1. 背景とコンテキスト

task-105で、task statusと直交する端末ローカルactive session、同期対象のimmutable work実績、Tenant Root DEK、削除tombstoneを実装した。本taskではその契約を利用し、Pomodoro / Stopwatchのwall-clock engineと、作業へ没入するproduction Focus experienceを完成させる。

`in_progress`はKanbanまたはユーザーの明示操作専用である。Focus開始・pause・resume・finishはtask statusを変更しない。Focus中にtaskを完了する場合だけ、sessionの保存終了に成功した後で明示的にtaskを`done`へ変更する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md` / `STATUS.md` / `BACKLOG.md`
- `docs/tasks/task-105-timer-sync-foundation.md`
- `docs/03_技術仕様書.md` §3.11 / `docs/05_設計判断記録.md` ADR-018
- `docs/08_Phase2計画書.md` P2-M7
- `docs/design/ui-spec.md` / `docs/design/visual-direction.md`
- `app/lib/src/router.dart` / `main.dart` / `core/bridge_service.dart` / `core/providers.dart`
- `app/lib/src/screens/tasks_screen.dart` / `task_detail_screen.dart`
- `app/lib/src/notifications/reminder_notifications.dart`
- task-105のRust client / storage / FRB Timer APIと生成物

## 3. ゴール

- PomodoroとStopwatchを開始・pause・resume・finishでき、background / 再起動後もwall-clock基準で正しく復元する。
- Focus setup / running / paused / add time / finish / discardをShell外の専用routeで提供する。
- open taskのtrailing swipeからFocusへ入り、Due変更はTask detailのpropertyへ集約する。
- Focus lifecycleとtask statusを直交させ、実績保存・task完了・Undoの順序を回帰テストで固定する。
- Task detailで見積時間と同期済み合計実績を静かに比較できる。

## 4. スコープ

### やること

- active sessionのconditional create / same-ID update契約。別session IDが存在する開始はtyped conflictとし、既存activeをUPSERTで黙って置換しない。
- Pomodoro既定値: work 25分、short break 5分、long break 15分、4 workごとにlong break。
- `timer_settings_v1`を既存の暗号化local settingsへJSON保存し、5分刻み・妥当範囲をtyped validationする。設定は同期しない。
- Stopwatchのstart / pause / resume / finishと、completed / interrupted work実績の原子保存。
- `DateTime.now`とdurable active stateによるwall-clock復元。background tickへ正しさを依存させない。
- background中のPomodoro target到達時刻を、pause区間を除いたtarget到達instantとして確定する。resume時刻をendedAtにしない。
- 既存`flutter_local_notifications` / `timezone`を使った明示opt-inのbest-effort Timer通知。Reminderのpayload/categoryとは別ownerへ分離する。
- kill中は通知だけを行い、DB確定や自動phase遷移はしない。resume / restart時にengineがsettleする。
- `BridgeService`、production bridge、Fake bridge、providers、cache invalidationをTimer APIへ接続する。
- Shell外の`/focus/:listId/:taskId` route。setupはwarm light、running / pausedはFocus専用dark inverseとする。
- Focus setup、running、paused、add time、finish、discard、task complete、error / restore状態。
- Home / List共通task rowのopen task trailing swipeをFocus revealへ変更する。closed taskはFocusを出さない。Due編集はTask detail property sheetで維持する。
- Task detailへestimated minutes / completed work実績合計の最小比較を追加する。
- Focus中のtask完了は、現在のwork sessionを保存終了してからtaskを`done`にする。保存失敗時はtaskを完了しない。Undoはtaskだけを再開し、Timerを自動再開しない。

### やらないこと

- Focus操作からの`todo` / `in_progress` / `done` / `wont_do`自動遷移（Focus内の明示task completeを除く）。
- active session同期、break実績同期、設定同期。
- background worker、exact alarm保証、Live Activity / Dynamic Island、Android foreground service。
- kill中のDB書込・phase自動遷移。
- streak、ranking、reward、統計dashboard。
- 通常画面のdark mode、新規package、Design Labからproductionへのimport。

## 5. 実装手順

1. **contract owner**: Rust storage / clientへconditional createとsame-ID transitionを追加し、typed conflict・原子finish・status非変更を固定する。FRB生成物まで先行commitする。
2. **engine owner**: `BridgeService` / Fake / providerへTimerを接続し、settings、wall-clock state machine、restore / resume settle、completed total invalidationを実装する。router / theme / ARBは編集しない。
3. **notification owner**: Reminderから分離したTimer notification adapterを既存pluginで実装し、permission拒否・cancel・resume時settleをテストする。
4. 共有contract統合後、**UI owner**がrouter、Focus screen/components、task swipe、Task detail comparison、theme token、ARBを単独所有して実装する。
5. engine ownerとUI ownerは重複ファイルを持たない。`router.dart`、`providers.dart`、`tasks_screen.dart`、`task_detail_screen.dart`、theme、ARB、Visual QA harnessは各1 ownerに限定する。
6. Focus中task完了、sync/cache invalidation、Home / List / Calendarとの復帰を統合する。
7. 実装不参加のverifierが統合HEADを独立検証し、不合格は画面・状態・具体差分でfix ownerへ戻す。

## 6. 受け入れ基準

- [ ] 別IDのactive sessionを開始しても既存activeを置換せずtyped conflictになる。同IDの正当なpause / resume / add time更新だけを許可する。
- [ ] Pomodoro既定25 / 5 / 15分、4 workごとのlong breakとlocal typed settingsが動作する。
- [ ] Stopwatchがstart / pause / resume / finishでき、pause時間を実績へ含めない。
- [ ] runningはwall-clock、pausedはaccumulatedだけから復元し、background / restart後も7日上限内で一致する。
- [ ] target超過をresume時にsettleしてもendedAtはtarget到達instantになり、active durationと整合する。
- [ ] completedまたは明示保存したinterrupted workだけを同期し、breakは同期しない。
- [ ] Focus開始・pause・resume・通常finishでtask statusが変わらない。
- [ ] Focus中task completeはsession保存成功後にだけ`done`となり、失敗時はstatus不変。UndoでTimerは再開しない。
- [ ] dedicated Focus routeがsetup / running / paused / add time / finish / discard / restore / errorを表現する。
- [ ] running / pausedのみdark inverse、setupと通常画面はwarm single-canvasを維持する。
- [ ] open task trailing swipeがFocusを表示し、DueはTask detail propertyから編集できる。
- [ ] Task detailでestimated / total actualが表示され、実績追加・sync・task削除後にinvalidateされる。
- [ ] 通知permission拒否でもTimerは動作し、通知はbest-effort、kill中DB確定なし、resume時settleとなる。
- [ ] semantics、44px以上のtap target、text scale 2.0、320px狭幅、日本語、RTL、Reduce Motionを満たす。
- [ ] Rust testsでconditional active、state transition、restore、target instant、atomic finish、status不変を固定する。
- [ ] Flutter testsでengine lifecycle、settings、notification、Focus全状態、swipe、detail集計、task complete / Undo、cache invalidationを固定する。
- [ ] Visual QAで390×844、320px、720 / 1024px、setup / running / paused / finish / error、background復帰を確認する。
- [ ] Cargo / release bridge / Flutter / hardcoded strings / boundary / `git diff --check`が成功し、独立検証が合格する。

## 7. 制約・注意事項

- Timer stateとtask statusは別state machineである。`in_progress`はKanban / 明示操作専用。
- engine判断を画面widgetへ分散しない。時刻計算、phase遷移、session保存順序は単一provider / controllerが所有する。
- periodic timerは描画更新だけに使い、durationの真実源にしない。
- lifecycle ownerは`main.dart`の既存`WidgetsBindingObserver`へ統合し、別observerを乱立させない。
- Timer notificationはReminder notificationとID / payload / categoryを分離する。
- FRB生成物はcodegenのみで更新し、手編集しない。
- productionはDesign Labをimportしない。fake dataはtest / Design Labに限定する。
- 新規依存は追加しない。必要になった場合は作業を止め、重要変更として承認を得る。

## 8. 完了報告に含めるべき内容

- conditional active契約とstate transition、wall-clock / pause / target instant計算。
- settings / notification / lifecycle / restart restoreの実装結果。
- Focus routeと全状態、task swipe、Task detail comparison、task complete / Undo順序。
- task status非変更の回帰証拠と、work / break同期境界。
- Rust / Flutter / Visual QA / full gate / 独立検証結果、commit hash。
- intentional skip、OS制約、未解決事項、後続の統合仕上げ範囲。
