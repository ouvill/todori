# task-87: typed field clock + placement/rank

## 1. 背景とコンテキスト

task-86はprotocol v2のbase revision CAS、op ID outbox、conflict merge/rebaseを実装し、stale clientによるACK済みblobのblind overwriteを防いだ。一方、production CRUDは現在も全fieldを同一HLCでstampし、plaintextは任意map、`sort_order`はsync payload外の可変長fractional indexである。このままではCAS conflict後のfield mergeがrecord-level LWWへ退化し、同時別field編集と並び替えの収束をrelease gateにできない。

ADR-012 / ADR-014に従い、task/list plaintextを型付きClocked payloadへ置換し、task completionとplacementをcompound fieldとして扱う。rankは固定幅128-bitへ置換し、production common clientを通る同時編集とreorder/rebalanceをtransactionalにする。本taskは同期プロトコル・local schema・データ損失リスクへ触れる重要変更レーンであり、今回の着手はプロダクトオーナー承認済み、完了判定には独立検証を必須とする。

## 2. 事前に読むべきファイル

- `docs/05_設計判断記録.md` ADR-012、ADR-014
- `docs/03_技術仕様書.md` 6章、11.1節
- `docs/tasks/task-85-transactional-crud-migration.md`
- `docs/tasks/task-86-protocol-v2-cas.md`
- `core/sync/src/{field_map,merge,enqueue,apply,envelope}.rs`
- `core/client/src/{task_service,crud_service}.rs`
- `core/domain/src/{entities,sort_order}.rs`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`

## 3. ゴール

- 任意のJSON field mapを、collectionごとに検証可能な型付きtask/list plaintextへ完全置換する。
- local mutationで実際に変わったfield groupだけのclockを進め、未変更fieldとmerge repushのclockを保持する。
- completion / placementの不整合な部分mergeを禁止し、task/listの順序を全端末で決定的に収束させる。
- production CRUD / common clientを通る2-client同時別field編集を自動release gateにする。

## 4. スコープ

### やること

- `Clocked<T> { value, hlc }`相当の型と、厳密に区別されたtask/list plaintext。live taskは少なくともtitle、note、priority、due/schedule/estimate、assignee、created/updated timestamp、completion、placementを、live listはname、color、icon、org/default/archive、created/updated timestamp、placementを復元可能な型で保持する。live payloadの`deleted_at`は同期せず、削除はprotocol v2 tagged tombstoneだけで表す。
- task completionを`status / completed_at / closed_reason`、task placementを`list_id / parent_task_id / rank`のcompound fieldとして各1 clockで扱う。list placementはrankを1 fieldとして扱い、collectionとplaintext kindの不一致、欠落、未知fieldを受理しない。
- production common client内でbefore/afterの型付き値を比較してchanged field groupを決める。createは全fieldを初期stampし、edit/status/undo/list mutation/reorderは実際に変わったgroupだけをstampする。`mutation_hlc`はdomain変更で進め、conflict merge/rebaseはfield clockと`mutation_hlc`を変えず`revision_hlc`だけを進める。
- rankを`00000000000000000000000000000000`〜`ffffffffffffffffffffffffffffffff`の32桁lowercase hexで表す。比較はu128数値順とSQLite binary text順が一致し、表示順は同一scope内の`(rank, record_id)`で決める。task scopeは`(list_id, parent_task_id)`、list scopeはlocal profileのlist集合とする。
- 新規末尾追加、task reorder、sync apply後の衝突、隣接rank間に空きがない場合を扱う。通常は中点を採番し、必要な場合だけ対象scopeを現在の`(rank, record_id)`順を保って十分な間隔へ再配番する。reorder/rebalanceで変更した全domain row、field clock、record state、outbox head、local HLCを1つの`BEGIN IMMEDIATE`でcommitし、途中失敗は全rollbackする。
- account-boundのtask reorderを`core/client`の共通transactionへ移す。anonymousのlocal-only挙動は維持するが、account-bound経路がbridge直下のrepository更新 + 後続enqueueへ戻らないようにする。
- 既存の可変長`sort_order`と任意map plaintextを残さない破壊的local migration / seed再生成。taskは`(list_id, parent_task_id, old sort_order, id)`、listは`(old sort_order, id)`の順を維持して固定幅rankへ正規化する。release前の開発server dataは再作成可能とし、旧plaintext fallback、dual read/write、deserialize aliasは追加しない。
- `docs/03_技術仕様書.md` 6.3節と必要なschema/test注記を、最終の型付きpayloadとrank/rebalance transactionに外科的に同期する。

### やらないこと

- task-86で完成したCAS wire、server current-head、op ID ACK契約の再設計。
- typed pull failure、durable quarantine、cursor page transaction、full resync / GC horizon。
- offline list作成とkey-bundle upload queue、aggregate delete scope / epoch、known-record cascade tombstone。
- 手動順以外の条件ソート、drag UIや画面デザインの変更。
- protocol v1または一時的な任意map plaintextとの互換層。

## 5. 実装手順

1. typed payload、compound field、rank codec / midpoint / rebalanceの失敗テストとproperty testを先に追加する。
2. `core/sync`の任意mapを型付きplaintextと型付きmergeへ置換し、collection一致、strict decode、changed-field stamp、semantic / revision clock分離を実装する。
3. local schemaを破壊的に更新し、既存domain順序を固定幅rankへ正規化して、旧sync state / outboxを捨てたv2 seedを型付きpayloadから再生成する。
4. create/edit/status/undo/list mutationのcommon-client transactionへbefore/after差分に基づくfield clock更新を接続する。
5. task reorderをcommon clientへ移し、固定幅rank生成、必要時だけのscope rebalance、複数recordのatomic outbox生成、failure rollbackを実装する。
6. production CRUDから作った2 clientをtask-86のCAS conflict/rebaseへ通すrelease-gate testを追加し、rank collisionと継続挿入の収束も検証する。
7. 技術仕様を同期し、独立verifierが差分、受け入れ基準、全品質ゲートを再実行する。

## 6. 受け入れ基準

- [ ] task/list plaintextは型付きClocked payloadだけを受理し、任意map、旧alias、collection/kind不一致、不正なcompletion / placement / rankをrejectする。
- [ ] production createは全field groupを初期stampし、edit/status/undo/list mutationはbefore/afterで実際に変わったgroupだけを進め、未変更field clockを保持する。merge repushはfield clockと`mutation_hlc`を変えない。
- [ ] completionの3要素とtask placementの3要素は各1 clockで原子的にmergeされ、異なる世代の部分値を組み合わせない。list placementもrankと1 clockで同期される。
- [ ] 全live rankが32桁lowercase hexで、同一scopeの表示順が全経路で`(rank, record_id)`に統一される。旧rank migrationはtask/listの観測順を維持し、旧plaintext fallbackを残さない。
- [ ] 新規追加とaccount-bound task reorderがcommon-client transactionを通り、空きがある場合は中点だけを採番し、空きなしまたは衝突時は対象scopeだけを現在順のまま再配番する。
- [ ] reorder/rebalance中の任意のdomain / field state / outbox / HLC failureで全変更がrollbackされ、成功時は変更された全recordが同一SQLite transactionでdomain rowと送信可能なoutbox headを持つ。
- [ ] release gateとして、2 clientが同じserver baseからproduction common-client CRUDで同一taskの別fieldを編集し、先着clientのpush ACK直後にそのclientを停止しても、後着clientのCAS conflict / merge / rebase / push後のserver headに両変更が残る。fixtureからplaintextやfield HLCを直接注入しない。
- [ ] same-field conflict、completion対別field編集、placement対別field編集、同rank collision、rank空間枯渇後の再挿入を含むmerge/property testが順序非依存に収束し、全端末のdomain順序が一致する。
- [ ] `docs/03_技術仕様書.md`が最終shapeと一致し、READMEの共通品質ゲート、Docker/Postgresを使うworkspace test、Flutter品質ゲート、`git diff --check`が成功する。
- [ ] 独立verifierがtask-86 CAS不変条件、transaction atomicity、production経路、public/private境界を再確認し、合格根拠を再現可能な形で返す。

## 7. 制約・注意事項

- serverは暗号blobを解釈しない。typed payloadのdecode、validation、merge、rank repairはclient側の暗号境界内で行う。
- field clockのchanged setをFRB / UI callerの自己申告へ委ねず、共通clientがtransaction内のbefore/afterから決定する。
- equal HLCで異なる値をargument orderで勝敗決定しない。corruptionとして明示的に拒否するか、型ごとの安定したcanonical total orderで対称に解決し、property testで固定する。
- rank比較にlocale、大小文字混在、可変長文字列を使わない。`record_id` tie-breakを永続rankへ毎回書き戻さず、rebalanceは必要時だけ行う。
- transaction内でHTTP、key refresh、その他network I/Oを行わない。複数recordのrebalanceを個別commitへ分割しない。
- FRB公開APIを変更した場合は2.12.0固定のcodegenを実行し、生成物を手編集しない。
- 本taskが独立検証まで合格する前に、production同時編集またはplacement/rankをrelease-readyと表現しない。

## 8. 完了報告に含めるべき内容

- task/list typed plaintextとClocked field groupの最終shape、旧map / rankの破棄方法。
- changed-field算出、completion / placement merge、`mutation_hlc` / `revision_hlc`分離の実装箇所。
- rank codec、中点、tie-break、rebalance scopeとtransaction境界。
- production common-client 2-client release gateの操作順と、両変更が残った観測証拠。
- migration、rollback、merge/property test、全品質ゲート、独立検証の結果。
- 本task外に残したquarantine、full resync、offline list作成、aggregate deleteの後続事項。
