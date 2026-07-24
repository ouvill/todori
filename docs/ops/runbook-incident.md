# 障害対応runbook

Taskveilの障害分類と初動を定義する。public repo安全のため、実連絡網、顧客対応文面、事業判断、実監視URL、実クレデンシャルは書かない。これらはprivate側または人間管理とする。

## 1. 共通前提

- Taskveilはローカルファーストである。サーバーが落ちても、クライアントはローカルDB上の既存データで作成・編集・閲覧を継続できる。
- サーバー停止中の同期、ログイン、新デバイス追加、アカウント登録は失敗または保留になる。
- E2EEのため、サーバー側でユーザーデータ本文を復号することはできない。調査は認証メタデータ、HTTPステータス、同期メタデータ、暗号blobサイズ、seq/HLC等に限定する。
- 秘密情報をログ、スクリーンショット、public issue、完了報告へ貼らない。

## 2. 初動チェックリスト

1. 影響範囲を分類する: サーバーダウン、DB障害、認証障害、同期障害、セッション大量失効、依存脆弱性。
2. 直近の変更を確認する: Lambdaイメージ、DB migration、設定、依存更新。
3. `/health` を確認する。
4. DB接続可否を確認する。connection string実値はprivate側/人間管理。
5. クライアントのローカル動作継続可否を確認する。
6. セキュリティ影響の可能性がある場合は [`SECURITY.md`](../../SECURITY.md) の方針に従い、public issueへ詳細を書かない。

## 3. サーバーダウン

症状:

- `/health` が失敗する。
- 登録、ログイン、同期が失敗する。
- クライアントはローカル編集を継続し、outboxへ蓄積する。

初動:

```sh
curl -i <PUBLIC_API_BASE_URL>/health
```

- 直近Lambda更新が原因なら、DB互換を確認して直前イメージへ戻す。
- DB migrationを伴わないコード問題なら [`runbook-server-deploy.md`](./runbook-server-deploy.md) のロールバック手順を使う。
- DB接続失敗ならDB障害として扱う。

ユーザー影響の見立て:

- 既存ローカルデータの閲覧・編集は継続可能。
- 同期は復旧後に再試行される。
- 新規ログインや新デバイス追加は復旧まで不可。

## 4. DB障害

症状:

- Lambdaは起動するがDB接続やqueryが失敗する。
- 登録、ログイン、push/pullが失敗する。

初動:

- Neon status、branch、connection pool、接続数、直近migrationを確認する。実URLとcredentialはprivate側/人間管理。
- migration直後なら [`runbook-db-migration.md`](./runbook-db-migration.md) のロールバック方針へ進む。
- connection pool枯渇が疑われる場合、Lambda同時実行数、pool max connections、Neon pool設定を確認する。

注意:

- DB内の `encrypted_blob` を復号する手順は存在しない。
- `sync_records_history` は上書き前blobの短期退避であり、サーバー側復号のためのものではない。

## 5. 認証障害

症状:

- OPAQUE登録/ログインが広範囲で失敗する。
- 誤パスワード以外でもlogin finishに失敗する。
- 新規デバイス追加ができない。

初動:

- OPAQUE中間状態テーブルの期限切れ、consume済み再利用、server setupの有無を確認する。
- 直近の `core/crypto`、`server/src/auth.rs`、DB migration、環境変数変更を確認する。
- パスワード、exportKey、Master Key、Recovery Keyをログに出さない。

切り分け:

- 既存セッションのpush/pullが成功するなら、認証フロー限定の障害。
- 既存セッションも失敗するなら、セッションまたはDB障害へ分類を広げる。

## 6. セッション大量失効

症状:

- 多数の端末が再ログインを要求される。
- `sessions.revoked_at`、`expires_at`、token hash照合に関連する失敗が増える。

初動:

- 直近のセッションTTL、時刻、DB migration、認可middleware変更を確認する。
- 誤失効なら、原因修正後に再ログインを案内する。既存ローカルデータは端末上に残る。
- token実値やhash元tokenをログに出さない。

注意:

- 失効したセッションを安易に復活させない。セキュリティ影響がある場合は人間判断を待つ。

## 7. 同期障害

症状:

- 登録/ログインは成功するがpush/pullが失敗する。
- 片端末の変更が他端末へ届かない。
- 競合解決や削除伝播に問題がある。

初動:

- `docs/dev/two-device-sync-test.md` のローカル手順で再現する。
- batch上限、blobサイズ上限、未来HLC拒否、tenant認可、cursor進行を確認する。
- ADR-016のterminal tombstone、server-trusted continuity、expired-device rebaseに加え、ADR-023のList削除時Task rehomeが維持されているか確認する。

ユーザー影響:

- ローカル編集は継続する。
- outboxに未送信変更が残る可能性がある。
- serverがcontinuity切れまたは`gc_horizon_seq`超過を返した場合は、実装済みのstable-key full resyncを開始し、`base_seq`後delta、高水位closure、seed-before-sweepが完了するまで通常pushを再開しない。

## 8. 依存脆弱性発覚

症状:

- `cargo audit`、GitHub advisory、外部報告で依存脆弱性が判明する。

初動:

```sh
cargo audit
```

- 影響範囲を分類する: 暗号、認証、SQLCipher/DB、HTTP server、ビルド/配布。
- exploit可能性、影響プラットフォーム、修正版有無を確認する。
- public issueに詳細な攻撃手順を書かない。
- セキュリティ影響がある場合は [`SECURITY.md`](../../SECURITY.md) の非公開導線に沿って扱う。

## 9. 事後記録

public repoに残せる記録は、再現しない抽象度の変更内容、影響範囲、修正済みバージョン、再発防止策に限る。顧客影響、法務判断、実アカウント、実ログ、credential、攻撃詳細はprivate側または人間管理とする。
