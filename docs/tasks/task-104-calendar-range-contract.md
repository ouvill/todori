# task-104: Calendar Range Contract and UI

> ステータス: 完了（Calendar期間契約・Week / Month・Home簡略化を独立検証合格）
> 作業日: 2026-07-13

## 1. 背景とコンテキスト

taskはADR-017のtyped due、開始予定を表す`scheduled_at`、成果を表す`completed_at`を持つが、Calendar向けの期間取得契約とproduction画面がない。Home向けqueryは表示対象を1 taskへ集約するため、dueとscheduledを別の予定として扱うCalendarには流用できない。

本taskでは、viewerのcivil-date範囲とUTC instant範囲を組にした半開区間契約をstorageからFRBまで追加し、その後にWeek / Month UI、日付変更、Completed、navigationを統合する。同じtaskのdueとscheduledは別occurrenceとして返し、task statusと計測状態は変更しない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md` / `STATUS.md` / `BACKLOG.md`
- `docs/03_技術仕様書.md`のtask / client / FRB記述
- `docs/05_設計判断記録.md` ADR-017
- `docs/08_Phase2計画書.md` P2-M6
- `docs/tasks/task-100-product-ui-redesign-v2.md`
- `docs/tasks/task-101-task-due-semantics-redesign.md`
- `docs/tasks/task-102-task-planning-attributes-and-capture.md`
- `core/storage/src/lib.rs`
- `core/client/src/runtime/application.rs`
- `app/rust/src/api.rs`とFRB生成設定
- `app/lib/src/core/bridge_service.dart` / `providers.dart`
- `app/lib/src/router.dart` / production task components

## 3. ゴール

- date-only due、datetime due、scheduled、completedを意味の異なるoccurrenceとして期間取得できる。
- dueとscheduledを併せ持つtaskを2 occurrenceとして表示できる。
- WeekはTodayと一貫したtask row、Monthは7列gridと選択日のagendaを提供する。
- Completedを`completed_at`基準の控えめな成果として確認できる。
- Calendar完成後にHomeをToday / Overdue / Completedへ簡略化し、Calendarをnavigationへ追加する。

## 4. スコープ

### やること

- `CalendarRange`とtyped `CalendarOccurrence`をstorage / client / FRB / Dartへ追加する。
- civil dateとUTC instantを対にした半開区間で、日付期限とinstant occurrenceを取得する。
- task本体、list名、list archive状態、occurrence種別と値を返す。
- active (`todo` / `in_progress`)はdue / scheduled、closed (`done` / `wont_do`)は`completed_at`だけをoccurrenceとして返す。archive済みlistを含め、削除済みtaskを除外する。
- Week / Month / selected-day agenda / wide two-pane / Completed disclosureを実装する。
- occurrence単位の日付変更と同等のaccessibility menuを実装する。
- Calendar navigation追加後にHomeの4期日区分をToday / Overdue / Completedへ簡略化する。
- focused Rust / bridge / provider / widget testとVisual QAを追加する。

### やらないこと

- Timer session、Pomodoro、Stopwatch、Focus routeの実装。
- Calendar操作によるtask statusや`in_progress`の自動変更。
- recurring task、外部calendar連携、通知時刻の変更。
- task LWW、同期plaintext、protocol、DB schemaの変更。
- 新規package、Design Labからproductionへのimport。

## 5. 実装手順

1. storageへ半開区間のCalendar queryとtyped occurrenceを実装する。
2. clientのfrontend-neutral viewを経由してFRB / Dartへ公開し、正規codegenする。
3. 境界、DST長の日、dual occurrence、全status / archived、deleted除外をtestで固定する。
4. providerへWeek / Month / selected dayの取得とcache invalidationを実装する。
5. WeekをTodayと同じ完了可能なtask row、Monthを7列grid + agendaとして実装する。
6. wide two-pane、Completed disclosure、occurrence単位の日付変更とmenuを実装する。
7. Calendarをnavigationへ追加し、HomeをToday / Overdue / Completedへ簡略化する。
8. 狭幅、日本語、text scale 2.0、RTL、各system stateをVisual QAし、統合HEADを独立検証する。

## 6. 受け入れ基準

- [x] `CalendarRange`はcivil dateとUTC instantの両方を持つ有効な半開区間である。
- [x] date-only dueはcivil date範囲、datetime due / scheduled / completedはUTC instant範囲で判定する。
- [x] occurrenceがtask本体、list名、list archive状態、typed kindと対応値を持つ。
- [x] dueとscheduledを持つ同一taskが別occurrenceとして返る。
- [x] `completed`は`completed_at`だけを基準とし、due / scheduledの代用にしない。
- [x] todo / in_progressはdue / scheduled、done / wont_doはcompletedだけを返し、closed taskを通常agendaとCompletedへ二重表示しない。
- [x] active / archived listを含み、deleted taskだけを除外する。
- [x] range終端は含まず、23時間 / 25時間のlocal dayでも固定24時間を仮定しない。
- [x] client / FRB / Dartがstorageへ薄く接続され、task LWW / schema / sync protocolを変更しない。
- [x] WeekはTodayと同じtask rowで完了操作ができ、Monthは7列gridと選択日のagendaを持つ。
- [x] wideではgridとday agendaを2 paneで表示する。
- [x] Completedは`completed_at`基準の控えめなdisclosureとして表示する。
- [x] dragは掴んだoccurrenceだけを変更し、同等の日付変更menuを利用できる。
- [x] Calendarをnavigationへ追加し、HomeをToday / Overdue / Completedへ簡略化する。
- [x] cache invalidation、semantics、RTL、狭幅、日本語、text scale 2.0を回帰test / Visual QAで確認する。
- [x] Rust / Flutterのfocused test、Visual QA、共通品質ゲートが成功する。
- [x] 実装非担当者の独立検証が合格する。

## 7. 制約・注意事項

- `TaskDue::Date`を端末timezoneの擬似instantへ変換しない。
- datetime dueの保存timezoneは表示contextであり、期間判定は保存済みUTC instantを使う。
- `scheduled_at`は開始予定、dueは完了期限、`completed_at`は成果時刻として別occurrenceを維持する。closed taskは成果として振り返るため、過去のdue / scheduledではなくcompleted occurrenceだけを返す。
- half-open rangeのcivil date境界とinstant境界は呼出側が同じviewer timezoneから構成する。storageで24時間加算しない。
- Calendar操作は既存task updateとLWWへ委譲し、別の競合解決規約を追加しない。
- Focus / Timerとtask statusを結び付けず、`in_progress`を自動設定しない。
- FRB生成物を手編集しない。
- productionからDesign Lab / visual QA mockをimportしない。
- 実装担当と独立検証担当を分け、WIPはtask-104の1件に限定する。

## 8. 完了報告に含めるべき内容

- CalendarRange / occurrenceの最終API shapeと半開区間の意味。
- date-only / datetime / scheduled / completed、dual occurrence、DST境界のtest結果。
- 全status / archived / deleted除外とtask LWW不変の証拠。
- Week / Month / wide / Completed / date change / Home / navigationの実装結果。
- Visual QA保存先と狭幅、日本語、text scale 2.0、RTL、各system stateの所見。
- 全品質ゲート、独立検証、commit hash、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-13
- 契約: `CalendarRange`をviewer-local civil dateとUTC instantの2つの半開区間としてstorage / client / FRB / generated Dartへ追加した。date-only dueはcivil範囲、datetime due / scheduled / completedはinstant範囲で判定し、23時間 / 25時間のDST日でも24時間加算しない。`CalendarOccurrence`はtask、list名、archive状態、typed kindを持つ。activeはdue / scheduled、closedは`completed_at`だけを返し、dual occurrenceを別々に保持する。archive済みlistを含め、deleted taskを除外する。
- mutation / cache: BridgeはFRBへの薄い委譲で、日付変更は既存task updateとLWWへ1回だけ委譲する。date-only / datetime due / scheduledのkindとwall timeを保持し、掴んだoccurrence以外を変更しない。completedは移動不可。task / list / sync mutation後にCalendar / Home / List cacheをinvalidateする。schema、sync plaintext、protocol、task status規約は変更しておらず、Calendarから`in_progress`を自動設定しない。
- UI: production `/calendar`へWeek 7日、locale準拠Month 7列grid、選択日agenda、1024px two-pane、720px single-pane、Completed disclosure、long-press dragと48px日付menu、detail往復を実装した。mobile / railはHome / Calendar / Capture / Lists / You。agendaは`AppHomeTaskRow`、3階層tree、priority、list contextを再利用する。due + scheduledは別identityで、task完了時は同一taskの全表示occurrenceがhalo / strike後500ms保持・420ms collapseし、保持中はCompletedへ二重表示しない。Reduce Motionでは即時確定する。datetime dueはviewer-local日に配置しつつ、保存timezoneのwall time、IANA ID、UTC offsetを表示・読み上げる。
- Home: 4期日区分をToday 1 streamへ簡略化し、overdueはcoral metadata、today due / scheduledを同じ流れに表示する。Tomorrow / UpcomingはCalendarへ移し、Homeには表示しない。成果欄はplanning属性に依存せず今日の`completed_at`で取得し、Homeだけ`Completed`と表示する。通常listの`Closed`は維持した。
- Visual QA: `app/build/visual_qa`で94 case成功、100 PNGを生成した。Calendar Week / Month / selected / dual / Completed / move sheet / empty / loading / error / datetime timezone / completion midframe、日本語、RTL、320px、text scale 2.0、720 / 1024pxとHome Completedを目視した。狭幅mode重なり、saved timezone欠落、Home旧Closed文言、Calendar halo remountを検出して修正し、最終画像でoverflow、home indicator下の未着色、tree connectorのcheckbox貫通、wide比率の問題がないことを確認した。赤白斜線はFlutter DEBUG bannerでgeometry評価外とした。
- 品質ゲート: `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Docker統合testを含む`cargo test --workspace`、`flutter analyze`、`flutter test --concurrency=1`（179成功、Visual QA harness 1件は通常実行で意図的skip）、hardcoded strings、client boundaries、`git diff --check`が成功した。Rustの実Keychain 1件と手動performance 1件は既定どおりignoreである。
- Commits: `e7d43e2`、`591fea0`、`db08972`、`e95b4ee`、`ab2bd10`、`e3c1a6e`、`2865ef9`、`0ee0bf7`、`ca22f3f`、`1bf0d82`、`97a4e30`。
- 未解決: なし。Timer同期、Pomodoro / Stopwatch / Focusは後続taskで実装する。

### 独立検証

- 判定: 合格（最終HEAD `97a4e30`、残存P1 / P2なし）。
- 根拠: 初回監査からplanning無しの今日完了がHome成果へ出ない、datetime dueの保存timezone欠落、Home成果欄が旧`Closed`表記、Calendar完了時のsubtree remountでhaloが消える、の4件を不合格とした。各修正と回帰test追加後に、半開区間 / DST / dual / closed分離 / archive / deleted、薄いbridge、kind別move / LWW、cache invalidation、Home簡略化、Week / Month / wide / tree、dual completion / Reduce Motion、accessibility menu、route state、status非変更、Design Lab境界を再照合した。Cargo fmt / workspace clippy / Rust focused、Flutter provider / Calendar / Home focused、Flutter analyze、hardcoded / client boundary、diff check、Visual QA 94件と100 PNGを再確認してすべて成功した。
- 検証者: 実装非担当サブエージェント `/root/task103_verifier`。
