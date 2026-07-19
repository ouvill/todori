# task-12: OSS公開前監査

> ステータス: 完了（`## 9. 完了報告` 追記済み。公開判断は人間判断）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

Taskveilは将来的にOSSとして公開する方針がある。task-11でGitHub ActionsのPhase 1品質ゲートが整備され、public repository化すればGitHub-hosted standard runnerのコスト面でも有利になる。一方で、TaskveilはE2EE Todoアプリであり、暗号設計、同期設計、課金・事業方針、未実装のセキュリティ事項、CI/runner設定など、公開前に確認すべき情報が多い。

このタスクは、リポジトリを実際にpublic化する前に、公開してよい状態かを監査し、公開ブロッカー、公開前に整えるべきOSS基本文書、CI/Actions運用上の注意点を棚卸しするためのものである。

公開判断は人間が行う。実行エージェントは、監査結果を具体的なファイル/行/リスクに紐づけて報告し、必要な修正タスク候補を提示する。

## 2. 事前に読むべきファイル

- `AGENTS.md`（秘密情報、品質ゲート、タスク運用、self-hosted runner注意）
- `README.md`
- `LICENSE`
- `CONTRIBUTING.md`
- `CLA.md`
- `docs/01_企画書.md`
- `docs/02_機能仕様書.md`
- `docs/03_技術仕様書.md`
- `docs/04_課金設計書.md`
- `docs/05_設計判断記録.md`
- `docs/06_事業・法務方針.md`
- `docs/07_Phase1計画書.md`
- `docs/tasks/BACKLOG.md`
- `.github/workflows/ci.yml`
- `.gitignore`
- `Cargo.toml` / `Cargo.lock`
- `app/pubspec.yaml` / `app/pubspec.lock`
- `app/rust_builder/cargokit/`（vendored Cargokitのライセンス・取り扱い）

## 3. ゴール

Taskveilリポジトリをpublic repositoryとして公開できるかを判断するため、以下を明文化する。

- 公開ブロッカーの有無（秘密情報、個人情報、公開不適切な事業・法務・セキュリティ情報など）
- OSS基本文書の整備状況（README、LICENSE、CONTRIBUTING、CLA、SECURITY、Code of Conductなど）
- vendored code / third-party licenseの扱い
- GitHub Actionsをpublic repositoryで動かす場合の安全設定
- self-hosted runnerをpublic repositoryへ接続しないための運用方針
- 公開前に必要な修正タスク候補
- 公開してよい / 条件付きで公開してよい / 公開前に修正必須、の判定

このタスクでは、公開ボタンを押さない。GitHub repositoryのvisibility変更は人間が行う。

## 4. スコープ

### やること

1. **秘密情報・個人情報スキャン**: `.env`、API token、秘密鍵、証明書、プロビジョニングプロファイル、メールアドレス、個人名、実サービス認証情報、DBファイル、ログファイルなどがコミットされていないか確認する。
2. **ドキュメント公開可否監査**: `docs/01`〜`07`、`docs/tasks/`、`README.md`、`CLA.md`、`CONTRIBUTING.md` を読み、公開に不向きな情報を列挙する。特に課金戦略、法務方針、未実装セキュリティ事項、サーバー/同期設計、脅威モデル上の未解決事項を確認する。
3. **OSS基本文書の棚卸し**: `LICENSE`、`README.md`、`CONTRIBUTING.md`、`CLA.md` の内容を確認し、`SECURITY.md`、`CODE_OF_CONDUCT.md`、issue/PR templateなどの不足を整理する。
4. **ライセンス確認**: Rust crate、Flutter/Dart package、vendored Cargokit、生成物のライセンス上の注意点を確認する。完全な法務判断は行わず、機械的に確認できる範囲と未確認事項を分けて報告する。
5. **CI/Actions公開時の安全確認**: `.github/workflows/ci.yml` がpublic repositoryでfork PRから実行されても危険な処理を含まないか確認する。secrets、write権限、`pull_request_target`、self-hosted runner label、release/deploy処理、外部アップロードの有無を確認する。
6. **GitHub設定チェックリスト作成**: public化時に人間がGitHub UIで確認すべき設定を列挙する（Actions権限、fork PR approvals、branch protection、Dependabot、secret scanning/code scanning、issue/PR設定など）。
7. **公開判定レポート作成**: 指示書末尾の「## 9. 完了報告」に、判定、公開ブロッカー、要修正項目、推奨タスクを記録する。
8. **必要最小限の補助文書追加**: 明らかに不足していて内容の裁量が小さい場合に限り、`SECURITY.md` などの雛形を追加してよい。ただし、公開方針や脆弱性受付先など人間判断が必要な項目はTODOとして残し、完了報告で明示する。

### やらないこと

- GitHub repositoryをpublic化すること。
- GitHub repository settingsを変更すること。
- secretsの作成・削除・ローテーション。
- 仕様書（`docs/01`〜`docs/04`）の改変。
- 事業方針、ライセンス方針、脆弱性受付窓口、CLA採用可否などの最終判断。
- CIコスト最適化のためのworkflow再設計。必要なら別タスクとして提案する。
- self-hosted runnerの導入・登録。
- アプリ実装や暗号実装の修正。問題を見つけた場合は、修正内容を別タスク候補として提示する。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. 2章のファイルを読む。
3. `rg --files` と `.gitignore` を確認し、公開前に気になるファイル種別を洗い出す。
4. 例として以下のような検索を行う（必要に応じて追加する）。
   - `rg -n "password|passwd|secret|token|api[_-]?key|private[_-]?key|BEGIN .*PRIVATE KEY|client[_-]?secret|access[_-]?token|refresh[_-]?token" .`
   - `rg -n "@|メール|email|住所|電話|phone|個人|本名" docs README.md CONTRIBUTING.md CLA.md`
   - `rg -n "TODO|FIXME|未実装|未解決|脆弱|セキュリティ|secret|keychain|self-hosted|pull_request_target" docs .github app core`
5. `rg --files -g 'LICENSE*' -g 'NOTICE*' -g 'SECURITY*' -g 'CODE_OF_CONDUCT*' -g 'CONTRIBUTING*'` でOSS基本文書を確認する。
6. `.github/workflows/ci.yml` を読み、public repo/fork PR上の安全性を確認する。
7. 依存ライセンスについて、lockfileや依存定義から確認できる範囲を整理する。必要なツールが未導入なら、ネットワーク追加なしでできる範囲に留め、未確認事項として記録する。
8. 公開判定を「公開可」「条件付き公開可」「公開前修正必須」のいずれかでまとめる。
9. 指示書末尾に「## 9. 完了報告」を追記し、8章の項目をすべて記録する。
10. ドキュメントのみの変更であっても、最低限 `git diff --check` を実行する。OSS基本文書を追加・変更した場合は、必要に応じてリンク切れやMarkdown体裁を目視確認する。

## 6. 受け入れ基準

- [ ] 秘密情報・個人情報・証明書類・DB/ログ類のコミット有無を確認し、結果を記録している。
- [ ] `docs/01`〜`07` と `docs/tasks/` の公開可否を確認し、公開不適切または要判断の箇所がファイル単位で列挙されている。
- [ ] `README.md`、`LICENSE`、`CONTRIBUTING.md`、`CLA.md` の現状評価が記録されている。
- [ ] `SECURITY.md`、`CODE_OF_CONDUCT.md`、issue/PR templateなど、不足するOSS基本文書の要否が整理されている。
- [ ] vendored Cargokitを含むthird-party licenseの確認結果と未確認事項が記録されている。
- [ ] public repository化後のGitHub Actions/fork PR/secrets/self-hosted runnerに関する安全確認が記録されている。
- [ ] GitHub UIで人間が確認すべき公開時設定チェックリストがある。
- [ ] 公開判定が「公開可」「条件付き公開可」「公開前修正必須」のいずれかで明示されている。
- [ ] 公開前に必要な修正タスク候補が、優先度と理由付きで提示されている。
- [ ] `docs/tasks/task-12-open-source-readiness.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。
- [ ] `git diff --check` が成功している。

## 7. 制約・注意事項

- `docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md`、`docs/04_課金設計書.md` は変更禁止である。公開不適切な内容があれば完了報告に記録し、必要なら別タスクとして「公開版ドキュメント分離」などを提案する。
- 秘密情報らしき文字列を発見しても、最終的な漏洩判定やローテーション判断は人間に委ねる。完了報告には該当ファイル、行、リスク、推奨対応を記録する。
- public repositoryではfork PRからのworkflow実行を前提に考える。`pull_request_target`、write権限、secrets、外部アップロード、self-hosted runner利用は特に慎重に扱う。
- public repositoryにself-hosted runnerを接続しない方針を前提に監査する。例外が必要な場合は、例外理由と隔離策を「要人間判断」として記録する。
- ライセンス確認は法務助言ではない。機械的な確認と、専門家または人間判断が必要な事項を分ける。
- 監査タスクで見つけた実装上のセキュリティ問題は、このタスク内で修正しない。修正指示書の形で提示する。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイルと監査対象範囲
- 実行した検索・確認コマンド
- 秘密情報・個人情報・証明書類・DB/ログ類の確認結果
- ドキュメント公開可否の確認結果
- OSS基本文書の整備状況
- third-party license / vendored codeの確認結果
- CI/Actions/public fork PR/self-hosted runner安全確認
- GitHub UIで人間が確認すべき公開時設定チェックリスト
- 公開判定（公開可 / 条件付き公開可 / 公開前修正必須）
- 公開前修正タスク候補（優先度、理由、対象ファイル）
- 検証結果（少なくとも `git diff --check`）
- 未解決事項・要人間判断

## 9. 完了報告

作業日: 2026-07-04

### 読んだファイルと監査対象範囲

- `AGENTS.md`
- `README.md`
- `LICENSE`
- `CONTRIBUTING.md`
- `CLA.md`
- `docs/01_企画書.md`
- `docs/02_機能仕様書.md`
- `docs/03_技術仕様書.md`
- `docs/04_課金設計書.md`
- `docs/05_設計判断記録.md`
- `docs/06_事業・法務方針.md`
- `docs/07_Phase1計画書.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-01-opaque-poc.md` から `task-12-open-source-readiness.md`
- `.github/workflows/ci.yml`
- `.gitignore`
- `Cargo.toml`
- `Cargo.lock`
- `app/pubspec.yaml`
- `app/pubspec.lock`
- `app/rust_builder/cargokit/LICENSE`
- `app/rust_builder/README.md`
- `app/rust_builder/cargokit/build_tool/README.md`

### 実行した検索・確認コマンド

- `git status --short`
- `rg --files -g 'LICENSE*' -g 'NOTICE*' -g 'SECURITY*' -g 'CODE_OF_CONDUCT*' -g 'CONTRIBUTING*' -g 'CLA*' -g 'README.md' -g '.gitignore' -g 'ci.yml'`
- `rg -n "password|passwd|secret|token|api[_-]?key|private[_-]?key|BEGIN .*PRIVATE KEY|client[_-]?secret|access[_-]?token|refresh[_-]?token" .`
- `rg -n "@|メール|email|住所|電話|phone|個人|本名" docs README.md CONTRIBUTING.md CLA.md`
- `rg -n "TODO|FIXME|未実装|未解決|脆弱|セキュリティ|secret|keychain|self-hosted|pull_request_target" docs .github app core`
- `rg --files -g '.env*' -g '*.pem' -g '*.p12' -g '*.mobileprovision' -g '*.db' -g '*.sqlite' -g '*.log' -g '*.key' -g '*.cer' -g '*.crt' -g '*.der'`
- `git ls-files | rg -n "(^|/)(\\.env|.*\\.(pem|p12|mobileprovision|db|sqlite|log|key|cer|crt|der))$"`
- `find .github -maxdepth 3 -type f -print`
- `find .github -maxdepth 3 -type d -print`
- `rg -c '^name = ' Cargo.lock`
- `rg -c '^  [A-Za-z0-9_]+:' app/pubspec.lock`
- `rg -n "pull_request_target|permissions:|secrets\\.|GITHUB_TOKEN|self-hosted|upload|deploy|release" .github/workflows/ci.yml`
- `rg -n "license|LICENSE|Apache|MIT|AGPL|GPL" app/rust_builder/cargokit app/rust_builder/README.md app/rust_builder/cargokit/build_tool/README.md`
- `git diff --check`

### 秘密情報・個人情報・証明書類・DB/ログ類の確認結果

- `.env`、秘密鍵、証明書、プロビジョニングプロファイル、DB、SQLite、ログ類に該当するgit管理ファイルは見つからなかった。
- `rg --files` ベースでも `.env*`、`*.pem`、`*.p12`、`*.mobileprovision`、`*.db`、`*.sqlite`、`*.log`、`*.key`、`*.cer`、`*.crt`、`*.der` は見つからなかった。
- `password` / `secret` / `token` 等の検索でヒットした主なものは、OPAQUE仕様・テスト名、task-12自身の監査語、Cargokit build toolの `GITHUB_TOKEN` 説明、`server/src/routes/sync_token` のモジュール名であり、実シークレットや認証情報のコミットは確認されなかった。
- メールアドレス・電話番号・住所のような具体的PIIは確認されなかった。ただし `docs/06_事業・法務方針.md` には「個人事業として開始」「Apple Developer Program は個人登録」「Google Play Console は個人登録」等の事業主体方針が含まれるため、個人運営実態を公開することの可否は人間判断が必要である。

### ドキュメント公開可否の確認結果

- `docs/01`、`docs/02`、`docs/03`、`docs/05`、`docs/07`、`docs/tasks/` は、プロダクト仕様・技術仕様・ADR・タスク運用が中心であり、OSS公開目的と大きく矛盾する公開ブロッカーは見つからなかった。
- `docs/03_技術仕様書.md` には脆弱性対応として `cargo audit` のCI組み込みと外部セキュリティ監査推奨が明記されているが、現時点のCIには `cargo audit` が入っていない。公開前または公開直後の追加タスク候補とする。
- `docs/04_課金設計書.md` は価格、収益シミュレーション、MRR/ARR、手数料、販売チャネル戦略などを含む。秘密情報ではないが、競争上・事業上の内部方針として公開してよいかは要判断である。
- `docs/06_事業・法務方針.md` は個人事業、ストア個人登録、Stripe適格性、暗号輸出規制、商標・ドメイン確認チェックリスト等を含む。OSS公開の透明性には資するが、個人運営・法務方針を公開する範囲として妥当か人間判断が必要である。
- `CLA.md` は草案であり、正式公開前に専門家レビュー予定と明記されている。外部コントリビューションを受け付ける前には、少なくともCLA採用可否と文面の確定が必要である。

### OSS基本文書の整備状況

- `README.md`: あり。プロダクト概要、ドキュメント地図、リポジトリ構成、開発コマンド、ライセンスへのリンクがある。
- `LICENSE`: あり。AGPL-3.0本文が置かれている。
- `CONTRIBUTING.md`: あり。AGPL-3.0-only、CLA、品質ゲート、Conventional Commitsが記載されている。ただし現行の品質ゲートは `flutter test` と `app/tool/check_hardcoded_strings.sh` を含むAGENTS.mdの完全版より短いため、公開前に同期するとよい。
- `CLA.md`: あり。ただし草案であり、専門家レビュー前であることが明記されている。
- `SECURITY.md`: なし。E2EEアプリとして脆弱性報告窓口、サポート対象バージョン、暗号問題の扱い、公開前の連絡方法を定める必要がある。
- `CODE_OF_CONDUCT.md`: なし。外部コントリビューションを本格的に受けるなら追加推奨。
- issue / PR template: `.github` 配下には `workflows/ci.yml` のみで、issue template / PR templateは未整備である。
- `NOTICE` / third-party attribution文書: なし。AGPL本体とCargokit同梱LICENSEはあるが、アプリ配布物向けのthird-party attribution一覧は未整備である。

### third-party license / vendored codeの確認結果

- ルート `Cargo.toml` の `[workspace.package]` は `license = "AGPL-3.0-only"`、`publish = false` である。
- `Cargo.lock` には `name =` 基準で215パッケージが含まれる。lockfileには各crateのライセンス情報が含まれないため、現時点では完全な依存ライセンス監査は未完了である。公開前に `cargo-deny` などでライセンスとadvisoryを機械チェックするタスクが必要である。
- `app/pubspec.lock` には91パッケージが含まれる。pub lockfileにも各パッケージのライセンス本文は含まれないため、Dart/Flutter依存のライセンス一覧生成は未完了である。
- `app/rust_builder/cargokit/` はvendored codeであり、`app/rust_builder/cargokit/LICENSE` にMIT LicenseおよびApache License 2.0が同梱されている。公開時はこのLICENSEを維持する必要がある。
- `rusqlite` は `bundled-sqlcipher-vendored-openssl` featureを使用しているため、SQLCipher/OpenSSLを含む配布時ライセンス・通知事項の確認が必要である。現時点では依存定義とlockfileの確認に留まり、法務判断は未実施である。

### CI/Actions/public fork PR/self-hosted runner安全確認

- `.github/workflows/ci.yml` は `push` / `pull_request` のみをトリガーとしており、`pull_request_target` は使用していない。
- `runs-on` は `macos-latest` であり、self-hosted runner labelは使っていない。
- workflow内に `secrets.*` の参照、deploy、release、外部アップロード、署名、ストア提出処理はない。
- 明示的な `permissions:` は未設定である。GitHubのデフォルト権限に依存するため、public repository化時は repository settings で Actions のデフォルト権限を read-only にし、必要ならworkflowにも `permissions: contents: read` を明記するタスクを推奨する。
- `cargo install flutter_rust_bridge_codegen`、`flutter pub get`、`dart pub get` がfork PR上で実行される。secretsを使わないため直ちに危険ではないが、public CIでは依存取得・ビルドスクリプト実行のサプライチェーンリスクがある。fork PR approval、Dependabot、pinning方針をGitHub設定で補う必要がある。
- CIはGitHub-hosted runner想定であり、public repositoryにself-hosted runnerを接続しない方針と整合している。

### GitHub UIで人間が確認すべき公開時設定チェックリスト

- Actions general settingsで、fork PR workflowの初回実行にmaintainer approvalを要求する。
- Actions default workflow permissionsを `Read repository contents permission` にする。
- `Allow GitHub Actions to create and approve pull requests` を無効にする。
- self-hosted runnerがrepository / organizationに登録されていないことを確認する。
- branch protectionまたはrulesetで `main` への直接pushを制限し、CI成功を必須にする。
- secret scanning、push protection、Dependabot alerts、Dependabot security updatesを有効化する。
- CodeQL/code scanningを有効化するか、少なくともRust/Dartに対する代替の静的解析方針を決める。
- Issues / Discussions / Projectsを公開時に有効化するか決める。
- issue template / PR template / security advisory reportingを整備する。
- repository description、topics、homepage、social preview、license表示が意図通りか確認する。
- `SECURITY.md` の脆弱性受付窓口を確定する。
- CLA運用を手動にするか、CLA assistant等を入れるか決める。

### 公開判定

判定: **条件付き公開可**。

実シークレット、証明書、DB、ログ、具体的PIIのコミットは確認されず、CIもpublic fork PRで直ちに危険な `pull_request_target` / secrets / deploy / self-hosted runner を含んでいない。一方で、`SECURITY.md`、Code of Conduct、issue/PR template、third-party attribution、依存ライセンス監査、CLA草案レビュー、課金・事業・法務文書の公開範囲判断が未完了であるため、「今すぐ広く外部コントリビューションを受ける状態」とは言い切れない。

公開する場合は、少なくとも `SECURITY.md` とGitHub Actions権限設定、secret scanning / Dependabot、CLA方針、公開するdocs範囲の人間判断を完了条件にすることを推奨する。

### 公開前修正タスク候補

1. **P0: `SECURITY.md` 作成**
   - 対象: `SECURITY.md`
   - 理由: E2EEアプリとして脆弱性報告窓口・対象バージョン・報告時に含める情報・公開前調整方針が必須に近い。
2. **P0: CLA草案の人間・専門家レビュー**
   - 対象: `CLA.md`, `CONTRIBUTING.md`
   - 理由: 現在のCLAは草案で、専門家レビュー予定と明記されている。外部PR受付前に確定が必要。
3. **P0: 公開対象docsの範囲判断**
   - 対象: `docs/04_課金設計書.md`, `docs/06_事業・法務方針.md`
   - 理由: 課金・収益シミュレーション・個人事業方針・ストア登録方針など、秘密ではないが事業上公開判断が必要な情報を含む。
4. **P1: GitHub Actions権限の明示**
   - 対象: `.github/workflows/ci.yml`, GitHub repository settings
   - 理由: workflowに `permissions:` を明記し、public fork PR時の権限を最小化する。
5. **P1: third-party license / advisory監査の自動化**
   - 対象: `Cargo.toml`, `Cargo.lock`, `app/pubspec.lock`, CI
   - 理由: Rust 215パッケージ、Dart/Flutter 91パッケージのライセンス・脆弱性確認がlockfile確認だけでは不足する。`cargo-deny`、`cargo audit`、Dart/Flutter依存ライセンス一覧生成を検討する。
6. **P1: `CODE_OF_CONDUCT.md` とissue/PR template追加**
   - 対象: `CODE_OF_CONDUCT.md`, `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`
   - 理由: public化後の外部参加導線と報告品質を整える。
7. **P1: `CONTRIBUTING.md` の品質ゲート同期**
   - 対象: `CONTRIBUTING.md`
   - 理由: AGENTS.mdの品質ゲートには `flutter test` と直書き検出が含まれるが、CONTRIBUTING.mdの記載は短い。
8. **P2: アプリ配布物向けthird-party attribution整理**
   - 対象: `NOTICE` または `THIRD_PARTY_NOTICES.md`
   - 理由: Cargokit、SQLCipher/OpenSSL、Rust/Dart依存、Flutter SDK由来の配布時表示・同梱要件を整理する。

### 検証結果

- `git diff --check`: 成功。

### 未解決事項・要人間判断

- `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` をpublic repositoryにそのまま含めるか、公開版ドキュメントから分離するかは人間判断が必要である。
- CLAを現在の草案のまま公開初期に採用するか、専門家レビュー完了まで外部PR受付を限定するかは人間判断が必要である。
- 脆弱性受付窓口（メールアドレス、GitHub private vulnerability reporting等）をどれにするか未決である。
- 依存ライセンス・脆弱性監査はlockfile確認までであり、`cargo-deny` / `cargo audit` / Dart側ライセンス一覧生成による完全監査は未実施である。
- GitHub repository settings（Actions権限、fork PR approval、secret scanning、Dependabot等）はこのタスクでは変更していない。
