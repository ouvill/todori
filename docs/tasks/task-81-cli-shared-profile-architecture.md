# task-81: CLI / Flutter共通ローカルプロファイル設計の確定

> ステータス: 完了（ADR-011採用・技術仕様とバックログへ反映）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

TaskveilはFlutterデスクトップ版に加えてWindows / macOS / Linuxで動作するRust CLIを提供する方針だが、現状の `cli/` はスタブであり、実際のクライアント初期化、repository操作、同期enqueue、アカウント状態管理は `app/rust` に寄っている。

また、Flutterデスクトップ版とCLIが同じ暗号化DBを利用するには、DBパスだけでなく同じDevice Keyを取得できる必要がある。現状はApple platformのみData Protection Keychainを本番経路とし、Windows / Linuxでは平文 `device.key` fallbackが残っている。さらに、FlutterとCLIが同時にSQLiteへ接続する場合のbusy timeout、migration排他、同期実行の単一化も未設計である。

2026-07-10のプロダクトオーナー裁定により、同一PC上のFlutterデスクトップ版とCLIは同一ローカルプロファイルを共有し、異なる端末・OS間はE2EE同期で収束させる方式を採用する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/03_技術仕様書.md` §2、§4.3、§5.3、§8
- `docs/05_設計判断記録.md`
- `docs/tasks/task-64-keychain-device-key.md`
- `docs/tasks/task-74-multiplatform-verification.md`
- `docs/tasks/task-75-core-extraction-refactor.md`
- `docs/tasks/task-77-keychain-entitlement.md`
- `core/crypto/src/dev_key_store.rs`
- `core/storage/src/lib.rs`
- `app/rust/src/api.rs`
- `app/rust/src/support.rs`
- `app/lib/main.dart`
- `cli/src/main.rs`

## 3. ゴール

- Flutterデスクトップ版とCLIのローカルDB共有単位を「同一PC上のTaskveil profile」として確定する。
- macOS / Windows / Linuxごとの本番Device Key Storeを確定する。
- Flutter / CLI共通のアプリケーションサービス層と依存方向を確定する。
- SQLite多重プロセスアクセスと同期多重実行の基本方針を確定する。
- 採用内容をADR、技術仕様、タスク一覧、バックログへ記録する。

## 4. スコープ

### やること

- `docs/05_設計判断記録.md` にADR-011を追加する。
- `docs/03_技術仕様書.md` のmonorepo構成とMCP / CLI節へ共通client/profile方針を追記する。
- OS別Device Key Storeを次のとおり確定する。
  - macOS: 同一Apple Teamで署名され、同じKeychain access groupを持つFlutterアプリとCLI。
  - Windows: current-user scopeのDPAPIでDevice Keyを保護する。
  - Linux: Secret Service APIを利用し、利用不能時に平文fallbackへ自動降格しない。
- 同一PCでは同じSQLCipher DBを共有し、別端末・別OS間ではDBファイルをコピーせずE2EE同期する方針を記録する。
- 後続実装を共通client/profile抽出、Windows/Linux secret store、CLI実接続へ分割する。

### やらないこと

- Rust / Dart / Flutter / CLIの実装変更。
- 新規crateやpub packageの追加。
- DB schema / migration変更。
- Keychain item、Device Key、SQLCipher鍵の移行。
- Windows Flutter hostの生成。
- CLIバイナリの署名・配布。
- git commit。

## 5. 実装手順

1. 現行のFlutter初期化、Device Key Store分岐、SQLCipher open、CLIスタブを確認する。
2. ADR-011へ共有単位、OS別secret store、共通client層、SQLite排他方針を記録する。
3. `docs/03_技術仕様書.md` §2 / §8をADR-011へ整合させる。
4. `docs/tasks/README.md` へtask-81を追加する。
5. `docs/tasks/BACKLOG.md` のCLI項目を、依存順が分かる後続タスクへ分割する。
6. Markdown構造、リンク、差分空白を検証する。

## 6. 受け入れ基準

共通受け入れ基準は `docs/tasks/README.md` の「共通受け入れ基準」を満たすこと。

- [x] ADR-011が採用状態で追加され、2026-07-10プロダクトオーナー裁定を出典としている。
- [x] 同一PCは同一profile / SQLCipher DB、別端末はE2EE同期という境界が明記されている。
- [x] macOS Keychain access group、Windows DPAPI current-user、Linux Secret Serviceが明記されている。
- [x] Windows / Linuxの平文 `device.key` fallbackを本番経路として認めていない。
- [x] 共通client/profile層をFlutter bridge、CLI、MCPの共有依存にする方向が明記されている。
- [x] `busy_timeout`、短いtransaction、migration排他、同期leaseが後続実装要件として明記されている。
- [x] バックログが設計→共通層→OS secret store→CLI実接続の順へ分割されている。
- [x] `git diff --check` が成功している。

## 7. 制約・注意事項

- Device KeyそのものをDBや設定ファイルへ平文保存しない。
- `--data-dir` 等でDBパスを指定できても、秘密鍵取得の認可を迂回できる設計にしない。
- macOS CLIは未署名 `cargo install` バイナリを正規配布経路としない。
- Linuxのheadless / SSH / systemd環境ではSecret Serviceやsession D-Busが存在しない場合があるため、暗黙の平文fallbackではなく明示エラーまたは将来の対話的unlock設計で扱う。
- 同一DBへ複数writerが接続できても、同期ループを無制御に複数プロセスで走らせない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` は変更しない。
- public repoへTeam秘密鍵、証明書、実ユーザーのKeychain情報を記載しない。

## 8. 完了報告に含めるべき内容

- 作業日。
- 採用した共有モデル。
- OS別Device Key Store表。
- 共通client/profileと各frontendの依存関係。
- SQLite多重プロセス要件。
- 更新ファイル。
- 検証結果。
- 未解決事項。

## 9. 完了報告

作業日: 2026-07-10

### 採用した共有モデル

- 同一PC上のFlutterデスクトップ版とCLIは、同じTaskveil profile、SQLCipher DB、Device Keyを共有する。
- macOS / Windows / Linuxの別PC間ではDBファイルやDevice Keyを持ち運ばず、既存E2EE同期で状態を収束させる。
- Flutter bridge、CLI、将来のMCP serverは共通client/profile層を呼び、repository + domain + outbox enqueueを各frontendへ複製しない。

### OS別Device Key Store

| OS | 採用方式 | 共有単位 |
|---|---|---|
| macOS | Data Protection Keychain + 共通access group | 同一Apple Teamで署名されたFlutter app / CLI |
| Windows | DPAPI current-user scope | 同一Windowsユーザー・同一PC |
| Linux | Secret Service API | 同一ログインセッションのsecret collection |

非Apple platformの平文 `device.key` / account secret fileは開発fallbackに限定し、本番CLI / Flutter desktopでは使用しない。

### SQLite多重プロセス要件

- connectionごとの `busy_timeout`。
- 書込とoutbox enqueueをまとめる短いtransaction。
- migration実行の排他。
- 同一profileで同期runを1つに制限するDB-backed lease。
- `SQLITE_BUSY` を構造化エラーとしてfrontendへ返すこと。

### 更新ファイル

- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md`
- `docs/tasks/task-81-cli-shared-profile-architecture.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`

### 検証結果

- `git diff --check`: 成功。
- `rg -n "ADR-011|DPAPI|Secret Service|busy_timeout|同期lease" docs`: 採用事項がADR、技術仕様、task、BACKLOGに存在することを確認。
- コード変更なしのためRust / Flutter品質ゲートは未実行。

### 未解決事項

- Windows Flutter hostは未生成であり、Windows DPAPI実装時に正式なprofile pathと配布形態を検証する必要がある。
- Linux headless環境でのunlock UXは、Secret Service実装タスクで明示的に設計する。
- macOS CLIのapp同梱方式と単独インストーラ方式の最終配布形態は、CLI実接続タスクで署名検証と合わせて確定する。
