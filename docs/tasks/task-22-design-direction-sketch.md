# task-22: デザイン方向性スケッチの作成

> ステータス: 完了（`## 9. 完了報告` 追記済み）
> 作業日: 2026-07-04

## 1. 背景とコンテキスト

TodoriのUIは、task-20でThemeData、共通task row、metadata、空状態、dialogなどのUI foundationが整備され、task-21で参考画像 `assets/brand/generated/todori-mobile-product.png` の方向性を実アプリへ反映した。

一方で、現時点では「柔らかく・親しみやすく・エレガント」という抽象的な方針はあるものの、今後の画面実装者が参照できる明確な画面スケッチ、モック、デザインルールが不足している。次のゴミ箱画面・復元UI、fractional index/並び替え、通知UIへ進む前に、Todoriの画面設計をぶらさないための小さなデザイン正本を作る必要がある
このタスクでは、実アプリ実装には入らず、画像モックと実装可能なデザインルールを作る。画像は方向性を揃えるための北極星であり、最終成果は「画像」と「そこから抽出したルール」の両方である。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/README.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/BACKLOG.md`
- `docs/07_Phase1計画書.md` M2-03 / M2-04 / M3-02 / M3-03 / M3-04 / M3-05 / M4-03
- `docs/tasks/task-20-ui-foundation.md`
- `docs/tasks/task-21-visual-direction.md`
- `assets/brand/generated/todori-mobile-product.png`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/task_components.dart`
- `app/lib/src/ui/states.dart`
- `app/lib/src/ui/dialogs.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`

## 3. ゴール

Todoriの「柔らかく・親しみやすく・エレガント」を、後続実装者が迷わず参照できるデザイン成果物へ具体化する。

- 主要画面の画像モックを作成する。
- 画像モックから、色、余白、角丸、typography、surface、task row、metadata、dialog、empty stateのルールを抽出する。
- 既存Flutter UI foundationへ後続タスクで反映しやすい粒度で、`docs/design/visual-direction.md` に記録する。
- 採用する表現と採用しない表現を明確に分ける。
- ゴミ箱画面・復元UI以降の実装タスクが、このデザイン正本を参照できる状態にする。

## 4. スコープ

### やること

1. **デザイン正本用ディレクトリの作成**:
   - `docs/design/` がなければ作成する。
   - `docs/design/visual-direction.md` を作成し、Todoriのデザイン方針を文章化する。
2. **画像モックの作成**:
   - 画像生成、手作業、または既存画像の派生作成により、以下の画面モックを作る。
     - リスト一覧
     - タスク一覧
     - タスク詳細
     - ゴミ箱/復元UI
     - 空状態または確認ダイアログ
   - 画像は `assets/brand/generated/` 配下に保存する。
   - ファイル名は内容が分かる名前にする。例: `todori-design-direction-lists.webp`、`todori-design-direction-tasks.webp`。
   - 画像内にprivate repo由来の情報、実在ユーザー情報、秘密情報、課金・法務・監査・公開前ロードマップの詳細を入れない。
3. **デザイントークンの記録**:
   - 色: background、surface、primary、secondary/accent、muted text、border、danger、success/warning相当。
   - 余白: 画面端、section間、row内、metadata間。
   - 角丸: screen surface、row、button、input、chip、dialog。
   - typography: 画面タイトル、section title、task title、body、metadata、empty state。
   - 影と境界線: 使う場合/使わない場合、強さ、目的。
4. **コンポーネント方針の記録**:
   - task rowの密度、checkbox、title、note preview、priority、due date、status、subtask progressの見せ方。
   - metadata chip/pillの使い方。
   - destructive action、restore action、confirm dialogの強さ。
   - empty state、loading state、error stateの見た目。
   - icon-only controlのtooltip/semantics方針。
5. **やらないデザインの明文化**:
   - かわいすぎるマスコット主導UIにしない。
   - SaaS dashboardのように硬くしすぎない。
   - Material標準そのままに寄せすぎない。
   - 装飾過多、影過多、カードの入れ子、過剰なグラデーションへ寄せない。
   - セキュリティ感を過剰に前面へ出さない。
6. **既存UI foundationとの差分整理**:
   - `app/lib/src/ui/theme.dart`、`task_components.dart`、`states.dart`、`dialogs.dart` に後続で反映すべき差分を箇条書きにする。
   - このタスク内でFlutterコードは変更しない。
7. **後続タスクへの入力作成**:
   - ゴミ箱画面・復元UIで参照すべきルールを `docs/design/visual-direction.md` に明記する。
   - 画像モックをそのままピクセル再現するのではなく、実アプリで守るべき判断基準として記録する。

### やらないこと

- Flutterアプリの実装を変更しない。
- `ThemeData`、共通コンポーネント、画面、ルーティング、ARB、テストを変更しない。
- Rust API、FRB生成物、DB schema、domain usecaseを変更しない。
- ゴミ箱画面・復元UIを実装しない。
- fractional index、並び替え、Undo、通知、検索、タグ、設定画面を実装しない。
- Figmaや外部デザインツールの使用を必須にしない。
- 画像モックのピクセル完全再現を後続実装の受け入れ基準にしない。
- 新規pub依存、UIフレームワーク、icon packageを追加しない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更しない。
- `todori-private/` 配下を読んだり変更したりしない。private側の詳細をpublic repoへ転記しない。

## 5. 実装手順（例）

1. `git -C todori status --short` で作業ツリーを確認する。
2. 2章のファイルを読み、task-20/21で既に決まっているUI foundationと視覚文法を確認する。
3. 「柔らかく・親しみやすく・エレガント」をTodori向けに言語化する。例: 静かな日用品、急かさないタスク管理、白い余白、深いグリーン、淡いセージ、控えめな保護シグナル。
4. 主要画面の画像モックを作り、`assets/brand/generated/` に保存する。
5. `docs/design/visual-direction.md` を作成し、各画像への相対リンク、採用する要素、採用しない要素を書く。
6. デザイントークンとコンポーネント方針を、後続実装者がFlutterへ写せる粒度で書く。
7. 既存UI foundationへ後続で反映すべき差分を「後続実装メモ」としてまとめる。
8. ドキュメントと画像だけが差分になっていることを確認する。
9. 指示書末尾に「## 9. 完了報告」を追記する。

## 6. 受け入れ基準

- [ ] `docs/design/visual-direction.md` が作成されている。
- [ ] リスト一覧、タスク一覧、タスク詳細、ゴミ箱/復元UI、空状態または確認ダイアログの画像モックが `assets/brand/generated/` 配下に保存されている。
- [ ] 各画像モックが `docs/design/visual-direction.md` から参照されている。
- [ ] `docs/design/visual-direction.md` に「柔らかく・親しみやすく・エレガント」をTodori向けに具体化した説明がある。
- [ ] 色、余白、角丸、typography、surface、影/境界線の方針が記録されている。
- [ ] task row、metadata chip、empty state、dialog、destructive/restore action、icon-only controlの方針が記録されている。
- [ ] 採用する表現と採用しない表現が分けて記録されている。
- [ ] 既存UI foundationへ後続で反映すべき差分が、`theme.dart` / `task_components.dart` / `states.dart` / `dialogs.dart` などの対象別に整理されている。
- [ ] ゴミ箱画面・復元UIで参照すべきデザイン判断が明記されている。
- [ ] Flutterアプリ実装、Rust API、FRB生成物、DB schema、domain usecaseに変更が入っていない。
- [ ] 新規pub依存、UIフレームワーク、icon packageが追加されていない。
- [ ] 画像内にprivate repo由来の情報、秘密情報、実在ユーザー情報、公開前ロードマップ詳細が含まれていない。
- [ ] `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` が変更されていない。
- [ ] `todori-private/` 配下が変更されていない。
- [ ] `git -C todori status --short` で意図したドキュメント・画像差分だけが表示されている。
- [ ] `docs/tasks/task-22-design-direction-sketch.md` の末尾に「## 9. 完了報告」が追記され、8章の項目がすべて記載されている。

## 7. 制約・注意事項

- このタスクはデザイン成果物作成であり、アプリ実装タスクではない。
- 画像モックは後続実装の方向性を揃えるための参照であり、ピクセル完全再現を要求しない。
- TodoriはE2EE Todoアプリである。安心感は出すが、未実装のKeychain本実装、アプリロック、同期E2EE、外部監査済み状態を示唆しない。
- Phase 1はローカル専用である。同期、アカウント、課金、Organization、AI、MCP/CLI実機能の画面を先取りしない。
- public repoに残す成果物として、画像・文書とも公開可能な抽象化済み内容にする。
- 既存の `assets/brand/generated/todori-mobile-product.png` は参考入力であり、唯一の正解ではない。
- 後続実装者が使えるよう、主観的な雰囲気だけで終わらせず、トークンやコンポーネント単位へ落とす。
- 実装した本人は最終合否判定をしない。完了報告後の検証は別セッションまたは親Codexが行う。

## 8. 完了報告に含めるべき内容

- 作業日
- 読んだファイル
- 作成した画像モックのファイル一覧
- 作成または更新したデザイン文書
- Todori向けに具体化したデザインコンセプト
- 採用した表現と採用しなかった表現
- デザイントークンの要約（色、余白、角丸、typography、surface、影/境界線）
- コンポーネント方針の要約（task row、metadata chip、empty state、dialog、destructive/restore action）
- ゴミ箱画面・復元UIへ渡すデザイン判断
- 既存UI foundationへ後続で反映すべき差分
- public/private境界の確認結果
- 変更しなかったもの（Flutter実装、Rust/FRB/DB/domain、docs/01〜03、todori-private）
- 検証結果（差分確認、画像・文書リンク確認）
- 未解決事項・要人間判断

## 9. 完了報告

- 作業日: 2026-07-04
- 読んだファイル:
  - `AGENTS.md`
  - `docs/tasks/README.md`
  - `docs/tasks/PLAYBOOK.md`
  - `docs/tasks/BACKLOG.md`
  - `docs/07_Phase1計画書.md` M2-03 / M2-04 / M3-02 / M3-03 / M3-04 / M3-05 / M4-03
  - `docs/tasks/task-20-ui-foundation.md`
  - `docs/tasks/task-21-visual-direction.md`
  - `assets/brand/generated/todori-mobile-product.png`
  - `assets/brand/generated/todori-desktop-product.png`
  - `assets/brand/generated/todori-mascot-kit-refined-no-border.png`
  - `assets/brand/generated/todori-mascot-kit-no-sticker-border.png`
  - `app/lib/src/ui/theme.dart`
  - `app/lib/src/ui/task_components.dart`
  - `app/lib/src/ui/states.dart`
  - `app/lib/src/ui/dialogs.dart`
  - `app/lib/src/screens/lists_screen.dart`
  - `app/lib/src/screens/tasks_screen.dart`
  - `app/lib/src/screens/task_detail_screen.dart`

### 作成した画像モック

- `assets/brand/generated/todori-design-direction-lists.webp`
- `assets/brand/generated/todori-design-direction-tasks.webp`
- `assets/brand/generated/todori-design-direction-task-detail.webp`
- `assets/brand/generated/todori-design-direction-trash-restore.webp`
- `assets/brand/generated/todori-design-direction-empty-dialog.webp`
- `assets/brand/generated/todori-design-direction-mobile-focus-tasks.webp`
- `assets/brand/generated/todori-design-direction-focus-timer.webp`
- `assets/brand/generated/todori-design-direction-completion-state.webp`

### 作成したデザイン文書

- `docs/design/visual-direction.md`
  - 上記8枚の画像モックと既存参考画像/マスコット素材への相対リンクを記載した。
  - 画像をピクセル完全再現の基準ではなく、後続UI実装の判断基準として扱う方針を明記した。

### Todori向けに具体化したデザインコンセプト

- 「静かな日用品」: 毎日触る道具として、柔らかく、親しみやすく、急かさない。
- 「完了は勝利ではなく片付く」: 完了時は派手に祝わず、行が静かに落ち着き、必要ならUndoで戻せる。
- 「Focusは宣言」: タイマーはユーザーが「今これをする」と決めるための面であり、スコア化や圧迫感を持たせない。
- 「安心感はUIの落ち着きで出す」: 暗号化マークを常時表示せず、E2EE/ローカル保護の説明は設定・オンボーディング・文書へ寄せる。

### 採用した表現

- 深いグリーン、淡いセージ、温かい白いsurface。
- priority dot + text metadata。
- 折り返し可能なpill metadata。
- サブタスクの薄い階層線。
- ゴミ箱/復元を危険ゾーンではなく、戻せる操作画面として扱う表現。
- タイマーを通常タイマー / Pomodoro / open-ended focus の方向性として扱う表現。
- スマホのToday領域は、到着時は少し贅沢に見せ、スクロール後や作業中はcompact headerへ畳む二段階表現。
- キャラは空状態・オンボーディング・まれなfocus/完了 acknowledgementに限定する方針。

### 採用しなかった表現

- メインタスクUIへの暗号化/lockアイコン常駐。
- キャラ主導UI、常時表示の相棒/アシスタント化、各画面への過剰配置。
- Today見出しを常時大きく固定し、通常作業中もスマホの表示密度を落とし続ける構成。
- Confetti、trophy、streak、Forest風gamificationなどの完了/集中演出。
- SaaS dashboard風の硬いstatus panel、重い影、カードの入れ子、過剰なgradient。
- Phase 1範囲外の同期、アカウント、課金、AI、MCP/CLI実機能の画面化。

### デザイントークン要約

- 色: `docs/design/visual-direction.md` に `backgroundSage #F2F7EF`、`surfaceWarm #FFFCF7`、`primaryGreen #2F6F4E`、`primaryContainerSage #DDEBDD`、`borderSage #D9E3D6`、`leafGreen #6FA17B`、`softSage #A8BEA8`、`cream #F6E7B7`、`charcoal #343938`、`coral #E8755A`、`peach #F3B996`、`amber #EDB73E` の固定パレットを記録した。マスコット由来のleaf/cream/amber/peach/coralは補助色として扱い、イラスト・empty state・timer detail・priority/warning/destructiveの小さな点に限定する。
- 余白: 8px rhythm。モバイル左右16px、wide layoutは24px以上。metadataは4〜8px gapで折り返し。
- 角丸: rowは14〜16px程度、pillはfully rounded、dialog/panelは18〜24px上限。将来UIが丸くなりすぎる場合は締める。
- typography: タスク一覧のToday領域は到着時には少し贅沢に使ってよいが、作業中はcompact headerへ畳める前提にする。task titleを最優先、metadataはlabelサイズ。
- surface/影/境界線: warm white surface + thin borderを基本にし、shadowは最小限。card-in-cardを避ける。

### コンポーネント方針

- task row: completion control、priority signal、title、metadata、action affordanceの順で読む。done rowは消さずに静かにする。
- metadata chip: status / priority / due date / subtask progressに限定し、情報が多すぎる場合はdetailへ逃がす。
- empty state: 通常アプリ内でキャラを出す主な場所。短い説明と次のactionに留める。
- dialog: text-ledで静かに。destructive/restoreは正確な文言を優先し、キャラ演出を使わない。
- destructive/restore action: Trashは運用画面として扱い、restoreを明確に、permanent deleteは将来追加時に二次的かつ明示確認にする。
- icon-only control: 標準iconを優先し、tooltip/semanticsを必須にする。

### ゴミ箱画面・復元UIへ渡すデザイン判断

- Trashは危険画面ではなく「戻せる一覧」として設計する。
- 削除済み行はmuted title、削除日時などのmetadata、明確なrestore actionを持つ。
- 復元は普通の操作として扱い、派手な成功演出は不要。
- permanent deleteを入れる場合はrestoreより弱い視覚優先度にし、確認dialogを必須にする。

### 既存UI foundationへ後続で反映すべき差分

- `theme.dart`: 現在のdeep green / sage / warm whiteを維持しつつ、UIが丸くなりすぎる場合はradiusを少し締める。danger/warning helperは繰り返し用途が出てから追加する。
- `task_components.dart`: priority dot + text metadata、薄い階層線、実用的なrow densityを維持する。将来のfocus affordanceは大きな常設heroではなく、row近辺または選択タスク面へ小さく入れる。
- `states.dart`: optional mascot slotを追加する場合はempty state中心に限定する。error stateへキャラを入れない。
- `dialogs.dart`: Trash/restore/destructive系は静かなtext-led dialogを維持する。キャラ演出を追加しない。
- 将来timer task: workflow追加になるため別タスク化し、normal timer / Pomodoro / open-ended focusを明示的な状態として設計する。
- 将来completion/Undo task: 完了直後のquiet stateとUndo snackbarを中心にし、celebration mechanicsを入れない。

### public/private境界

- 成果物はpublic repoに置ける抽象化済みデザイン方針のみで構成した。
- private repo由来の課金、収益、法務、監査、公開前ロードマップ詳細は含めていない。
- E2EE/ローカル保護の表現は、Phase 1で未実装のKeychain本実装、アプリロック、同期E2EE、外部監査済み状態を示唆しないよう制限した。

### 変更しなかったもの

- Flutter実装は変更していない。
- Rust API、FRB生成物、DB schema、domain usecaseは変更していない。
- `docs/01_企画書.md` / `docs/02_機能仕様書.md` / `docs/03_技術仕様書.md` は変更していない。
- `todori-private/` 配下は読んでおらず、変更していない。
- 新規pub依存、UIフレームワーク、icon packageは追加していない。

### 検証結果

- task-22画像8枚をPNGからlossless WebPへ変換し、`file assets/brand/generated/todori-design-direction-*.webp ...` でWebPとして存在することを確認した。
- `docs/design/visual-direction.md` からtask-22画像8枚と既存参考画像/マスコット素材への相対リンクを記載した。
- 人間判断により、非採用の既存マスコット画像6枚（`todori-mascot-2d-*`、`todori-mascot-concept.png`、`todori-mascot-kit-identity-board.png`）を削除対象にした。
- `git -C todori status --short` で、意図したドキュメント・画像差分のみが残っていることを確認した。
- このタスクはFlutter/Rust実装変更なしのため、`cargo fmt` / `cargo clippy` / `cargo test` / `flutter analyze` / `flutter test` / `check_hardcoded_strings.sh` は実行対象外とした。

### 未解決事項・要人間判断

- タイマー機能はユーザー要望として明確になったが、Phase 1計画ではスコープ外のため、実装する場合は別途タスク化が必要。
- キャラの実アプリ投入量は「空状態・オンボーディング中心」を初期方針とし、実装時のスクリーンショットで過剰に見えないか再判断する。
