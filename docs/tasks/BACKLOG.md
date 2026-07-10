# Todori バックログ

Next以外の未着手候補だけを置く。現在と次の3件は [`STATUS.md`](./STATUS.md)、完了履歴は既存 `task-*.md` とgit、マイルストーンは [`docs/07_Phase1計画書.md`](../07_Phase1計画書.md) / [`docs/08_Phase2計画書.md`](../08_Phase2計画書.md) を正本とする。

## 運用ルール

- 完了項目をこのファイルへ残さない。
- 候補を `STATUS.md` のNextへ移す時にこのファイルから削除し、状態を重複させない。
- task番号は実装着手が決まった時点で採番する。候補段階では採番しない。
- Laterは最大20件を目安とする。上限を超えたら優先度を付けずIceboxへ移す。
- 仕様変更・依存追加・暗号・鍵・課金・public/private境界は、人間承認後にtaskへ昇格する。
- taskの結果はtask文書とgitへ残す。

## Later

| 候補 | 内容 | 出典・依存 |
|---|---|---|
| Fuzzy-scan full resync / GC horizon | stable-key current-state scan、`base_seq` 後delta、page transactionのhigh-water closure、outbox除外付きmark-and-sweep、push前preflightを実装する | ADR-010 / ADR-012。transactional client、field clock / placement、typed pull / quarantineの完了後 |
| Aggregate削除scope / epoch設計 | 別端末の未知descendantも含むlist/subtree削除intent、復活規約、opaque scope metadata、tombstone GC、List DEK bundle保持/削除条件を別ADRで裁定する | ADR-009 / ADR-010 / ADR-012。裁定まではList DEK bundleを削除しない |
| 同期server RLS hardening | non-owner application role、実際のRLS policy、必要なFORCE RLS、cross-tenant testを実装する | ADR-012。protocol v2 CAS / collection immutabilityはtask-86で完了 |
| デフォルトInbox重複の方針決定 | 端末ごとに生成されたdefault listの一意化・マージ・表示統合のどれを採用するか裁定する | task-79未解決事項 |
| Windows / Linux本番Device Key Store | Windows current-user DPAPI、Linux Secret Serviceを実装し、平文 `device.key` / account secret fileを本番経路から除外する | ADR-011 / task-81。新規依存は人間承認が必要 |
| CLI実接続 | 共通client/profile層からFlutter desktopと同じSQLCipher DBを開き、CRUD・検索・同期を提供する。macOSは同一Team / Keychain access groupで署名する | ADR-011。共通client/profileとOS secret storeに依存 |
| MCPサーバー実接続 | CLIと同じ共通client/profile層からタスクCRUD・検索・同期をstdio MCPとして公開する | FTS5 task-62、sync task-72、ADR-011に依存 |
| サーバーのデバイス行重複排除 | 同一インストールからの再ログインで既存device rowを再利用する | 2026-07-10実機同期確認 |
| Android Keystore DeviceKeyStore | Androidの開発用 `FileDeviceKeyStore` を本番用Android Keystore実装へ置き換える | 技術仕様§4.3 / task-74 |
| SQLCipherクロスビルドCI | iOS / AndroidのSQLCipherビルド差分をCIで継続検証する | Phase 1計画書§6 |
| オンボーディング / 初回起動体験 | DK復旧不可の注意表示を含む初回体験を設計・実装する | Phase 1計画書§5、2026-07-06人間裁定 |
| Phase 1リリース前のlight固定 | ダークモード正式対応まで `themeMode` をlight固定する | 2026-07-06人間裁定 |
| iOSリリース準備 | release build、署名、ストア提出前コンプライアンスを確認する | M5-01。人間作業を含む |
| macOS dogfooding配布 | macOS desktop buildを配布し、既知差分をリリースノートへ記録する | M5-02。人間判断を含む |
| クラッシュレポート方針 | F-53のオプトイン、PII除去、実送信有無を確定する | M5-03。法務・プライバシー判断を含む |
| P2-M6 カレンダー表示 | 月 / 週表示、due / scheduled表示、日付変更、同期反映を実装する | Phase 2計画書 P2-M6 / F-13 |
| P2-M7 タイマー / Pomodoro | Pomodoro、通常タイマー、見積対実績、Focus Timer UIを実装する | Phase 2計画書 P2-M7 / F-16〜F-18 |
| P2-M8 テンプレート / 繰り返し | テンプレート、RRULE準拠生成、streak、重複生成防止を実装する | Phase 2計画書 P2-M8 / F-19〜F-21 |

## Quick fixes

task文書へ昇格せず、軽量レーンで処理できる候補である。

- Closed見出しの `Closed 2 closed` のような冗長表記を整理する。出典: 2026-07-07親レビュー。

## Icebox

優先順位を付けない。四半期またはマイルストーン境界で残す価値を再評価する。

- 自然言語日付入力（`tomorrow` / `next Friday` / `明日` 等）。出典: task-52スコープ外。
- タスク行右側affordanceをchevron継続とするかFocus開始ボタンへ変えるか。出典: design direction / UI spec。
- リストへプロジェクト型 / エリア型の区別を導入するか。出典: 2026-07-07人間コメント。

## 人間作業・判断の詳細

- iOS実機でKeychain鍵保持、署名付きゼロプロンプト、通知、同期を確認する。出典: task-64 / 65 / 77。
- Android実機で同期動作を確認する。出典: task-74。
- AWS / ECR / Lambda / Neonへ本番デプロイし、WAF / API Gateway / CloudFront前段を確定する。出典: Phase 2計画書。
- 課金 / IAP / 外部課金 / レシート検証をprivate側事業設計と合わせて確定する。出典: Phase 2計画書 / `docs/billing_overview.md`。
- coral / amber系表示のコントラストを裁定する。出典: task-66。
- `~/.codex/config.toml` へ `~/.cargo` を追加するか判断する（任意）。

## 補充ルール

候補の供給源は次に限定する。

1. Phase計画書の未達マイルストーン
2. task完了報告の未解決事項
3. ADRの帰結・後続実装
4. ドッグフーディングで確認された具体的な問題
5. プロダクトオーナーの明示的な決定

出典のない候補を追加しない。追加時点ではtask文書を作らず、`STATUS.md` のNextへ昇格して着手が決まった段階で作成する。
