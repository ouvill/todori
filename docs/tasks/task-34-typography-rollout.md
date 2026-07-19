# task-34: typography rollout ── Newsreader+システム和文セリフの本番反映とLora退役

> ステータス: 完了（2026-07-06）
> 作業日: 2026-07-06

## 1. 背景とコンテキスト

2026-07-06のタイポグラフィ人間裁定（`docs/design/ui-spec.md` 裁定済み事項参照）を本番へ反映する。Design Lab 4案比較（A: Newsreader範囲制限 / B: Lora現行 / C: オールInter / D: A+和文明朝）の結果、**D案の構成**（Newsreader範囲制限＋システム和文セリフフォールバック、その他はInter）が採用され、Loraは本番から退役することが決まった。和文明朝フォントは容量とロケール（欧米展開時に不要）の理由で同梱せず、システムフォントのセリフ（Apple系: ヒラギノ明朝 ProN）へフォールバックする。明朝非搭載OS（Android標準等）ではシステム標準書体へ自然に劣化することは裁定で許容済みである。

このタスクは`docs/design/ui-spec.md`セクション2のタイポグラフィ表（2026-07-06裁定後の目標状態）を、実装（`app/lib/src/ui/theme.dart` / `app/pubspec.yaml`）へ一致させる作業に限定する。新機能追加ではない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/ui-spec.md`（セクション2タイポグラフィ表、裁定済み事項、セクション6）
- `docs/design/visual-direction.md`
- `docs/tasks/task-30-design-mood-alignment.md`
- `docs/tasks/task-33-flutter-design-lab.md`
- `app/lib/src/ui/theme.dart`
- `app/pubspec.yaml`
- `app/assets/fonts/Lora/`、`app/assets/fonts/Newsreader/`、`app/assets/fonts/Inter/` の内容
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/tool/fetch_lab_fonts.sh`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`

## 3. ゴール

- `app/lib/src/ui/theme.dart` のタイポグラフィを、`docs/design/ui-spec.md` セクション2の裁定後の表と一致させる（Todayヘッダー=Newsreader+システム和文セリフフォールバック、それ以外すべてInter）。
- `app/pubspec.yaml` の `fonts:` からLora定義を削除し、本番アプリにLoraを同梱しない。
- Design Lab（B案=Lora）の比較用スクリーンショットが引き続き生成できることを確認する（アセット自体は残す）。
- 本番スクリーンショット（en/ja）で、Todayヘッダーのセリフ表現とその他Inter表現が視認できることを確認する。
- ui-spec.mdセクション2の「反映完了まで」の但し書きを外し、表と実装が一致した状態にする。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

- `app/lib/src/ui/theme.dart`
- `app/pubspec.yaml`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/test/widget_test.dart`（タイポ変更でfinder/期待が壊れる場合のみ）
- `docs/design/ui-spec.md`（セクション2の注記更新のみ）
- `docs/tasks/task-34-typography-rollout.md`（完了報告の追記のみ）

### やること

1. `app/lib/src/ui/theme.dart`:
   - displayMedium（Today見出しが使うrole）を `fontFamily: 'Newsreader'`、`fontFamilyFallback: ['Hiragino Mincho ProN', ...]`（必要なら `'Noto Serif CJK JP'` / `'Noto Serif JP'` も連ねる）、`fontWeight: w600` に変更する。
   - AppBarの `titleTextStyle`・`headlineSmall` 等、現行Loraを指定している箇所をすべてInterへ変更する（`docs/design/ui-spec.md` セクション2の更新後の表に一致させる）。
   - Loraへの参照をtheme.dartから完全に除去する。
2. `app/pubspec.yaml`: `fonts:` からLora定義を削除する（NewsreaderとInterは残す）。`app/assets/fonts/Lora/` のファイル自体はDesign Lab比較用に**削除しない**。
3. Design Lab / visual QAハーネス:
   - B案(Lora)のフォント読み込みが、pubspec経由ではなく `app/assets/fonts/Lora/*.ttf` からの `FontLoader` 直接読み込みで動き続けることを確認する（必要なら修正する）。
   - 本番スクショ用に `'Newsreader'` と `'Hiragino Mincho ProN'`（macOSシステムの `/System/Library/Fonts/ヒラギノ明朝 ProN.ttc`）を `FontLoader` 登録する。
   - `home_tasks_ja.png` を新規追加する: 日本語ロケール（ja）でhome画面を撮影し、「今日」見出しがヒラギノ明朝（セリフ）で描画されることを確認できるようにする。
4. widget test: タイポ変更でfinder/期待が壊れる場合のみ追従する。
5. `docs/design/ui-spec.md` セクション2の注記から「反映完了まで」の但し書きを外し、表と実装が一致した状態にする。

### やらないこと

- タスク行の構成・メタデータ、l10nキー構成、Lucide置換、Lab task_list構成の本番反映（それぞれ別タスク）。
- 和文フォントの新規同梱、新規pub依存、Rust/FRB/DB変更、`docs/01〜03`・`taskveil-private/`・`.github/` 変更。
- Newsreaderをタスクタイトルやセクション見出しへ拡大適用しない。セリフは「28px級以上かつ1画面1〜2箇所」の規則を厳守し、Todayヘッダー以外への適用は範囲外とする。
- `app/assets/fonts/Lora/` の削除。アセット自体はDesign Lab比較用に残す。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認し、無関係な差分があれば触らない。
2. `docs/design/ui-spec.md` セクション2の裁定後の表、裁定済み事項、`app/lib/src/ui/theme.dart`、`app/pubspec.yaml` を読み、現状との差分を洗い出す。
3. `app/build/visual_qa/` があれば `app/build/visual_qa_before/` へ退避し、`sh app/tool/visual_qa.sh` を実行してbeforeスクリーンショットを保存する。
4. `theme.dart` のdisplayMediumをNewsreader+システム和文セリフフォールバックへ変更し、AppBarの`titleTextStyle`・`headlineSmall`等のLora指定をInterへ変更する。
5. `app/pubspec.yaml` の `fonts:` からLora定義を削除する。
6. `visual_qa_screenshots_test.dart` を確認し、B案(Lora)比較用FontLoaderがpubspec非依存で動くことを確認する。必要なら本番スクショ用のNewsreader/ヒラギノ明朝FontLoader登録を追加・調整する。
7. `home_tasks_ja.png` を新規スクリーンショットとして追加し、`sh app/tool/visual_qa.sh` を再実行してafterスクリーンショットを取得する。
8. 既存widget testを実行し、タイポ変更で壊れるfinderがあれば最小限追従させる。
9. `docs/design/ui-spec.md` セクション2の注記を更新する。
10. 品質ゲートを実行する。
11. 指示書末尾に完了報告を追記する。

## 6. 受け入れ基準

- [ ] `docs/tasks/README.md` の共通受け入れ基準をすべて満たす。
- [ ] `home_tasks.png` で「Today」見出しがNewsreaderセリフ、「Tasks」セクション見出し・AppBar相当がInterで描画されている。
- [ ] `home_tasks_ja.png` で「今日」見出しが明朝（セリフ）で描画されている。
- [ ] `task_detail.png` のタイトルがInterで描画されている。
- [ ] 本番テーマにLora参照がなく、pubspecのfontsにLora定義がない（`grep -r "Lora" app/lib/ app/pubspec.yaml` で確認）。
- [ ] Design LabのB案PNGが引き続き生成できる。
- [ ] before/afterスクショパスが完了報告に記録されている。
- [ ] アプリ同梱フォントが増えていない（Newsreader/Interのみ。和文フォント非同梱）。

## 7. 制約・注意事項

- このタスクはタイポグラフィの本番反映であり、新機能開発ではない。
- 和文見出しはシステムフォント依存であるため、OS間で「今日」見出しの見た目が変わる（Apple系はヒラギノ明朝、明朝非搭載OSは標準ゴシック等へ劣化する）ことは2026-07-06人間裁定で許容済みの仕様である。Android実機での明朝非搭載時の劣化描画は本タスクでは未検証であり、完了報告の未解決事項に記録すること。
- Newsreaderの適用範囲を拡大しない。「28px級以上かつ1画面1〜2箇所」の規則（`docs/design/ui-spec.md` 裁定済み事項）を超える適用は行わない。
- `app/assets/fonts/Lora/` はDesign Lab比較用にリポジトリへ残す。削除しない。
- `google_fonts` パッケージ等の新規pub依存は追加しない。
- 秘密情報、Device Key、SQLCipher鍵、DB鍵を表示・ログ・Debug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- `theme.dart` のタイポグラフィ変更内容（Newsreader/Interの適用箇所、システム和文セリフフォールバックの設定内容）
- `app/pubspec.yaml` の変更内容（Lora定義削除、Newsreader/Inter定義の維持確認）
- Design Lab B案(Lora)フォント読み込みの確認結果・変更内容（あれば）
- `home_tasks_ja.png` 新規追加の内容と目視確認結果
- before/afterスクリーンショットの保存パス（`app/build/visual_qa_before/` / `app/build/visual_qa/`）と比較結果
- 追加/更新したwidget testの対象と結果
- 品質ゲートの実行結果
- `docs/design/ui-spec.md` セクション2の注記更新内容
- Android実機での明朝非搭載劣化描画が未検証であること
- 未解決事項・要人間判断

## 9. 完了報告

- 作業日: 2026-07-06
- 読んだファイル: `AGENTS.md`、`docs/tasks/README.md`、`docs/design/ui-spec.md`（セクション1・2・裁定済み事項・セクション6）、`app/lib/src/ui/theme.dart`、`app/pubspec.yaml`、`app/test/visual_qa/visual_qa_screenshots_test.dart`、`app/test/visual_qa/design_lab_mocks.dart`、`app/tool/visual_qa.sh`、`app/tool/fetch_lab_fonts.sh`、`app/lib/src/screens/tasks_screen.dart`、`app/lib/src/screens/task_detail_screen.dart`、`app/lib/src/screens/lists_screen.dart`、`app/test/widget_test.dart`

### `theme.dart` のタイポグラフィ変更内容

- `textTheme.displayMedium`（Todayヘッダーが使うrole）: `fontFamily: 'Newsreader'`、`fontFamilyFallback: _serifCjkFontFamilyFallback`（`['Hiragino Mincho ProN', 'Noto Serif CJK JP', 'Noto Serif JP']`）、`fontWeight: FontWeight.w600` に変更。
- `textTheme.displayLarge` / `displaySmall` / `headlineMedium` の`fontFamily: 'Lora'`上書きを完全に削除（元々theme.dart内で他画面から未参照だったため、base（Inter）へ委譲する形で削除）。
- `textTheme.headlineSmall`（Tasksセクション見出し・タスク詳細タイトルが使うrole）: `fontFamily: 'Lora'`を削除し、`color`/`fontWeight: w700`の上書きのみ残した（結果としてbaseのInterへ委譲）。
- `appBarTheme.titleTextStyle`（AppBarタイトル）: `fontFamily: 'Lora'`を削除し、`color`/`fontWeight: w700`の上書きのみ残した（結果としてInterへ委譲）。
- ベースの`fontFamily: 'Inter'` + `fontFamilyFallback: _cjkFontFamilyFallback`（`['Hiragino Sans', 'Noto Sans CJK JP', 'Noto Sans JP']`、角ゴシック系）は全role共通の既定として維持。displayMediumだけが専用の明朝系フォールバック（`_serifCjkFontFamilyFallback`）で上書きする構成。
- `grep -rn "Lora" app/lib/` は0件（`app/lib/src/screens/tasks_screen.dart`のコメントも「Newsreader display serif」へ更新済み）。

### `app/pubspec.yaml` の変更内容

- `fonts:` から `family: Lora` の定義ブロック（Lora-Regular/Medium/SemiBold/Bold）を削除。`family: Inter` と `family: Newsreader` の定義は変更なしで維持。
- 直上のコメントを「Lora決定事項・Newsreaderのdisplay Medium限定適用・Loraアセットは維持するがpubspec宣言はしない」旨に更新。
- `app/assets/fonts/Lora/`（Lora-Bold.ttf, Lora-Medium.ttf, Lora-Regular.ttf, Lora-SemiBold.ttf, OFL.txt）は削除せず維持を確認済み。
- `grep -r "Lora" app/pubspec.yaml` はコメント2行のみ（Lora退役を説明する文言）で、有効な`fonts:`定義としては0件。

### Design Lab B案（Lora）フォント読み込みの確認結果

- `visual_qa_screenshots_test.dart`の`_loadBrandFont(family: 'Lora', weightPaths: _loraWeightPaths)`は既存のまま、`app/assets/fonts/Lora/*.ttf`を`dart:io File.readAsBytes`で直接読み込む実装であり、pubspecの`fonts:`宣言に依存していなかったことを確認した（`flutter test`はファイルシステム相対パスを直接読めるため、pubspec宣言はテスト実行時のフォント読み込みには無関係）。コード変更は不要だった。
- `design_lab_typo_b_lora_today.png` / `design_lab_typo_b_lora_focus.png` を含むLab B案の8スクリーンショットは今回のafter生成でも問題なく出力され、目視確認でも「Today」「Tasks」見出しがLoraセリフのまま描画されていることを確認した（本番の`home_tasks.png`ではTasksがInterに変わっている対比を確認済み）。
- `design_lab_mocks.dart`のB案関連コメント（`_typoLoraB`直上、`_LabTypoOverride`直上）を「Lora=現行本番」から「Lora=2026-07-06以前の旧本番、現在はDesign Lab比較用baseline」へ事実訂正した。

### `home_tasks_ja.png` 新規追加の内容と目視確認結果

- `visual_qa_screenshots_test.dart`に`home_tasks_ja`テストを追加: `_seedRealisticData`と同じシードデータを使い、`_useJaLocale`ヘルパー（新規追加、`tester.platformDispatcher.localeTestValue`/`localesTestValue`を`Locale('ja')`に設定）でjaロケールを強制した状態でスクリーンショットを取得する。
- `_loadRealFonts`に`_loadMinchoFallbackFont`（新規関数）を追加し、macOSシステムフォント`/System/Library/Fonts/ヒラギノ明朝 ProN.ttc`を`Hiragino Mincho ProN`ファミリー名で`FontLoader`登録した（`_minchoFallbackFamily`/`_minchoFallbackPaths`も新規定数）。既存の`Hiragino Sans`ファミリー登録（角ゴシック用）とは別ファミリーとして独立登録。
- 目視確認（`Read`ツールでPNGを直接閲覧）: `home_tasks_ja.png`で「今日」見出しがセリフ（明朝、ストロークに終筆の抑揚あり）で描画され、`home_tasks.png`の「Today」（Newsreaderセリフ、字形の違う欧文セリフ）と対比して両方ともセリフ表現であることを確認した。同画面内の「タスク」セクション見出し・pillラベル・行タイトル等はゴシック（Inter＋Hiragino Sansフォールバック）のままであることも確認した。

### before/afterスクリーンショットの保存パスと比較結果

- before: `app/build/visual_qa_before/`（作業開始前、変更前テーマでの24枚。当時は`home_tasks_ja.png`は存在しない）
- after: `app/build/visual_qa/`（`sh app/tool/visual_qa.sh`再実行後の25枚、`home_tasks_ja.png`を新規に含む）
- 目視確認（`Read`ツールでの直接閲覧、テキスト差分ではなくピクセル比較ではない）:
  - `home_tasks.png`: 「Today」見出しがNewsreaderセリフ、「Tasks」セクション見出し・AppBar相当・pill・行タイトルはInterで描画されている。
  - `home_tasks_ja.png`（新規）: 「今日」見出しが明朝（セリフ）、他はゴシックで描画されている。
  - `task_detail.png`: AppBarタイトル「Task detail」、タスク詳細タイトル「Plan the product launch event」ともにInterで描画されている。
  - `design_lab_typo_b_lora_today.png`: 「Today」「Tasks」ともにLoraセリフのままで、B案比較用画像が引き続き生成されることを確認した。

### 追加/更新したwidget testの対象と結果

- `app/test/widget_test.dart`は変更不要だった（タイポ変更でfinder/期待値が壊れる箇所なし）。`cd app && flutter test`で全38件成功（visual QAスキップ1件含む）。
- `app/test/visual_qa/visual_qa_screenshots_test.dart`に`home_tasks_ja`テストケースを追加し、`sh app/tool/visual_qa.sh`実行で25/25件成功（既存24件＋新規1件）。

### 品質ゲートの実行結果

- `cargo fmt --all -- --check`: 差分なし（成功）
- `cargo clippy --workspace -- -D warnings`: 警告0件（成功）
- `cargo test --workspace`: 全件成功
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release`: 成功
- `cd app && flutter analyze`: `No issues found!`
- `cd app && flutter test`: 全38件成功（visual QAスキップ1件含む）
- `sh app/tool/check_hardcoded_strings.sh`: 検出0件（成功、exit code 0）
- `git diff --check`: 差分なし（空白関連エラーなし）
- `sh app/tool/visual_qa.sh`: 25/25件成功

### `docs/design/ui-spec.md` セクション2の注記更新内容

- 「この表は2026-07-06タイポ裁定後の目標状態である。本番反映はtask-34。反映完了までの間、実装と本表の差分はtask-34のスコープであり、他タスクで独自にタイポを変更してはならない。」という但し書きを、「この表は2026-07-06タイポ裁定後の目標状態であり、task-34で本番実装（`app/lib/src/ui/theme.dart` / `app/pubspec.yaml`）へ反映済みである。以後この表を変更したい場合は設計タスクとして本書を更新してから実装すること。」へ更新（未反映を示す文言を除去）。
- 加えて親承認済みの追加修正として、セクション1（形容詞の翻訳表）の「Loraセリフの柔らかい見出し。」を「ディスプレイセリフ（Newsreader＋システム和文セリフ）の柔らかい見出し（Todayヘッダーのみ、セクション2参照）。」へ、「セリフ見出し（Lora）とサンセリフ本文（Inter）の対比。」を「セリフ見出し（ディスプレイセリフ: Newsreader＋システム和文セリフ、Todayヘッダーのみ）とサンセリフ本文（Inter）の対比。」へ、それぞれ更新しセクション2との不一致を解消した。

### Android実機での明朝非搭載劣化描画

- 本タスクでは未検証である。`fontFamilyFallback`に`'Hiragino Mincho ProN'`等を指定しているが、Android標準（明朝非搭載）実機・エミュレータでの実描画確認は行っていない。visual QAハーネスもmacOSシステムフォント（ヒラギノ明朝 ProN）のみを登録しており、Android側フォールバック先（Noto Serif CJK JP等の有無・実際の描画結果）は未検証のまま。2026-07-06人間裁定により、この劣化は許容事項として扱われている。

### 未解決事項・要人間判断

- Android実機（明朝フォント非搭載）での「今日」見出しの実描画結果は未検証（上記参照）。
- OS間で「今日」見出しの見た目が変わる（Apple系はヒラギノ明朝、明朝非搭載OSは標準ゴシック等へ劣化する）ことは、2026-07-06人間裁定で許容済みの仕様である旨を確認済み。追加のspec変更・要人間判断事項はなし。
