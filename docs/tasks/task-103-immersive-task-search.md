# task-103: Immersive Task Search

> ステータス: 進行中（Bridge / provider契約を先行実装）
> 着手日: 2026-07-13

## 1. 背景とコンテキスト

local DBにはFTS5によるtask検索があり、`todori-client`とFRB Rust APIも`search_tasks`を公開している。一方、production Dart層の`BridgeService`、Riverpod状態、専用routeが未接続であるため、既存検索機能をユーザーが利用できない。

本taskでは既存FTS契約を変更せず、title / noteを対象とするdebounce付き検索状態とimmersive Search routeをproductionへ接続する。検索結果はtask statusやlist archive状態で隠さず、削除済みtaskだけを除外する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md` / `STATUS.md` / `BACKLOG.md`
- `docs/03_技術仕様書.md`のtask / FTS記述
- `docs/tasks/task-62-fts5-wiring.md`
- `docs/tasks/task-100-product-ui-redesign-v2.md`
- `docs/tasks/task-102-task-planning-attributes-and-capture.md`
- `core/storage/src/lib.rs`の`search_tasks` / `build_fts_prefix_query`
- `core/client/src/runtime/application.rs`
- `app/rust/src/api.rs`
- `app/lib/src/core/bridge_service.dart` / `providers.dart`
- `app/lib/src/router.dart`
- `app/test/support/fake_bridge_service.dart`

## 3. ゴール

- production Dart層から既存FTS5検索を呼び出せる。
- 空query、debounce中 / 検索中、結果、0件、errorが明示的な状態として扱える。
- 古い非同期結果が新しいqueryの結果を上書きしない。
- title / note、全status、archive済みlistのtaskを検索できる。
- 結果からTask detailへ遷移でき、元のSearchへ戻れる。

## 4. スコープ

### やること

- `BridgeService.searchTasks`と`FrbBridgeService`を既存`rust_api.searchTasks`へ接続する。
- FakeBridgeServiceへproduction相当のtitle / note prefix AND検索を追加する。
- Riverpodへdebounce、明示的idle / loading / data / error、stale-result protectionを持つ検索状態を追加する。
- active / archived list名を結果contextへ合成する。
- immersive Search routeとsingle-canvas検索画面を実装する。
- 空query、検索中、結果、0件、error、詳細遷移を実装する。
- Home / Lists / Youの既存search導線を同じrouteへ接続する。
- 英日ARB、semantics、keyboard、back navigation、widget test、Visual QAを追加する。

### やらないこと

- FTS schema、tokenizer、ranking、storage queryの変更。
- task本文以外のlist名、tag、添付、自然言語日付を検索対象へ追加すること。
- Calendar、Timer、Pomodoro、Focusの実装。
- remote / server検索、新規package導入。
- Design Labをproductionからimportすること。

## 5. 実装手順

1. 既存storage FTS契約とclient / FRB公開関数をtestで確認する。
2. BridgeService / fakeへsearch APIを追加する。
3. query generationとtimer cancellationを持つRiverpod検索状態を実装し、active / archived list contextを合成する。
4. providerのidle / loading / data / empty / error / stale-result testを追加する。
5. immersive routeとSearch screenをsingle-canvas文法で実装する。
6. 検索結果をTask detail routeへ接続し、全status / archived listの表示contextを保つ。
7. 狭幅、日本語、text scale 2.0、keyboard表示、全状態をVisual QAする。
8. 統合HEADで品質ゲートを実行し、実装非担当者が独立検証する。

## 6. 受け入れ基準

- [ ] BridgeServiceが既存FRB `searchTasks(query)`を薄く公開する。
- [ ] 空または空白queryはbridgeを呼ばずidleになる。
- [ ] 非空queryはdebounce中からloadingとして観測できる。
- [ ] title / noteの各query termをprefix ANDとして検索する。
- [ ] todo / in_progress / done / wont_doをすべて返す。
- [ ] active listとarchived listのtaskを返し、削除済みtaskだけを除外する。
- [ ] 結果へlist名とarchive状態のcontextを付与する。
- [ ] 古いrequestの成功 / errorが新しいquery、または空queryの状態を上書きしない。
- [ ] immersive Search routeが空query、loading、結果、0件、errorをsingle-canvasで表示する。
- [ ] 結果からTask detailへ遷移し、戻るとqueryと結果を維持する。
- [ ] keyboard操作、clear、back、tooltip / semantics、48px級tap targetを満たす。
- [ ] 320px、390x844、日本語、text scale 2.0でoverflowや操作不能がない。
- [ ] FTS schema / query、sync protocol、DB migration、新規依存を変更していない。
- [ ] focused provider / widget test、Visual QA、共通品質ゲートが成功する。
- [ ] 独立検証で検索範囲とstale-result protectionが合格する。

## 7. 制約・注意事項

- storageの`build_fts_prefix_query`と`bm25`順を正本とし、Dart側で結果の再検索・再rankingをしない。
- list archive状態は表示contextであり、検索対象を制限するfilterではない。
- completed taskはユーザーの成果であり、検索結果から除外しない。
- provider dispose、query clear、連続入力時にtimerと古いFutureを無効化する。
- errorへquery本文やtask内容を不要に記録・log出力しない。
- productionからDesign Lab / visual QA mockをimportしない。
- 実装担当と独立検証担当を分け、WIPはtask-103の1件に限定する。

## 8. 完了報告に含めるべき内容

- BridgeServiceとprovider stateの最終API shape。
- FTS検索範囲、prefix AND、ranking、削除除外を変更していない証拠。
- debounce値、idle / loading / data / error遷移、stale-result test。
- immersive route、detail遷移、全status / archived contextの結果。
- Visual QA保存先と狭幅、日本語、text scale 2.0、keyboardの所見。
- 全品質ゲート、独立検証、commit hash、未解決事項。
