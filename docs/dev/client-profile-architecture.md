# Client profile / frontend adapter architecture

この文書は、Flutter bridge、CLI、MCPからRust共通実装へ入る依存境界と命名規則を定める。profile共有の設計判断はADR-011、同期protocolの正本は`docs/03_技術仕様書.md`とする。

## 目標構成

```mermaid
flowchart TB
  Flutter["Flutter UI"] --> Bridge["todori_app_bridge\nFRB functions + DTO mapping"]
  CLI["todori-cli\nclap I/O adapter"] --> Client
  MCP["todori-mcp-server\nstdio / MCP adapter"] --> Client
  Bridge --> Client["todori-client\nClientProfile + application services"]

  Client --> Domain["todori-domain\nentities + invariants"]
  Client --> Crypto["todori-crypto\nkey hierarchy + E2EE"]
  Client --> Storage["todori-storage\nSQLCipher schema + repositories"]
  Client --> Sync["todori-sync\nprotocol + state machines"]
  Client --> Secrets["OS secret store adapters"]
  Client --> DB[("SQLCipher profile DB")]
  Sync --> Server["E2EE sync server"]
```

依存方向はfrontend adapter → `todori-client` → 下位crateの一方向とする。Flutter、CLI、MCPはrepository、DB key、master key、tenant ID、`LocalMutationContext`、sync storeを受け取らない。`ClientProfile`の高水準methodへtyped inputを渡し、frontend固有の入力・出力へ変換する。

## 所有責務

| 層 | 所有するもの | 所有しないもの |
|---|---|---|
| `todori_app_bridge` | FRB公開関数、文字列/typed input変換、Dart向けDTO変換、process内profile handle | repository、SQLCipher open、鍵、account/sync state、同期順序、runtime生成 |
| `todori-cli` | clap、対話、表示、exit code | CRUD規則、repository、暗号、同期coordinator |
| `todori-mcp-server` | MCP schema、認可prompt、stdio transport、tool response | CRUD規則、repository、暗号、同期coordinator |
| `todori-client` | profile open、account/session、application service、transaction境界、sync coordinator、SQLite sync adapter | Flutter/Dart/FRB、clap、MCP transport |
| `todori-domain` | entity、不変条件、純粋な状態遷移 | DB、network、frontend |
| `todori-storage` | schema、migration、repository、transaction primitive | frontend、network同期順序 |
| `todori-sync` | wire型、E2EE record、merge、同期state machine/trait | Flutter、具体SQLite repository、profile UI |

## Fuzzy-scanの配置

- stable-key page、delta、high-water closure、mark/sweepに必要なprotocol/state machine/traitは`todori-sync`。
- resync generation、preflight、lease、crash recovery、実行順序は`todori-client`。
- cursor/mark table/schema/transactionは`todori-storage`。
- SQLite trait adapterは`todori-client`。
- server current-state scanとGC horizonは`todori-server`。
- Flutter bridgeは`profile.sync_now`と`profile.sync_status`以外のFuzzy-scan実装を持たない。

このためFuzzy-scanを追加しても、FRB公開APIやFlutter側Rust adapterを変更せずに実装できることを設計レビュー条件とする。

## crate命名

`core/`はCargo workspace内の配置ディレクトリで、crateではない。次を正規形とする。

```text
directory:     core/<role>
Cargo package: todori-<role>
Rust import:   todori_<role>
```

`[package] name = "core"`、`[lib] name = "core"`、dependency alias `core = { ... }`、曖昧なumbrella `todori-core` crate、雑多なroot module `mod core`を追加しない。Rust標準の`::core`と名前を競合・混同させないためである。

`todori_app_bridge`はCargo package、lib target、FRB stem、pod名が一致する既存のビルド契約なので改名しない。

## レビューと機械的check

新しいfrontend機能は次の順で実装する。

1. `todori-client`へfrontend-neutralなinput/output/errorとapplication serviceを追加する。
2. domain/storage/syncをまたぐtransactionと回帰testをclient側で完成させる。
3. Flutter/CLI/MCP adapterへ薄い入出力変換を追加する。

`sh app/tool/check_client_boundaries.sh`はfrontend manifestの直接依存、bridge sourceの禁止import、bare `core` crate/aliasを検査する。Cargo compileだけでは検知できない境界の意図をCIで固定する。

task-92で`app/rust/src/support.rs` / `sync_store.rs`を削除し、application/profile責務を`ClientProfile`へ全面移設した。task-93でnetwork FRB関数もasyncへ統一し、bridge内blocking executorを削除した。bridgeの通常依存はFRBと`todori-client`だけで、Todori workspace内依存はclientのみであり、legacy exceptionは存在しない。CIは下位crate参照0、runtime生成0、削除済みmoduleの再作成禁止、manifest allowlistを検査する。Fuzzy-scanはこの境界を変えずに`todori-sync` / `todori-storage` / `todori-client` / serverへ実装する。

Networkを伴うaccount/sync APIは`ClientProfile`とFRBの両方でasyncとし、Futureを直接awaitする。Flutter/Dart、CLI、MCPの各runtime内で自然に実行し、adapterやclientがnested runtimeを生成しない。低水準の`Client`、`LocalMutationContext`、SQLite sync store、local crypto helperは通常public APIではなく、server統合testが`test-support` featureを明示した場合だけ利用できる。
