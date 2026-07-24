---
id: 019f9053-29dc-74e0-a73c-4ee48b63c0b5
title: Replace List crypto boundary with Tenant
status: done
lane: critical
milestone: maintenance
---

# Replace List crypto boundary with Tenant

## 1. 背景とコンテキスト

現行production実装はListごとのDEK、key bundle、同期前処理を持ち、Listを暗号境界としている。この構造では同じ共有・membership範囲にあるList間のTask移動にも再暗号化とList key lifecycleが必要になり、配置entityであるListと共有・暗号・同期scopeが結合している。

2026-07-24にProduct Ownerは、過去にrevertした全面E2EE再設計を復元せず、現行mainを基点として次の限定したdomain変更を行うことを承認した。設計相談の結果、新しいSpace entityは追加せず、既存Tenantを暗号・共有・同期・local DB境界として明確化する。今回の実装はPersonal Tenantだけを有効化し、Shared Tenantの状態機械は後続のcritical設計ゲートへ分離する。

- AccountとTenantはmembershipによる多対多とし、Account作成時にPersonal Tenantとowner membershipを作る。
- Tenantを暗号・共有・同期・local DB境界とする。
- Personal Tenantは複数Listを持つ。
- List、Task、Tag、Completion、Comment等はTenant内の暗号化Recordとする。
- List削除はTask削除へcascadeしない。
- 同一Tenant内のList移動は配置変更とし、Tenant間移動は再暗号化を伴うcopy/deleteとする。
- List DEK、`list_key_bundles`、List単位key APIを廃止する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md`
- `core/domain`
- `core/crypto/src/key_hierarchy.rs`
- `core/storage/src/lib.rs`
- `core/sync`
- `core/client`
- `server`

## 3. ゴール

- Tenantをdomain、暗号key generation、Record routing、同期cursor、共有membershipの一貫した境界にする。
- Listを通常のTenant内domain entityへ変更し、List lifecycleからkey lifecycleを分離する。
- Personal / Sharedの違いをListではなくTenantの属性とmembership policyで表現できる基盤を作る。
- fresh pre-release baselineとしてList単位key schema / API / runtime cacheを残さない。

## 4. スコープ

### やること

- Account / Tenant / TenantMembershipのdomain境界
- Tenant Key generationからRecord Keyを導出するkey hierarchy
- Tenant単位のlocal key cacheとserver key bundle
- Tenant単位のopaque Record同期、cursor、quota / membership境界
- TenantごとのSQLCipher DBを開けるprofile/catalog境界
- List非cascade、同一Tenant内配置変更、Tenant間copy/deleteの不変条件
- storage schemaのfresh breaking更新と関連test
- client、bridge、既存UIを壊さないために必要なadapter更新
- 技術仕様、ADR、運用上必要な公開文書の外科的更新

### やらないこと

- revertしたE2EE product foundations redesign全体の復元
- OPAQUE、Account recovery、anonymous membership、PQC、認証方式の再設計
- Shared Tenantの作成・公開
- 招待、承諾、取消、離脱、除名、ownership transfer
- Shared TenantのRole / permission matrixとmember向けTenant Key配送
- Record author署名を使う暗号学的write authorization
- 添付file、enterprise organization、field単位ACL
- 既存development DB / wire protocolとの互換layerまたはdata migration
- Product要件文書`docs/01_企画書.md` / `docs/02_機能仕様書.md`の不要な全面改稿

## 5. 実装手順

1. List IDがkey、Record、sync、storage、server APIへ伝播する箇所を棚卸しする。
2. Tenant / Record / placementの不変条件とbreaking schemaを仕様・ADRへ固定する。
3. domain、crypto、storageの順でTenant境界を実装する。
4. sync、server、clientをTenant単位key / routingへ置換する。
5. bridge / Flutter adapterを更新し既存のPersonal Space利用経路を維持する。
6. List非cascade、同一Tenant移動、cross-Tenant拒否、key isolationのtestを追加する。
7. 全品質ゲートと独立検証を行う。

## 6. 受け入れ基準

- [x] Tenantが暗号・membership・sync・local DB境界としてdomainと技術仕様に定義されている。
- [x] Personal Tenantとowner membershipがAccount作成時に確定する。
- [x] Personal Tenantに複数Listを作成でき、追加Listごとのkey生成・uploadを行わない。
- [x] Tenant IDとList IDが同一視されていない。
- [x] Record keyはTenant Key generationとRecord identityからdomain-separatedに導出される。
- [x] `ListDek`、`list_key_bundles`、`pending_list_key_bundles`、List key APIがproduction code/schemaから除去されている。
- [x] List削除がTaskを削除せず、Taskを有効な同一Tenant内配置へ収束させる。
- [x] 同一Tenant内のList移動はRecord再暗号化keyを変更しない。
- [x] Tenant間移動は今回有効化せず、暗黙のcross-Tenant参照をfail closedにする。
- [x] 別Tenantのkey、Record、membership、cursorを取り違えるnegative testがある。
- [x] Shared Tenantの作成・招待・member write経路が未設計のまま有効になっていない。
- [x] 一般リリース前のbreaking baselineとして旧schema / protocol fallbackを残していない。
- [x] Rust / Flutter / boundary品質ゲートが成功している。
- [x] 独立検証が合格している。

## 7. 制約・注意事項

- 暗号namespace v1、FRB 2.12.0、Keychain / Keystore固定契約は変更しない。
- Tenant Root DEK、Record Key、plaintextをlogや完了報告へ出さない。
- current-head、tombstone、offline rebaseのdata safetyをList IDからTenant IDへ機械的に改名するだけで済むと仮定しない。
- UI上のListと共有境界を再結合するcompatibility aliasを作らない。
- 未設計のShared Tenantでは、key possessionだけをwrite権限として扱う暫定実装を作らない。
- `authorize(tenant, actor, action)`相当のserver認可境界を分散させず、Personal owner以外をfail closedにする。
- public repoへprivateな事業・法務・監査情報を置かない。

## 8. 完了報告に含めるべき内容

- 削除したList境界と導入したTenant境界
- schema / protocol / APIのbreaking変更
- key isolation、List非cascade、move semanticsのtest証拠
- 品質ゲートと独立検証結果
- 実行不能な検証と未解決事項

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-24
- 結果: Tenant Root DEKからRecord identityごとのkeyを導出する構造へ切り替え、List key generation、bundle、API、runtime cacheを除去した。Listは通常の暗号化Recordとなり、List削除時はTask、Reminder、Timer Session、Undo履歴を削除せずdefault Inboxへ収束する。Account登録はPersonal Tenantと単一active owner membershipを作成し、Shared / Enterpriseはdomainとschemaと同期認可でfail closedにした。
- Breaking変更: envelope v5（`TDE5` / `TDA5`）、Tenant専用manifest `TKM2`、sync protocol v7、local schema v21。`TKM2`と`key_recipients`からList scope discriminator / List IDを除去し、旧List key reader / writerとfallbackは残していない。
- 証拠: `record_key_is_deterministic_and_bound_to_tenant_generation_collection_and_record`、`membership_cannot_cross_tenant_boundary`、`shared_tenant_is_fail_closed_until_protocol_is_approved`、List削除のstorage / sync / Flutter integration test、Account登録後のPersonal kind / 単一owner integration assertion、RLS cross-Tenant test。`cargo test --workspace --quiet`、`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、Rust bridge release build、`flutter analyze`、`flutter test`（275 passed、visual QA opt-in 1 skipped）、client boundary 2 scripts、hardcoded string check、`git diff --check`を実行した。
- Commit: 未コミット
- 未解決: Shared / Enterpriseの招待、離脱、role別認可、Tenant Root DEK配送、Tenant subscription / seat課金、複数Tenant DB catalogと切替UIは後続のcritical設計判断。Flutterのvisual QA screenshot suiteは環境変数によるopt-inのため1件skip。List削除前のUndo行は履歴として保持するが、Task配置の更新後に旧操作を再実行すると通常の更新競合になる。

### 独立検証

- 判定: 合格
- 根拠: 初回検証は、FlutterがList削除後のReminder通知をcancelすること、List crypto scopeがmanifest / recipient schemaへ残ること、削除確認文言と機能仕様がcascade削除を案内することをP1として指摘した。修正後の再検証で、Inbox rehomeとReminder / Timer / Undo行保持、OS通知cancel除去、Tenant専用`TKM2`、Tenant専用recipient schema、ARB生成物 / Bridge契約 / `docs/02_機能仕様書.md`、Account登録のPersonal kind / 単一owner assertionを確認した。`cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、TKM2 / manifest anchor / storage / auth / rotation重点test、`flutter analyze`、Flutter integration test 8件、client boundary 2 scripts、`git diff --check`を独立再実行し、blocking findingなし。
- 検証者: sub-agent `/root/independent_review`
