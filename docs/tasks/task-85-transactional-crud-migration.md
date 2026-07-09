# task-85: 既存List CRUDのtransactional client移行

> ステータス: 実装中
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

task-83はtask editだけを共通client transactionへ移し、task-84はsession非依存LocalCryptoContextを実装した。残るtask create/status/undoとlist rename/archive/unarchiveは、domain commit後に別connectionでoutboxを登録するため、enqueue失敗時にlocal-only変更が残る。

## 2. 事前に読むべきファイル

- `docs/05_設計判断記録.md` ADR-011〜ADR-013
- `docs/tasks/task-83-transactional-client-foundation.md`
- `docs/tasks/task-84-local-crypto-context.md`
- `core/client/src/task_service.rs`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`

## 3. ゴール

- 既存List配下でoffline完結できる主要CRUDを`core/client`へ移す。
- domain row、undo、HLC、outbox、record stateを同一`BEGIN IMMEDIATE` transactionで確定する。
- Flutter bridgeをDTO変換とanonymous fallbackへ近づける。

## 4. スコープ

### やること

- task create、status transition、undo。
- list rename、archive、unarchive。
- 必要な`SqliteWriteTx`操作の追加。
- success/failure injection、offline context、bridge signature回帰テスト。
- account-bound pathは共通clientのみを通し、anonymous pathは現行local-onlyを維持する。

### やらないこと

- offline list作成とkey-bundle upload queue。
- task reorderのprotocol v2 placement同期。
- task/list deleteのknown-record cascade tombstone。
- reminder/settingsの同期化。
- field clock / wire protocol v2。

## 5. 実装手順

1. write transactionへlist/task query・insert/update・undo restoreを追加する。
2. `core/client`へtask/list application serviceを追加する。
3. failure triggerでdomain/undo/HLC/outbox/stateのrollbackを証明する。
4. account-bound bridge mutationを共通clientへ委譲する。
5. 独立検証と全品質ゲートを実行する。

## 6. 受け入れ基準

- [ ] task create/status/undoが共通client transactionを通る。
- [ ] list rename/archive/unarchiveが共通client transactionを通る。
- [ ] 各操作でdomain row、必要なundo、HLC、outbox、record stateがatomicにcommitされる。
- [ ] outbox/state失敗時に全状態がrollbackされる。
- [ ] status/undoのdomain conflict semanticsが既存挙動を維持する。
- [ ] account-bound session期限切れでもLocalCryptoContextからoutboxを生成する。
- [ ] Flutter公開signatureとDTOを維持する。
- [ ] workspace/Flutter品質ゲートと`git diff --check`が成功する。

## 7. 制約・注意事項

- transaction中にnetwork I/Oを行わない。
- anonymous profileだけがlocal-only pathを使用できる。
- reorderをv1 payloadのまま「同期対応済み」としない。
- delete root 1件だけのtombstone経路を共通clientへ固定しない。
- public FRB APIと生成物を手編集しない。

## 8. 完了報告に含めるべき内容

- 移行したoperation一覧。
- transaction failureごとのrollback証拠。
- anonymous/account-bound bridge分岐。
- 品質ゲート。
- reorder、delete、offline list createの後続事項。
