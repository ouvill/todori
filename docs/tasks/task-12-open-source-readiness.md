# task-12: OSS公開前監査

## 1. 背景とコンテキスト

Todoriは将来的にOSSとして公開する方針がある。task-11でGitHub ActionsのPhase 1品質ゲートが整備され、public repository化すればGitHub-hosted standard runnerのコスト面でも有利になる。一方で、TodoriはE2EE Todoアプリであり、暗号設計、同期設計、課金・事業方針、未実装のセキュリティ事項、CI/runner設定など、公開前に確認すべき情報が多い。

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

Todoriリポジトリをpublic repositoryとして公開できるかを判断するため、以下を明文化する。

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
