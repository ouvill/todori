# Todori 開発ステータス

> 更新日: 2026-07-17

UUIDv7 work item方式のpilot中である。長期計画はPhase計画書、設計判断はADR、新形式work itemの状態は各 `work-*.md` のfront matter、完了履歴はtask本文とgitを参照する。このファイルにはpilot前の進捗スナップショットと人間作業だけを残す。

## 現在

- 進行中: なし。
- 保留: なし。
- 最新の完了: **task-108 Focus / Timer Visual Refinement** — Focus全状態をwarm open-dialへ統一し、全品質ゲート、Visual QA、iOS Simulator motionの独立検証まで完了した。
- Phase 1: M1〜M4完了。M5リリース準備は課金基盤完成後まで延期する。
- Phase 2: P2-M1〜M4・M6・M7完了。P2-M5は削除同期、macOS / iOS Simulator確認、Android Rust FFI / Flutter release APK build、Android Keystore実装まで完了した。Android接続実機でのKeystore instrumentation test、Device Key rotation / DB reopen、同期確認が残る。P2-M8テンプレート / 繰り返しは未着手である。
- 一般リリースゲート: **Billing foundation release gate**。課金基盤、iOS sandbox E2E、server-side entitlement、失効時認可が完了するまでstore提出、release tag、公開告知を行わない。

## UUIDv7 work item pilot

pilot対象の候補と状態は新形式work itemだけに記録する。次のコマンドで確認する。

```sh
rg -n '^status: (backlog|active|blocked)$' docs/tasks/work-*.md
```

`STATUS.md` へNext一覧を重複転記しない。pilot合格後の全面移行と、このファイルの廃止判断は別work itemで扱う。

## 人間作業・判断

- iOS実機で通知、Keychainゼロプロンプト、同期を通し確認する。
- AWS / Neon本番デプロイと前段構成を決定する。
- RevenueCat / App Store商品を承認済み価格、初回trialなし、16日Billing Grace Periodの契約どおりに設定してsandbox E2Eを完了する。
- Android接続実機で`connectedDebugAndroidTest`を実行し、Keystore鍵の非export性、active / pending capsuleのroundtripを確認する。
- Android実機でDevice Key rotation、プロセス再起動後のDB reopen、同期動作を確認する。

## 作業開始時に読むもの

1. `AGENTS.md`
2. 対応するPhase計画書・技術仕様・ADR
3. 対象の `work-*.md`、または既存の `task-*.md`
4. `PLAYBOOK.md`（標準・重要変更レーンの場合）
5. この `STATUS.md` / `BACKLOG.md`（pilot移行情報やlegacy候補が必要な場合だけ）
