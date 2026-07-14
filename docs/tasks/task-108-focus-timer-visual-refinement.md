# task-108: Focus / Timer Visual Refinement

> ステータス: 進行中
> 着手日: 2026-07-14

## 1. 背景とコンテキスト

task-106でPomodoro / Stopwatch / Focusのwall-clock engineと専用routeを実装し、task-107でproduction全体の遷移・状態・Visual QAを統合した。現在のFocusはsetupのwarm canvasからrunning / pausedの全面dark inverseへ切り替わるため、同じアプリ内の連続した体験に見えにくい。また、active画面へ複数の同格ボタンとsession終了系操作が常設され、計時中に必要な情報と判断の優先順位が弱い。

プロダクトオーナーは、Focus全状態をTodori共通のwarm canvasへ戻し、没入感を色面の反転ではなく、Shell外route、情報量の削減、静かなopen dial、単一の主操作で作る方向を採用した。本taskはvisual refinementであり、task-105/106で確立したTimer保存・同期・wall-clock・task status直交の契約は変更しない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md` / `DESIGN_PLAYBOOK.md` / `STATUS.md`
- `docs/tasks/task-105-timer-sync-foundation.md`
- `docs/tasks/task-106-pomodoro-stopwatch-focus.md`
- `docs/tasks/task-107-integrated-product-finish.md`
- `docs/design/ui-spec.md` / `docs/design/visual-direction.md`
- Focus production screen / theme / ARB / router / Timer providers
- Design LabのFocus mockとproduction Visual QA / Focus widget tests

## 3. ゴール

- setup / running / paused / break / finished / restore / error / conflictを、同じwarm single-canvasの連続したFocus experienceとして再構成する。
- Pomodoroの残量とStopwatchのelapsedを、カードや円形背景面を置かない細いopen dialで区別して伝える。
- active画面の常設操作をPause / Resumeと`Session options`へ絞り、Add time、finish、task complete、save exit、discardを状態別trayへ整理する。
- Focus lifecycle、session保存順序、task status非変更、restart復元、break handoffを視覚変更後も維持する。
- Design Labをproductionから独立したまま、同じ裁定済みvisual directionへ更新する。

## 4. スコープ

### やること

- 全Focus状態のScaffoldを`AppColors.canvas`へ統一し、Focus専用dark inverseとinverse分岐をproductionから削除する。
- 中央に開始角135度・描画範囲270度の細いopen dialを実装する。外周カード、円形surface、heavy shadowは置かない。
- Pomodoroはhairline track上のforest arcを残り時間に応じて減少させる。pausedは同じ値を保ったままarcをsageへ弱める。work / short break / long breakはphase labelとaccentで区別する。
- Stopwatchは完了率を示さず、静的なopen arcとelapsed clockを使う。
- setupをtask title、compactなPomodoro / Stopwatch selector、preview dial、時間・設定、最大幅280pxのStartへ集約する。
- active画面の常設操作を64px級の円形Pause / Resumeと`Session options`に限定し、マスコットを置かない。
- warm surfaceがhome indicatorまで続く共通bottom sheetを実装する。Pomodoro workはAdd 5 min / Finish session / Complete task / Save and exit / Discard、StopwatchはAdd timeを除く同じ操作、breakはEnd break / Discardを表示する。
- close、system back、画面内`Session options`を同じsheetへ接続する。sheetを閉じた場合はactive sessionを継続する。
- finishedは同じwarm canvasとdial構図を維持し、記録時間、Start break、Doneだけを表示する。
- setup→runningを260msのfade + 0.985→1.0 scale、pause / resumeを180msのarc・label・icon遷移、finishedを260msのdial収束として実装する。Reduce Motionでは装飾遷移を省略して即時切替する。
- production widgetをimportしないDesign LabのFocus mockをwarm open-dial方向へ更新する。
- 必要な英日ARB、semantics、Visual QA case、widget testを更新する。

### やらないこと

- Timer / Focus操作からのtask status自動変更。`in_progress`はKanbanまたは明示的task操作専用のまま維持する。
- Timer engine、wall-clock計算、session保存順序、通知、同期collection、storage / client / FRB APIの変更。
- active session同期、break実績同期、Timer設定同期。
- 通常dark mode、Focus専用dark surface、Live Activity、Dynamic Island、background worker、exact alarm。
- 新規package、font、画像素材、productionからDesign Labへのimport。
- task-106 / task-107の履歴変更。

## 5. 実装手順

1. spec ownerが本taskの1〜8章と`ui-spec.md`を先行更新し、warm canvas、open dial、操作階層、motion、Design Lab境界を共有契約として確定する。
2. production UI ownerがthemeから未使用になるFocus inverse tokenとwidgetのinverse分岐を削除し、setup / active / finished / system statesをwarm canvasへ統一する。
3. 同ownerがopen dial painter、Pomodoro / Stopwatch / paused / breakの表示差、primary Pause / Resume、状態別Session options sheetを実装する。Timer engineのstate判断はwidgetへ移さない。
4. test ownerがFocus lifecycleの既存回帰テストをsheet導線へ更新し、dial、warm canvas、semantics、back / close、状態別action、Reduce Motionを追加する。
5. Design Lab ownerがproduction codeをimportせずFocus mockと独立interactionを同じvisual directionへ更新する。
6. Visual QAのbeforeを退避し、afterを390×844、320px日本語text scale 2.0、720px、1024pxと全Focus状態で生成する。Simulator録画または実機でcolor flashとmotionを確認する。
7. 統合HEADでFlutter full gate、Cargo / boundary gate、hardcoded string検査、`git diff --check`を実行し、実装不参加のverifierが全Focus PNGとtask-105/106契約を独立検証する。

## 6. 受け入れ基準

- [x] setup / running / paused / break / finished / restored / error / conflictのScaffoldがすべて`AppColors.canvas`を使い、状態遷移で全面dark inverseまたは色のflashが発生しない。
- [x] Pomodoroは135度開始・270度のopen dialで、hairline track上のforest arcが残量に応じて減少する。pausedはsageへ弱まり、背景は変わらない。
- [x] Stopwatchは同じopen-dial文法を使うが、完了率を示す進捗arcを表示せずelapsedを伝える。
- [x] setupがcompact selector、preview、時間・設定、最大幅280pxのStartからなる1本の静かな縦軸になり、外周cardや巨大なmode buttonを使わない。
- [x] active画面で常設される操作は64px級のPause / Resumeと`Session options`だけであり、マスコットと同格CTA群がない。
- [x] Session options sheetがhome indicatorまでwarm surfaceを連続させ、Pomodoro work / Stopwatch / breakごとに指定されたactionだけを表示する。
- [x] close / system back / Session optionsが同じsheetへ到達し、sheet dismissalだけではsessionをfinish / discardしない。
- [x] finishedがwarm canvasとdial構図を維持し、記録時間、Start break、Doneだけを表示する。
- [x] setup→running 260ms、pause / resume 180ms、finished 260msの遷移を持ち、Reduce Motionでは装飾motionなしに即時確定する。
- [x] Focus start / pause / resume / finish / discardでtask statusが変わらず、Complete taskはsession保存成功後だけ`done`、UndoはTimer非再開を維持する。
- [x] restart restore、active conflict、error、break handoff、deep-link exitの既存挙動がvisual変更後も維持される。
- [x] semantics、44px以上のhit target、clockとprimary actionの読み上げ、色以外のphase / pause表現、RTL、320px、日本語、text scale 2.0を満たす。
- [x] Design Lab Focusがwarm open-dialへ更新され、productionからDesign Lab / fake dataへのimportがない。
- [ ] Visual QAで全Focus状態と指定viewportをbefore / after目視比較し、Simulator録画または実機でcolor flashとmotionを確認する。
- [ ] Flutter full gate、Cargo / boundary gate、hardcoded strings、`git diff --check`が成功し、独立検証が合格する。

## 7. 制約・注意事項

- 本taskはvisual / interaction hierarchyの変更であり、Timerのdomain・persistence・sync契約を再設計しない。
- periodic tickは表示更新にだけ使い、dialの真実源は既存controllerが返すwall-clock stateとする。
- Stopwatchへ恣意的なgoalや完了率を導入しない。PomodoroとStopwatchの意味差を色だけで伝えない。
- destructive actionはsheet下部へ分離し、coralと文言の両方で意味を伝える。既存の確認と保存失敗時の再試行可能性を維持する。
- modal sheetはroot navigator上で表示し、SafeArea外を含む下端へwarm surfaceを塗る。
- dial、clock、primary control、ripple、semantics boundsの中心を一致させる。装飾arcはpointer hit testを持たない。
- productionはDesign Labをimportしない。Design Labはfake dataと独立stateだけを使う。
- task-106 / task-107は完了履歴であり、本taskの新しい裁定を遡及して書き換えない。

## 8. 完了報告に含めるべき内容

- warm canvas化、削除したinverse token / 分岐、open dialの幾何・状態別表現。
- setup / active / finishedとSession options sheetの構成、close / back / dismissal挙動。
- Focus lifecycle、status非変更、finish-before-done、Undo非再開、restart / break handoffの回帰証拠。
- motion timing、Reduce Motion、semantics、RTL、狭幅、日本語、text scaleの検証結果。
- Design Lab境界とproduction import guardの結果。
- before / after PNG保存先、確認した全Focus状態、Simulator録画または実機確認結果。
- Flutter / Cargo / hardcoded strings / boundary / `git diff --check`、独立検証結果、commit hash、intentional skip、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-14
- UI: Focus全状態を`AppColors.canvas`へ統一し、`AppFocusColors`とproductionのinverse分岐を削除した。135度開始・270度sweepのhairline open dialへ置換し、Pomodoroは残量arc、Stopwatchは静的arc、paused / breakはsageで区別する。
- 操作階層: setupをcompact selector、preview、時間設定、最大幅280pxのStartへ集約した。activeの常設操作は64px Pause / Resumeと`Session options`だけにし、状態別actionをhome indicatorまでwarm surfaceが続く共通sheetへ移した。close / system backも同じsheetを開き、dismissだけではsessionを変更しない。
- 契約維持: Timerのdomain、storage、FRB、同期APIは変更していない。Focus lifecycle、status非変更、session保存後のtask complete、Undo非再開、restart restore、break handoffを回帰テストで固定した。
- 再訪修正: `Save and exit`、finishedの`Done`、system Backで、永続化済みsessionを残したまま表示用`lastCompletion`だけをclearする。これにより同じtaskのFocusへ再訪するとsetupへ戻り、新しいsessionを開始できる。別taskの`lastCompletion`はfinished表示に使わない。英語の`safely recorded`とDesign Labの不要なsafe表現も簡潔なcopyへ変更した。
- 自動終了: foregroundでrunning中のPomodoro work / breakが0へ到達すると、1秒のdisplay tickから既存wall-clock settlementを実行する。workは遅延したtick時刻ではなく正確なtarget時刻でcompleted sessionを保存してfinished / break pendingへ進み、breakはwork実績を追加せず`Break complete`へ進む。失敗時はdurable active sessionを残して次のtick / resume / restartで再試行する。Stopwatchとtask statusの契約は変更していない。
- motion / accessibility: setup→running / finishedを260ms、pause / resumeを180msとし、Reduce Motionは即時切替とした。320px日本語text scale 2.0、RTL、64px primary、44px以上のsecondary hit target、clock / action semanticsを検証した。
- Design Lab: production widgetをimportせず、独立fake stateのwarm open-dial setup / active / finishedへ更新した。
- Visual QA: beforeは`app/build/visual_qa_before_task108/`、afterは`app/build/visual_qa/`。全125 caseが成功し、manifest 133行と133 PNGが一致した。Focusはsetup / running / paused / sheet / finished / restored / restoring / error / conflict / break / break finished / Stopwatch / RTL / Reduce Motion / 320 / 720 / 1024を目視した。
- 品質ゲート: Rust workspace 290件成功 / intentional ignored 2件。Flutter full 232件成功 / Visual harness通常gate intentional skip 1件。Timer engine 19 / 19、Focus 13 / 13、Design Lab 3 / 3、専用Visual QA 125 / 125。Cargo fmt / clippy / release bridge、Flutter analyze、hardcoded strings、client boundary / negative self-test、`git diff --check`は成功した。
- Commit: `a9e3cb2`, `41f7cd4`, `ae082c1`, `fe80bf5`, `1811f57`, `f290ea1`

### 独立検証

- 初回判定: 不合格（P0 0 / P1 0 / P2 2）。実装不参加のverifierがHEAD `41f7cd4`で全品質ゲートとFocus PNGを再検証し、production不具合は検出しなかった。P2はSimulator / 実機motion確認未実施と、Stopwatch / RTL / Reduce Motion専用PNG不足だった。
- 是正後判定: 不合格（P0 0 / P1 0 / P2 1）。`ae082c1`でStopwatch / RTL / Reduce Motionの3専用caseを追加し、verifierが3 / 3、全124 / 124、manifest / PNG 132 / 132、該当3 PNGを再確認した。Visual QA不足のP2は解消した。
- 再訪修正判定: 合格（P0〜P2 findingなし）。verifierが`fe80bf5`の`Save and exit`後の実績保持・setup復帰・再startを確認し、system Backの不足を指摘した。`1811f57`でBackとtask-scoped completionを是正し、Focus 12 / 12とdiffを再確認して合格した。
- 自動終了判定: 合格（P0〜P2 findingなし）。verifierが`f290ea1`を独立検証し、Timer engine 19 / 19、Focus 13 / 13、Flutter full 232件、analyze、hardcoded strings、`git diff --check`、`focus_break_finished`の生成と目視を再確認した。workのtarget時刻保存、breakの実績非追加、失敗時のretry設計を含めて合格した。
- 未解決: 最新HEADのiOS Simulator build / install / launchとHome実画面確認は成功したが、macOSが`osascript`のAssistive Accessを拒否したため、Focusのcolor flash / motion録画は未実施である。この人間確認と独立合格まではtaskを進行中のまま維持する。
