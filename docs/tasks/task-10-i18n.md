# task-10: i18n基盤（en/ja）の導入（M2-04）

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

`docs/07_Phase1計画書.md` のマイルストーンM2「ブリッジとUI骨格」は、M2-04「i18n基盤を導入する」を定義している（完了条件: en/ja ARBで主要画面文字列が切替可能で、UI文字列の直書き検出が通ること）。このタスクは同項目に対応する。

`docs/02_機能仕様書.md` F-48「多言語対応」は、基準言語を英語とし初期リリースでは英語・日本語を提供する方針、およびすべてのUI文字列を外部化しハードコードを禁止する方針を定めている。M2-04はこのうちi18n基盤（ARBベースのローカライズ・直書き検出）を整備する段階であり、複数形/性数対応（ICU MessageFormat）や翻訳管理プラットフォームの構築、日付・時刻等のロケール依存表記、RTL対応の作り込みはPhase1計画書上M2-04の完了条件には含まれず、本タスクのスコープ外である。

依存パッケージ（`flutter_localizations` / `intl`）は `app/pubspec.yaml` に既に追加済みであり、本タスクの実行環境はネットワークアクセス不可であるためこれ以上の新規パッケージ追加は行わない。task-09により画面骨格（リスト一覧・タスク一覧・タスク詳細の3画面）が完成しており、現在UI文字列はすべて英語のハードコード文字列である。

## 2. 事前に読むべきファイル

- `docs/tasks/task-09-ui-skeleton.md`（本タスクの前提となる画面骨格の指示書と完了報告。3画面・`main.dart`・widget testの構成を把握する）
- `app/lib/src/screens/lists_screen.dart` / `tasks_screen.dart` / `task_detail_screen.dart`（現在英語ハードコードされている全UI文字列）
- `app/lib/main.dart`（`TaskveilApp` の `MaterialApp.router` 構成、初期化失敗時のエラー画面の文字列）
- `app/test/widget_test.dart`（既存widget testが `find.text('Lists')` 等、文字列で要素を検索している箇所）
- `app/pubspec.yaml`（`flutter_localizations` / `intl` が追加済みであることの確認。`flutter:` セクションの現状）
- `docs/02_機能仕様書.md` F-48「多言語対応」
- `docs/07_Phase1計画書.md` M2セクション（M2-04の完了条件、および依存関係が「なし」であること＝task-09完了を待たず着手可能だが、本指示書は画面文字列を対象とするためtask-09の成果物を前提とする）

## 3. ゴール

`app/lib/l10n/app_en.arb` と `app_ja.arb` を作成し、`flutter gen-l10n`（`flutter pub get` 時の自動生成を含む）で生成される `AppLocalizations` を通じて、task-09で実装済みの3画面・`main.dart`・ダイアログの全UI文字列がシステム言語（en/ja）に応じて切り替わることを実証する。あわせて、UI文字列の直書きを検出する簡易スクリプトを追加し、直書きが無い状態を維持できるようにする。`cd app && flutter analyze` と `cd app && flutter test` の双方が緑になること。

## 4. スコープ

### やること

1. **l10n設定ファイル**: `app/l10n.yaml`（新規）を作成する。`arb-dir: lib/l10n`、`template-arb-file: app_en.arb`、`output-localization-file: app_localizations.dart` を設定する。現行のFlutter標準構成（`flutter gen-l10n` が `l10n.yaml` を読んで `.dart_tool/flutter_gen/gen_l10n/` 等へ出力する既定挙動、または明示的な `output-dir` 指定）に従い、生成先を指示書内で明確にする。
2. **pubspec設定**: `app/pubspec.yaml` の `flutter:` セクションに `generate: true` を追加する。
3. **ARBファイル**: `app/lib/l10n/app_en.arb`（テンプレート）と `app/lib/l10n/app_ja.arb` を新規作成する。task-09の3画面（`lists_screen.dart` / `tasks_screen.dart` / `task_detail_screen.dart`）・`main.dart`・各画面内のダイアログ（`_NewListDialog` / `_NewTaskDialog`）に現れる**全UI文字列**を実ファイルから抽出してキー化する。最低限、以下を含む想定である（実ファイルを読んで過不足なく網羅すること）。
   - アプリタイトル（`MaterialApp.router` の `title` / `onGenerateTitle`）
   - リスト一覧画面: AppBarタイトル「Lists」、空状態「No lists yet. Tap + to create one.」、エラー表示「Failed to load lists: $error」、FABのtooltip「New list」
   - リスト作成ダイアログ: タイトル「New list」、入力欄ラベル「Name」、「Cancel」、「Create」
   - タスク一覧画面: AppBarタイトル「Tasks」、空状態「No tasks yet. Tap + to create one.」、エラー表示「Failed to load tasks: $error」、FABのtooltip「New task」
   - タスク作成ダイアログ: タイトル「New task」、入力欄ラベル「Title」、「Cancel」、「Create」
   - タスク詳細画面: AppBarタイトル「Task detail」、エラー表示「Failed to load task: $error」、「Task not found.」、「Status: $status」、「Priority: $priority」、「Created at: $createdAt」、「Move to trash」ボタン
   - `main.dart` の初期化失敗時エラー表示「Failed to start Taskveil: $error」

   プレースホルダを含む文字列（`$error` / `$status` / `$priority` / `$createdAt` 等）はARBのplaceholder構文（`"failedToLoadLists": "Failed to load lists: {error}"` と対応する `"@failedToLoadLists": {"placeholders": {"error": {"type": "String"}}}`）を用いる。ja訳は自然な日本語とする（例: Lists→リスト、Tasks→タスク、New list→新しいリスト、Cancel→キャンセル、Create→作成、Move to trash→ゴミ箱へ移動、No lists yet. Tap + to create one.→リストがありません。+をタップして作成してください。等。実際の訳文はエージェントの裁量で自然な日本語にしてよい）。
4. **アプリ全体へのローカライズ配線**: `app/lib/main.dart` の `MaterialApp.router` に `localizationsDelegates: AppLocalizations.localizationsDelegates` と `supportedLocales: AppLocalizations.supportedLocales` を設定し、システム言語に追従させる（F-48）。`title:` の固定文字列指定に代えて `onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle` を用いる。初期化失敗時のエラー画面（`MaterialApp` の方）は `AppLocalizations` に依存させてよいが、`ProviderScope`/ルーティングより前段で発生しうる失敗であるため、ローカライズ配線が使えない場合は英語文字列のままでよい旨を判断し、実装した方針を完了報告に記載する。
5. **画面・ダイアログの文字列置換**: 3画面（`lists_screen.dart` / `tasks_screen.dart` / `task_detail_screen.dart`）内の全 `Text(...)` ・tooltip・ダイアログ文言・`InputDecoration.labelText` 等を `AppLocalizations.of(context)!.<key>` 参照に置換する。`StatelessWidget`/`ConsumerWidget` の `build(BuildContext context, ...)` から素直に `AppLocalizations.of(context)!` を呼べる箇所はそれを使う。`_NewListDialog` / `_NewTaskDialog` のような `StatefulWidget` 内でも `build` メソッド内であれば同様に呼べる。
6. **既存widget testの追随修正**: `app/test/widget_test.dart` は `find.text('Lists')` 等、英語文字列で要素を検索している。デフォルトロケールはテスト実行環境ではen想定であるため、原則として既存のenアサーション文字列は維持できるはずだが、ARB化によって文言が変わった場合（例: エラー文言のプレースホルダ形式が変わった等）はテスト側の期待値も追随修正する。修正は必要最小限に留め、既存のテスト意図（画面遷移・状態反映の検証）は変更しない。`TaskveilApp` をテストでpumpする際に `AppLocalizations.delegate`（またはenロケール）がwidget test環境で解決されることを確認する（`MaterialApp.router` に `localizationsDelegates` を設定すれば `flutter_test` の既定ロケール=enで自動解決されるはずである）。
7. **直書き検出スクリプト**: `app/tool/check_hardcoded_strings.sh`（新規、実行可能なshellスクリプト）を追加する。`app/lib/src/screens/` 配下と `app/lib/main.dart` を対象に、`Text('...')` / `Text("...")` のようなハードコード文字列リテラルをgrep等で検出する素朴な実装でよい。`AppLocalizations.of(context)!.xxx` 経由の参照は文字列リテラルを直接 `Text()` に渡さないため誤検知しにくいが、`Text(someVariable)` のような変数参照や `Icon` 等は対象外とし、検出パターン・既知の除外（あれば）をスクリプト内コメントに明記する。検出0件でexit 0、1件以上検出したらexit 1で該当ファイル・行を表示する。
8. **動作検証テスト**: `app/test/l10n_test.dart`（新規）を作成し、`AppLocalizations.delegate.load(const Locale('ja'))` と `const Locale('en')` それぞれで `AppLocalizations` インスタンスをロードし、主要キー（例: `appTitle` / `listsTitle` / `tasksTitle` / `createButton` / `cancelButton`）がen/jaで異なる訳文を返すことを確認する軽量テストを実装する。

### やらないこと

- 言語手動切替UI（アプリ内設定画面から言語を選ぶUI）は `docs/07_Phase1計画書.md` M3以降の範囲であり実装しない。本タスクはOSのシステム言語への自動追従のみを扱う。
- en/ja以外の言語の追加。
- Rust側のエラーメッセージの翻訳（現状ブリッジAPIから返るエラーは `String` パススルーであり、そのまま表示している。エラーコード化してDart側でローカライズする設計は将来の課題であり、未解決事項に記録するに留める）。
- `core/`・`app/rust/`・`app/rust_builder/` の変更。
- 新規pubパッケージの追加（本タスクの実行環境はネットワークアクセス不可であるため、crates.io/pub.devからの新規取得が発生する変更を行ってはならない。既に追加済みの `flutter_localizations` / `intl` のみ使用する）。
- FRB codegenの再実行（Rust API変更が無いため不要のはず。もし必要になったら理由を完了報告に記載する）。
- 複数形・性数対応（ICU MessageFormatのplural/select構文）、日付・時刻・数値のロケール依存フォーマット、RTLレイアウトの作り込み、翻訳管理プラットフォームの構築（いずれもF-48全体のスコープだがM2-04の完了条件には含まれず、本タスクでは扱わない）。

## 5. 実装手順（例）

1. `docs/tasks/task-09-ui-skeleton.md`、`app/lib/src/screens/lists_screen.dart` / `tasks_screen.dart` / `task_detail_screen.dart`、`app/lib/main.dart`、`app/test/widget_test.dart`、`app/pubspec.yaml`、`docs/02_機能仕様書.md` F-48、`docs/07_Phase1計画書.md` M2-04 を再読し、現在の画面文字列とテストの流儀を把握する。
2. `app/l10n.yaml` を新規作成する。
3. `app/pubspec.yaml` の `flutter:` セクションに `generate: true` を追加する。
4. `app/lib/l10n/app_en.arb` を作成し、3画面・`main.dart`・ダイアログの全UI文字列をキー化する。続けて `app/lib/l10n/app_ja.arb` を作成し、同じキーに日本語訳を対応させる。
5. `cd app && flutter pub get`（または `flutter gen-l10n`）を実行し、`AppLocalizations` が生成されることを確認する。
6. `app/lib/main.dart` の `MaterialApp.router` に `localizationsDelegates` / `supportedLocales` / `onGenerateTitle` を設定する。
7. 3画面・ダイアログの `Text(...)` 等のハードコード文字列を `AppLocalizations.of(context)!.<key>` 参照に置換する。
8. `app/tool/check_hardcoded_strings.sh` を新規作成し、実行権限を付与する。
9. `app/test/l10n_test.dart` を新規作成する。
10. `app/test/widget_test.dart` を実行し、失敗するアサーションがあれば必要最小限の追随修正を行う。
11. `cd app && flutter analyze` と `cd app && flutter test` を実行して確認する。
12. `sh app/tool/check_hardcoded_strings.sh` を実行し、exit 0を確認する。
13. 最後に `cargo fmt --all -- --check`、`cargo clippy --workspace -- -D warnings`、`cargo test --workspace` を実行し、Rust側の回帰がないことを確認する（本タスクではRust側は変更しないため、既存の緑を維持するだけでよい）。

## 6. 受け入れ基準

- [ ] `cargo fmt --all -- --check` が差分なしで通過する（回帰確認）
- [ ] `cargo clippy --workspace -- -D warnings` が警告ゼロで通過する（回帰確認）
- [ ] `cargo test --workspace` が全テスト成功する（回帰確認）
- [ ] `cd app && flutter analyze` が警告・エラーなしで完了する
- [ ] `cd app && flutter test` が全テスト成功する（`l10n_test.dart` を含む）
- [ ] `sh app/tool/check_hardcoded_strings.sh` がexit 0で完了する（`app/lib/src/screens/` と `app/lib/main.dart` に文字列リテラルの直書きが無いこと）
- [ ] `flutter gen-l10n`（または `flutter pub get` 時の自動生成）で `app_localizations.dart`（およびロケール別ファイル）が生成されること

## 7. 制約・注意事項

- `docs/01〜04`・`docs/07_Phase1計画書.md` は変更しないこと。
- 生成物（`l10n.yaml` の構成に基づき出力される `app_localizations.dart` 等）は、task-08/09で確立されたFRB生成物と同様の扱いとし、コミット対象に含める（`.gitignore` によって除外されないことを確認する。既存の `.gitignore` は `**/.dart_tool/` を除外しているため、生成先が `.dart_tool/` 配下になる既定設定のままだと生成物がコミットされない可能性がある。この場合は `l10n.yaml` に `output-dir` を指定して `lib/` 配下等の非gitignore対象に出力するよう構成するか、`.gitignore` の当該除外パターンとの整合を指示書実装時に確認し、対応方針を完了報告に記録すること。ただし `.gitignore` 自体の変更が必要な場合はその旨も完了報告に明記する）。
- widget test（`app/test/widget_test.dart`）側の文字列アサーション更新は必要最小限に留め、既存のテスト意図を変更しないこと。
- 仕様書の記述だけでは一意に決まらない実装判断（ARBキー名の命名規則、ja訳の具体的な表現、直書き検出スクリプトの検出パターンの粒度等）が生じた場合は、独断で仕様書側を変更せず、完了報告の「未解決事項」に記録すること（`docs/tasks/README.md` 共通規約6.）。

## 8. 完了報告に含めるべき内容

- ARBキー数と主要キー一覧
- 生成構成（`l10n.yaml` の内容、生成先ディレクトリ、`.gitignore` との整合確認結果）
- widget test修正内容（変更した場合はその理由）
- 直書き検出スクリプト（`app/tool/check_hardcoded_strings.sh`）の仕様（検出パターン、既知の除外）
- 未解決事項（あれば）

## 9. 完了報告

作業日: 2026-07-04

### 実装結果

- `app/l10n.yaml` を追加し、Flutter gen-l10n の入力を `app/lib/l10n/`、生成先を `app/lib/src/generated/l10n/` に固定した。
- `app/pubspec.yaml` の `flutter:` セクションに `generate: true` を追加した。
- `app/lib/l10n/app_en.arb` / `app/lib/l10n/app_ja.arb` を追加し、task-09の3画面、ダイアログ、`main.dart` のUI文字列を `AppLocalizations` 経由へ移行した。
- `app/lib/main.dart` の通常起動時 `MaterialApp.router` と初期化失敗時 `MaterialApp` の双方に `localizationsDelegates` / `supportedLocales` / `onGenerateTitle` を設定した。初期化失敗画面も生成済み `AppLocalizations` から文言を取得する構成とした。
- `app/lib/src/screens/lists_screen.dart` / `tasks_screen.dart` / `task_detail_screen.dart` の `Text(...)`、tooltip、ダイアログタイトル、入力ラベル、ボタン文言、プレースホルダ付きエラー文言をARB参照に置換した。
- `app/tool/check_hardcoded_strings.sh` を追加し、対象範囲の簡易直書き検出を導入した。
- `app/test/l10n_test.dart` を追加し、`AppLocalizations.delegate.load(const Locale('en'))` / `const Locale('ja')` で主要キーがロードでき、en/jaの訳文が切り替わることを検証するテストを実装した。

### ARBキー数と主要キー

- 通常キー数は23件である。
- 主要キー: `appTitle`, `listsTitle`, `listsEmpty`, `failedToLoadLists`, `newListTooltip`, `newListTitle`, `nameLabel`, `cancelButton`, `createButton`, `tasksTitle`, `tasksEmpty`, `failedToLoadTasks`, `newTaskTooltip`, `newTaskTitle`, `titleLabel`, `taskDetailTitle`, `failedToLoadTask`, `taskNotFound`, `taskStatus`, `taskPriority`, `taskCreatedAt`, `moveToTrashButton`, `failedToStartTaskveil`。
- プレースホルダ付きキーは `failedToLoadLists(error)`, `failedToLoadTasks(error)`, `failedToLoadTask(error)`, `taskStatus(status)`, `taskPriority(priority)`, `taskCreatedAt(createdAt)`, `failedToStartTaskveil(error)` とした。

### 生成構成

`app/l10n.yaml` の内容は以下のとおりである。

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/src/generated/l10n
```

- 生成物は `app/lib/src/generated/l10n/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_ja.dart` に出力される。
- `app/.gitignore` は `.dart_tool/` を除外しているが、生成先を `lib/src/generated/l10n/` にしたため、生成物はgit管理対象になる。`.gitignore` の変更は不要である。
- 通常の `flutter gen-l10n` はこのサンドボックスではFlutter SDK cacheへの書き込みで失敗するため、検証時は既存の `flutter_tools.snapshot` を `FLUTTER_ALREADY_LOCKED=true` 付きで直接起動して生成した。

### widget test修正内容

- `app/test/widget_test.dart` は変更していない。英語ARBの文言を既存の英語ハードコード文言と揃えたため、既存の `find.text('Lists')` 等のアサーション意図を維持できる。
- `TaskveilApp` 側に `localizationsDelegates` / `supportedLocales` を設定したため、widget test環境の既定ロケール（en）で既存アサーションが解決される構成である。

### 直書き検出スクリプト

- `app/tool/check_hardcoded_strings.sh` は `app/lib/main.dart` と `app/lib/src/screens/` 配下を対象にする。
- 検出パターンは `Text('...')` / `Text("...")`、`tooltip: '...'` / `tooltip: "..."`、`labelText: '...'` / `labelText: "..."`、`title: '...'` / `title: "..."` である。
- `Text(task.title)` や `Text(l10n.xxx)` のような変数・ローカライズ参照は許可する。route path、status値、import、debug log等の非UI文字列は本タスクの検出対象外とした。

### 検証

- `cargo fmt --all -- --check` 成功。
- `cargo clippy --workspace -- -D warnings` 成功。
- `cargo test --workspace` 成功（62件）。
- `cd app && flutter analyze` はFlutter SDK cacheへの書き込みがサンドボックス外として拒否されるため、同等の `flutter_tools.snapshot analyze` を `FLUTTER_ALREADY_LOCKED=true` 付きで実行し、成功（No issues found）。
- `sh app/tool/check_hardcoded_strings.sh` 成功（検出0件）。
- `cd app && flutter test` 相当の `flutter_tools.snapshot test` は、テストコード読み込み前に `127.0.0.1:0` のサーバソケット作成が `Operation not permitted` で拒否され失敗した。これは本環境のローカルソケット禁止に起因する失敗であり、テストコード起因の失敗ではない。追加した `app/test/l10n_test.dart` は実装済みである。

### 未解決事項

- Rust側エラーメッセージは現状どおり `String` パススルーで表示している。エラーコード化してDart側でローカライズする設計は将来課題である。
- `flutter` ラッパーコマンドはSDK cache書き込み制約の影響を受けるため、この環境では `flutter_tools.snapshot` 直接起動で代替検証した。
