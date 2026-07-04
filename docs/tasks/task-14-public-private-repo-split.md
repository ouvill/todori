# task-14: public/privateリポジトリ分割の実施

> ステータス: 完了（`## 9. 完了報告` 追記済み。追加作業でprivate repoへの実退避も実施）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

task-12「OSS公開前監査」では、Todoriをpublic repository化する前に確認すべき秘密情報、公開不適切情報、OSS基本文書、CI/Actions安全性を棚卸しした。task-13「public/privateドキュメント分割方針の策定」では、ユーザーが選択した「public repoを主、private repoを非公開資料側」とする方針に基づき、文書ごとのpublic/private分類、要約ルール、後続タスク候補を整理した。

このタスクは、task-13の移行計画を実際の作業指示に落とし込み、public repoとして残す `todori/` と、private側の sibling repo を分けて運用できる初期状態を作るためのものである。

CodexなどのAIコーディングエージェントは、同じワークスペース配下に sibling repo として配置された複数のGit repositoryを同時に参照できる。そのため、推奨構成は以下とする。

```text
todori-root/
├── todori/                 # public repo: コード・公開ドキュメントの正本
└── todori-private/         # private repo: 事業/法務/監査/内部資料
```

private repoを `todori/` の内側へネストしたり、public repoからprivate repoをsubmodule参照したりすると、private repoの存在やURL、内部運用の痕跡がpublic側に残りやすい。このタスクでは sibling repo 運用を前提にする。

ユーザー判断として、private repo名は `todori-private` とする。task-12/task-13時点で実シークレットや証明書のコミットは確認されていないため、このタスクではGit履歴rewriteは行わず、現在のファイル配置と公開版要約を整える方針とする。履歴上の課金・法務詳細を完全に消す必要が後から生じた場合のみ、別タスクで履歴分離を扱う。

## 2. 事前に読むべきファイル

- `AGENTS.md`（docs/01〜04変更禁止、タスク運用、公開前監査の扱い）
- `README.md`
- `CONTRIBUTING.md`
- `CLA.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-12-open-source-readiness.md`
- `docs/tasks/task-13-public-private-docs-split.md`
- `docs/01_企画書.md`
- `docs/02_機能仕様書.md`
- `docs/03_技術仕様書.md`
- `docs/04_課金設計書.md`
- `docs/05_設計判断記録.md`
- `docs/06_事業・法務方針.md`
- `docs/07_Phase1計画書.md`

## 3. ゴール

Todoriをpublic/privateの2リポジトリで運用するため、以下を実施する。

- private repoの初期ディレクトリ構成案を、実際に作成できる作業単位へ落とす。
- `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` のpublic要約版を作成する。
- public repoの入口文書から、privateへ退避すべき詳細文書へ直接誘導しないようリンクと説明を整理する。
- private repoへ移すべき内容と、public repoに残す要約・抽象化済み内容の対応表を残す。
- Codexで複数repoを扱うときの作業手順を明文化し、誤ってprivate内容をpublic repoへ混入させない運用チェックを用意する。

このタスクでは、GitHub上のrepository作成、visibility変更、権限設定は行わない。必要な人間作業は完了報告の「未解決事項・要人間判断」に記録する。

## 4. スコープ

### やること

1. **作業ツリー確認**: `git -C todori status --short` でpublic repoの未コミット変更を確認する。private repoが既に存在する場合は `git -C todori-private status --short` も確認する。
2. **private repo配置確認**: `todori-root/todori-private/` が存在するか確認する。存在しない場合は、作成する前に完了報告へ「人間がGitHub private repoを作成またはローカル初期化する必要がある」と記録する。実際に `git init` するかどうかは人間判断とする。
3. **public要約文書作成**: `docs/billing_overview.md` と `docs/legal_overview.md` を新規作成し、task-13の要約・抽象化ルールに従って公開可能な粒度で記載する。
4. **private退避マッピング作成**: task-14完了報告内に、どの情報をprivate側のどのパスへ移す想定かを記録する。
5. **READMEリンク整理**: `README.md` が `docs/04_課金設計書.md` や `docs/06_事業・法務方針.md` の詳細版へ直接誘導している場合、公開版要約文書へのリンクへ差し替える。
6. **docs/tasks一覧更新確認**: 必要に応じて `docs/tasks/README.md` と `docs/tasks/BACKLOG.md` の進捗・優先度を更新する。
7. **複数repo運用手順の記録**: 完了報告に、Codexで sibling repo を同時に扱う際の基本コマンド（例: `git -C todori status`, `git -C todori-private status`）と注意点を記録する。
8. **public混入チェック**: public repo側にprivate詳細が残っていないか、少なくとも `docs/04` / `docs/06` / `README.md` / 新規要約文書を目視確認し、必要な検索を実行する。
9. **検証**: ドキュメントのみの変更として、最低限 `git -C todori diff --check` を実行する。private repoを作成または変更した場合は、private側でも `git -C todori-private status --short` を確認する。
10. **完了報告追記**: 指示書末尾へ「## 9. 完了報告」を追記し、実施内容、移行マッピング、検証結果、未解決事項を記録する。

### やらないこと

- GitHub上でpublic repositoryやprivate repositoryを作成・削除・設定変更しない。
- GitHub repositoryのvisibilityを変更しない。
- private repoをpublic repoの内側へネストしない。
- public repoからprivate repoをsubmodule/subtree参照しない。
- `docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md`、`docs/04_課金設計書.md` の内容を書き換えない。
- 実装コード、CI、`.github/workflows/` を変更しない。
- 課金方針、法務方針、CLA採用可否、脆弱性受付窓口、商標・ドメイン取得方針を最終決定しない。
- Git履歴から過去の文書を削除・rewriteしない。task-12/task-13時点の判断では履歴rewriteは不要とし、実シークレット等が後から見つかった場合のみ別タスクで扱う。
- privateへ退避すべき詳細を、public要約文書へ具体数値・未確定法務メモ・攻撃手順の形で転記しない。

## 5. 実装手順（例）

1. `git -C todori status --short` を実行し、public repoの状態を確認する。
2. `todori-private/` の有無を確認する。存在する場合は `git -C todori-private status --short` を実行する。存在しない場合は、作成要否を完了報告の人間判断事項に残す。
3. task-13の完了報告を再読し、`docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` の章・節単位分類を作業入力にする。
4. `docs/billing_overview.md` を作成し、課金方針を公開可能な粒度で要約する。具体価格、転換率、MRR/ARR、手数料比較、税務メモは含めない。
5. `docs/legal_overview.md` を作成し、OSS方針、ライセンス、プライバシー/利用規約の公開向け方針を要約する。個人事業・ストア登録・暗号輸出規制・商標/ドメイン調査の内部メモは含めない。
6. `README.md` のドキュメントリンクを確認し、公開版要約文書へ誘導する構成に整理する。
7. private repoが既に存在し、人間がこのタスク内でのローカルファイル作成を許可している場合のみ、task-13で提案された `business/`、`legal/`、`security/`、`roadmap/`、`drafts/` の初期READMEを作成する。許可がない場合は作成せず、作成案を完了報告に残す。
8. `rg -n "MRR|ARR|ARPU|転換率|損益分岐|個人事業|暗号輸出|商標|ドメイン|RevenueCat|Stripe" todori/README.md todori/docs/billing_overview.md todori/docs/legal_overview.md` などで、要約文書に詳細情報が混入していないか確認する。
9. `git -C todori diff --check` を実行する。
10. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [x] public/private分割の実作業対象と、GitHub上の人間作業対象が分離されている。
- [x] `docs/billing_overview.md` が作成され、課金方針が公開可能な粒度で要約されている。
- [x] `docs/legal_overview.md` が作成され、事業・法務方針が公開可能な粒度で要約されている。
- [x] `README.md` から課金・法務の詳細版へ直接誘導せず、公開版要約文書へ誘導している。
- [x] `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` の詳細情報について、private repo側の退避先候補が記録されている。
- [x] private repoをpublic repoの内側へネストしていない。
- [x] public repoからprivate repoをsubmodule/subtree参照していない。
- [x] Codexで複数repoを扱うための基本コマンドと注意点が完了報告に記録されている。
- [x] public要約文書に、価格仮案、収益試算、転換率、個人事業の内部事情、暗号輸出規制の詳細チェックリスト、商標/ドメイン調査メモ、未修正脆弱性の再現手順が含まれていない。
- [x] `docs/tasks/task-14-public-private-repo-split.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。
- [x] `git -C todori diff --check` が成功している。

## 7. 制約・注意事項

- public repoはビルド、テスト、改変、監査、脆弱性報告、ライセンス確認に必要な情報を単体で保持する。
- E2EEの透明性に必要な暗号設計、鍵階層、同期仕様、サーバーが知り得る情報/知り得ない情報は、原則publicに残す。
- private repoへ移すのは、事業戦略、法務メモ、未確定ロードマップ、公開前監査の生メモ、AIエージェント運用など、public repo利用者が知らなくてもビルド・監査・貢献できる情報に限る。
- `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` は現時点では履歴上public repoに残っている。task-12/task-13時点で実シークレット等は確認されていないため、公開準備では履歴rewriteを必須にしない。
- private repoをまだ作成していない場合でも、public repo側の要約文書と移行マッピングは作成できる。
- private repoの名前は `todori-private` とする。GitHub org/user、権限、branch protection、バックアップ方針は人間判断である。
- AGPLで公開する以上、ビルドや改変に必要な生成元、設定、手順をprivate側だけに置いてはならない。
- 本タスクは公開準備タスクであり、M3以降のアプリ機能実装より前に実施してよい。ただし、実装コードには触れない。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- public repo側で変更・作成したファイル
- private repo側で変更・作成したファイル、または未作成の場合の理由
- `docs/04_課金設計書.md` からpublic要約へ残した内容とprivateへ退避する内容
- `docs/06_事業・法務方針.md` からpublic要約へ残した内容とprivateへ退避する内容
- READMEリンク整理の結果
- private repo側の退避先マッピング
- Codexで複数repoを扱う運用手順
- public混入チェックの結果
- 検証結果（少なくとも `git -C todori diff --check`）
- 未解決事項・要人間判断

## 9. 完了報告

作業日: 2026-07-04

### 読んだファイル

- `AGENTS.md`
- `README.md`
- `CONTRIBUTING.md`
- `CLA.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/tasks/task-12-open-source-readiness.md`
- `docs/tasks/task-13-public-private-docs-split.md`
- `docs/tasks/task-14-public-private-repo-split.md`
- `docs/01_企画書.md`（公開範囲関連の参照箇所）
- `docs/02_機能仕様書.md`（タスク指定上の前提として参照）
- `docs/03_技術仕様書.md`（課金・E2EE境界関連の参照箇所）
- `docs/04_課金設計書.md`
- `docs/05_設計判断記録.md`
- `docs/06_事業・法務方針.md`
- `docs/07_Phase1計画書.md`

### public repo側で変更・作成したファイル

- 作成: `docs/billing_overview.md`
- 作成: `docs/legal_overview.md`
- 更新: `AGENTS.md`
- 更新: `README.md`
- 更新: `docs/01_企画書.md`
- 更新: `docs/03_技術仕様書.md`
- 更新: `docs/07_Phase1計画書.md`
- 更新: `docs/tasks/README.md`
- 更新: `docs/tasks/BACKLOG.md`
- 更新: `docs/tasks/task-14-public-private-repo-split.md`
- 削除: `docs/04_課金設計書.md`
- 削除: `docs/06_事業・法務方針.md`

### private repo側で変更・作成したファイル

初回完了時点では `todori-root/todori-private/` が存在しなかったためprivate側の実ファイル作成は行わなかった。その後、ユーザーが `todori-private/` を作成したため、追加作業として以下を作成した。

- `README.md`
- `business/README.md`
- `business/billing-design.md`
- `legal/README.md`
- `legal/business-legal-policy.md`
- `security/README.md`
- `roadmap/README.md`
- `drafts/README.md`

GitHub上のprivate repository権限設定、branch protection、backup方針は人間作業として残す。

### `docs/04_課金設計書.md` からpublic要約へ残した内容とprivateへ退避する内容

public要約として `docs/billing_overview.md` に残した内容:

- ローカル機能はアカウントやサブスクリプションなしで利用できる方針。
- 課金対象は暗号化同期、暗号化クラウドバックアップ、組織共有などサーバー依存機能に限定する方針。
- 課金状態とE2EEコンテンツを分離し、サーバーがタスク内容を知り得ない境界。
- 失効時もローカルデータの閲覧・編集を妨げない方針。
- aggressiveなpaywallや営業目的の通知を避けるUX方針。

privateへ退避した内容:

- 具体価格、割引、trial実験、launch offer。
- 収益試算、契約数、conversion仮定、financial forecast。
- provider別の手数料比較、運用コスト計算、税務/請求運用メモ。
- 詳細なbilling event schemaや未確定の運用判断。

退避先:

- `todori-private/business/billing-design.md`

### `docs/06_事業・法務方針.md` からpublic要約へ残した内容とprivateへ退避する内容

public要約として `docs/legal_overview.md` に残した内容:

- ソース公開により、E2EEとプライバシー主張を第三者が検証可能にする方針。
- `AGPL-3.0-only` とCLAの公開向け説明。
- privacy policy / termsで扱うべきユーザー向け原則。
- 配布前に必要な一般的なplatform / compliance確認を完了させる方針。
- Todoriというproject identityを公開文書で一貫して使う方針。

privateへ退避した内容:

- maintainer運営体制や公開に不要なaccount setup detail。
- platform registration、provider form、review stepなどのpre-release作業メモ。
- raw legal draft、review comment、未確定risk note。
- name availability research、launch-planning note。

退避先:

- `todori-private/legal/business-legal-policy.md`

### READMEリンク整理の結果

`README.md` のドキュメント一覧から、詳細版の `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` への直接リンクを外し、以下へ差し替えた。

- `docs/billing_overview.md`
- `docs/legal_overview.md`

また、`AGENTS.md`、`docs/tasks/README.md`、`docs/01_企画書.md`、`docs/03_技術仕様書.md`、`docs/07_Phase1計画書.md` の現行参照を公開版要約へ差し替え、公開側に具体価格、収益試算、provider固有の課金判断、詳細な法務運用メモへの直接リンクが残らないようにした。private repo名や退避先マッピングはpublic向け入口文書には載せず、本完了報告内に留める。

### private repo側の退避先マッピング

本完了報告に以下の初期マッピングを記録した。

| public側の元情報 | private側の退避先候補 | public replacement |
|---|---|---|
| `docs/04_課金設計書.md` の詳細 | `business/pricing.md`, `business/revenue-scenarios.md`, `business/kpi.md` | `docs/billing_overview.md` |
| `docs/06_事業・法務方針.md` の詳細 | `legal/app-store.md`, `legal/export-compliance.md`, `legal/trademark-domain.md`, `legal/terms-privacy-drafts.md` | `docs/legal_overview.md` |
| raw security review notes | `security/audit-notes.md`, `security/vulnerability-triage.md` | `SECURITY.md` and fixed-issue summaries |
| internal roadmap notes | `roadmap/internal-priorities.md`, `roadmap/release-planning.md` | public roadmap summaries |
| rough design notes | `drafts/rough-design-notes.md` | public ADRs or technical docs after review |

### Codexで複数repoを扱う運用手順

本完了報告に以下を記録した。

- public repo確認: `git -C todori status --short`
- private repo確認: `git -C todori-private status --short`
- private repoは `todori/` の内側に置かない。
- public repoからprivate repoをsubmodule/subtree参照しない。
- 複数エージェント利用時は、同じファイルを同時編集しないよう担当範囲を分ける。
- public diffを確認し、private detailが混入していないか確認してからcommitする。

### public混入チェックの結果

実行した確認:

- `rg -n "MRR|ARR|ARPU|転換率|損益分岐|個人事業|暗号輸出|商標|ドメイン|RevenueCat|Stripe|\$[0-9]|¥[0-9]|04_課金設計書|06_事業・法務方針" README.md AGENTS.md docs/01_企画書.md docs/02_機能仕様書.md docs/03_技術仕様書.md docs/05_設計判断記録.md docs/07_Phase1計画書.md docs/billing_overview.md docs/legal_overview.md docs/tasks/README.md docs/tasks/BACKLOG.md`

結果:

- `README.md`、`docs/01_企画書.md`、`docs/03_技術仕様書.md` に含まれる一般語「暗号」だけが検出された。
- 現行のpublic入口・通常ドキュメント・公開要約文書には、価格仮案、収益試算、転換率、個人運営の内部事情、詳細な規制チェックリスト、provider固有の課金判断、未修正脆弱性の再現手順、`docs/04_課金設計書.md` / `docs/06_事業・法務方針.md` への現行リンクは含めていない。

### 検証結果

- `git -C todori diff --check`: 成功。
- `git -C todori-private diff --check`: 成功。

### 未解決事項・要人間判断

- `todori-private` repositoryのGitHub上のアクセス権限、branch protection、バックアップ方針は人間作業である。
- `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` の詳細版ファイルは、追加作業でpublic repoから削除し、`todori-private/` へ退避した。
- task-12/task-13時点で実シークレット等は確認されていないため、Git履歴rewriteは不要と判断している。後から実シークレット等が見つかった場合のみ別タスクで扱う。
- public化前に `SECURITY.md` を追加し、GitHub private vulnerability reportingを有効化する必要がある（task-15）。
