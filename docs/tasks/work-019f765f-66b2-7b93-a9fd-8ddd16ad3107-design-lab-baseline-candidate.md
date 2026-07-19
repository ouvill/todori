---
id: 019f765f-66b2-7b93-a9fd-8ddd16ad3107
title: Design Lab baseline and candidate convergence
status: done
lane: standard
milestone: maintenance
---

# Design Lab baseline and candidate convergence

## 1. 背景とコンテキスト

Interactive Design Labは、採用済みUIをfake widgetとして複製し続けたため、productionの機能・情報設計・tokenと乖離した。productionと`docs/design/ui-spec.md`を正本に戻し、Labを実アプリのbaselineと未採用差分だけを持つcandidateへ分離する。

既存の未統合branch `work/019f71e4-75f8-7a41-94b3-89958ce2c03b-design-lab-production-parity`は非採用とし、merge、cherry-pick、実装参照、削除を行わない。未コミットのquiet-daybook worktreeにも触れない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/design/ui-spec.md`
- `docs/tasks/task-33-flutter-design-lab.md`
- `app/lib/main.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/design_lab_main.dart`

## 3. ゴール

- Design Labの既定baselineがproduction `TaskveilApp`、production router、production providerをfake dataで実行する。
- Candidateは未採用差分だけをregistry経由で実行し、採用済み画面の複製を持たない。
- production Visual QAとinteractive baselineが同じfixtureを使う。
- 旧全面mock、独立state、旧IA、書体比較をcurrent harnessから除去する。
- UI Spec、Design Playbook、実装、検証が同じ正本分担を明示する。

## 4. スコープ

### やること

- `DesignLabMode`、`DesignLabCandidate`、candidate registry、dart-define選択を追加する。
- `FakeBridgeService`上の現実的なproduction fixtureを共通化する。
- baseline entrypointとwidget testをproduction appへ接続する。
- Visual QAをproduction baselineとactive candidateだけへ整理する。
- 旧Design Lab mock / interactive testを削除する。
- `ui-spec.md`と`DESIGN_PLAYBOOK.md`へ採用・削除workflowを追記する。

### やらないこと

- production screen、router、provider、Rust、FRB、DB、同期仕様の変更。
- parity branchまたはquiet-daybook worktreeの取り込み・変更・削除。
- private repo、`docs/01`〜`docs/03`の変更。
- push、PR、main merge。

## 5. 実装手順

1. production fixtureとbaseline entrypointを追加する。
2. candidate registryと空状態、registry validationを追加する。
3. Visual QAを共通fixtureへ接続し、旧mock caseとsourceを除去する。
4. UI SpecとDesign Playbookへ正本分担と採用workflowを記録する。
5. Flutter / repository gateとVisual QAを実行し、全current PNGを目視する。
6. 実装非担当者が統合HEADを独立検証し、合格後に完了報告と`done`を記録する。

## 6. 受け入れ基準

- [x] baselineが実際の`TaskveilApp`でHome / Calendar / Lists / Menuを表示し、Search / Templates / Task detail / Focusへproduction routeで遷移できる。
- [x] fixtureに期限・予定、優先度、3階層subtask、完了、複数reminder、template、日英混在が含まれる。
- [x] candidate registryがID、target route、hypothesis、UI Spec delta、work itemを必須にし、重複を拒否する。
- [x] active candidate 0件で明示的な空状態を表示する。
- [x] production codeがDesign Lab、Visual QA、fake bridgeをimportしない。
- [x] 旧全面mock、独立state、旧IA、書体比較がcurrent source / screenshot manifestから除去される。
- [x] production Visual QAが390px、320px日本語text scale 2.0、wide、RTL、Reduce Motionを含めて成功し、manifestとPNG数が一致する。
- [x] Flutterとrepositoryの該当品質ゲート、独立検証が合格する。

## 7. 制約・注意事項

- Candidateはproduction theme / componentを既定利用し、変更差分だけをLab専用widgetとして実装する。
- 採用・却下したcandidateを実行可能なarchiveとして残さない。履歴はwork item、UI Spec、gitに残す。
- fake data文字列はtest / tool限定とし、production ARBを増やさない。
- 新規依存を追加しない。

## 8. 完了報告に含めるべき内容

- baseline / candidate interfaceとfixtureの概要。
- 削除した旧mockとcurrent Visual QA manifestの整理結果。
- production route、fixture内容、candidate validationのtest結果。
- 全Visual QA目視所見、品質ゲート、独立検証、commit、未解決事項。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-19
- 結果: `DesignLabMode`と`DesignLabCandidate`を追加し、既定baselineを`FakeBridgeService`を注入したproduction `TaskveilApp` / routerへ置き換えた。Candidateはactive registryの未採用差分だけをproduction theme上で起動し、0件時は追加方法を示す空状態を表示する。
- Fixture: `DesignLabFixture`をinteractive baselineとproduction Visual QAで共有した。期限・予定、優先度、見積、3階層subtask、done / wont-do、複数reminder、template / weekly schedule、日英混在を含む。
- 整理: current `main`にあった旧全面mock、独立state、旧IA、採用済みprototype、書体比較、外部font取得script、旧interactive testを削除した。旧parity branchは未統合・非採用のまま保存し、quiet-daybook worktreeとprivate repoには変更を加えていない。
- 証拠: `design_lab_baseline_candidate_test.dart`の5 test、`flutter analyze`、release Rust bridge build後の`flutter test` 275件（Visual QA 1件は通常どおり環境flag未指定でskip）、hardcoded strings、client boundary / negative test、Cargo fmt / clippy / workspace test、`git diff --check`が成功した。
- Visual QA: `sh app/tool/visual_qa.sh`が106 testに成功し、`current-manifest.txt` 114行とPNG 114枚が一致した。旧`design_lab_*`画像は0件。Home、Calendar、Lists、Menu、Task detail、Focus、Templates、reminder、390px、320px日本語text scale 2.0、wide、RTL、Reduce Motionを確認した。
- 実行条件: sandbox内の最初の`cargo test --workspace`はlocal socket bindが`Operation not permitted`、最初の`flutter test`はworkspace外Flutter SDK cache書き込みが拒否された。同一commandを許可付きで再実行し、どちらも成功した。
- Commit: 未コミット（完了報告記録時）。
- 未解決: 今回起因の不一致はなし。billing 2枚の文字ブロックは未変更`main`の同名PNGとSHA-256が一致する既存事象であり、production UIを変更しない本work itemの範囲外とした。

### 独立検証

- 判定: 合格。
- 根拠: P0 / P1 / P2 / P3すべて0件。統合差分と未追跡4ファイル、branch起点、変更禁止範囲、Baseline / Candidate契約、共有fixture、旧mock除去、docs契約を監査した。current manifest 114行とPNG 114枚の重複・欠落がないことを確認し、6枚のcontact sheetで全114枚を目視した。108枚は`main`生成物とbyte同一で、fixture変更により変わった6枚も`main`版と原寸比較して正常だった。billing既存事象以外に新規overflow、glyph欠落、構造崩れはなかった。
- 検証者: 実装を担当していない独立検証エージェント。
