# task-30: design mood alignment ── typography / metadata quieting / row density

## 1. 背景とコンテキスト

task-25/28/29でLists / Tasks / Task detail / Trash / Dialog / Empty stateのpolishを重ねたが、参照画像（`assets/brand/generated/todori-design-direction-mobile-focus-tasks.webp` / `assets/brand/generated/todori-design-direction-tasks.webp` / `assets/brand/generated/todori-design-direction-task-detail.webp`）の雰囲気には近づいていない。

親レビューで、task-28後に恒久化したスクリーンショット基盤（`app/tool/visual_qa.sh` と `app/test/visual_qa/visual_qa_screenshots_test.dart`）の出力と参照画像を比較した結果、根本原因は次の5点と特定された。

1. **ブランドタイポグラフィ不在**: 参照画像はセリフ体のディスプレイ書体とジオメトリックなサンセリフの組み合わせだが、現状の実装はOS標準フォントのみで統一されている。
2. **タスク行のメタデータチップ過多**: Status/Priority/Dueの3チップ×冗長ラベルで表示されており、参照の「相対日付ピル1個＋優先度ドット」に対して視覚ノイズが3倍以上ある。
3. **行密度の破綻**: チップの折返しとシェブロンの独立行により1タスクの表示が巨大化している。参照はコンパクトな行リズムを保っている。
4. **Task detailに `Local protection` ロックチップが残存**: `docs/design/visual-direction.md` の「Security Signal」節にある「主要タスクUIに恒常的なlock/encryptionマークを置かない」方針に違反している。
5. **Task detailの表示バグ・重複**: `Created at:` が生epoch値をそのまま表示している、pending数がヘッダーとセクション内で重複表示されている、Tasksセクションヘッダーがcard-in-cardに見える。

このタスクは機能追加ではない。上記5点の解消に**限定**して、既存のFlutter UI、i18n、アクセシビリティ、widget test、品質ゲートを維持しながら実装する。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/design/visual-direction.md`
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `docs/tasks/task-22-design-direction-sketch.md`
- `docs/tasks/task-25-design-calibration-ui-pass.md`
- `docs/tasks/task-28-visual-polish.md`
- `docs/tasks/task-29-product-experience-alignment.md`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/trash_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/pubspec.yaml`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/tool/check_hardcoded_strings.sh`
- 参照画像: `assets/brand/generated/todori-design-direction-mobile-focus-tasks.webp` / `assets/brand/generated/todori-design-direction-tasks.webp` / `assets/brand/generated/todori-design-direction-task-detail.webp`

必要に応じて、現在の実装で参照されている `app/lib/src/generated/l10n/` の生成結果も確認する。ただし生成物は手編集しない。

## 3. ゴール

- ブランドタイポグラフィ（セリフのディスプレイ書体 + ジオメトリックなUI本文書体）を導入し、Today見出し・画面タイトル・セクション見出しに適用する。
- タスク行のメタデータ表現を、参照画像に近い「相対日付ピル1個＋優先度ドット」相当まで削減し、視覚ノイズを減らす。
- 行密度を圧縮し、メタデータのないタスク1件がタイトル1行＋α程度の高さに収まるようにする。
- Task detailの `Local protection` ロックチップを削除し、`Created at:` の表示バグとpending数の重複表示、Tasksセクションヘッダーのcard-in-card感を解消する。
- 上記すべてを、長いタイトル、i18n（en/ja）、Dynamic Type、狭幅、48pxタップ領域、tooltip/semanticsを壊さずに行う。

## 4. スコープ（やること・やらないこと）

### 想定変更ファイル

後続workerは、実装に必要な場合に限り、以下を中心に変更する。実際の差分は受け入れ基準を満たす最小範囲に留める。

- `app/assets/fonts/Lora/*.ttf`, `app/assets/fonts/Lora/OFL.txt`（新規追加）
- `app/assets/fonts/Inter/*.ttf`, `app/assets/fonts/Inter/OFL.txt`（新規追加）
- `app/pubspec.yaml`（`fonts:` セクション追加）
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/l10n/app_en.arb`
- `app/lib/l10n/app_ja.arb`
- `app/lib/src/generated/l10n/` 配下のl10n生成物
- `app/test/widget_test.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `docs/tasks/task-30-design-mood-alignment.md`（実装完了時の `## 8. 完了報告に含めるべき内容` に相当する報告の追記のみ）

### やること

**A. フォント資産の導入（新規pub依存なし、アセットとしてバンドル）**

- Google Fonts CSS API（例: `curl -A 'curl' 'https://fonts.googleapis.com/css2?family=Lora:wght@400;500;600;700'` でTTF URLが得られる。Interも同様のURLパターン）から static TTF を取得し、以下に配置する。
  - `app/assets/fonts/Lora/Lora-{Regular,Medium,SemiBold,Bold}.ttf` + `OFL.txt`（`https://github.com/google/fonts/raw/main/ofl/lora/OFL.txt`）
  - `app/assets/fonts/Inter/Inter-{Regular,Medium,SemiBold,Bold}.ttf` + `OFL.txt`（`ofl/inter`）
- CSS APIが単一weightずつしか返さない場合はweightごとにリクエストする。
- variable font 1本しか得られない場合はvariable fontを採用してよいが、その場合は `FontVariation` でweightが実際に効くことをスクリーンショットで確認する。効かない場合はstatic TTFを別手段で取得する。
- 役割分担: **Lora = ディスプレイ書体**（Today見出し、画面タイトル、セクション見出し、AppBarタイトル）。**Inter = UI本文**（それ以外すべて）。日本語はプラットフォームのフォールバック（ヒラギノ/Noto）に任せ、日本語用フォントを新規導入しない。

**B. `theme.dart` のタイポグラフィ**

- `ThemeData(fontFamily: 'Inter', ...)` を基本とする。
- `displayLarge`〜`displaySmall`、`headlineMedium`、`headlineSmall`、AppBarの `titleTextStyle` に `fontFamily: 'Lora'` を適用する。weightは現状のスタイルを踏襲しつつ、Todayヘッダーはw600程度でセリフの品位を保つ（太すぎるw700+セリフの多用は避ける）。

**C. タスク行のメタデータ削減（`task_components.dart` と呼び出し側）**

- タスク行（Tasks画面・detail画面のサブタスク行）から**Statusチップを完全に削除**する。状態はチェックボックス・完了時のmuted/strikethrough・既存semanticsで伝える。
- **Priorityチップを行から削除**する。優先度は既存の priority dot + semantic label のみで伝える。dotの色は `docs/design/visual-direction.md` のトークンに合わせる: high=`#E8755A`（coral）、medium=`#EDB73E`（amber）、low=`#A8BEA8`（softSage）、none=dot非表示。
- **Dueチップは相対日付表記に変更**する。今日→「Today/今日」、明日→「Tomorrow/明日」、それ以外→ロケール依存短縮形（`DateFormat.MMMd`）。「Due: 」等のプレフィックスは削除し、カレンダーアイコンは維持する。期限切れはテキスト/アイコンをcoral系にするが、色だけに依存しないよう、semanticsに期限切れである旨を含める。
- サブタスク進捗チップは「1/3」形式の短い表記＋アイコンを維持する。プレフィックス文言があれば削除する。
- 新規/変更文言はen/ja ARB化し `flutter gen-l10n` を実行する。

**D. 行密度の圧縮**

- チェックボックスを円形にする（`Checkbox` の `shape: CircleBorder()` 等）。タップ領域48px級は維持する。
- シェブロン/並び替えコントロールを行の右端に**垂直センター**配置し、独立した最下行にしない。
- 行の縦paddingを詰め、メタデータなしのタスク1件がタイトル1行＋α程度の高さに収まるようにする。メタデータがある場合はタイトルの下に1行のWrapで続くようにする。
- 長いタイトル・日本語・Dynamic Type・狭幅での折返しは既存テストの期待どおり維持する。

**E. Tasks画面ホームヘッダーの整理**

- pending数の表示を1箇所にする（ヘッダー上部の「7 pending」ピルとTasksセクション内のピルの重複を解消する）。
- 「Tasks」セクションヘッダーをカード（DecoratedBox+border）から、プレーンなテキスト見出し（Lora）＋pendingピル＋追加ボタンの行に変更し、card-in-card感をなくす。

**F. Task detail画面**

- `Local protection` ロックチップを削除する（`docs/design/visual-direction.md` の「Security Signal」節準拠）。関連するl10nキーが他で未使用になる場合は削除してよい。
- `Created at:` の生epoch表示を修正し、ロケール依存の日付表記（`DateFormat.yMMMd` 等）にする。
- タイトルブロックはborder付きカードをやめ、背景の上に直接タイトル（Lora, headline級）＋メタデータチップを置く構成にする。
- メタデータチップはC.と同じ文法（Status表記はdetailでは残してよいが「Status: 」プレフィックスなしの短い表記にする）。

**G. 検証**

- 変更前に `app/build/visual_qa/` を `app/build/visual_qa_before/` へ退避してから作業し、`app/tool/visual_qa.sh` を実行してbefore/afterのスクリーンショット比較ができるようにする。
- `app/test/visual_qa/visual_qa_screenshots_test.dart` のフォント読み込みを更新する。バンドルしたLora/InterのTTFを実アセットから該当family名でFontLoader登録し、日本語グリフ用にヒラギノ系を同familyへ追加登録する（FontLoaderは同一familyに複数フォントを追加登録でき、グリフフォールバックする）。スクリーンショット上でセリフ見出し・日本語の両方が正しく描画されることを確認する。
- 既存widget testを新しいUI構造に合わせて更新する（Statusチップ削除等でfinderが変わる箇所を修正する）。

### やらないこと

- 新機能追加なし（Focus timer、検索、通知、設定画面、マスコット画像の組み込み、bottom navigationなし）。
- Rust API / FRB / DB schema / domain / storage / core配下 / cli / mcp-server / server 変更なし。
- 新規pub依存なし。フォントはアセットとしてバンドルし、`google_fonts` パッケージ等は使わない。
- Lists画面・Trash画面の構成変更なし（テーマ変更（フォント/色トークン）の波及のみ許容する）。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` の変更禁止。
- `todori-private/` 配下、`.github/` 配下の変更禁止。
- 画像モックのピクセル再現はしない。i18n・Dynamic Type・狭幅・48pxタップ領域・tooltip/semanticsを壊さない。

## 5. 実装手順例

1. `git status --short` で作業ツリーを確認し、無関係な差分があれば触らない。
2. 2章のファイルと参照画像を読み、task-25/28/29の較正方針・polish内容・product experience alignmentの結果を把握する。
3. `app/build/visual_qa/` があれば `app/build/visual_qa_before/` へ退避し、現状の `app/tool/visual_qa.sh` を実行してbeforeスクリーンショットを保存する。
4. Google Fonts CSS APIからLora/InterのTTF（各weight）を取得し、`app/assets/fonts/{Lora,Inter}/` へ配置する。各ディレクトリにOFLライセンスファイルも配置する。
5. `app/pubspec.yaml` に `fonts:` セクションでLora/Interのfamilyとweightを登録する。
6. `theme.dart` でfontFamilyのデフォルトをInterにし、display/headline/AppBarタイトルにLoraを適用する。
7. `task_components.dart` を中心に、タスク行のStatus/Priorityチップを削除し、Due表記を相対日付化し、円形チェックボックスと行密度を圧縮する。
8. `tasks_screen.dart` のホームヘッダーからpending数の重複表示を解消し、Tasksセクションヘッダーのcard-in-card構成をプレーンな見出し行に変更する。
9. `task_detail_screen.dart` からLocal protectionチップを削除し、Created atの日付表示を修正し、タイトルブロックのカード構成を見直す。
10. UI文字列を変更した場合はARB（`app_en.arb` / `app_ja.arb`）へ反映し、`cd app && flutter gen-l10n` を実行する。
11. `visual_qa_screenshots_test.dart` のフォント読み込みをLora/Inter/ヒラギノ系に更新し、`sh app/tool/visual_qa.sh` を実行してafterスクリーンショットを取得し、beforeと比較する。
12. 既存widget testを新しいUI構造に合わせて更新する。
13. 品質ゲートを実行する。
14. 指示書末尾に完了報告を追記する。

## 6. 受け入れ基準

- [ ] `app/tool/visual_qa.sh` の `home_tasks.png` で、タスク行に「Status:」「Priority:」チップが存在しない。
- [ ] 同スクリーンショットで、期日は「Today/Tomorrow/短縮日付」の相対表記であり「Due: 2026-07-05」形式が存在しない。
- [ ] 同スクリーンショットで、「Today」見出しとセクション見出しがセリフ体（Lora）で描画されている。
- [ ] 同スクリーンショットで、pending数の表示が1箇所である。
- [ ] 同スクリーンショットで、メタデータなしタスク行がタイトル1行程度の高さに収まり、シェブロンが行の右端に垂直センター配置されている。
- [ ] `task_detail.png` で、Local protectionチップが存在せず、Created atがロケール日付表記である。
- [ ] チェックボックスが円形である。
- [ ] priority dotが coral/amber/softSage のトークン色で、priority noneはdotなしである。
- [ ] before/afterスクリーンショットの保存パスが完了報告に記録されている。
- [ ] 追加・変更UI文字列がen/ja ARB化され、ARB変更時は生成済みlocalizationsが更新されている。
- [ ] `app/lib/src/generated/l10n/` 配下は `flutter gen-l10n` による生成差分のみで、手編集されていない。
- [ ] 長いタイトル、日本語/英語、Dynamic Type相当、狭幅で行・メタデータ・見出しが破綻しない。
- [ ] icon-only controlのtooltip/semanticsが維持されている。
- [ ] priority/due/statusの意味が色だけに依存せず、text/icon/semanticsでも分かる。
- [ ] 主要操作のタップ領域が48px級に保たれている。
- [ ] `cargo fmt --all -- --check` が成功している。
- [ ] `cargo clippy --workspace -- -D warnings` が成功している。
- [ ] `cargo test --workspace` が成功している。
- [ ] `cd app && flutter analyze` が成功している。
- [ ] `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` の後、`cd app && flutter test` が成功している。
- [ ] `sh app/tool/check_hardcoded_strings.sh` が成功している。
- [ ] `git diff --check` が成功している。
- [ ] `app/assets/fonts/Lora/OFL.txt` と `app/assets/fonts/Inter/OFL.txt` が同梱されている。
- [ ] `app/pubspec.yaml` にLora/Interの `fonts:` 定義があり、新規pub依存が追加されていない。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `todori-private/` と `.github/` が変更されていない。
- [ ] `docs/tasks/task-30-design-mood-alignment.md` の末尾に完了報告が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはvisual mood alignmentであり、新機能開発ではない。
- `docs/design/visual-direction.md` はpublic repoのデザイン正本である。実装判断がずれた場合でも、この指示書のスコープでは正本自体の更新は必須にしない（矛盾を発見した場合は完了報告の未解決事項に記録する）。
- フォントはGoogle Fonts（Lora, Inter）由来のOFL（SIL Open Font License）ライセンスファイルを必ず同梱する。ライセンスファイルなしでフォントバイナリだけを追加しない。
- `google_fonts` パッケージ等の新規pub依存は追加しない。フォントはアセットとしてバンドルし、`pubspec.yaml` の `fonts:` セクションで登録する。
- `visual_qa_screenshots_test.dart` はデフォルトでskipされる設計を維持し、`TODORI_VISUAL_QA=1` のときのみ実行されるようにする（既存の仕組みを壊さない）。
- before/afterのスクリーンショット比較は、`app/build/visual_qa_before/` と `app/build/visual_qa/` のパスを完了報告に明記する。両ディレクトリはコミット対象にしない。
- UI文字列は必ずARB化する。`Text('...')`、`Tooltip(message: '...')` などの直書きを残さない。
- `flutter_rust_bridge` は `2.12.0` 固定であり、Rust側crateとDart側pubのバージョン一致を崩さない。
- 秘密情報、Device Key、SQLCipher鍵、DB鍵を表示・ログ・Debug出力に含めない。
- `docs/01〜03` は変更禁止である。仕様と実装の矛盾を見つけた場合は、仕様書を書き換えず完了報告の未解決事項に記録する。
- public repoにprivate repoの課金、収益、法務、監査、公開前ロードマップ詳細を転記しない。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- フォント資産の取得方法（取得元URL・weight・variable font採用の有無）とライセンス同梱の確認結果
- `theme.dart` のタイポグラフィ変更内容（Lora/Interの適用箇所）
- タスク行のメタデータ削減内容（削除したチップ、Due表記の相対日付化、priority dotの色トークン）
- 行密度圧縮の内容（円形チェックボックス、シェブロン配置、行の高さ）
- Tasksホームヘッダーのpending数重複解消とセクション見出しの変更内容
- Task detail画面のLocal protectionチップ削除、Created at修正、タイトルブロック変更の内容
- 削除したl10nキー一覧（あれば）
- 追加/変更したi18nキーと `flutter gen-l10n` の実行結果
- `visual_qa_screenshots_test.dart` のフォント読み込み変更内容
- before/afterスクリーンショットの保存パス（`app/build/visual_qa_before/` / `app/build/visual_qa/`）と比較結果
- 追加/更新したwidget testの対象と結果
- 品質ゲート6点、`check_hardcoded_strings.sh`、`git diff --check` の実行結果
- やらなかったことが守られていること（新機能なし、新規pub依存なし、Rust/FRB/DB/domain/storage変更なし、Lists/Trash構成変更なし）
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` を変更していないこと
- `todori-private/` と `.github/` を変更していないこと
- public/private境界の確認結果
- 未解決事項・要人間判断
