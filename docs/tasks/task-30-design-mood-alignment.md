# task-30: design mood alignment ── typography / metadata quieting / row density

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-05

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

## 9. 完了報告

### 作業日

2026-07-05

### 読んだファイル

- `AGENTS.md`
- `docs/tasks/README.md`
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
- `app/lib/l10n/app_en.arb` / `app_ja.arb`
- `app/pubspec.yaml`
- `app/test/widget_test.dart`
- `app/test/support/fake_bridge_service.dart`
- `app/test/visual_qa/visual_qa_screenshots_test.dart`
- `app/tool/visual_qa.sh`
- `app/tool/check_hardcoded_strings.sh`
- 参照画像: `assets/brand/generated/todori-design-direction-mobile-focus-tasks.webp` / `-tasks.webp` / `-task-detail.webp`（`sips`でPNGへ変換してReadツールで目視）

`docs/tasks/PLAYBOOK.md` と `docs/tasks/BACKLOG.md` はリポジトリに現存しなかった（`docs/tasks/README.md` のタスク一覧とAGENTS.mdの記述で代替した）。未解決事項に記録する。

### フォント資産の取得方法とライセンス確認

- 取得元: Google Fonts CSS2 API を weight ごとに個別リクエストして TTF URL を取得（例: `curl -A 'curl' 'https://fonts.googleapis.com/css2?family=Lora:wght@400'`、`family=Inter:wght@500` 等）。返ってきた `fonts.gstatic.com/.../*.ttf` URLを `curl -A 'curl'` で取得。
- 取得した weight: Lora/Inter とも Regular(400) / Medium(500) / SemiBold(600) / Bold(700) の4 static weight。variable fontは使用していない。
- 配置先: `app/assets/fonts/Lora/Lora-{Regular,Medium,SemiBold,Bold}.ttf`、`app/assets/fonts/Inter/Inter-{Regular,Medium,SemiBold,Bold}.ttf`。
- `file` コマンドで全8ファイルが `TrueType Font data` であることを確認済み。
- ライセンス: `https://github.com/google/fonts/raw/main/ofl/{lora,inter}/OFL.txt` を取得し、`app/assets/fonts/{Lora,Inter}/OFL.txt` に同梱。取得後、`git diff --check` が指摘した行末空白（アップストリームのテンプレート由来、1行のみ）を空白のみ除去して正規化した（本文の単語・意味は無変更であることを再ダウンロード版とdiffして確認済み）。

### `theme.dart` のタイポグラフィ変更内容

- `ThemeData(fontFamily: 'Inter', ...)` を基本とし、`fontFamilyFallback: ['Hiragino Sans', 'Noto Sans CJK JP', 'Noto Sans JP']` を追加（後述の日本語グリフ対応、実機では通常OS標準フォールバックで足りるが明示した）。
- `textTheme.copyWith` で `displayLarge` / `displayMedium` / `displaySmall` / `headlineMedium` / `headlineSmall` に `fontFamily: 'Lora'` を適用。AppBarの `titleTextStyle` にも `fontFamily: 'Lora'` を追加。
- Todayヘッダー（`_HomeTasksHeader`、`displayMedium` 使用）の `fontWeight` を `w700` → `w600` に変更し、太すぎるセリフ+ボールドの組み合わせを避けた。
- 適用箇所: Todayヘッダー、Tasksセクション見出し、Task detailのタイトル、Lists画面タイトル（`titleLarge`ベースのAppBarタイトル経由）、AppBar全般。

### タスク行のメタデータ削減内容

- `taskMetadataItemsFor` からStatus/Priorityチップを完全に削除（Tasks画面・detail画面のサブタスク行が対象）。状態はチェックボックス/取り消し線、優先度はpriority dot + tooltip/semanticsのみで伝える。
- Due表記を `formatRelativeDueDate` で相対化: 今日→`dueToday`（Today/今日）、明日→`dueTomorrow`（Tomorrow/明日）、それ以外→`DateFormat.MMMd(locale)`。`taskDueAt` ARBから「Due: 」プレフィックスを削除（値をそのまま表示するテンプレートに変更）。期限切れは `emphasisColor` でcoral着色し、`taskDueOverdue`（新規キー）をsemanticLabelとして付与し色だけに依存しないようにした。
- サブタスク進捗チップは `subtaskProgress` ARBから「Progress: 」プレフィックスを削除し `{doneCount}/{totalCount}` の短い表記にした。アイコン（`account_tree_outlined`）は維持。
- priority dotの色トークンを `docs/design/visual-direction.md` に合わせて固定: high=`#E8755A`（coral）、medium=`#EDB73E`（amber）、low=`#A8BEA8`（softSage）、none=dot非表示。従来のbrightness分岐（緑/黄/赤系）を廃止し、トークンどおりの固定色にした（未解決事項に注記）。

### 行密度圧縮の内容

- `_TaskRowLeading` の `Checkbox` に `shape: const CircleBorder()` を追加し円形化した（タップ領域48x48は維持）。
- `AppTaskRow` から `LayoutBuilder` ベースの「狭幅/Dynamic Typeでchevron/並び替えcontrolを独立した最下行へ逃がす」ロジックを削除し、常に行の右端に `SizedBox(height: 48, child: Center(child: trailing))` で垂直センター配置する構成にした。
- 行のPadding上下を `AppSpacing.sm`(8) から `AppSpacing.xs`(4) に詰め、メタデータなしタスクがタイトル1行＋αに収まるようにした。

### Tasksホームヘッダーの変更内容

- `_HomeTasksHeader` から `_PendingBadge` を削除（重複表示の解消）。pending数は `_TaskSectionHeader` の1箇所のみに統一。
- `_TaskSectionHeader` を `DecoratedBox`（card + border）から、`Row`（Lora見出しテキスト + pendingピル + 追加button）のプレーンな見出し行に変更し、card-in-card感を解消した。

### Task detail画面の変更内容

- `AppProtectionSignal`（Local protectionロックチップ）の呼び出しを削除し、ウィジェット自体も未使用になったため削除した。
- タイトルブロックを `Material`（border付きcard）から、背景に直接置く `Column` に変更。タイトル行の先頭に `PriorityDot`（priorityがある場合のみ）を追加し、priorityチップの代わりにdot+tooltip/semanticsで伝える構成にした。
- `Created at:` の生epoch表示バグを修正。`formatAbsoluteDate(locale, epochMs)`（`DateFormat.yMMMd`）を新設し、`taskCreatedAt` ARBのplaceholder型を `int` → `String` に変更、フォーマット済み文字列を渡すようにした。
- メタデータは `taskMetadataItemsFor(..., includeStatus: true, includeNoDueDate: true)` で、Statusのみ「Status: 」プレフィックスなしの短い表記（`taskStatusLabel`直値）で残し、Due/subtask progressは行と同じ文法（相対日付・短縮progress）にした。

### 削除したl10nキー一覧

- `taskStatus`（"Status: {status}"）: rowからStatusチップを削除したことで全箇所で未使用になったため削除。
- `localProtectionLabel` / `localProtectionTooltip`: Local protectionチップ削除に伴い削除。

### 追加/変更したi18nキーと `flutter gen-l10n`

- 追加: `dueToday`（"Today" / "今日"）、`dueTomorrow`（"Tomorrow" / "明日"）、`taskDueOverdue`（"Overdue: {dueAt}" / "期限超過: {dueAt}"、semanticsのみで使用）。
- 変更: `taskDueAt` の値を "Due: {dueAt}" → "{dueAt}" に変更（prefix除去）。`subtaskProgress` を "Progress: {doneCount}/{totalCount}" → "{doneCount}/{totalCount}" に変更。`taskCreatedAt` のplaceholder型を `int` → `String` に変更。
- `cd app && flutter gen-l10n` を実行し、`app/lib/src/generated/l10n/` 配下（`app_localizations.dart` / `_en.dart` / `_ja.dart`）を再生成した。手編集はしていない。

### `visual_qa_screenshots_test.dart` のフォント読み込み変更内容

- バンドルした `assets/fonts/Inter/*.ttf`（4 weight）を `FontLoader('Inter')` に、`assets/fonts/Lora/*.ttf`（4 weight）を `FontLoader('Lora')` にそれぞれ登録するよう変更した。
- 当初、指示書どおり「同一familyに日本語グリフ用のヒラギノを追加登録してフォールバックさせる」実装を試みたが、実機検証の結果、weightの異なる複数typefaceが同一family内に存在すると、Skiaのスタイルマッチングが常に「重み距離が最も近いLatin typeface」を選び、そのtypefaceがカバーしないグリフ（日本語）についてsame-family内の他typefaceへフォールバックしない（tofu表示になる）ことを実機で確認した。
- 対策として、`ThemeData.fontFamilyFallback`（`theme.dart`側で追加した `['Hiragino Sans', 'Noto Sans CJK JP', 'Noto Sans JP']`）と対応させ、テストハーネス側で `Hiragino Sans` という別familyにヒラギノ角ゴシックW3を単独登録する方式に変更した。この方式は公式にサポートされた `fontFamilyFallback` の仕組みであり、実際にスクリーンショットで日本語・セリフ見出し双方が正しく描画されることを確認した（詳細はコード内コメントに記録）。
- Material Iconsのロードは既存のまま維持。

### before/afterスクリーンショットの保存パスと比較結果

- before: `app/build/visual_qa_before/`（作業開始前の既存 `app/build/visual_qa/` を退避したもの。task-28/29時点の状態）
- after: `app/build/visual_qa/`（`sh app/tool/visual_qa.sh` 実行後の最新出力）
- 比較結果（目視、Readツールで両方確認済み）:
  - `home_tasks.png`: Status/Priorityチップが消え、Dueが相対表記（Today/Tomorrow/Jul 1）になった。Today/Tasks見出しがLora（セリフ）で描画されている。pending数表示が1箇所（Tasksセクション行）になった。チェックボックスが円形になり、チェブロンが行右端に垂直センター配置され、メタデータなし行がタイトル1行＋αの高さに収まっている。priority dotがcoral/amber/softSageのトークン色になっている。日本語タイトル（地図アプリのUI微調整を仕上げる、等）が正しく描画されている（beforeの時点でも日本語は表示されていたが、フォント変更後も引き続き正しく描画されることを確認）。
  - `task_detail.png`: Local protectionチップが消え、`Created at: Jan 1, 1970` のようにロケール日付表記になった（beforeは `Created at: 5` という生epoch値のバグがあった）。タイトルブロックがborder付きcardでなくなり、背景に直接タイトル（Lora）+ priority dot + メタデータチップが並ぶ構成になった。pending数の重複表示バグ（beforeにはなかったが、Tasksセクション側の修正に対応）は該当なし。
  - `lists.png` / `home_tasks_empty.png` / `trash.png` / `task_edit_dialog.png` / `confirm_dialog.png`: いずれもLora見出し・Inter本文が反映され、既存機能（trash chip、edit dialog、confirm dialog）はレイアウト崩れなく表示されている。Trash画面はChip文法・構成とも変更していない（意図どおり）。

### 追加/更新したwidget testの対象と結果

- `test/l10n_test.dart`: `localProtectionLabel` の期待値を削除し、`dueToday` の期待値（en: "Today" / ja: "今日"）に置き換えた。
- `test/widget_test.dart`:
  - `tapping a list navigates to its task list`: 既存の `Local protection` findsNothing はそのまま維持。
  - `polished list, sort, detail, and dialog surfaces stay stable`: detail画面のPriority確認を `find.text('Priority: High')` から `find.byTooltip('Priority: High')` に変更（priorityがdot+tooltipのみになったため）。
  - `tapping a task navigates to its detail screen`: `Local protection` の期待を `findsOneWidget` → `findsNothing` に、`Status: To do` を `To do`（短縮表記）に変更。
  - `task list shows three-level subtasks with descendant progress`: `Progress: 1/2` / `Progress: 1/1` を `1/2` / `1/1`（短縮表記）に変更。
  - `editing a task updates detail, list, and fake bridge state`: detail画面のPriority確認を `find.byTooltip('Priority: High')` に変更。
  - `long task titles survive narrow width and Dynamic Type`: 行密度圧縮により長いタイトルの折返し行数が増え固定drag量(-220px)では目的の行に届かなくなったため、`tester.drag` の固定オフセットを `tester.scrollUntilVisible` に置き換えた（意図＝狭幅+長文+Dynamic Type耐性+並び替え操作フローの検証は維持、スクロール手段のみ頑健化）。
  - いずれも既存テストの意図（長文/狭幅/Dynamic Type耐性、操作フロー）は弱めていない。finder変更は構造変更に追従する最小限。
- 結果: `flutter test`（visual QA harnessを除く37件）全て成功。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功（Rust全crateのユニットテスト成功、変更なし）。
- `cd app && flutter analyze`: 成功（No issues found）。
- `cd app/rust && env CARGO_TARGET_DIR=target cargo build --release` → `cd app && flutter test`: 成功（37 tests passed、visual QA harnessはskip）。
- `sh app/tool/check_hardcoded_strings.sh`: 成功（検出なし）。
- `git diff --check`: 成功（OFL.txtの行末空白を正規化した後）。

### やらなかったことの遵守確認

- 新機能追加なし（Focus timer、検索、通知、設定画面、マスコット画像組み込み、bottom navigation、いずれも未実装のまま）。
- Rust API / FRB / DB schema / domain / storage / core配下 / cli / mcp-server / server の変更なし（`cargo test --workspace` の結果も無変更で全通過）。
- 新規pub依存の追加なし（`pubspec.yaml` の `dependencies:` は無変更、`fonts:` セクションのみ追加）。`google_fonts` パッケージ等は使用していない。
- Lists画面・Trash画面の構成変更なし（`lists_screen.dart` / `trash_screen.dart` は無変更。テーマ経由のフォント/色トークンの波及のみ）。

### `docs/01〜03` の変更有無

- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない（`git status` で確認済み）。

### `todori-private/` と `.github/` の変更有無

- どちらも変更していない（`git status` に該当パスの差分なし）。

### public/private境界の確認結果

- 変更はすべて `app/` 配下のUI実装・アセット・テストと `docs/tasks/task-30-*.md` の完了報告のみ。private repo固有の課金・収益・法務・監査・非公開ロードマップ情報の転記はない。フォントはOFL（SIL Open Font License）ライセンスのGoogle Fonts資産で、ライセンスファイルを同梱済みのためpublic repo公開に問題はない。

### 未解決事項・要人間判断

1. `docs/tasks/PLAYBOOK.md` と `docs/tasks/BACKLOG.md` が指示書2章に記載されているが、現在のリポジトリに存在しなかった。`docs/tasks/README.md` のタスク一覧とAGENTS.mdの記述で代替して読み進めた。ファイル構成とタスク指示書の記述に差異がある可能性がある。
2. 指示書は「FontLoaderは同一familyに複数フォントを追加登録でき、後続がグリフフォールバックになる」と明記しているが、実機検証の結果、重み(weight)の異なる複数typefaceが同一family内にある場合はこの仕組みが機能せず（tofu表示になる）、`ThemeData.fontFamilyFallback` を使った別family方式に変更する必要があった。指示書のFontLoader前提が現在のFlutter engineの挙動と一致しない可能性があり、他タスクでも同様の技法を使う場合は注意が必要。
3. Task detail画面の主タスク自体のPriority表現について、指示書F章は「メタデータチップはC.と同じ文法（Status表記はdetailでは残してよい）」と記載しており、Priorityについての明示的な例外記述はなかったため、C章の「Priorityチップを行から削除する」をdetailの主タスクにも適用し、priority dot + tooltip/semanticsのみで伝える実装にした。参照画像（`todori-design-direction-task-detail.webp`）では「High priority」という文言付きチップが描かれているが、visual-direction.mdの「Calibration Rule」（画像は方向性の参考であり最終レイアウトの真実ではない）に従い、指示書本文の記述を優先した。この解釈が意図と異なる場合は別タスクでの手直しが必要。
4. priority dotの色をbrightness(light/dark)で分岐させず、design-directionのトークン色（coral/amber/softSage）に固定した。ダークテーマでのコントラスト・視認性は今回の`visual_qa`ハーネス（ライトテーマのみスクリーンショット）で未検証。
5. `AppProtectionSignal` ウィジェットクラスは完全に削除した（未使用になったため）。将来的に設定/オンボーディング画面でセキュリティ説明用に同種のUIが必要になった場合は、再実装が必要になる。
6. Trash画面の日付表示（`taskDeletedAt` / Trash行のDueチップ）は今回のDue相対化・プレフィックス除去の対象外とした（Trash画面の構成変更をしない、という指示書のスコープ制約に従い、`formatDueDate`（絶対日付・YYYY-MM-DD）をそのまま維持）。相対日付表記との一貫性が将来的に議論になる可能性がある。
