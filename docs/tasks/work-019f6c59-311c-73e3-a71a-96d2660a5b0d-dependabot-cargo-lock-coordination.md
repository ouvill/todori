---
id: 019f6c59-311c-73e3-a71a-96d2660a5b0d
title: Dependabot Cargo lock coordination
status: active
lane: critical
milestone: maintenance
---

# Dependabot Cargo lock coordination

## 1. 背景とコンテキスト

Dependabotのroot Cargo更新とfuzz Cargo更新が同じroot manifestを変更しながら、それぞれ片方のlockfileだけを更新した。さらに暗号系major updateが一括化され、PR #17 / #18はlock不整合とRust API非互換を同時に起こした。exact pinとroot / fuzz双方の`--locked`検証は暗号release gateとして維持する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/ops/crypto-release-gate.md`
- `.github/dependabot.yml`
- `tool/check_crypto_dependency_pins.sh`

## 3. ゴール

rootとfuzzのCargo更新を同一Dependabot定義へ統合し、通常の破壊的暗号依存更新を自動PRから分離する。security updateを維持しつつ、不完全なlockfile更新をfail closedで検出する。

## 4. スコープ

### やること

- Cargoの複数directory更新とdependency-name単位のversion groupを設定する。
- security updateを別groupで維持する。
- exact-pinおよび暗号互換性依存の通常minor / major updateを手動reviewへ移す。
- root / fuzz lock不整合時の診断を明示する。
- 公開runbookへ依存更新policyを記録する。
- PR #17 / #18を後継PRへの説明付きでcloseする。

### やらないこと

- PR #17 / #18上で暗号API移行を行わない。
- exact pin、`--locked`、暗号release gateを緩和しない。
- Rust / FRB / wire / DB APIを変更しない。
- GitHub Actions更新PR #23を変更しない。

## 5. 実装手順

1. 最新mainから専用branch / worktreeを作成する。
2. Dependabotのroot / fuzz定義を統合し、version / security groupと更新制限を設定する。
3. pin checkのroot / fuzz診断とrunbookを更新する。
4. ローカル品質gateと独立検証を通す。
5. merge後にDependabot更新を実行し、両lockfileを含む単一PRになることを確認する。
6. 横断更新が成立しない場合はCargo version updateを停止し、security updateと手動更新へfail closedする。

## 6. 受け入れ基準

- Dependabot Cargo設定が`/`と`/fuzz`を単一entryで扱う。
- version updateがdependency-name単位、security updateが抑止されない。
- protected dependencyの通常minor / major updateが自動提案されない。
- root / fuzzのどちらがstaleかpin checkの失敗メッセージで判別できる。
- root / fuzz双方のlocked metadata、暗号release gate、共通品質gateが成功する。
- 実生成されたDependabot patch PRが両lockfileを含むか、決定済みfallbackが適用される。
- 独立検証が合格する。

## 7. 制約・注意事項

- security updateをignoreしない。
- Dependabot固有の挙動を推測だけで合格にせず、merge後の生成PRで確認する。
- 不完全な自動PRのためにlock検証や暗号gateを緩和しない。
- public repoへprivate情報を含めない。

## 8. 完了報告に含めるべき内容

- 設定したdirectory / group / ignore policy。
- root / fuzz lock検証と全品質gateの結果。
- Dependabot再実行結果、またはfallback適用結果。
- PR #17 / #18のclose結果。
- 独立検証の判定と根拠。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-17
- 結果: Cargoのroot / fuzz更新を単一設定へ統合し、version updateをdependency-name単位、security updateを全依存group、protected dependencyの通常更新をpatch限定にした。両lockfileの`--locked`検証とrelease gateは維持し、失敗対象を診断できるようにした。
- 証拠: YAML構造検証、pin check、root / fuzz locked metadata、`cargo fmt`、`cargo clippy`、`cargo test`、`cargo audit --deny warnings`、bridge release build、Flutter analyze / 253 tests、client boundary gatesが成功した。parser fuzzは61秒で384,932 runs、crashなしだった。
- Commit: `064044b`
- 未解決: merge後に実生成されるDependabot PRの両lockfile更新を確認する。成立しなければversion update停止fallbackを適用する。確認後にPR #17 / #18を説明付きでcloseし、本work itemを`done`へ更新する。

### 独立検証

- 判定: 合格（ローカル変更。remote実PR確認は未完了）
- 根拠: 実装を担当していないエージェントがDependabot設定をGitHub公式仕様と照合し、YAML構造、`git diff --check`、shell構文、pin check、front matterを再実行して指摘なしと判定した。
- 検証者: independent_stage1_review agent
