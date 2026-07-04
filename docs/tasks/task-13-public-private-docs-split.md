# task-13: public/privateドキュメント分割方針の策定

> ステータス: 完了（`## 9. 完了報告` 追記済み。実分割は後続タスク）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

task-12「OSS公開前監査」では、実シークレット・証明書・DB・ログ・具体的PIIのコミットは確認されず、CIにもpublic fork PRで直ちに危険な `pull_request_target` / secrets / deploy / self-hosted runner は含まれないことを確認した。一方で、`docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` には、課金戦略、収益試算、個人事業としての運営方針、ストア登録方針、暗号輸出規制、商標・ドメイン確認など、秘密情報ではないが公開範囲の人間判断が必要な情報が含まれる。

ユーザーは、TodoriのOSS公開運用として「public repoを主、private repoを内部メモ置き場」とする方針を選択した。つまり、コード・ビルドに必要な設定・公開可能な技術仕様はpublic `todori` を正本とし、課金・法務・未確定ロードマップ・公開前の荒い設計メモ・セキュリティ監査メモなどはprivate側で育て、publicへ出す場合は要約・抽象化して転記する運用である。

このタスクは、実際にリポジトリをpublic化する前に、どの文書をpublicに残し、どの情報をprivate repoへ退避し、publicにはどの粒度の要約を残すかを具体化するための指示書である。ドキュメント分類と移行計画を作ることが目的であり、実装コードには触れない。

## 2. 事前に読むべきファイル

- `AGENTS.md`（docs/01〜04変更禁止、タスク運用、公開前監査の扱い）
- `README.md`（public repoの入口として残すべき情報）
- `CONTRIBUTING.md`
- `CLA.md`
- `docs/tasks/task-12-open-source-readiness.md`（OSS公開前監査の完了報告。特に公開判定、公開前修正タスク候補、未解決事項）
- `docs/tasks/BACKLOG.md`
- `docs/tasks/README.md`
- `docs/01_企画書.md`
- `docs/02_機能仕様書.md`
- `docs/03_技術仕様書.md`
- `docs/04_課金設計書.md`
- `docs/05_設計判断記録.md`
- `docs/06_事業・法務方針.md`
- `docs/07_Phase1計画書.md`

## 3. ゴール

Todoriを「public repoを主、private repoを内部メモ置き場」で運用するため、以下を明文化する。

- public repoに残す文書・情報
- private repoへ退避する文書・情報
- public repoに要約版を残す文書・情報
- privateからpublicへ転記するときの抽象化ルール
- 実際の分割作業を行う後続タスク候補
- 人間判断が必要な事項

成果物は、`docs/tasks/task-13-public-private-docs-split.md` 末尾の「## 9. 完了報告」に記録される分類表と移行計画である。必要に応じて、public/private分類のための新規ドキュメント（例: `docs/publication_policy.md`）を追加してよいが、判断に迷う内容は実ファイル移動ではなく完了報告の「要人間判断」に留める。

## 4. スコープ

### やること

1. **文書棚卸し**: `README.md`、`CONTRIBUTING.md`、`CLA.md`、`docs/01`〜`07`、`docs/tasks/` を読み、文書ごとに public / private / public要約 + private詳細 / 要人間判断 のいずれかへ分類する。
2. **情報単位の分類**: 文書全体を機械的に分類せず、必要に応じて章・節・表単位で分類する。特に `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` は、公開してよい概要とprivateに置くべき詳細を分けて評価する。
3. **publicに残す条件の定義**: ビルド・改変・監査に必要な情報、OSS利用者・コントリビューターに必要な情報、E2EEの透明性に資する情報をpublicに残す条件として明文化する。
4. **privateへ退避する条件の定義**: 収益試算、価格戦略の未確定案、個人事業・法務メモ、商標・ストア・ドメイン調査、公開前の荒い設計メモ、未公開ロードマップ、セキュリティ監査メモなどをprivateへ退避する条件として明文化する。
5. **public要約ルールの作成**: private詳細をpublicに転記する場合のルールを定める。例: 金額や転換率などの数値試算は省き、方針レベルに抽象化する。個人運営上の事情は一般化する。攻撃手順に近いセキュリティメモは公開しない。
6. **移行計画の作成**: 実際にファイルを移す前に、どの後続タスクで何を行うかを優先度付きで提案する。例: `docs/04` のpublic要約作成、`docs/06` のpublic要約作成、private repo初期構成、`README.md` の文書リンク整理。
7. **公開repoに必要な最低限の文書確認**: 分割後もpublic repo単体でビルド・テスト・貢献・セキュリティ報告・ライセンス確認に必要な情報が欠けないか確認する。
8. **完了報告追記**: 指示書末尾に「## 9. 完了報告」を追記し、分類表、移行計画、未解決事項、人間判断事項を記録する。

### やらないこと

- GitHub上でpublic repositoryやprivate repositoryを作成・削除・設定変更しない。
- 現在のリポジトリから `docs/04_課金設計書.md` や `docs/06_事業・法務方針.md` を削除しない。
- private repoへの実ファイル移動、履歴分離、submodule/subtree設定、同期スクリプト作成は行わない。
- `docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md`、`docs/04_課金設計書.md` の内容を書き換えない。
- 課金方針、法務方針、CLA採用可否、脆弱性受付窓口、商標・ドメイン取得方針を最終決定しない。
- 公開用に情報を隠す目的で、ビルド・改変・監査に必要なソースコード、生成元、設定、手順をprivate化しない。
- `core/`、`app/`、`server/`、`cli/`、`mcp-server/` の実装コードを変更しない。
- `.github/workflows/` を変更しない。Actions権限の最小化は別タスクで扱う。
- `SECURITY.md`、`CODE_OF_CONDUCT.md`、issue/PR templateをこのタスクで作成しない。必要性と優先度を移行計画に記録する。

## 5. 実装手順（例）

1. `git status --short` で作業ツリーを確認する。既存の未コミット変更がある場合は内容を確認し、無関係な変更を戻さない。
2. 2章のファイルを読む。特にtask-12の「公開判定」「公開前修正タスク候補」「未解決事項・要人間判断」を再読する。
3. `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` を章・節単位で読み、publicに残せる概要とprivateに退避すべき詳細を分ける。
4. `docs/01`、`docs/02`、`docs/03`、`docs/05`、`docs/07`、`docs/tasks/` について、publicに残すことでE2EEの透明性・OSS開発に資するか、攻撃者や競合へ不要な内部情報を与えるかを評価する。
5. 分類表を作る。最低限、列は「対象」「推奨配置」「理由」「publicに残す要約」「要人間判断」を含める。
6. private repo側の初期ディレクトリ案を作る。例: `business/`、`legal/`、`security/`、`roadmap/`、`drafts/`。実際のディレクトリ作成はしない。
7. public repo側に残す文書構成案を作る。例: `README.md`、`CONTRIBUTING.md`、`SECURITY.md`、`docs/01`〜`03`、公開版ADR、公開版ロードマップ。
8. 後続タスク候補を優先度付きで作る。task-12の候補（`SECURITY.md`、Actions権限、license/advisory監査等）との依存関係も整理する。
9. 必要最小限の追加文書を作る場合は、`docs/01`〜`04` 以外に新規ファイルとして作成する。内容は分類ルールに限り、公開可否の最終判断を勝手に確定しない。
10. `git diff --check` を実行する。
11. 指示書末尾へ「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `README.md`、`CONTRIBUTING.md`、`CLA.md`、`docs/01`〜`07`、`docs/tasks/` のpublic/private分類が文書単位または章・節単位で記録されている。
- [ ] `docs/04_課金設計書.md` について、publicに残せる概要、privateへ退避すべき詳細、要人間判断事項が具体的に分かれている。
- [ ] `docs/06_事業・法務方針.md` について、publicに残せる概要、privateへ退避すべき詳細、要人間判断事項が具体的に分かれている。
- [ ] public repoに残すべき情報の条件が、ビルド・改変・監査・貢献・E2EE透明性の観点で明文化されている。
- [ ] private repoへ置くべき情報の条件が、事業戦略・法務メモ・未確定判断・セキュリティ監査メモの観点で明文化されている。
- [ ] private詳細をpublicへ転記するときの要約・抽象化ルールが具体例付きで記録されている。
- [ ] 分割後もpublic repo単体でビルド・テスト・改変・脆弱性報告・ライセンス確認に必要な情報が欠けないことを確認している。
- [ ] 実際のファイル移動・削除・GitHub repository設定変更を行っていない。
- [ ] 後続タスク候補が優先度、理由、対象ファイル付きで提示されている。
- [ ] `docs/tasks/task-13-public-private-docs-split.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。
- [ ] `git diff --check` が成功している。

## 7. 制約・注意事項

- `docs/01_企画書.md`、`docs/02_機能仕様書.md`、`docs/03_技術仕様書.md`、`docs/04_課金設計書.md` は変更禁止である。分類や要約案は完了報告または新規方針文書に書き、既存仕様書を書き換えない。
- AGPLで公開する以上、ビルド・改変・検証に必要なソースコード、生成元、設定、手順をprivate側だけに置いてはならない。
- E2EEの信頼性に関わる暗号設計・鍵階層・脅威モデルは、攻撃手順や未修正脆弱性の詳細を除き、原則publicに残す方向で評価する。
- 事業・法務・課金の情報は、秘密情報でなくても公開による不利益がありうる。最終判断は人間に委ね、エージェントは分類理由と選択肢を示す。
- private repoの名称、作成場所、アクセス権限、同期方式はこのタスクでは決めきらない。必要なら後続タスクとして提案する。
- 既存の未コミット変更がある場合、無関係な変更は戻さない。READMEやBACKLOGに追記が必要な場合は、既存差分を尊重して最小限の追加に留める。
- このタスクは公開準備タスクであり、M3以降のアプリ機能実装より前に実施してよい。ただし、実装コードには触れない。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- public/private分類表（対象、推奨配置、理由、public要約、要人間判断）
- `docs/04_課金設計書.md` の章・節単位の扱い
- `docs/06_事業・法務方針.md` の章・節単位の扱い
- public repoに残す情報の条件
- private repoへ退避する情報の条件
- privateからpublicへ転記するときの要約・抽象化ルール
- private repo側の初期ディレクトリ案
- public repo側の文書構成案
- 後続タスク候補（優先度、理由、対象ファイル）
- 検証結果（少なくとも `git diff --check`）
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
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/task-01-opaque-poc.md` から `docs/tasks/task-13-public-private-docs-split.md`
- `docs/01_企画書.md`
- `docs/02_機能仕様書.md`
- `docs/03_技術仕様書.md`
- `docs/04_課金設計書.md`
- `docs/05_設計判断記録.md`
- `docs/06_事業・法務方針.md`
- `docs/07_Phase1計画書.md`

### public/private分類表

| 対象 | 推奨配置 | 理由 | publicに残す要約 | 要人間判断 |
|---|---|---|---|---|
| `README.md` | public | public repoの入口であり、概要・構成・開発コマンド・ライセンス導線が必要 | 課金/事業詳細への直リンクは公開版要約へ差し替える | `docs/04` / `docs/06` を直接リンクし続けるか |
| `CONTRIBUTING.md` | public | 外部貢献に必要 | AGENTS.mdの6ゲートと同期した公開貢献手順 | CLA運用確定後の文言 |
| `CLA.md` | public要約 + 要判断 | PR受付時に必要だが現状は草案 | CLAが必要である旨、同意方法、草案/レビュー状況 | 専門家レビュー前に公開するか |
| `docs/01_企画書.md` | public要約 + private詳細 | プロダクト思想は公開価値が高いが、価格仮案・ロードマップ・商標前メモを含む | E2EE/ローカルファースト/対象ユーザー/大まかなロードマップ | §6の価格例、§8の未確定ロードマップをどこまで出すか |
| `docs/02_機能仕様書.md` | public | OSS利用者・貢献者が挙動を理解するため必要 | 原則そのまま。未実装機能は「計画」と明示 | Org/監査ログ等の将来機能の公開範囲 |
| `docs/03_技術仕様書.md` | public | E2EE透明性、監査、ビルド・改変に必須 | 暗号設計、鍵階層、ローカルDB、同期、テスト方針を残す | 未修正脆弱性や攻撃手順に近い監査メモは別途privateへ |
| `docs/04_課金設計書.md` | public要約 + private詳細 | 方針は公開できるが価格仮案、MRR/ARR、転換率、手数料、税務検証は事業内部資料 | Freeはローカル機能を制限しない、同期/共有を有料、データを人質にしない、E2EEと課金の分離 | 価格・チャネル・RevenueCat/Stripe採用判断を公開する粒度 |
| `docs/05_設計判断記録.md` | public | 技術判断の理由はOSS監査・貢献に有用 | 原則そのまま。ADR-008の事業/マーケ表現だけ必要なら抑制 | Neonリージョン、競合比較、コスト認識の公開粒度 |
| `docs/06_事業・法務方針.md` | public要約 + private詳細 | OSS方針は公開必要だが個人事業、ストア登録、暗号輸出、商標/ドメイン調査は内部法務メモ | OSS方針、AGPL-3.0-only、CLA方針、利用規約/プライバシーポリシーの公開向け要約 | 個人事業方針、暗号輸出規制メモ、商標/ドメイン調査の公開可否 |
| `docs/07_Phase1計画書.md` | public | 現在の開発計画・完了条件として貢献者に有用 | Phase 1範囲、マイルストーン、既知リスクを残す | 未確定スケジュールを外部約束に見せない表現 |
| `docs/tasks/README.md` | public | タスク運用ルールと進捗一覧として必要 | 完了済み/未着手、依存関係、共通規約を残す | 内部運用色が強い場合は公開版に簡略化 |
| `docs/tasks/BACKLOG.md` | public要約 + private詳細 | 開発予定共有には有用だが優先順位・未確定ロードマップは内部判断を含む | 直近の公開ロードマップと貢献歓迎領域 | 優先順位や内部判断メモをどこまで公開するか |
| `docs/tasks/PLAYBOOK.md` | private | AIエージェント運用の内部手順であり、利用者・貢献者に必須ではない | 必要ならCONTRIBUTINGへ「タスク指示書方式」を短く記載 | publicに残す場合の簡略版作成 |
| `docs/tasks/task-01`〜`task-11` | public | 実装履歴・検証結果として透明性がある | 完了報告を含めて残す。環境制約や未解決事項も公開可能 | 長い内部作業ログを公開repoに残すか |
| `docs/tasks/task-12` | public要約 + private詳細 | OSS公開監査結果は有用だが公開前弱点リストの詳細は慎重に扱う | 実シークレットなし、CIに危険設定なし、不足文書あり | 公開前修正候補の詳細なリスク記述 |
| `docs/tasks/task-13` | public | 分割方針そのものとして公開可能 | 本完了報告を移行計画の入力にする | 実分割後に公開版へ要約するか |

### `docs/04_課金設計書.md` の章・節単位の扱い

| 節 | 推奨配置 | public要約 | private詳細 |
|---|---|---|---|
| 1. 目的と基本方針 | public要約 | ローカル機能無料、データを人質にしない、計測最小化、押し売りしないpaywall | なし |
| 2.1 機能マトリクス | public | Free/Pro/Orgの機能境界 | なし |
| 2.2 価格（仮案） | private詳細 | 「価格は未定、同期/共有を有料化予定」 | 具体価格、通貨別価格、割引率 |
| 2.3 トライアル | public要約 + private詳細 | トライアル提供を検討 | 期間、カード要否、チャーン/転換率の検証方針 |
| 2.4 検討事項 | private詳細 | 未決事項あり | ライフタイムプラン不採用理由、学割/非営利割引検討 |
| 3. 収益シミュレーション | private | 公開しない。必要なら「持続可能な運営を前提に検討中」 | MAU、転換率、ARPU、MRR/ARR、損益分岐 |
| 4. 購入チャネル設計 | public要約 + private詳細 | モバイルIAP、Desktop/OrgはWeb決済を想定 | Stripe Managed Payments限定理由、手数料比較、規約リスク評価 |
| 5. コンバージョン導線 | public要約 | ダークパターン禁止、自然な課金導線 | 優先順位、win-back、保持期間の詳細判断 |
| 6. 技術設計 | public要約 + private詳細 | エンタイトルメントはサーバー側、E2EE鍵/コンテンツと分離 | テーブル案、RevenueCat採用根拠、状態機械、不正対策詳細 |
| 7. 運用 | private詳細 | 透明な解約/返金導線を整える | 価格改定、インボイス、税務、Managed Payments適格性、フォールバック |
| 8. KPI・計測 | public要約 + private詳細 | 課金KPIはサーバー側課金イベント中心、クライアント行動計測は最小化 | KPI定義、LTV/チャーン、Org ARR、分析方針詳細 |
| 9. 未決事項 | private詳細 | 未決事項があることのみ | 学割、エンタープライズプラン案 |

### `docs/06_事業・法務方針.md` の章・節単位の扱い

| 節 | 推奨配置 | public要約 | private詳細 |
|---|---|---|---|
| 1. 事業主体 | private詳細 | 運営主体情報は正式公開時の法定表示・プライバシーポリシーで必要範囲のみ公開 | 個人事業、ストア個人登録、無限責任、適格性確認 |
| 2. OSS方針 | public | ソース公開、AGPL-3.0-only、CLA前提、監査可能性 | ライセンス比較の内部議論は必要ならADR化またはprivate |
| 3. 暗号輸出規制への対応 | public要約 + private詳細 | 暗号輸出規制を確認し、ストア提出前に必要手続きを行う | EAR/BIS/NSA/ANSSI等の具体チェックリストと提出メモ |
| 4. プライバシーポリシー・利用規約の方針 | public要約 + private詳細 | データ最小化、責任制限、E2EE復旧不可リスクの明示 | 法域別の条項検討、専門家レビュー前のドラフト |
| 5. プロダクト名 | public要約 + private詳細 | 名称Todori、由来、ブランド方向 | 候補比較、商標/ストア/ドメイン/SNS調査メモ |
| 6. リポジトリ運用 | public要約 | GitHubでpublic化し、ActionsでCIする | private運用中の内部手順や公開時設定チェック |

### public repoに残す情報の条件

- ビルド、テスト、改変、配布物の再現に必要なソースコード、生成元、設定、手順。
- OSS利用者・コントリビューターがライセンス、CLA、品質ゲート、開発フローを理解するために必要な文書。
- E2EEの透明性に資する暗号設計、鍵階層、ローカルDB暗号化、サーバーが知り得る情報/知り得ない情報。
- 仕様理解と互換実装に必要なデータモデル、API境界、同期プロトコル、ADR。
- セキュリティ報告、脆弱性対応、依存ライセンス確認に必要な公開窓口と手順。

### private repoへ退避する情報の条件

- 価格仮案、収益試算、転換率、ARPU、MRR/ARR、損益分岐、チャネル別手数料などの事業戦略情報。
- 個人事業・法人化・ストア登録・税務・暗号輸出規制・商標/ドメイン/SNS調査など、公開前または専門家レビュー前の法務/運営メモ。
- 未確定ロードマップ、優先順位の内部判断、競合比較、マーケティング訴求の試行錯誤。
- 未修正脆弱性、攻撃手順、セキュリティ監査の生メモ、公開前に悪用可能な具体情報。
- AIエージェント運用や作業配分など、public repo利用者が知らなくてもビルド・監査・貢献できる内部手順。

### privateからpublicへ転記するときの要約・抽象化ルール

1. 金額、転換率、MAU、ARPU、MRR/ARR、手数料控除後利益率などの数値試算は出さず、「持続可能な運営を前提に検討中」のような方針表現にする。
2. 個人事業、登録名義、法務リスク、税務検証は、正式な公開文書に必要な範囲だけを一般化して記載する。
3. セキュリティ監査メモは、修正済み事項は概要と対策を公開し、未修正の攻撃手順・再現手順・具体的弱点は公開しない。
4. 未確定ロードマップは日付コミットを避け、「planned」「under consideration」「out of scope for Phase 1」のように状態で表す。
5. 外部サービス採用理由は、競合を過度に詳細比較せず、要件・出口戦略・プライバシー影響の観点に抽象化する。
6. E2EE透明性に関わる情報は原則公開し、隠す場合は「悪用可能性」「未修正」「個人/法務情報」のいずれに該当するか理由を残す。

### private repo側の初期ディレクトリ案

```text
private-todori-notes/
├── business/
│   ├── pricing.md
│   ├── revenue-scenarios.md
│   └── kpi.md
├── legal/
│   ├── app-store.md
│   ├── export-compliance.md
│   ├── trademark-domain.md
│   └── terms-privacy-drafts.md
├── security/
│   ├── audit-notes.md
│   └── vulnerability-triage.md
├── roadmap/
│   ├── internal-priorities.md
│   └── release-planning.md
└── drafts/
    └── rough-design-notes.md
```

### public repo側の文書構成案

```text
todori/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CLA.md
├── SECURITY.md
├── CODE_OF_CONDUCT.md
├── docs/
│   ├── product_overview.md
│   ├── feature_spec.md
│   ├── technical_spec.md
│   ├── billing_overview.md
│   ├── adr.md
│   ├── legal_overview.md
│   ├── roadmap.md
│   └── tasks/
│       ├── README.md
│       └── public-task-history.md
└── .github/
    ├── ISSUE_TEMPLATE/
    └── pull_request_template.md
```

既存ファイル名を維持する場合も、`README.md` からは公開版の `billing_overview` / `legal_overview` へリンクし、詳細版の `docs/04` / `docs/06` はprivateへ退避する。

### 後続タスク候補

| 優先度 | タスク | 理由 | 対象ファイル |
|---|---|---|---|
| P0 | 公開版 `docs/04` 要約作成 | 価格・収益試算をpublicから分離するため | `docs/04_課金設計書.md`, 新規 `docs/billing_overview.md` |
| P0 | 公開版 `docs/06` 要約作成 | 個人事業・法務メモをpublicから分離するため | `docs/06_事業・法務方針.md`, 新規 `docs/legal_overview.md` |
| P0 | private repo初期構成の作成 | 退避先と分類ルールを先に固定するため | private repo側 `business/`, `legal/`, `security/`, `roadmap/`, `drafts/` |
| P0 | `README.md` の文書リンク整理 | public入口からprivate詳細へ直接誘導しないため | `README.md` |
| P0 | `SECURITY.md` 作成 | task-12で不足。E2EEアプリとして脆弱性受付が必要 | `SECURITY.md` |
| P1 | `CONTRIBUTING.md` の品質ゲート同期 | AGENTS.mdの6ゲートと公開貢献手順を揃えるため | `CONTRIBUTING.md` |
| P1 | Actions権限の明示 | public fork PRでの権限最小化 | `.github/workflows/ci.yml` |
| P1 | `CODE_OF_CONDUCT.md` とissue/PR template追加 | 外部参加導線を整えるため | `CODE_OF_CONDUCT.md`, `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md` |
| P1 | third-party license / advisory監査自動化 | task-12で未完了。配布時のライセンス確認が必要 | `Cargo.toml`, `Cargo.lock`, `app/pubspec.lock`, CI |
| P2 | task履歴の公開版整理 | 長い内部作業ログと公開向け進捗のバランスを取るため | `docs/tasks/` |

### 分割後のpublic repo単体確認

- ビルド・テストに必要なRust/Flutter/FRB/cargokit/SQLCipher設定はpublicに残す。
- 暗号設計、Device Key、SQLCipher鍵導出、E2EE同期の仕様はpublicに残す。
- `README.md`、`CONTRIBUTING.md`、`LICENSE`、`CLA.md`、今後追加する `SECURITY.md` があれば、貢献・脆弱性報告・ライセンス確認の入口はpublicだけで完結する。
- 課金・法務の詳細をprivateへ退避しても、アプリのビルド、改変、監査、テスト、基本仕様理解には支障がない。
- `SECURITY.md`、Actions権限明示、依存ライセンス/advisory監査は分割とは別に公開前整備が必要である。

### 検証結果

- `git diff --check`: 成功。
- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功。
- `cd app && flutter analyze`: 成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter test`: 成功。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。

補足: `flutter analyze` と `flutter test` は通常実行時にFlutter SDKキャッシュ（ワークスペース外）への書き込みがサンドボックスで拒否されたため、承認付きで再実行して成功した。これは環境制約であり、コード起因の失敗ではない。

### 未解決事項・要人間判断

- `docs/04_課金設計書.md` と `docs/06_事業・法務方針.md` を実際にprivateへ退避するか、public要約を併置するかは人間判断が必要である。
- `README.md` から課金設計書・事業法務方針へ直接リンクし続けるかは、公開版要約作成時に判断する。
- CLA草案を専門家レビュー前にpublic repoへ残すか、外部PR受付前までに確定するかは人間判断が必要である。
- 脆弱性受付窓口、GitHub private vulnerability reportingの利用可否、連絡先メールは未決である。
- private repoの名称、権限、同期方式、履歴分離方法はこのタスクでは決定していない。
- 本タスクでは実ファイル移動、削除、GitHub repository設定変更、`.github/workflows/` 変更、実装コード変更は行っていない。
