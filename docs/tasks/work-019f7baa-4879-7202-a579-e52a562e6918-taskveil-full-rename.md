---
id: 019f7baa-4879-7202-a579-e52a562e6918
title: Taskveil full product and technical rename
status: active
lane: critical
milestone: maintenance
---

# Taskveil full product and technical rename

## 1. 背景とコンテキスト

一般リリース前に製品名をTaskveilへ変更する。将来の運用で旧名称が製品、package、暗号、同期、DB、CI、文書に混在しないよう、現行の全追跡ファイルとパスを一括移行する。プロダクトオーナーは、端末とpre-release server環境のデータ初期化、暗号・wire・storage identifierのbreaking change、過去task文書の現行名称への置換を承認した。Gitの過去commitは書き換えない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/03_技術仕様書.md`
- `docs/05_設計判断記録.md`
- `docs/ops/crypto-release-gate.md`

## 3. ゴール

製品、公開API、package、binary、platform identity、課金商品、環境変数、HTTP / realtime protocol、暗号context、local storage、DB namespace、CI、public/private文書と追跡pathをTaskveilへ統一する。public/private両repositoryの現行追跡ファイルに旧名称を残さない。

## 4. スコープ

### やること

- UI、通知、platform metadata、brand asset pathをTaskveilへ変更する。
- Dart、Rust、FRB、CLI、server、worker、MCP、fuzz、CIのpackage / type / binary名を変更する。
- Bundle ID、billing product ID、Keychain / Keystore、HKDF、AAD、JWT、header、DB role / setting、環境変数を変更する。
- public/privateの全追跡文書と追跡pathを変更する。
- pre-release local/server/sandbox dataを移行せず再作成する。
- GitHub repository名とremoteを最終検証後に変更する。

### やらないこと

- Git commit historyをrewriteしない。
- 旧identifierのalias、fallback、dual read/writeを追加しない。
- 商標登録を実施しない。

## 5. 実装手順

1. 変更前の追跡ファイル、path、external environmentをinventoryする。
2. 全contentとpathをTaskveilへ機械的に移行し、identifier別の期待値へ正規化する。
3. l10n、FRB、lockfile、platform生成物を正規手順で再生成する。
4. 旧名称0件検査と全品質gateを実行する。
5. 明示したpre-release環境だけを初期化し、GitHub repositoryとremoteを変更する。
6. 独立検証後に完了報告を記録する。

## 6. 受け入れ基準

- public/private両repositoryで、追跡ファイル内容とpathの旧名称検索が0件になる。
- `TaskveilClient`、`taskveil_app_bridge`、`com.taskveil.app`、`TASKVEIL_*`、`X-Taskveil-*`、`taskveil.*`が各層で一貫する。
- Flutter / FRB / Rust / server / realtime worker / CI boundaryの全gateが成功する。
- Android、Apple、Linuxのmetadataとlocal key/storage identifierが新名称へ一致する。
- pre-release環境のreset対象と結果、未実施のexternal作業が明記される。
- 実装者と異なるreviewerの独立検証が合格する。

## 7. 制約・注意事項

- 本work itemは暗号、鍵、同期、DB、課金、public/private境界、データ損失を含むcritical変更である。
- production相当環境を発見した場合は削除せず停止して確認する。
- 秘密値やprivate事業詳細をpublic repoへ記載しない。
- 旧名称を残す例外はGit historyだけとし、現行追跡ファイルには許可リストを設けない。

## 8. 完了報告に含めるべき内容

- 変更したidentifier一覧と旧名称0件の証拠。
- 生成と全品質gateのcommand / 結果。
- resetしたlocal / server / sandbox環境の正確な対象。
- GitHub repository rename、remote、redirect確認結果。
- 独立検証者、判定、未解決risk。

## 9. 実装・検証記録（2026-07-20）

### 9.1 実装結果

- 製品表記、domain、Dart / Rust package、公開client型、FRB bridge、CLI / server / worker、Bundle ID、billing product ID、環境変数、HTTP header、JWT / signature domain、DB namespace、暗号・local storage identifierをTaskveilへ統一した。
- ARBを正本として生成l10nを再生成し、FRB生成物、Cargo / Flutter / npm / CocoaPods lockfileとplatform設定を更新した。
- public / private / local workspace repositoryの現行追跡文書とbrand asset pathを更新した。Git commit historyは変更していない。
- GitHub repositoryを`ouvill/taskveil`と`ouvill/taskveil-private`へ変更し、両local remoteを新URLへ更新した。変更前URLのredirectと新URLが同じHEADを返すことを確認した。

### 9.2 品質gate

- `cargo fmt --all -- --check`
- `cargo check --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`
- `cargo audit --deny warnings`
- pinned nightlyによる`crypto_parsers` fuzz 60秒run
- `flutter analyze`、Flutter test 275件成功・Visual QA harness 1件skip
- `tool/visual_qa.sh`による106 screenshot scenario
- iOS Simulator debug build、Android debug APK build、macOS unsigned debug build
- realtime worker unit test 12件、typecheck、Wrangler dry-run build
- hardcoded string、client boundary、crypto dependency pin、secret pattern、CI change classifier検査

上記はすべて成功した。Linux native build、signed Apple build、実端末での購入・通知・同期E2Eは対象platform / credentialを用いるrelease gateで継続する。

### 9.3 reset結果

- localhost限定の開発PostgreSQL containerと匿名volumeを削除し、他のcontainerが存在しないことを確認した。
- boot済みiOS Simulatorから旧application identityのapp dataをuninstallで削除した。
- 接続Android端末には新旧いずれのapplication packageも存在しなかった。
- macOSの旧application support DB群とpreferences plistをTrashへ移動した。TCCで保護されたcontainerには約516 KiBのframework cacheと一時directoryが残るため、必要なら利用者がFull Disk Access付きでcontainer全体を削除する。
- 旧Apple Keychain serviceの対象itemが存在しないことを確認した。
- production相当のlocal containerは発見されなかった。Cloudflare credentialが未設定であり、remote pre-release resourceの列挙・削除は未実施である。

### 9.4 未完了gate

- RevenueCatとApp Store Connectは未認証sessionだったため、新しいapp / product作成とsandbox E2Eは未実施である。承認済みStore設定の具体条件はprivate正本で管理する。
- 実装者と異なるreviewerの初回独立検証はFAILとなったが、指摘6件の修正後に再レビューPASS・新規findingなしを確認した。独立検証gateは完了した。
- external Store設定とremote pre-release環境確認が完了するまで本work itemは`active`を維持する。

### 9.5 初回独立レビューの修正

- Android JNI exportを`com.taskveil.app.AndroidCapsuleStore`と一致させ、再生成APK内のsymbolとPixel 7a上のKeystore instrumentation 2件を確認した。
- ASCII表記に加えて日本語の旧製品表記と旧名称由来をpublic/private追跡文書から除去した。
- Bundle ID `com.taskveil.app`とdomain `taskveil.com`をprivate正本で分離した。
- Taskveil namespace v1のHKDF、key wrap AAD、Keychain、Keystore alias、preferences、Android AADをAGENTS・設計文書・実装・golden vectorへ固定した。暗号suite、sync protocol、DB schema、capsule plaintext形式のversionは独立して維持する。
- Android、iOS、macOS、Linuxのユーザー向け表示名を`Taskveil`へ統一し、Android APKとmacOS unsigned debug appを再buildした。
- 新規public work itemからprivate siblingの直接参照と具体的な非公開Store条件を除去した。
- 実装者と異なるreviewerが上記6件を再検査し、すべてPASS・新規findingなしと判定した。
