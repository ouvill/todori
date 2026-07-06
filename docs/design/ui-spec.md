# Todori UI Spec ── 拘束力のある具体値と判断規則

> Status: binding implementation spec
> Last updated: 2026-07-06

`docs/design/visual-direction.md` は方向性と哲学を扱う。本書は**実装時に従う具体値と判断規則**を定める。両者が矛盾した場合は本書が優先する。本書の変更は設計タスク（またはドッグフーディング/親レビュー起点のタスク）経由でのみ行う。実装エージェントが自己判断で本書を書き換えてはならない。

「親しみやすく・落ち着いて・エレガント」という形容詞そのものを実装判断の根拠にしてはならない。形容詞は本書の規則へ翻訳済みである。指示書・完了報告・レビューはすべて本書のセクション番号か具体的な値/規則を引用して書くこと。

## セクション1: 形容詞の翻訳表

### 親しみやすい（friendly）とは

- 丸いフォルム: 円形チェックボックス、pill型チップ（角丸999）、カードの角丸（セクション2のRadius表の値）。
- 人間の言葉: 相対日付（Today/Tomorrow/短い月日表記）。ISO日付（`2026-07-05`のような形式）や内部ステータス文字列（`todo`/`in_progress`等の生値）をUIに出さない。
- 挿絵・マスコットは空状態とオンボーディングのみ。通常のタスク一覧・詳細・ダイアログには出さない。
- Loraセリフの柔らかい見出し。
- **こうではない**: 派手な色、キャラの常駐、感嘆符、絵文字、celebration演出。

### 落ち着いた（calm）とは

- 背景sage × 表面warm whiteの2層構造のみ。第3の面色を発明しない。
- 影なし・1pxのthin border（dialog/sheet/FABのみ最小限の`elevation`可、値はセクション2参照）。
- 1画面の色数上限: 緑系2（primary / primaryContainer）＋中立2（onSurface / onSurfaceVariant）＋アクセント最大1（coral または amber、どちらか一方のみを主に使う）。
- 同じ情報を画面内に2回出さない（例: pending数はTasksセクション見出しの1箇所のみ）。
- **こうではない**: 灰色一色の無機質さ、要素を全部薄くすること。

### エレガント（elegant）とは

- セリフ見出し（Lora）とサンセリフ本文（Inter）の対比。
- 余白による分離。線・囲み・カードを増やして分離しない（card-in-card禁止）。
- 正確な整列: dot・チェック・テキストの整列基準を明示指定する（「なんとなく上寄せ」禁止。セクション3参照）。
- 小さく精密なメタデータ（チップは行あたり最大2個）。
- **こうではない**: 装飾の追加。エレガンスは足して作るものではなく、削って整えた結果である。

## セクション2: 拘束トークン（現行実装の実値を正とする）

以下は `app/lib/src/ui/theme.dart` と `app/lib/src/ui/task_components.dart` の現行実装から転記した実値である。この表にない値を新規に発明してはならない。値を変えたい場合は設計タスクとして本書を更新してから実装する。

### タイポグラフィ（role別）

| Role | 使用箇所 | TextTheme | フォント | Weight | 色 |
|---|---|---|---|---|---|
| AppBarタイトル | Tasks/TaskDetail画面のAppBar `title` | `titleLarge`（AppBarThemeの`titleTextStyle`経由） | Lora | w700 | `colorScheme.primary` |
| Todayヘッダー見出し | Homeの「Today」大見出し | `displayMedium` | Lora | w600（呼び出し側で明示上書き、line-height 0.95） | `colorScheme.primary` |
| Today日付サブタイトル | 「Today」下の日付行 | `titleMedium` | Inter | w600（テーマ既定） | `colorScheme.onSurfaceVariant` |
| リスト名pill | Homeのリスト名チップ文字 | `labelMedium` | Inter | w600（テーマ既定） | `colorScheme.primary` |
| セクション見出し（Tasks） | 「Tasks」セクション見出し行 | `headlineSmall` | Lora | w700（テーマ既定） | `colorScheme.primary`（呼び出し側で上書き。テーマ既定は`onSurface`） |
| 完了セクション見出し | 「Completed」折りたたみ見出し | `titleMedium` | Inter | w600（テーマ既定） | `colorScheme.onSurfaceVariant` |
| リスト一覧の行タイトル | `/lists` の各リスト名 | `titleLarge` | Inter（Lora上書きなし） | w600（呼び出し側で明示） | `colorScheme.onSurface` |
| タスク行タイトル | `AppTaskRow` のタイトル | `titleMedium` | Inter | w600（テーマ既定） | 未完了=`onSurface` / 完了=`onSurfaceVariant`+取り消し線 |
| タスク詳細タイトル | Task detail見出し | `headlineSmall` | Lora | w700（テーマ既定） | `colorScheme.onSurface`（上書きなし） |
| タスク詳細メモ | note本文 | `bodyLarge` | Inter | 既定 | `colorScheme.onSurfaceVariant`（line-height 1.35） |
| メタデータpill文字 | `TaskMetadata`のpillラベル | `labelMedium` | Inter | w600（テーマ既定） | `colorScheme.primary`、または`emphasisColor`（例: 期限切れcoral） |
| Subtasks小見出し | 詳細画面の「Subtasks」 | `titleMedium` | Inter | w600（テーマ既定） | 既定色（上書きなし） |
| 作成日キャプション | 詳細画面のcreated at | `bodySmall` | Inter | 既定 | `colorScheme.onSurfaceVariant` |

- 基準フォント: `fontFamily: 'Inter'`（`ThemeData`既定）。Lora明示上書きは `displayLarge/displayMedium/displaySmall/headlineMedium/headlineSmall` のみ。`titleLarge`・`titleMedium`・`labelMedium`・本文系はLora化しない。
- 日本語グリフはLora/Interにバンドルされないため、`fontFamilyFallback = ['Hiragino Sans', 'Noto Sans CJK JP', 'Noto Sans JP']` を経由してプラットフォームフォールバックへ委ねる（新規日本語フォント追加はしない、task-30の決定）。
- ビューポート幅に応じた文字サイズのスケーリングはしない。プラットフォームのテキストスケーリングと折返しに委ねる。

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

- 画面横padding: `AppSpacing.md`（16）。
- 行内padding: 実装は縦`AppSpacing.xs`（4）〜`AppSpacing.sm`（8）程度、横は行の左端インデント（`AppSpacing.md` + 深さ×`AppSpacing.lg`）＋右端`AppSpacing.sm`。
- セクション間: `AppSpacing.lg`（24）〜`AppSpacing.xl`（32）。Todayヘッダーとタスクセクションの間は`AppSpacing.xl`。
- メタデータ内の間隔（pill同士、アイコンとラベル）: `AppSpacing.xs`（4）。
- `AppSpacing`にない中間値（例: 12, 20, 28）を新規に使わない。

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
- チェックボックス/完了アイコンのタップ領域: 48×48（`_TaskRowLeading`の`SizedBox(width: 48, height: 48)`）。
- 行右端のシェブロン/並び替えコントロールの領域: 高さ48（`SizedBox(height: 48)`で中央揃え）。
- メタデータpill内アイコン: 15px。
- チップは1行あたり最大2個。3個目が必要になったら詳細画面へ送る（セクション3参照）。

## セクション3: コンポーネント解剖図

### タスク行（`AppTaskRow`）

構成順序（左から右）:

1. 円形チェック/完了アイコン（48×48タップ領域）
2. priority dot（priorityが1以上のときのみ）
3. タイトル（`titleMedium`、折返し可）
4. メタデータ行（タイトルの下、最大2チップ。現行は「日付pill → 進捗pill」の順）
5. 右端: シェブロンまたは並び替え/その他の`trailing`（行全体の垂直センター）

**整列規則（重要）**: priority dotとチェックボックス（先頭コントロール）は「タイトルの1行目」と垂直センター整列させる。行全体（複数行になったメタデータ込みの高さ）とのセンター整列ではない。多行タイトルでdot/チェックが浮いて見える整列崩れを避けるため、整列の基準は常に「タイトル1行目のベースライン/センター」と明示する。右端のシェブロン/`trailing`のみ行全体の垂直センターでよい。

メタデータの順序: 日付pill（相対表記: Today/Tomorrow/短い月日）→ 進捗pill（`1/3`形式）。3個目のメタデータが必要になった場合はチップを増やさず詳細画面へ送る。

完了行の表現: チェックはfilled/mutedのcheck_circle系アイコン、タイトルはstrikethrough + `onSurfaceVariant`、行の面（Material color）はやや不透明度を下げて背景に沈める（現行実装は`surface.withValues(alpha: 0.72)`、borderも`outlineVariant.withValues(alpha: 0.7)`）。

### チップ/pill

- 情報表示専用。ボタンとして機能させない（画面が明示的にinteractiveにする場合を除く）。
- プレフィックス付き冗長ラベル（`Due:` `Status:` `Priority:`）を禁止。アイコン＋短い語のみ（例: 相対日付そのもの、`1/3`）。
- 角丸999、`labelMedium`、アイコン15px、border thin（`outlineVariant`ベース、強調時は`emphasisColor`のalpha 0.6）。

### 画面規範

- **Today/home**: 上部バー（メニュー/ソート/ゴミ箱） → Today見出し + 日付サブタイトル → リスト名pill → Tasksセクション行（見出し + pending pill + 追加ボタン。pending表示はここ1箇所のみ） → タスク行リスト → Add task FAB。
- **Task detail**: タイトル（Lora、カード囲みなし） → note（あれば） → メタデータチップ最大4（詳細画面のみstatusチップ追加を許容） → created（`bodySmall`キャプション） → Subtasks小見出し → サブタスク行 → actions。ロック/暗号化の常設表現は禁止（`visual-direction.md` Security Signal参照）。
- **Trash**: 「戻せる操作画面」。復元actionはprimary色、警告色（coral等）の面は使わない。
- **Dialog**: 文章主体、装飾なし。destructiveのみcoralを使う。

## セクション4: 判断規則（迷ったとき）

1. 迷ったら削る。「要素を足す」か「削って整える」の二択なら常に後者を選ぶ。
2. 新しい色・角丸・サイズ・影・面色を発明しない。トークンにない値が必要になったら実装を止め、完了報告の未解決事項に書く。
3. 同じ情報を2箇所に出さない。
4. チップは1行に2個まで。
5. アイコンはMaterial標準を使う。lucide等の別アイコンセットの本番導入は依存追加＝人間承認が必要な設計判断（セクション6参照）。
6. 整列は基準（1行目センター/行全体センター/baseline）を明示して実装する。
7. 参照画像（`assets/brand/generated/`）と本書が矛盾したら本書が優先する。本書に穴があれば、タスク内では最も保守的な解（=削る側）を取り、完了報告の未解決事項でspec追記を提案する。

## セクション5: 既知の逸脱（現状 spec 違反として認識済みのもの）

- 本番タスク行のpriority dotとチェックボックスが、多行タイトル時にタイトル1行目と整列していない（2026-07-06 親レビューで確認。修正タスク対象。セクション3の整列規則参照）。
- Trash画面の日付が絶対表記のまま（`docs/tasks/BACKLOG.md`既載）。

## セクション6: 未決事項（要人間判断。勝手に本番へ入れない）

- Design Lab 3案（calm/dense/smart lists）のどれを本番Todayの次形態として採用するか。
- タスク行右側のaffordance: chevron継続か、将来のFocus開始ボタンか（Focus timer実装時に決定）。
- `lucide_icons_flutter` の本番採用可否（現状はDesign Lab実験用。依存追加の人間承認が未実施なら要確認）。
- Newsreaderフォントの扱い（Design Lab実験用。本番はLora/Interのまま）。
- ダークモードの正式トークン（priority dot固定hexのコントラスト含む）。
