# Todori UI Spec ── 拘束力のある具体値と判断規則

> Status: binding implementation spec
> Last updated: 2026-07-08

`docs/design/visual-direction.md` は方向性と哲学を扱う。本書は**実装時に従う具体値と判断規則**を定める。両者が矛盾した場合は本書が優先する。本書の変更は設計タスク（またはドッグフーディング/親レビュー起点のタスク）経由でのみ行う。実装エージェントが自己判断で本書を書き換えてはならない。

「親しみやすく・落ち着いて・エレガント」という形容詞そのものを実装判断の根拠にしてはならない。形容詞は本書の規則へ翻訳済みである。指示書・完了報告・レビューはすべて本書のセクション番号か具体的な値/規則を引用して書くこと。

## セクション1: 形容詞の翻訳表

### 親しみやすい（friendly）とは

- 丸いフォルム: 円形チェックボックス、pill型チップ（角丸999）、カードの角丸（セクション2のRadius表の値）。
- 人間の言葉: 相対日付（Today/Tomorrow/短い月日表記）。ISO日付（`2026-07-05`のような形式）や内部ステータス文字列（`todo`/`in_progress`等の生値）をUIに出さない。
- 日付・時刻の表記はホストOSの言語・ロケール設定に従う（2026-07-06人間指示）。`DateFormat` は固定パターン文字列ではなく skeleton API（`yMMMEd` 等）を用い、言語ごとの自然な語順・区切りをintlに委ねる。相対表記（Today/明日等）のl10n文言はこの原則の例外として維持する。
- 挿絵・マスコットは空状態とオンボーディングのみ。通常のタスク一覧・詳細・ダイアログには出さない。
- ディスプレイセリフ（Newsreader＋システム和文セリフ）の柔らかい見出し（Home日付見出しのみ、セクション2参照）。
- **こうではない**: 派手な色、キャラの常駐、感嘆符、絵文字、celebration演出。

### 落ち着いた（calm）とは

- 背景sage × 表面warm whiteの2層構造のみ。第3の面色を発明しない。
- 影なし・1pxのthin border（dialog/sheet/FABのみ最小限の`elevation`可、値はセクション2参照）。
- 1画面の色数上限: 緑系2（primary / primaryContainer）＋中立2（onSurface / onSurfaceVariant）＋アクセント最大1（coral または amber、どちらか一方のみを主に使う）。
- 同じ情報を画面内に2回出さない（例: pending数はTasksセクション見出しの1箇所のみ）。
- **こうではない**: 灰色一色の無機質さ、要素を全部薄くすること。

### エレガント（elegant）とは

- セリフ見出し（ディスプレイセリフ: Newsreader＋システム和文セリフ、Home日付見出しのみ）とサンセリフ本文（Inter）の対比。
- 余白による分離。線・囲み・カードを増やして分離しない（card-in-card禁止）。
- 正確な整列: dot・チェック・テキストの整列基準を明示指定する（「なんとなく上寄せ」禁止。セクション3参照）。
- 小さく精密なメタデータ（チップは行あたり最大2個）。
- **こうではない**: 装飾の追加。エレガンスは足して作るものではなく、削って整えた結果である。

## セクション2: 拘束トークン（現行実装の実値を正とする）

以下は `app/lib/src/ui/theme.dart` と `app/lib/src/ui/task_components.dart` の現行実装から転記した実値である。この表にない値を新規に発明してはならない。値を変えたい場合は設計タスクとして本書を更新してから実装する。

### タイポグラフィ（role別）

| Role | 使用箇所 | TextTheme | フォント | Weight | 色 |
|---|---|---|---|---|---|
| AppBarタイトル | Tasks/TaskDetail画面のAppBar `title` | `titleLarge`（AppBarThemeの`titleTextStyle`経由） | Inter | w700 | `colorScheme.primary` |
| Home日付見出し | Home上部の1行日付（例: `July 7` / `7月7日(火)`） | `displaySmall` または `displayMedium` を28-32px級へ調整 | Newsreader（欧文）＋ システム和文セリフフォールバック（`fontFamilyFallback`に`'Hiragino Mincho ProN'`等） | w600（呼び出し側で明示上書き、line-height 0.95〜1.0） | `colorScheme.primary` |
| Homeリスト名ラベル | Home行タイトル下の小さなアイコン+リスト名 | `labelMedium` または `bodySmall` | Inter | w600（テーマ既定） | `colorScheme.onSurfaceVariant` |
| セクション見出し（Tasks） | 「Tasks」セクション見出し行 | `headlineSmall` | Inter | w700（テーマ既定） | `colorScheme.primary`（呼び出し側で上書き。テーマ既定は`onSurface`） |
| 完了セクション見出し | 「Completed」折りたたみ見出し | `titleMedium` | Inter | w600（テーマ既定） | `colorScheme.onSurfaceVariant` |
| リスト一覧の行タイトル | `/lists` の各リスト名 | `titleLarge` | Inter | w600（呼び出し側で明示） | `colorScheme.onSurface` |
| タスク行タイトル | `AppTaskRow` のタイトル | `titleMedium` | Inter | w600（テーマ既定） | 未完了=`onSurface` / 完了=`onSurfaceVariant`+取り消し線 |
| タスク詳細タイトル | Task detail見出し | `headlineSmall` | Inter | w700（テーマ既定） | `colorScheme.onSurface`（上書きなし） |
| タスク詳細メモ | note本文 | `bodyLarge` | Inter | 既定 | `colorScheme.onSurfaceVariant`（line-height 1.35） |
| メタデータpill文字 | `TaskMetadata`のpillラベル | `labelMedium` | Inter | w600（テーマ既定） | `colorScheme.primary`、または`emphasisColor`（例: 期限切れcoral） |
| Subtasks小見出し | 詳細画面の「Subtasks」 | `titleMedium` | Inter | w600（テーマ既定） | 既定色（上書きなし） |
| 作成日キャプション | 詳細画面のcreated at | `bodySmall` | Inter | 既定 | `colorScheme.onSurfaceVariant` |

- 基準フォント: `fontFamily: 'Inter'`（`ThemeData`既定）。Newsreaderのセリフ上書きはHome日付見出しなどのdisplayロールのみで、**28px級以上かつ1画面1〜2箇所**の規則を厳守する（2026-07-06タイポ裁定）。`titleLarge`・`headlineSmall`・`titleMedium`・`labelMedium`・本文系はセリフ化しない。
- 日本語グリフはNewsreader/Interにバンドルされないため、`fontFamilyFallback` を経由してプラットフォームフォールバックへ委ねる（新規日本語フォント同梱はしない、2026-07-06タイポ裁定）。Home日付見出しの和文は明朝系フォールバック（`'Hiragino Mincho ProN'`等）、その他Inter適用箇所の和文は角ゴシック系フォールバック（`'Hiragino Sans'`等）を使う。
- ビューポート幅に応じた文字サイズのスケーリングはしない。プラットフォームのテキストスケーリングと折返しに委ねる。

> この表は2026-07-06タイポ裁定後の目標状態であり、task-34で本番実装（`app/lib/src/ui/theme.dart` / `app/pubspec.yaml`）へ反映済みである。以後この表を変更したい場合は設計タスクとして本書を更新してから実装すること。

### 角丸（Radius、現行値をcanon化）

| 用途 | 値 | 出典 |
|---|---:|---|
| 汎用`Card`（`CardThemeData`） | 18 | `theme.dart` `cardTheme` |
| FAB | 18 | `theme.dart` `floatingActionButtonTheme` |
| タスク行（`AppTaskRow`のMaterial/InkWell） | 16 | `task_components.dart`（汎用Cardの18とは別の実値。行の分離を汎用カードよりわずかに締める） |
| Dialog | 20 | `theme.dart` `dialogTheme` |
| PopupMenu | 16 | `theme.dart` `popupMenuTheme` |
| Filled/Outlined/TextButton、Input、SnackBar | 14 | `theme.dart` 各`ButtonStyle`・`inputDecorationTheme`・`snackBarTheme` |
| Chip/pill（メタデータpill、pending badge、list name pill等） | 999（完全な丸） | `task_components.dart` `_MetadataPill`、`tasks_screen.dart` 各pill |

**この表にない角丸値を発明しない。** 新しい面が必要になったら上記のいずれかの値を再利用する。

### 間隔（AppSpacing、`theme.dart`で定義された5段階のみを使う）

| トークン | 値 |
|---|---:|
| `AppSpacing.xs` | 4 |
| `AppSpacing.sm` | 8 |
| `AppSpacing.md` | 16 |
| `AppSpacing.lg` | 24 |
| `AppSpacing.xl` | 32 |

- 画面横padding: 通常画面は `AppSpacing.md`（16）。Homeは2026-07-07 Home裁定により横幅を優先し、パネル/セクション外側は `AppSpacing.sm`（8）級まで圧縮してよい。
- 行内padding: 実装は縦`AppSpacing.xs`（4）〜`AppSpacing.sm`（8）程度、横は通常行で左端インデント（`AppSpacing.md` + 深さ×`AppSpacing.lg`）＋右端`AppSpacing.sm`。Home行は左右12〜16px級に収め、深さ表示がない横断行では余白を増やしてカード化しない。
- セクション間: `AppSpacing.lg`（24）〜`AppSpacing.xl`（32）。Home上部の日付見出しとセクション群の間は、トップ圧縮を優先して `AppSpacing.md`（16）〜`AppSpacing.lg`（24）を目安にする。
- メタデータ内の間隔（pill同士、アイコンとラベル）: `AppSpacing.xs`（4）。
- `AppSpacing`にない中間値（例: 20, 28）を新規に使わない。例外として、2026-07-07 Home裁定に基づくHome行の左右paddingのみ12px級を許容する。

### 色（用途の拘束。パレット本体は`visual-direction.md`参照）

- `coral`（`#E8755A`）: 期限切れの強調、破壊的操作（削除確定）、high priority dotのみ。装飾や通常状態には使わない。
- `amber`（`#EDB73E`）: medium priority dot、タイマー詳細（将来機能）、小さな強調のみ。大面積の背景色にはしない。
- Priority dot色（固定・現行実装値）:
  - high (`priority == 3`) = `#E8755A`（coral）
  - medium (`priority == 2`) = `#EDB73E`（amber）
  - low (`priority == 1`) = `#A8BEA8`（softSage）
  - none (`priority <= 0`) = dot自体を描画しない（非表示。色を透明にするのではなくウィジェットを出さない）
- 1画面のアクセント色は原則1系統（coral or amber）に絞る。両方を同時に主張させない。

### サイズ

- Priority dotの直径: 11px（`Container(width: 11, height: 11)`、`task_components.dart` `PriorityDot`）。旧仕様案の8pxではなく11pxが現行実装値であり、これをcanonとする。
- チェックボックス/完了アイコンのタップ領域: 48×48（`AppTaskCheckbox`の`SizedBox(width: 48, height: 48)`）。
- 行右端のシェブロン/並び替えコントロールの領域: 高さ48（`SizedBox(height: 48)`で中央揃え）。
- メタデータpill内アイコン: 15px。
- チップは1行あたり最大2個。3個目が必要になったら詳細画面へ送る（セクション3参照）。

## セクション3: コンポーネント解剖図

### タスク行（`AppTaskRow`）

構成順序（左から右）:

1. 円形チェック/完了アイコン（48×48タップ領域）
2. タイトル（`titleMedium`、折返し可）
3. メタデータ行（タイトルの下、最大2チップ + priority dot。priority dotはpriorityが1以上のときのみメタデータ行の先頭に置く）
4. 右端: 通常表示では何も置かない。手動並び替えモードでも上下移動ボタンは置かず、長押しドラッグ&ドロップで順序を変更する

**整列規則（重要）**: チェックボックス（先頭コントロール）は「タイトルの1行目」と垂直センター整列させる。行全体（複数行になったメタデータ込みの高さ）とのセンター整列ではない。priority dotはタイトル脇へ置かず、メタデータ行の先頭で日付pillと同じ行の中央に揃える。

メタデータの順序: priority dot（priority noneの場合は非表示）→ 日付pill（相対表記: Today/Tomorrow/短い月日）→ 進捗pill（`1/3`形式）。3個目のメタデータが必要になった場合はチップを増やさず詳細画面へ送る。priority noneのときはメタデータ行の先頭が日付pillになる。

完了行の表現: チェックはfilled/mutedのcheck_circle系アイコン、タイトルはstrikethrough + `onSurfaceVariant`、行の面（Material color）はやや不透明度を下げて背景に沈める（現行実装は`surface.withValues(alpha: 0.72)`、borderも`outlineVariant.withValues(alpha: 0.7)`）。

Closed（`done` / `wont_do`）状態のルートタスク行の先頭コントロールをタップすると、確認ダイアログなしで `todo` へ再オープンする。これは2026-07-07ドッグフーディング由来の規則であり、既存の完了時Undoスナックバー動線とは独立した操作である。

チェックボックスは表示される場所すべて（一覧のルート行、ネストされたサブタスク行、詳細画面のSubtasks行、アーカイブ済みリストを開いた画面内）で常にトグルとして機能する。未完了（`todo` / `in_progress`）をタップした場合は `done` へ、Closed（`done` / `wont_do`）をタップした場合は `todo` へ遷移する。未完了子孫を持つタスクを完了する場合の確認ダイアログは維持する。閲覧専用のチェックボックスまたは見た目だけの完了アイコンを作らない。この規則は2026-07-07ドッグフーディング第2回由来である。

チェックボックス表現: 未チェックリングはstroke 1.5px級・`onSurfaceVariant`系のmuted色とする。チェック時は塗り + チェックマークがスケールイン（250ms級、軽いオーバーシュート = `easeOutBack` 系）で描画され、チェック解除は静かな短いフェード（150ms級）で戻る。紙吹雪等のcelebrationはしない。この規則は2026-07-08ドッグフーディング第5回由来である。

### タスク一覧構造

Homeのタスク行群は、Overdue / Today / Tomorrow / Upcoming の4セクションに分ける。単一の大きなwarm white surface + 外側1px borderパネルの中へ各セクションを収める構造は維持してよいが、パネル外側マージンは8px級へ圧縮し、横幅を優先する。行ごとの独立した重いカード、強いborder、card-in-cardの見え方は禁止する。

各セクションは、見出し + 件数バッジ + 開閉chevronで構成する。Overdue見出しはcoral、Today/Tomorrow/UpcomingはprimaryまたはonSurface系を使い、色だけに依存せず見出し文言でも意味を伝える。Upcomingは明後日以降の期日ありルートタスクを含める。期日なしルートタスクはHome対象外である。

Homeセクションのルートタスクは、期日の有無に関わらず、開いている配下サブツリー全体を階層ガイド付きで連れて表示する。同一セクション内の重複は排除し、子が同一セクションに該当する場合は親の下にのみ表示する。子が親と異なる、より早いセクションに該当する場合は、その子を該当セクションにも単独表示する。この単独表示は親コンテキストなしの現行Home行表現とし、状態は親配下表示と同期する。この規則は2026-07-08ドッグフーディング第4回由来である。

Home行は、左からチェック、タイトル/小さなリスト名ラベル、右寄せメタデータの順に構成する。タイトル下にはリスト名を小さなラベル（アイコン + リスト名）として表示し、従来のリスト名pillを置き換える。priority dot + 日付pillは行右側へ寄せ、日付pillは枠線なしの色付きpillにする。日付pillの面色は、期日超過=淡coral、今日=淡sage、明日以降=淡amberを基本とし、テキスト色は既存トークンのcoral/primary/amber系に従う。Home行は、ルートタスクのチェック円の左端をセクション見出しの左端と同じx位置に揃える（現行実装ではセクション内容基準で4px、パネルpadding込みで12px級）。48×48タップ領域は維持し、サブタスクの各階層は24px刻みの相対インデントを保ったまま同じ基準から左へ寄せる。この規則は2026-07-08ドッグフーディング第6回由来である。

Closedセクションに入るのはルートタスクのみ。サブタスクは状態に関わらず常に親の下に表示し、閉じたサブタスクは muted + 取り消し線で親にぶら下がる。ツリーごとClosedへ移動するのは親自身が閉じたときだけ。この規則は2026-07-07ドッグフーディング由来であり、サブタスク関係を一覧上で失わないための構造規範である。

サブタスクの階層ガイドは、縦線を親チェックボックスの水平中心から降ろし、子の横棒はその縦線から子チェックボックスの垂直中心へ向かうが、円リングの手前4px程度で終端してリングへ接触/貫入させない。各深さの子のチェックボックス中心は同一のx座標列に整列する。最後の子はL字（└）として縦線を横棒で終端し、同じ親の後続兄弟がある子はT字（├）として縦線を継続する。3階層以上のネストでは、未完了の祖先階層の縦線が子孫行まで正しく続く。この規則は2026-07-07ドッグフーディング第2回、2026-07-08ドッグフーディング第5回、および2026-07-08ドッグフーディング第6回由来である。

Closedセクション見出しは、Design Labの「Completed today N」に近い控えめな1行とする。中央寄せまたは左寄せの小さな見出し + 件数 + 開閉chevron 1つで構成し、見出し自体を大きなカードや強いボタンにしない。

手動並び替えはドラッグ&ドロップ（長押し）で行う。並び替えは同一親内の兄弟間のみ許可し、別親の間や階層をまたぐ位置にはドロップできない。上下移動ボタンは置かず、アクセシビリティはreorder semanticsアクション（Move up / Move down）で担保する。この規則は2026-07-07ドッグフーディング第3回由来である。

### チップ/pill

- 情報表示専用。ボタンとして機能させない（画面が明示的にinteractiveにする場合を除く）。
- プレフィックス付き冗長ラベル（`Due:` `Status:` `Priority:`）を禁止。アイコン＋短い語のみ（例: 相対日付そのもの、`1/3`）。
- 角丸999、`labelMedium`、アイコン15px、border thin（`outlineVariant`ベース、強調時は`emphasisColor`のalpha 0.6）。Home行の日付pillに限り、2026-07-07 Home裁定によりborderなしの淡色塗りを使う。

### 画面規範

- **Home**: ルート画面はTodayではなくHomeである。上部バー（メニュー/ソート） → セリフの日付1行（例: `July 7` / `7月7日(火)`、28〜32px級displayロール） → Overdue / Today / Tomorrow / Upcoming のセクション群 → 画面下部常設クイック追加バー。大型の「Today」見出しと日付サブ行の2段構成、画面下中央のpill型Add task FAB、入力ダイアログは廃止する。通常タスク行の右端chevronは禁止し、行タップで詳細へ遷移できることはsemanticsで明示する。Home横断ビューでは手動並び替えを行わない。
- **Homeセクション**: Overdue（見出しcoral）/ Today / Tomorrow / Upcoming（明後日以降、期日ありルートタスクのみ）を表示する。各セクションは件数バッジ付きで折りたたみ可能にする。期日なしルートタスクはHome対象外であり、従来どおり通常リスト画面で扱う。セクションに表示されるルートタスクは、期日の有無に関わらず開いている配下サブツリー全体を階層ガイド付きで連れて表示する。同一セクション内の重複は排除し、子が同一セクションに該当する場合は親の下のみ、子が親より早い別セクションに該当する場合はそのセクションにも単独表示する。この規則は2026-07-08ドッグフーディング第4回由来である。
- **Homeクイック追加バー**: 画面下部バーはタスク作成シートのトリガーである。タップでボトムシートが開く。シートはドラッグハンドル、大きなタイトル入力（自動フォーカス）、Note入力、Listチップ（選択メニュー）、Dueチップ（日付選択/クリア）、Add taskボタンで構成する。既定値はHomeでは既定Inbox+今日、通常リスト画面では当該リスト+期日なしとする。追加後もシートは開いたまま入力がクリアされ、連続追加できる。時刻（Plan）チップは時刻機能実装まで置かない。自然言語日付解析は将来機能であり、現時点では実装しない。この規則は2026-07-08ドッグフーディング第4回由来である。
- **Homeスワイプ/モーション**: leading swipeは完了、trailing swipeは期日変更に割り当てる。チェック、行の出入り、セクション開閉は150〜250ms級の軽いアニメーションに留め、過剰演出、celebration、confettiは禁止する。
- **リスト一覧**: 行は純粋なナビゲーション行とし、行内に操作メニューやchevronを置かない。リスト単位の操作（改名/アーカイブ/削除）は、そのリストを開いた画面の右上overflowメニューに置く。既定インボックスでは保護対象操作（削除/アーカイブ）をメニューに表示しない。この規則は2026-07-07ドッグフーディング由来である。
- **Lists画面のHome導線**: 最上部のスマートリンク名は「Today」ではなく「Home」とする。アイコン/tooltip/semantics/l10nもHomeへ揃える。
- **Task detail**: タイトル行（先頭に円形チェックボックス + `headlineSmall`タイトル、カード囲みなし） → note（あれば。未設定時は「ノートを追加」プレースホルダ行） → メタデータ行（statusチップ、priority dot、期日チップ、進捗チップ。詳細画面のみstatusチップ追加を許容し、priority dotはタイトル脇ではなくメタデータ行へ置く。期日・優先度はタップで編集して即保存） → created（`bodySmall`キャプション） → Subtasks小見出し → サブタスク行 → actions。タイトル行先頭のチェックボックスは、一覧と同じ見た目・48px級タップ領域・常時トグル規則に従う。サブタスクの詳細では、タイトルの上に親タスクへ遷移できる親タスク名の行（控えめなリンク表現）を表示する。表示するのは直近の親のみで、祖父母以上のパンくずは出さない。タイトルとnoteはタップでその場のTextFieldに変わり、フォーカス喪失/確定で保存する。空タイトルは保存せず元に戻す。インライン編集（タイトル/ノート）の起動タップ領域は、表示テキストのコンテンツ幅ではなく行の全幅とする。読み取り表示と編集状態は同一のTextStyle、padding、strut/line-heightを使い、編集開始時に該当要素のオフセットが動かないようにする。右上の一括編集ボタンと一括編集ダイアログは禁止し、削除・status変更などのoverflowは維持する。Subtasksは直接の子だけでなく子孫ツリー全体を、一覧と同じ階層ガイド文法で表示する。インライン編集状態でもこの表のタイポグラフィ、間隔、角丸、影規則を維持する。ロック/暗号化の常設表現は禁止（`visual-direction.md` Security Signal参照）。この編集がたつき防止とSubtasks子孫表示の規則は2026-07-07ドッグフーディング第2回由来であり、親リンク・全幅タップ・タイトル行チェックの規則は2026-07-07ドッグフーディング第3回由来である。
- **Dialog**: 文章主体、装飾なし。destructiveのみcoralを使う。

### Undoスナックバー

Undoスナックバーは4秒程度で自動消滅する。永続表示にしない。Undo実行後、または新しいUndoスナックバーを表示する前には既存のスナックバーを隠し、複数のUndo通知が画面上で積み重ならないようにする。この規則は2026-07-07ドッグフーディング第2回由来である。

## セクション4: 判断規則（迷ったとき）

1. 迷ったら削る。「要素を足す」か「削って整える」の二択なら常に後者を選ぶ。
2. 新しい色・角丸・サイズ・影・面色を発明しない。トークンにない値が必要になったら実装を止め、完了報告の未解決事項に書く。
3. 同じ情報を2箇所に出さない。
4. チップは1行に2個まで。
5. アイコンは Lucide（`lucide_icons_flutter`）に統一する（2026-07-06裁定）。本番反映完了までの間、既存Material Iconsは暫定として残ってよいが、新規実装や置き換え時にMaterialとLucideを同一画面へ混在させて追加しない。
6. 整列は基準（1行目センター/行全体センター/baseline）を明示して実装する。
7. 参照画像（`assets/brand/generated/`）と本書が矛盾したら本書が優先する。本書に穴があれば、タスク内では最も保守的な解（=削る側）を取り、完了報告の未解決事項でspec追記を提案する。

## セクション5: 既知の逸脱（現状 spec 違反として認識済みのもの）

- なし（2026-07-07時点）。

## 裁定済み事項

- **2026-07-06 人間裁定**: Design Lab の Today/Task 体験は当初の3案比較（calm/dense/smart lists）から、人間がAIと共同で探索した結果、**calm発展形の単一方向**（現行 `design_lab_task_list.png` 等の8画面）へ集約された。dense案・smart lists単独案はclosed。smart listsの概念は `design_lab_list_overview` に吸収済み。以後のセッションはこの3案比較を再開しない。本番への反映は別タスクの指示書で範囲を定めて行う。
- **2026-07-06 人間裁定**: 本番アイコンセットとして `lucide_icons_flutter` を採用する。本番反映時は全画面で Lucide に統一し、Material Icons と同一画面で混在させない。tooltip/semanticsは維持する。反映は別タスクの指示書で行う。
- **2026-07-06 人間裁定（タイポグラフィ）**: Design Labの4案比較（A: Newsreader範囲制限 / B: Lora現行 / C: オールInter / D: A+和文明朝）の結果、**D案の構成を採用**する。ただし和文明朝フォントは容量とロケール（欧米展開時に不要）の理由で**同梱しない**。和文はシステムフォントのセリフ（Apple系: ヒラギノ明朝 ProN）へフォールバックし、明朝非搭載OS（Android標準等）ではシステム標準書体へ自然に劣化することを許容する。具体構成:
  - ディスプレイ書体: Newsreader（欧文、既存同梱アセット）＋ システム和文セリフフォールバック
  - セリフの適用範囲: **28px級以上かつ1画面1〜2箇所のみ**（現行画面ではToday見出しのみ。将来のタイマー数字も対象）
  - AppBarタイトル・セクション見出し（Tasks等）・タスク/詳細タイトル・本文: すべてInter
  - Loraは本番から退役（decommission）。アセットはDesign Lab比較用にリポジトリへ残すが、pubspecのfonts定義から外し、アプリには同梱しない
  - Zen Old MinchoはLab実験専用（同梱しない、`app/tool/fetch_lab_fonts.sh` 経由）
- **2026-07-06 人間裁定（ダークモード）**: ダークモードは対応方針だが直近スコープ外。Phase 1リリースはライトモードのみを正式サポートし、リリース前にthemeModeをlight固定する。dark系トークン・コードは残置し、正式対応の再開はBACKLOGで管理する。それまで新規UI実装はライトモードでの検証のみを必須とする。
- **2026-07-07 人間裁定（北極星アプリ）**: 操作感・体験品質の参照基準は TickTick および Todoist とする。デザイン批評・実装判断で迷った場合は「TickTick/Todoistならどうするか」を判断補助に使う（ビジュアルトーンは既存のTodoriブランド＝深緑/セージ/セリフ見出しを維持し、両アプリの操作感・密度・応答性・モーションの水準を参照する）。
- **2026-07-07 人間裁定（データ保持原則）**: 完了済みタスク（done/wont_do）は振り返りのための記録資産であり、リスト削除を含むいかなる整理操作でも暗黙に失われてはならない。リスト削除はリストの論理削除とし、完了済みタスクは削除済みリストに紐付いたまま保全する（未完了タスクはゴミ箱へ、復元時は既定インボックスへremap）。振り返り（ログブック）UIはPhase 3検討。ゴミ箱の完全削除機能を将来実装する場合も、この原則との整合（完了済み履歴を巻き込まない設計）を確認すること。
- **2026-07-07 人間裁定（削除モデル）**: ゴミ箱を廃止し、削除は恒久削除とする。削除導線は詳細画面のサブメニュー＋不可逆警告の追加確認（一覧のスワイプ等の即時削除導線は設けない）。削除Undoなし。完了・編集Undoは維持する。保全経路はアーカイブとする。データ保持原則（同日裁定、上記）の「暗黙に失われてはならない」は、警告つき明示的削除を妨げない。詳細は `docs/05_設計判断記録.md` ADR-009参照。
- **2026-07-07 人間裁定（Home改善サイクル第1回）**: `assets/brand/explorations/home-20260707/` の3案（A: TickTick方向、B: Todoist方向、C: 現行構造polish）を比較し、A案の構造（効率重視・Overdue/Todayグルーピング・常設quick add・swipe前提）とC案の行表現を組み合わせたハイブリッドを採用する。人間調整として、横幅の外マージンと内paddingを圧縮し、トップ部分を圧縮し、Tomorrow/Upcomingセクションを含める。これによりルートは「Today」ではなく「Home」と再定義する。`flutter_animate` / `flutter_slidable` の追加はこの裁定で承認済みだが、実装は個別タスク指示書の範囲に従う。

## セクション6: 未決事項（要人間判断。勝手に本番へ入れない）

- タスク行右側のaffordance: chevron継続か、将来のFocus開始ボタンか（Focus timer実装時に決定）。
