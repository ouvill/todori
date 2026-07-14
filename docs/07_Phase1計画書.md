# Phase 1計画書

E2EE Todoアプリ「Todori」のPhase 1（MVP）を、実装可能なマイルストーンと検証可能な完了条件に分解する。Phase 1はローカル専用版であり、同期・アカウント・課金は扱わない。

## 1. Phase 1スコープ

Phase 1の先行プラットフォームはiOSとする（`docs/01_企画書.md` §8、公開向けの法務・OSS方針は `docs/legal_overview.md` を参照）。開発ホストはmacOSであるため、iOSビルドとSimulator/実機確認をローカルで実施できる。日常のdogfoodingと自動テスト用にはmacOSデスクトップビルドを維持する。

| 分類 | Phase 1に含める機能 | 判断 |
|---|---|---|
| UI | 初回はシンプルUI固定に近い導線で開始し、F-02を実装する。F-01のUIモード選択は設定値の保存口のみ用意し、高機能UI（F-03）への実画面遷移はPhase 3へ送る | MVPの迷いを減らすため |
| タスク管理 | タスクCRUD（F-05）、サブタスク、`done` / `wont_do` / 再オープン（F-06）、削除・Undo（F-07、2026-07-07仕様改訂: ゴミ箱廃止・恒久削除。`docs/05_設計判断記録.md` ADR-009参照）、並び替え（F-08） | 企画書§8の中核 |
| リスト | リストCRUDと既定インボックス（F-09） | ローカルTodoとして必須 |
| タグ | F-10はPhase 3へ送る | 企画書§8のMVP記述外で、検索/フィルタUIの複雑度が高い |
| 全文検索 | Phase 1ではF-11の技術基盤のみM1で検証し、ユーザー向け検索UIを後続へ送った。その後task-103で先行実装済み | SQLCipher + FTS5の技術リスクを早期に潰し、製品UIは後続の没入型Searchとして実装した |
| 通知 | ローカル通知（F-24）、複数通知時刻・スヌーズの最小版（F-25）、iOS通知を先行。デスクトップ通知（F-26）はmacOS dogfooding用の動作確認に留める | E2EE設計上ローカル通知が正となるため |
| セキュリティ | Device Key + SQLCipherによる保存時暗号化（`docs/03_技術仕様書.md` §5、§7.1） | Phase 1の必須要件 |
| アプリロック | F-43はPhase 1.5候補へ送る | iOS生体認証/Keychain統合のリスクが高く、保存時暗号化とは独立に出せる |
| i18n | en/jaのi18n基盤（F-48）を初期から導入 | 企画書§3、技術仕様書§1.4と整合 |
| アクセシビリティ | F-49は最低限のSemantics、Dynamic Type追従、コントラスト確認をPhase 1に含める | 後付けが難しいため |
| 非機能 | 起動2秒以内（F-50）、1万件リストの60fps目標（F-51）、オフライン動作（F-52）を検証する。クラッシュレポート（F-53）はオプトイン設計のみPhase 1で決め、実送信はリリース準備へ送る | ローカル専用MVPの品質ゲート |

## 2. スコープ外

Phase 1では、同期・アカウント機能（F-27〜F-31）、Organization共有（F-32〜F-35）、課金（公開向け概要は `docs/billing_overview.md`）、カレンダー表示（F-13）、Pomodoro/タイマー（F-16〜F-18）、テンプレート・繰り返し（F-19〜F-21）、ローカルAI（F-36〜F-39）、MCP/CLIの実機能（F-40, F-41）は実装しない。`cli/` と `mcp-server/` の雛形crateは存在するが、Phase 1ではローカルDB実操作の接続対象にしない。

## 3. PoC結果への依存

| PoC | Phase 1への影響 | 現状 |
|---|---|---|
| task-01 OPAQUE認証PoC | Phase 1はローカル専用のため直接使わない。Phase 2移行時の `core/crypto` 設計に影響する | `opaque-ke 3.0.0` + Argon2 + Ristretto255で登録/ログイン/exportKey/MK wrapを検証済み。`ServerSetup` 128 bytes、サーバーログイン状態 192 bytes |
| task-02 SQLCipher PoC | M1の前提。`core/storage` の暗号化DB、FTS5、repository実装に直結する | host / iOS Simulator core test、iOS実機target link、Android Rust FFI buildまで成功。iOS / Android cross-build CIと実機継続検証が残る |
| task-03 flutter_rust_bridge PoC | M2の前提。Flutter UIからRust coreを呼ぶ全機能の基礎 | `flutter_rust_bridge 2.12.0`のproduction API、macOS実行、iOS Simulator build / install / launchまで接続済み。iOS実機とAndroid Flutter build / 実機検証が残る |

補足（2026-07-04 iOS実行検証、その後の更新を反映）: `aarch64-apple-ios-sim`向けクロスビルド（vendored OpenSSL/SQLCipher含む）、Simulator上のcrypto / storage test、実機target linkが成功した。その後、cargokit経由のiOS Simulator build / install / launchとproduction UI起動まで確認した。残るiOS固有作業は実機でのKeychain、通知、購入・復元、同期の通し確認である。

## 4. マイルストーン

### M1: コア層完成

| ID | 内容 | 依存タスク | 完了条件 |
|---|---|---|---|
| M1-01 | `core/domain` にリスト/タスク操作ユースケースを追加する | なし | ユースケース単体テストでCRUD、ステータス遷移、サブタスク制約が通ること |
| M1-02 | SQLCipherスキーマをPhase 1対象テーブルへ拡張する | task-02 | `cargo test -p todori-storage` で暗号化DB、誤鍵失敗、FTS5、repository roundtripが通ること |
| M1-03 | リスト/タスク/ゴミ箱/Undo用repositoryを実装する | M1-01, M1-02 | insert/get/update/delete/restoreの統合テストがDB永続化込みで通ること |
| M1-04 | DK生成、OSキーチェーン保存、SQLCipher鍵導出の抽象を定義する | M1-02 | 開発ホスト上のテストダブルでDK生成からDB openまでのテストが通ること |

### M2: ブリッジとUI骨格

| ID | 内容 | 依存タスク | 完了条件 |
|---|---|---|---|
| M2-01 | `flutter_rust_bridge` の再生成手順とCIキャッシュ方針を固定する | task-03 | `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml` が差分なしで再実行できること |
| M2-02 | Rust APIをユースケース単位に公開する | M1-01, M2-01 | Dartテストからリスト作成、タスク作成、取得が呼べること |
| M2-03 | Flutterの画面遷移骨格と状態管理方針を実装する | M2-02 | リスト一覧、タスク一覧、タスク詳細へ遷移できるwidget testが通ること |
| M2-04 | i18n基盤を導入する | なし | en/ja ARBで主要画面文字列が切替可能で、UI文字列の直書き検出が通ること |

### M3: 機能完成

| ID | 内容 | 依存タスク | 完了条件 |
|---|---|---|---|
| M3-01 | リストCRUD UIを実装する | M2-03 | 画面からリスト作成/名称変更/削除ができ、DBに反映されること |
| M3-02 | タスクCRUD UIを実装する | M1-03, M2-03 | 画面からタスク作成/編集/削除/復元ができ、DBに反映されること |
| M3-03 | サブタスク無制限階層と進捗表示を実装する | M3-02 | 3階層以上のサブタスク作成、親完了時の確認、進捗率表示のwidget testが通ること |
| M3-04 | `done` / `wont_do` / 再オープン操作を実装する | M3-02 | 各ステータス遷移がUIから実行でき、禁止遷移が表示上選べないこと |
| M3-05 | Undoと手動/条件並び替えを実装する | M3-02 | 削除/完了/編集のUndoと、手動/締切/優先度/作成順ソートのテストが通ること |

### M4: 通知・暗号化・磨き込み

| ID | 内容 | 依存タスク | 完了条件 |
|---|---|---|---|
| M4-01 | iOSローカル通知とスヌーズ最小版を実装する | M3-02 | iOS実機/Simulatorで通知登録、通知取消、スヌーズ再登録を確認できること |
| M4-02 | DK + SQLCipher鍵管理を本実装する | M1-04 | アプリ再起動後も正しい鍵でDBを開け、別鍵/平文SQLiteで読めない自動テストが通ること |
| M4-03 | アクセシビリティ最低基準を満たす | M2-04, M3-01 | Dynamic Type、スクリーンリーダーラベル、コントラストの確認項目が通ること |
| M4-04 | 性能検証を行う | M3-05 | 1万件データで起動2秒以内、主要リスト操作60fps目標を計測し、結果を記録すること |

### M5: リリース準備（課金基盤完成後へ延期）

2026-07-15のプロダクトオーナー決定により、M5はPhase 1のローカル基盤完了直後には実行せず、課金基盤のrelease gate合格後に行う。Phase 1の製品実装範囲へ課金を混在させるのではなく、一般リリースの前提としてiOS購入・復元、server-side entitlement、失効時認可を別work itemで完成させる。

| ID | 内容 | 依存タスク | 完了条件 |
|---|---|---|---|
| M5-01 | iOSビルド/署名/ストア提出準備を整える | M4、課金release gate | macOS環境でReleaseビルドが成功し、ストア提出前のコンプライアンス確認項目が整理されていること |
| M5-02 | macOS dogfoodingビルドを配布可能にする | M4 | macOS desktopで主要操作が通り、既知差分がリリースノートに記録されていること |
| M5-03 | クラッシュレポート方針を確定する | M4 | F-53のオプトイン文言、PII除去対象、Phase 1で実送信するかの判断が記録されていること |

## 5. リスクと先送り判断

| リスク | 影響 | 対策または判断 |
|---|---|---|
| SQLCipherのiOS/Androidビルド差分 | target更新でリリース不能になり得る | iOS Simulatorのcore test、iOS実機target link、Android Rust FFI buildは成功済み。継続的なiOS / Android cross-build CIは別work itemで残る |
| flutter_rust_bridgeのプラットフォーム組み込み | UIからcoreを呼べない | cargokit経由のmacOS実行、iOS Simulator build / install / launch、production UI起動まで確認済み。残るrelease確認はiOS実機とAndroid Flutter実機である。命名制約: crate名/pod名/FRB stemは `todori_app_bridge` で一致させる |
| ローカル通知のOS制限 | 期待時刻に通知されない | Phase 1はiOS先行で実機確認を必須にし、Desktop通知はdogfooding扱いにする |
| UIモード切替の設計負債化 | Phase 3で高機能UI追加時に作り直し | Phase 1では状態管理とルーティングにモード拡張点だけ用意し、高機能画面は実装しない |
| タグ/全文検索/アプリロックの範囲膨張 | MVP完了が遅れる | Phase 1ではタグと検索UIを後続へ、アプリロックをPhase 1.5候補へ送った。検索UIはtask-103で先行実装済み、タグとアプリロックは未実装 |
| パスワード紛失UX | Phase 1ローカル専用では対象外 | OPAQUE/Recovery KeyはPhase 2で扱う。Phase 1ではDK/OSキーチェーン復旧不可の注意表示を検討する |

## 6. 既存仕様書との差異・確認事項

- `docs/01_企画書.md` §8はPhase 1概要に全文検索・タグ・アプリロックを明記していない一方、`docs/02_機能仕様書.md` の対象F番号には含まれる。Phase 1では後続へ送り、検索UIだけはtask-103で先行実装した。タグとアプリロックは未実装である。
- SQLCipherとFRBのhost / iOS / Android基礎検証は成立した。残る継続検証はiOS / Android cross-build CI、iOS / Android実機、Android Keystoreであり、一般リリースはさらに課金release gateへ依存する。
- `docs/03_技術仕様書.md` §1.5はOPAQUE中間状態をPostgres ephemeral tableへ保存するとしており、task-01のDynamoDB想定とは異なる。本計画では最新の技術仕様書を正とし、Phase 2実装時はPostgres保存を前提にする。
- 2026-07-07仕様改訂のゴミ箱廃止、明示確認付き恒久削除、削除Undoなし、リストアーカイブは、task-37 / task-38で実装済みである。既存M3マイルストーンの過去の完了条件文言は履歴として維持する。
