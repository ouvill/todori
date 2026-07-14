---
id: 019f614f-03a5-7c63-85a3-34de156a76ff
title: Billing foundation release gate
status: backlog
lane: critical
milestone: M5
---

# Billing foundation release gate

## 1. 背景とコンテキスト

Todoriは一般リリース前であり、E2EE同期を含む主要な製品基盤は実装済みである。一方、課金実装は`server/src/routes/billing.rs`のTODOを含め未着手で、購入・復元、サーバー側検証、エンタイトルメント反映、失効時の同期制御がend-to-endで成立していない。プロダクトオーナーは2026-07-15に、課金基盤が完成するまで最初の一般リリースを行わないと決定した。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/01_企画書.md` §6、§8
- `docs/03_技術仕様書.md` §6.1、§10
- `docs/billing_overview.md`
- `docs/07_Phase1計画書.md` M5
- `docs/08_Phase2計画書.md`
- `server/src/routes/billing.rs`
- account、session、sync authorization、Flutter account UIの現行実装とテスト

## 3. ゴール

購入または復元された有効な利用権をサーバーが検証し、アカウントのエンタイトルメントへ冪等に反映し、クライアント表示と同期APIの認可へ一貫して適用できる課金基盤を完成させる。ローカル機能とローカルデータは課金状態に依存させない。

## 4. スコープ

### やること

- iOSの購入・復元フローと、購入結果をサーバー検証へ渡すクライアント境界を実装する。
- provider固有payloadを正規化するbilling adapter、署名・真正性検証、event重複排除、監査可能な処理結果をサーバーへ実装する。
- subscription / entitlementの永続状態と状態遷移を実装する。
- 同期APIがリクエストごとにserver-side entitlementを検証する。
- active、trial、grace、expired、revoked、復元、返金、重複event、順不同eventを自動テストする。
- Flutterで購入、復元、現在状態、失敗、失効を静かで文脈的なUIとして表示する。
- sandbox環境で購入・復元・更新・失効をend-to-end確認し、リリースゲートの証拠を記録する。

### やらないこと

- 具体価格、売上予測、launch offer、provider手数料比較をpublic repoへ記録しない。
- Organization課金、seat課金、Web課金、Android課金を最初のiOSリリース必須範囲へ含めない。
- ローカルCRUD、ローカル検索、Calendar、Timer、テンプレート等を有料化しない。
- クライアントが提示したplanや未検証receiptを認可の正本にしない。
- 購入payload、メールアドレス、token、鍵、復号済みコンテンツをログや完了報告へ含めない。

## 5. 実装手順

1. public仕様と人間承認済みの非公開事業判断から、初回iOSリリースに必要なproduct、状態、trial、grace、失効規約を確定する。
2. 新規依存、provider SDK、webhook、署名鍵、secret管理の供給網・権限境界をレビューし、導入前承認を記録する。
3. server schema、event ingestion、検証adapter、冪等な集約、entitlement query、sync authorizationを実装する。
4. `todori-client`へfrontend-neutralなentitlement APIを置き、FRBをtyped DTO変換と薄い委譲に限定する。
5. Flutterの購入・復元・状態表示をARB、accessibility、失敗復帰込みで実装する。
6. unit / integration / widget / sandbox E2Eを実行し、失効後もローカル編集可能であることを確認する。
7. 統合HEADを独立検証し、課金・実機・法務・運用のリリースチェックリストをすべて閉じてから一般リリース準備へ進む。

## 6. 受け入れ基準

- iOS sandboxで購入と購入復元が成功し、同一アカウントのserver entitlementへ反映される。
- receipt / transaction / webhookはserver側で検証され、改ざん、不正署名、別accountへのreplayが拒否される。
- event IDとtransaction IDの重複処理が冪等で、順不同eventからも決定済み状態規約へ収束する。
- active / trial / graceでは許可され、expired / revokedでは同期APIがserver側で拒否する。
- 課金失効後も既存local DBの閲覧・編集・local-only機能が継続し、再有効化後に通常同期へ復帰する。
- クライアントの表示状態を改ざんしてもserver-side authorizationを迂回できない。
- 購入、復元、失敗、保留、失効のUIがen/ja、accessibility、再起動復元を含めて検証される。
- repositoryの共通品質ゲート、課金固有テスト、独立検証、iOS sandbox E2Eが合格する。
- 課金基盤が未完了の間、store提出、release tag、公開告知を行わないことが運用文書と一致している。

## 7. 制約・注意事項

- `lane: critical` とし、新規SDK / dependency、課金状態規約、保存schema、secret運用は実装前に人間承認を得る。
- public repoには実装・検証に必要な公開可能情報だけを置き、価格、収益、契約、provider比較の詳細を置かない。
- エンタイトルメントの正本はserver-side aggregateとし、外部providerは更新sourceとして抽象化する。
- pre-release方針に従い、未実装の旧経路や仮planを残すcompatibility layerを追加しない。
- App Store、課金provider、署名鍵、webhook secretの実値をcommitしない。

## 8. 完了報告に含めるべき内容

- 実装した購入、検証、event集約、entitlement、同期認可、Flutter UIの概要
- schema / API / dependency / secret運用に関する承認済み判断
- unit / integration / widget / sandbox E2Eと独立検証の結果
- activeから失効・復元までの観測証拠と、local-only機能を維持した証拠
- 一般リリースへ進めるかのゲート判定と、残る人間作業
