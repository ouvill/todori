# task-105: Timer Sync Foundation

> ステータス: 進行中（ADRと共有同期契約を実装中）
> 作業日: 2026-07-13

## 1. 背景とコンテキスト

P2-M7のPomodoro / Stopwatch / Focusには、再起動可能な端末ローカル計測と、複数端末で振り返れる完了実績の両方が必要である。task statusの`in_progress`はKanban上の明示状態であり、FocusやTimerの実行状態ではない。

本taskではUIやTimer engineより先に、active sessionと同期済みwork sessionを分離した状態モデル、Tenant Root DEKのlocal runtime供給、`timer_sessions`同期collection、削除tombstoneを重要変更として確定・実装する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md` / `STATUS.md` / `BACKLOG.md`
- `docs/03_技術仕様書.md` §3.11 / §4 / §6
- `docs/05_設計判断記録.md` ADR-007 / ADR-011〜017
- `docs/08_Phase2計画書.md` P2-M7
- `core/domain` / `core/storage` / `core/crypto` / `core/sync` / `core/client`
- `server/src` / `server/migrations` / `server/tests`
- `app/rust/src/api.rs`とFRB生成設定

## 3. ゴール

- task statusとTimer状態を直交させ、Timer操作で`in_progress`を含むstatusを変更しない。
- 1 device 1 active sessionをdurableに保存し、wall-clockからrunning / pausedを復元できる。
- 完了または明示保存した中断work sessionだけをTenant Root DEKで暗号化して同期する。
- task / list永久削除時に関連timer sessionを同一transactionで削除・tombstone化する。
- UI / engineが後続taskで利用できる厳密なdomain / storage / sync / client / FRB契約を提供する。

## 4. スコープ

### やること

- ADR-018と技術仕様へTimer状態、暗号、同期、削除契約を記録する。
- domainへactive / completed timer sessionの型、validation、復元用duration計算を追加する。
- local schema v18へsingleton active state、completed timer session、Tenant Root DEK cacheを追加する。
- Tenant Root DEKをMKでlocal-wrapし、account runtimeの同期鍵として復元する。
- protocol v5へ`timer_sessions` collectionとstrict typed plaintextを追加し、既存envelope v3 / AAD契約を維持する。
- completed sessionのenqueue / apply / immutable merge / tombstoneを実装する。
- serverのopaque collection CHECKとstable scan / history / continuity cursorを更新する。
- task / list永久削除と関連session tombstoneをatomicにする。
- 必要最小のclient / FRB DTOとAPI、focused Rust / bridge testsを追加する。

### やらないこと

- Pomodoro / Stopwatchのtick engine、通知、background lifecycle adapter。
- Flutter provider、router、screen、ARB、Focus UI、見積対実績表示。
- Timer開始 / pause / finishによるtask status変更。
- break sessionの実績同期、端末ローカル設定の同期。
- streak、ranking、reward、統計dashboard、新規package。

## 5. 実装手順

1. ADR-018、技術仕様、schema / protocol / envelope互換境界を確定する。
2. domain entity、validation、wall-clock復元計算を実装する。
3. local schema v18とrepositoryへactive singleton / completed session / Tenant Root DEK cacheを追加する。
4. account登録・login・restartでTenant Root DEKをlocal cache / runtimeへ供給する。
5. strict timer plaintext、collection、既存envelope v3、immutable merge、enqueue / applyを実装する。
6. server schemaとopaque sync経路を`timer_sessions`へ拡張する。
7. task / list永久削除へ関連sessionのdomain削除・sync tombstoneを同一transactionで統合する。
8. FRB最小API、focused tests、全Rust / bridge / boundary gate、独立検証を実行する。

## 6. 受け入れ基準

- [ ] Focus / Timerの開始・pause・resume・finishがtask statusを変更するAPIを持たない。
- [ ] active stateはdevice-local singletonでrunning / pausedとwork / short break / long breakを表現する。
- [ ] running復元は`accumulated_active_ms + max(0, now - last_resumed_at)`、paused復元はaccumulatedだけを使う。
- [ ] 完了または明示保存した中断work sessionだけをcompleted sessionとして保存・同期する。
- [ ] breakはlocal計測 / 設定に限定し、同期実績へ変換しない。
- [ ] completed sessionがtask_id、mode、finish kind、started / ended、active duration、created_at、UTC timestamp範囲を厳密検証し、active完了はID / task / mode / work / started_at一致を必須とする。
- [ ] completed session live recordはimmutableで、同ID・同内容は冪等、異内容はmergeせずcorruptionとして拒否する。
- [ ] timer session tombstoneはterminalで、task / list永久削除時に関連sessionとatomicにenqueueされる。
- [ ] Undoでtaskを再開してもTimerを自動再開しない。
- [ ] Tenant Root DEKがtenant IDへ束縛したlocal-wrapでcacheされ、login / restart後のruntimeへ平文永続化なしで供給される。
- [ ] `timer_sessions`はTenant Root DEKと既存envelope v3 AADで暗号化され、wrong key / collection / record IDを拒否する。
- [ ] protocol v5、envelope v3、local schema v18、server migrationが一致し、v18 migrationは既存outbox / state / cursor / quarantine / full-resync state / marks / originを保全する。
- [ ] serverは`timer_sessions`のopaque blob / tombstoneだけを扱い、task_idやdurationを平文で保持しない。
- [ ] migration / write failureでactive / completed / key cache / outbox / record state / HLCが部分commitしない。
- [ ] sync convergence、immutable conflict、delete tombstone、one-active、復元、暗号AAD、migrationのRust testが成功する。
- [ ] full Cargo / bridge release / boundary / diff gateと独立検証が成功する。

## 7. 制約・注意事項

- `in_progress`はKanbanまたはユーザーの明示操作だけで変更する。
- active sessionは同期せず、端末をまたいだ排他lockを作らない。
- completed work sessionは不変の実績recordであり、修正は旧record tombstone + 新UUID recordで表す。
- task_idは暗号plaintext内だけに置き、server-visible relationを追加しない。
- Tenant Root DEK / MK / plaintext / session titleをlog、error、完了報告へ含めない。
- pre-releaseのbreaking migrationとし、dual read/write、version alias、旧payload fallbackを追加しない。
- 新規依存を追加しない。
- production Flutter UIとDesign Labを変更しない。

## 8. 完了報告に含めるべき内容

- ADR / domain状態遷移 / duration source / immutable mergeの最終契約。
- local / server schema、protocol / envelope version、migration結果。
- Tenant Root DEKのserver wrap / local cache / runtime供給とAAD。
- enqueue / apply / tombstone / task-list削除atomicityの実装結果。
- FRB API shape、全focused / full gate、独立検証、commit hash。
- skip、環境制約、未解決事項、後続Pomodoro / Stopwatch / Focus範囲。
