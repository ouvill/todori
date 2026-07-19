# task-89: 初回オンボーディング

> ステータス: 完了（初回オンボーディング実装、独立再検証合格）
> 作業日: 2026-07-10

## 1. 背景とコンテキスト

Taskveilは暗号化・同期・日常のタスク操作を実装しているが、初回起動時は説明なくHomeへ入る。E2EEアプリでは、通常画面へlock表示を常駐させず、初回だけ「ローカル保存」「同期時の暗号化」「ローカル専用データの復旧限界」を平易に伝える必要がある。デザイン面でも、通常画面の情報密度を上げずにTaskveilの静かで親しみやすい第一印象を作れる場所はオンボーディングである。

本taskは2026-07-10のプロダクトオーナー指示「E2EEのTODOアプリを、オシャレで洗練され、触って喜びを感じるものにする」を、既存のdesign sourceとバックログ候補「オンボーディング / 初回起動体験」へ接続して着手する標準変更レーンである。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/{STATUS,README,PLAYBOOK,DESIGN_PLAYBOOK}.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` §1 / §5
- `docs/design/{visual-direction,ui-spec}.md`
- `app/lib/main.dart`
- `app/lib/src/core/providers.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/l10n/app_{en,ja}.arb`
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`

## 3. ゴール

- 初回起動時だけ、通常Homeの前にTaskveilの価値とプライバシー境界を伝える。
- 既存のsage / warm white / deep green、Newsreader / Inter、既存radius / spacingだけで、静かでエレガントな第一印象を作る。
- 完了状態をSQLCipher内の既存`settings`へ保存し、2回目以降は日常起動を無音・無介入にする。

## 4. スコープ

### やること

- 3ページ以内の初回オンボーディング画面をFlutterで追加する。
- 価値訴求、ローカルDBの保存時暗号化、同期時のE2EE、ローカル専用データの復旧限界を過大主張なくen/jaで伝える。
- `onboarding_completed`相当の端末ローカル設定を既存`SettingsRepository`経由で保存する。
- 完了前に設定保存が失敗した場合はHomeへ遷移せず、再試行可能なエラーを表示する。
- ページ位置、CTA、イラスト相当の抽象markへsemanticsを付け、狭幅・Dynamic Type・Reduce Motionへ対応する。
- widget testとVisual QAスクリーンショットを追加する。

### やらないこと

- 暗号方式、鍵階層、DB schema、Rust API、FRB生成物、同期protocolを変更しない。
- 通知権限、Keychain認証、アカウント登録、課金、UIモード選択を求めない。
- lock iconや暗号化表示をHomeへ常駐させない。
- 新規依存、常設マスコット、全画面celebration、音、強いshadowを追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更しない。

## 5. 実装手順

1. `sh app/tool/visual_qa.sh`でbeforeを生成し、`app/build/visual_qa_before_task_89/`へ保存する。
2. settings用notifierと初回gateを追加する。
3. 既存トークンだけでオンボーディング画面を実装し、文言をARB化する。
4. 未完了・完了永続化・保存失敗・Dynamic Type・Reduce Motionのwidget testを追加する。
5. Visual QAへen / ja / text scale 2.0を追加し、after PNGを目視する。
6. Flutter変更の品質ゲートとworkspace全体の品質ゲートを実行する。
7. 実装事実を`## 9. 完了報告`へ記録し、別セッションまたは人間へ独立検証を渡す。

## 6. 受け入れ基準

- [x] 未設定時だけオンボーディングがHomeより先に表示される。
- [x] 完了CTA後に設定が保存されてHomeへ遷移し、再起動相当の再buildでは表示されない。
- [x] 設定保存失敗時はHomeへ進まず、再試行できる。
- [x] 文言はローカル保存時暗号化と同期E2EEを区別し、同期なしのローカル専用データが端末紛失・アプリ削除で復旧不能になり得ることを示す。
- [x] 通知権限・Keychain prompt・アカウント登録を初回起動時に発火しない。
- [x] en / ja、390x844、狭幅320x640、text scale 2.0でoverflowしない。
- [x] Reduce Motion時はページ遷移アニメーションを省略する。
- [x] CTAは44px以上、ページ位置と主要markにsemanticsがある。
- [x] `onboarding_en.png` / `onboarding_ja.png` / `onboarding_text_scale_2.png`を目視し、warm white surface、sage背景、primary green、Newsreader見出し、装飾の抑制度を確認する。
- [x] 既存Home / Lists / Detailスクリーンショットに意図しない差分がない。
- [x] `flutter analyze` / `flutter test` / `check_hardcoded_strings.sh` / `git diff --check`が成功する。
- [x] workspaceのRust品質ゲートが成功する。
- [x] 独立検証が合格する。

## 7. 制約・注意事項

- `docs/design/ui-spec.md`のトークン表にないspacing / radiusを新規に発明しない。
- E2EEの表現は現在の実装事実に限定する。「絶対安全」「運営者でも必ず読めない」等の監査済みに見える表現を使わない。
- 初回gateのloadingでHomeや同期処理を先に起動しない。
- オンボーディング完了設定は端末ローカルであり、同期しない。
- 画面を閉じただけでは完了扱いにせず、CTA成功時だけ保存する。
- 実装者は合否を自己判定しない。

## 8. 完了報告に含めるべき内容

- 変更ファイルと実装結果
- 採用したデザイン規則と採用しなかった演出
- en / ja文言が伝えるセキュリティ境界
- settings keyと永続化動作
- 追加したtest名とVisual QAのbefore / afterパス
- 全品質ゲート結果
- Rust / FRB / DB schema / docs 01〜03 / private repoを変更していないこと
- 未解決事項

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-10
- 結果: 初回だけ3ページのオンボーディングをHomeより先に表示し、`onboarding_completed=1`を既存のSQLCipher内`settings`へ保存した後だけ通常画面へ進むようにした。完了済み端末は従来どおりHomeへ入り、オンボーディング判定中は同期providerを起動しない。
- 画面: sage背景、primary containerの円形mark、Newsreader 32pxの主見出し、Inter本文、pill型page indicator、全幅CTAで構成した。新規画像asset、常設マスコット、lock常駐表示、強いshadow、全画面celebrationは追加していない。
- セキュリティ文言: ローカルDBの端末上暗号化、同期選択時の送信前暗号化、同期しないデータが端末紛失・アプリ削除で復旧不能になり得る境界をen / jaで分離して記載した。「絶対安全」等の監査済みに見える表現は使用していない。
- 失敗処理: 完了設定の保存に失敗した場合は最終ページに留まり、エラーと再試行CTAを表示する。設定読取失敗時もHomeへ進まず再試行画面を表示する。
- lifecycle gate: foreground resume時もオンボーディング完了を確認し、未完了・読取中・読取失敗では`syncStatusProvider`を生成せず同期を開始しない。
- アクセシビリティ: page / artwork semantics、44px以上のCTA、text scale 2.0でscroll可能な本文、Reduce Motion時の`jumpToPage`を実装した。
- 仕様同期: `docs/design/ui-spec.md`のNewsreader display roleを初回オンボーディングの主見出し1箇所へ限定拡張した。
- Commit: `bd7c894`（`feat: 初回オンボーディングを追加`）
- 未解決: iOS実機のVoiceOver読上げ順とスワイプ感触は、配布前の人間ドッグフーディングで確認する。

### テストと証拠

- 追加test:
  - `onboardingStatusProvider defaults to incomplete and persists`
  - `first run persists completion before opening Home`
  - `first run blocks foreground resume sync until completion`
  - `failed completion stays on onboarding and can retry`
  - `reduce motion advances onboarding without animation`
  - `onboarding supports narrow Dynamic Type`
- before: `app/build/visual_qa_before_task_89/`（44 PNG）
- after: `app/build/visual_qa/`（新規 `onboarding_en.png` / `onboarding_ja.png` / `onboarding_text_scale_2.png`）
- `diff -qr app/build/visual_qa_before_task_89 app/build/visual_qa`: 新規3 PNG以外の差分なし。
- 目視: en / jaはsage背景、warm white補助surface、primary green、Newsreader見出し、控えめなmarkとCTAの重心を確認した。text scale 2.0は本文とCTAが画面内で到達可能で、overflow例外なし。
- `flutter gen-l10n`: 成功
- `flutter analyze`: 成功（No issues found）
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `flutter test`: 成功（P2修正後の再実行で130 passed、Visual QA harness 1 skip）
- `sh app/tool/visual_qa.sh`: 成功（45 tests）
- `sh app/tool/check_hardcoded_strings.sh`: 成功
- `cargo fmt --all -- --check`: 成功
- `cargo clippy --workspace -- -D warnings`: 成功
- `cargo test --workspace`: sandbox内の初回実行はDocker socketへの`Operation not permitted`でserver integrationのみ実行不能。権限付きで同一HEADを再実行し、server integrationを含め成功。
- `git diff --check`: 成功
- Rust API、FRB定義/生成物、DB schema、暗号・同期実装、`docs/01〜03`、`.github/`、`taskveil-private/`は変更していない。

### 独立検証

- 判定: 合格（P1 / P2 / P3なし）
- 根拠: 初回独立検証で、オンボーディング中のforeground resumeが同期gateを迂回できるP2を1件検出した。`didChangeAppLifecycleState`へ完了条件を追加し、ログイン済みでも未完了中は同期しない回帰testを追加した。検証役が修正差分とtargeted 9 testsを再確認し、loading / error / incompleteでは`syncStatusProvider`を生成しないこと、テストが実際のresume lifecycleを発火していること、`git diff --check`、public/private境界を確認して合格とした。
- 検証者: 別エージェント
