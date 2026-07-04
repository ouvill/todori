# task-15: SECURITY.mdと脆弱性報告導線の整備

> ステータス: 未着手

## 1. 背景とコンテキスト

task-12「OSS公開前監査」では、Todoriをpublic repositoryとして公開する前に `SECURITY.md` が不足していること、脆弱性受付窓口が未決であること、GitHub private vulnerability reportingの利用可否を人間判断事項として記録した。task-13では、E2EEアプリとして脆弱性報告・セキュリティ対応に必要な公開窓口と手順はpublic repoに残すべき情報として分類した。

ユーザー判断として、Todori public化前に `SECURITY.md` を作成し、GitHub public repository化時には private vulnerability reporting を有効化する方針とする。`SECURITY.md` は、外部の利用者・研究者・コントリビューターに対して「セキュリティ問題をpublic issueではなく非公開導線で報告してほしい」と明示するための文書である。

このタスクは、Todoriの現状がpre-releaseであること、E2EE/SQLCipher/Device Key/同期設計がセキュリティ上重要であることを踏まえ、公開前に最低限必要な `SECURITY.md` と関連README導線を整備するためのものである。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `README.md`
- `CONTRIBUTING.md`
- `CLA.md`
- `docs/tasks/task-12-open-source-readiness.md`
- `docs/tasks/task-13-public-private-docs-split.md`
- `docs/tasks/task-14-public-private-repo-split.md`
- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md`
- `.github/workflows/ci.yml`

## 3. ゴール

Todori public repoに、脆弱性報告とセキュリティ対応の入口として以下を整備する。

- `SECURITY.md` を作成する。
- サポート対象バージョンをpre-release前提で明記する。
- public issueに脆弱性詳細を書かないよう案内する。
- GitHub private vulnerability reportingを利用する方針を記載する。
- private vulnerability reportingが未有効または利用できない場合の代替連絡先をTODOまたは要人間判断として明記する。
- E2EE、鍵管理、SQLCipher、同期、認証/アカウント復旧など、Todoriでセキュリティ影響が大きい領域をscopeとして整理する。
- `README.md` または `CONTRIBUTING.md` から `SECURITY.md` へ必要最小限の導線を追加する。

## 4. スコープ

### やること

1. **現状確認**: `SECURITY.md` が存在しないこと、README/CONTRIBUTINGに脆弱性報告導線がないことを確認する。
2. **`SECURITY.md` 作成**: repository rootに `SECURITY.md` を作成する。
3. **Supported Versions記載**: Todoriはpre-releaseであり、初回stable releaseまでは `main` branch を対象にセキュリティ修正する方針を記載する。
4. **Reporting a Vulnerability記載**: public issueではなく、GitHub private vulnerability reportingを使う方針を記載する。
5. **代替連絡先の扱い**: メールアドレス等が未決の場合は、仮の個人連絡先を作らず、完了報告の「要人間判断」に記録する。文書内では「private vulnerability reportingが利用できない場合の連絡先は公開前に確定する」と明記してよい。
6. **Scope記載**: E2EE設計、鍵導出/鍵保存、SQLCipher DB、同期プロトコル、サーバー側メタデータ、認証/アカウント復旧、CI/配布物をscopeに含める。
7. **非対象の明確化**: 一般的なバグ、機能要望、非セキュリティのクラッシュは通常issueへ誘導する。
8. **README/CONTRIBUTING導線**: 必要に応じて、脆弱性報告は `SECURITY.md` を参照する旨を短く追記する。
9. **GitHub設定チェック記録**: private vulnerability reportingはGitHub UIで有効化が必要なため、完了報告に人間作業として記録する。
10. **検証**: `git diff --check` を実行する。
11. **完了報告追記**: 指示書末尾へ「## 9. 完了報告」を追記する。

### やらないこと

- GitHub repository settingsを変更しない。
- GitHub private vulnerability reportingを実際に有効化しない。
- メールアドレス、法人/個人名、住所などの公開連絡先を推測で追加しない。
- セキュリティ脆弱性の詳細、未修正の攻撃手順、再現用exploitをpublic文書に書かない。
- 暗号設計や実装コードを変更しない。
- CIやActions権限を変更しない。
- bug bounty、SLA、報奨金、法的safe harborを勝手に約束しない。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。
2. `rg --files -g 'SECURITY.md' -g '.github/SECURITY.md'` で既存security policyの有無を確認する。
3. `README.md` と `CONTRIBUTING.md` を読み、脆弱性報告導線の追記位置を決める。
4. `SECURITY.md` を作成する。最低限、以下の章を含める。
   - `# Security Policy`
   - `## Supported Versions`
   - `## Reporting a Vulnerability`
   - `## Scope`
   - `## Out of Scope`
   - `## Disclosure`
5. `README.md` または `CONTRIBUTING.md` に `SECURITY.md` への短いリンクを追加する。
6. `git diff --check` を実行する。
7. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] repository rootに `SECURITY.md` が作成されている。
- [ ] Todoriがpre-releaseであり、初回stable releaseまでは `main` branch をサポート対象とする旨が記載されている。
- [ ] 脆弱性詳細をpublic issueへ投稿しないよう明記されている。
- [ ] GitHub private vulnerability reportingを使う方針が記載されている。
- [ ] private vulnerability reportingが未有効または使えない場合の代替連絡先が、確定済みなら記載され、未確定なら要人間判断として完了報告に残されている。
- [ ] E2EE、鍵導出/鍵保存、SQLCipher、同期、認証/アカウント復旧、CI/配布物がscopeに含まれている。
- [ ] bug bounty、SLA、法的safe harborなど、未決の約束を勝手に追加していない。
- [ ] `README.md` または `CONTRIBUTING.md` から `SECURITY.md` への導線がある。
- [ ] GitHub UIでprivate vulnerability reportingを有効化する必要が、完了報告の人間作業として記録されている。
- [ ] `docs/tasks/task-15-security-policy.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。
- [ ] `git diff --check` が成功している。

## 7. 制約・注意事項

- `SECURITY.md` は公開文書である。未修正脆弱性や攻撃手順は書かず、報告導線と対応方針を中心にする。
- E2EEアプリでは、暗号設計・鍵管理・同期メタデータ・認証復旧の扱いが重要である。scopeは広めに取り、報告者が迷わないようにする。
- 代替連絡先は人間が決める。エージェントは個人メール、住所、SNSアカウント等を推測して書かない。
- private vulnerability reportingはGitHub repository settings側の機能であり、ファイル追加だけでは有効にならない。
- public化前に `SECURITY.md` を入れることを必須とする。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 作成・変更したファイル
- `SECURITY.md` の章構成
- supported versionsの扱い
- vulnerability reporting導線
- scope / out of scope
- README/CONTRIBUTING導線の変更内容
- GitHub UIで人間が行う必要がある設定
- 検証結果（少なくとも `git diff --check`）
- 未解決事項・要人間判断
