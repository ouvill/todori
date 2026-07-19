# task-99 エレガントUI全面再設計

> ステータス: 完了（Home挙動を維持したエレガントUI全面再設計）
> 作業日: 2026-07-11

## 1. 背景とコンテキスト

現行アプリは機能とHomeのタスク管理挙動を優先して構築されており、画面全体の視覚階層、密度、余白、面の使い分けが粗い。プロダクトオーナーは2026-07-11に、Homeのタスクツリーと完了体験を維持しながら、既存デザインへ拘束されない抜本的なUI再設計を指示した。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/design/ui-spec.md`
- `docs/design/visual-direction.md`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/ui/task_components.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`

## 3. ゴール

- Taskveilを静かで温かく、日常的に使えるエレガントなTODOアプリとして再構成する。
- Homeの期日セクション、サブタスクツリー、完了Undo、チェック起点の完了モーションを保持する。
- Home、リスト、タスク詳細、作成シート、ダイアログの視覚言語を同じトークンへ統一する。

## 4. スコープ

### やること

- 色、タイポグラフィ、面、border、操作部品のテーマ再設計。
- Homeヘッダー、セクション、タスク行、空状態、クイック追加の再設計。
- リスト管理、タスク詳細、作成シート、ダイアログへ共通テーマを反映。
- 既存のLucide、Inter、Newsreader、flutter_animateを活用した応答性とモーションの調整。
- Home / Lists / Accountを統合するレスポンシブアプリシェルと、画面階層ごとの遷移演出。
- widget testとvisual QAの期待値を、挙動を維持したまま新構造へ追従。

### やらないこと

- タスク、リスト、同期、暗号、DB schema、FRB APIの変更。
- カレンダー、Focus timer、検索等の未実装機能追加。
- 常駐マスコットの導入。
- dark modeの正式サポート化。

## 5. 実装手順

1. 改修前のvisual QA一式を `app/build/visual_qa_before/` へ保存する。
2. 既存ブランド色を保ちながら、warm surface主体の階層へthemeを再構成する。
3. Homeを巨大な囲みカードから解放し、ヘッダー、期日セクション、ツリー行、空状態を再実装する。
4. Quick Add、リスト、詳細、シート、ダイアログを共通の密度と角丸へ揃える。
5. widget test、静的検査、visual QAを実行し、全PNGを目視する。

## 6. 受け入れ基準

- [x] HomeでOverdue / Today / Tomorrow / Upcomingの挙動と各タスク最大1回表示が維持される。
- [x] Homeのサブタスクが接続線を伴うツリーとして読み取れ、長い日英タイトルでも破綻しない。
- [x] チェックONでチェック描画、局所パーティクル、左から右の取り消し線、退場、Undoが維持される。
- [x] 空のHomeが0件セクションの羅列ではなく、次の操作が明確な静かな空状態になる。
- [x] Homeの大きな一枚カードを廃止し、セクションと行の視覚階層がスクリーンショットで判別できる。
- [x] Quick Add、リスト、詳細、シート、ダイアログが同じ色・角丸・border・タイポグラフィ体系で表示される。
- [x] モバイルはNavigationBar、幅720px以上はNavigationRailでHome / Lists / Accountへ直接移動できる。
- [x] トップレベル、リスト内、詳細で異なる目的に沿った遷移があり、詳細ではグローバルナビゲーションが隠れる。
- [x] 390x844、text scale 2.0、日本語でoverflowや操作不能がない。
- [x] tooltip、semantics、48px級タップ領域、色以外の情報伝達を維持する。
- [x] Flutter品質ゲートと `git diff --check` が成功する。
- [x] `app/build/visual_qa_before/` と `app/build/visual_qa/` の全PNGを目視比較する。

## 7. 制約・注意事項

- Homeのデータ選別、ツリー構築、完了操作の非同期制御は変更しない。
- UI文字列を追加する場合は英日ARBへ追加し、`flutter gen-l10n` を実行する。
- 既存承認済み依存と同梱フォントを優先し、新規依存は必要性が明確な場合だけ追加する。
- 画面全体confetti、heavy shadow、card-in-card、常駐セキュリティ表示は導入しない。

## 8. 完了報告に含めるべき内容

- 変更した画面と共通トークン。
- 保持したHome挙動と完了モーション。
- before / afterスクリーンショットの保存先と目視所見。
- 実行した品質ゲートと結果。
- 独立検証の判定と指摘。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-11
- 結果: warm neutral主体のthemeへ更新し、Homeを日付キッカー + display見出し、余白で分けた期日セクション、軽い独立task surface、浮遊Quick Add、単独空状態へ再設計した。Lists、Task detail、sheet、dialogも共通のsurface / radius / typographyへ統一した。
- IA追補: Home / Lists / Accountを同格のグローバル領域へ変更し、モバイルNavigationBar / ワイドNavigationRailを実装した。トップレベルはfade + 短い縦移動、リスト内はslide + fade、詳細はfade + scaleで遷移し、詳細ではシェルを隠す。
- 保持した挙動: Homeの4期日セクション、各タスク最大1回表示、サブタスクツリー、完了確認、Undo、チェックpath、局所パーティクル、左から右の取り消し線、Reduce Motionを維持した。
- 証拠: before=`app/build/visual_qa_before/`（47 PNG）、after=`app/build/visual_qa/`（49 PNG）。visual QA 47テストに成功し、Home英日、空状態、text scale 2.0、Lists、Task detail、create sheet、完了3フレーム、ワイド画面のNavigationRailを目視確認した。
- 仕様同期: `docs/design/ui-spec.md` を2026-07-11人間裁定と新しい実装値へ更新した。
- Commits: `c43a655`（UI再設計本体）、`e1e1588`（IA・画面遷移追補）
- 未解決: なし。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功。sandbox内ではDocker接続が拒否されたため、承認付き環境で再実行してserver統合testを含め成功。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功。
- `cd app && flutter analyze`: 成功。
- `cd app && flutter test --concurrency=1`: 130件成功、visual QA 1件は設計どおり環境変数未指定でskip。既定並列実行で同一fake IDを使う画面test間の干渉が出たため、最終判定は逐次隔離実行を使用した。
- `sh app/tool/visual_qa.sh`: 47件成功。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `sh app/tool/check_client_boundaries.sh`: 成功。
- `sh app/tool/test_client_boundaries.sh`: 成功。
- `git diff --check`: 成功。

### 独立検証

- 判定: 合格（P1なし / P2なし、非ブロッキングP3も最終修正済み）。
- 根拠: verifierが指定after / before PNG、完了3フレーム、モバイルNavigationBar、ワイドNavigationRail、詳細でのshell非表示、階層別遷移、実装差分、widget test、仕様同期、48pxタップ領域、生成target除外を確認した。初回指摘の旧UI spec不整合、44pxセクションタップ領域、`app/target`未追跡と、追補時のvisual QA件数表記を修正し、再検証で合格した。
- 検証者: 実装を担当していない独立検証エージェント。
