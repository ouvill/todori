# Todori UI Spec ── 拘束力のある具体値と判断規則

> Status: binding implementation spec
> Last updated: 2026-07-14

`docs/design/visual-direction.md` は方向性と哲学を扱う。本書は**実装時に従う具体値と判断規則**を定める。両者が矛盾した場合は本書が優先する。本書の変更は設計タスク（またはドッグフーディング/親レビュー起点のタスク）経由でのみ行う。実装エージェントが自己判断で本書を書き換えてはならない。

「親しみやすく・落ち着いて・エレガント」という形容詞そのものを実装判断の根拠にしてはならない。形容詞は本書の規則へ翻訳済みである。指示書・完了報告・レビューはすべて本書のセクション番号か具体的な値/規則を引用して書くこと。

## セクション0: 現行production採用契約（2026-07-14）

プロダクトオーナーはInteractive Design Labの**single-canvas方向**をproductionへ採用した。本節は、2026-07-11以前のserif display、白いpanel、独立task surface、pill中心の規則より優先する。下段の過去裁定は判断履歴であり、本節と矛盾する外観を復活させる根拠にしない。

### 視覚文法

- 通常画面は`#F8F5EC`のwarm canvas 1枚を基礎とする。文字位置、余白、短いaccent line、`#D9DDD3`のhairlineで階層を作り、白いsection panel、外周card、通常task card、card-in-cardを置かない。
- productionの基準書体はInterとする。通常画面のhero、screen title、section title、task title、本文、操作へNewsreader、Source Serif 4、Lora、システム明朝を使わない。ウェイト、サイズ、letter spacing、余白で階層を作る。
- 角丸は形状に意味がある操作へ限定する。通常rowとsectionは角丸面を持たない。input / button / menuは8px、modal sheet / dialogは上端または外周12pxを基準とし、円形checkbox、中央capture、真にpill形状である選択操作だけ完全な丸を許可する。
- pillは情報階層の既定表現にしない。task metadata、list count、section count、propertyはplain text、dot、2列property row、hairlineで表す。pillは選択中filter、短いpreset、状態を直接切り替えるcompact controlなど、形状自体に操作意味がある場合だけ使う。
- productionはFocusを含む全画面でlight surfaceだけを正式対象とする。Focusも`#F8F5EC`のwarm canvasを継続し、状態遷移で画面全体をdark inverseへ切り替えない。通常dark modeとFocus専用dark surfaceは対象外とする。
- 通常headerへブランド名、bird icon、マスコットを常設しない。マスコットはOnboarding / empty stateへ控えめに使用できるが、Focusのsetup / active / finishedには置かない。

### 構造と操作

- HomeはTodayを1本の連続streamとして表示し、今日予定（`scheduled_at`）、今日が期限のtask、期限超過taskを統合する。期限超過は行内の短いcoral metadataで区別し、Tomorrow / UpcomingはCalendarへ集約する。各task最大1回表示、subtask tree、完了 / reopen / Undoを維持し、`completed_at`が今日の成果だけを小さなCompleted disclosureに表示する。
- task rowはtransparentな連続streamとし、行間のhairlineまたは余白で区切る。checkbox、priority dot、title、短いcontext metadataを同じ基準線へ整列し、通常時の外周面、chevron、常設CTAを置かない。
- subtask connectorはcheckboxの円へ接触させない。横棒はring手前約4pxで終端し、親checkbox直下にも余白を設けて幹線が円を貫かないようにする。3階層以上でも本文幅を優先する。
- mobile navigationはHome / Calendar / Lists / MenuのLucide icon + 小さなlabel + active underlineを低強度で表示し、中央captureだけを円形primary actionにする。MenuはAccountへ直行せず、実在する遷移先だけを並べた一覧を開く。Search、task detail、Focusなどの専用routeではglobal navigationを隠す。
- Search、Calendar、Focusはproductionの実データ・provider・routeへ接続済みである。Design Labのfake route/stateは見た目とinteractionの探索用に限り、productionの実装根拠またはfallbackとして扱わない。
- edge icon buttonは44px以上、task checkboxは48px級のhit targetを持ち、icon / ring / ripple / semantics boundsの中心を一致させる。LTR / RTLのleading / trailingへ追従する。
- 完了motionはpress 90ms級、fill約200ms、タップ後130msからcheck path約330ms、単一halo約520ms、strikethrough、500msの結果保持、420msのheight collapseを順に行う。行はfadeしながら最大4px上へ抜け、後続行は同じheight factorへ追従する。通常完了に多色particleを使わない。checkbox ringは1.0px級、check pathは1.4px級とし、light hapticを添える。Reduce Motionでは装飾motionと保持遅延を省略して状態を即時確定する。

### Design Lab境界

- Design Labのproduction baselineはfake dataを注入した実際の`TodoriApp`、production router、provider、l10n、semantics、componentで描画する。採用済み画面をLab専用widgetとして複製しない。
- Candidateは未採用の差分だけをregistryへ登録し、対象route、仮説、本書との差分、対応work itemを必須とする。既定ではproduction theme / componentを再利用し、比較に必要な差分だけをLab専用widgetにする。
- 採用または却下したCandidateを実行可能なarchiveとして残さない。採用時は本書の裁定、production実装、production Visual QA、Candidate削除を同一work itemで完了し、履歴はwork itemとgitに残す。
- production codeからDesign Lab、Visual QA、fake bridgeへの依存をboundary checkまたは同等の静的検査で検出する。依存方向はDesign Lab / testからproductionへの一方向だけを許可する。
- 正本の責任は、本書が視覚契約、productionが挙動・情報設計・アクセシビリティ、Design Labが未採用差分の探索である。Candidateがproductionの挙動を代替したりfallbackになったりしてはならない。

## セクション1: 形容詞の翻訳表

### 親しみやすい（friendly）とは

- 柔らかな精度: 円形チェックボックス、warm canvas、低彩度色、Interの読みやすい本文。rounded cardやpillの量で親しみやすさを作らない。
- 人間の言葉: 相対日付（Today/Tomorrow/短い月日表記）。ISO日付（`2026-07-05`のような形式）や内部ステータス文字列（`todo`/`in_progress`等の生値）をUIに出さない。
- 日付・時刻の表記はホストOSの言語・ロケール設定に従う（2026-07-06人間指示）。`DateFormat` は固定パターン文字列ではなく skeleton API（`yMMMEd` 等）を用い、言語ごとの自然な語順・区切りをintlに委ねる。相対表記（Today/明日等）のl10n文言はこの原則の例外として維持する。
- 挿絵・マスコットは空状態とオンボーディングだけに限定する。通常のタスク一覧・詳細・ダイアログ・Focusには出さない。
- Interのサイズ、weight、letter spacingの差で柔らかく明瞭な階層を作る。
- **こうではない**: 派手な色、キャラの常駐、感嘆符、絵文字、画面全体のcelebration演出。

### 落ち着いた（calm）とは

- warm canvas 1層を通常画面の基礎とし、surfaceを重ねて階層を作らない。
- 影なし・hairline中心とする。dialog / sheet / 中央captureだけ、背景から分離する最小限のelevationを許可する。
- 1画面の色数上限: 緑系2（primary / primaryContainer）＋中立2（onSurface / onSurfaceVariant）＋アクセント最大1（coral または amber、どちらか一方のみを主に使う）。
- 同じ情報を画面内に2回出さない（例: pending数はTasksセクション見出しの1箇所のみ）。
- **こうではない**: 灰色一色の無機質さ、要素を全部薄くすること。

### エレガント（elegant）とは

- Interのtype scale、weight、letter spacingと正確な余白による階層。
- 余白による分離。線・囲み・カードを増やして分離しない（card-in-card禁止）。
- 正確な整列: dot・チェック・テキストの整列基準を明示指定する（「なんとなく上寄せ」禁止。セクション3参照）。
- 小さく精密なメタデータ。dot、plain label、property rowを優先し、pillを既定にしない。
- **こうではない**: 装飾の追加。エレガンスは足して作るものではなく、削って整えた結果である。

## セクション2: productionトークン

以下はtask-108で裁定した現行production契約である。task-108着手前のFocus inverse、過去のserif、独立surface、14〜28pxの常用角丸、情報pillは下段の裁定履歴にだけ残し、新規UIへ横展開しない。

### タイポグラフィ（role別）

| Role | 使用箇所 | TextTheme | フォント | Weight | 色 |
|---|---|---|---|---|---|
| AppBarタイトル | Tasks/TaskDetail画面のAppBar `title` | `titleLarge`（AppBarThemeの`titleTextStyle`経由） | Inter | w600 | `colorScheme.onSurface` |
| 主見出し / オンボーディング見出し | Home、Lists、Onboardingの主見出し | `displayMedium`または画面密度に応じたcompact title | Inter + システム角ゴシックfallback | w600、line-height 1.05級 | `colorScheme.onSurface` |
| Home日付キッカー | Home主見出し上のローカライズ日付 | `labelMedium` | Inter | w600、letter spacing 0.9級 | `colorScheme.onSurfaceVariant` |
| Homeリスト名ラベル | Home行タイトル下の小さなアイコン+リスト名 | `labelMedium` または `bodySmall` | Inter | w600（テーマ既定） | `colorScheme.onSurfaceVariant` |
| セクション見出し（Tasks） | 「Tasks」セクション見出し行 | `headlineSmall` | Inter | w700（テーマ既定） | `colorScheme.primary`（呼び出し側で上書き。テーマ既定は`onSurface`） |
| 完了セクション見出し | 「Completed」折りたたみ見出し | `titleMedium` | Inter | w600（テーマ既定） | `colorScheme.onSurfaceVariant` |
| リスト一覧の行タイトル | `/lists` の各リスト名 | `titleMedium` | Inter | w600（呼び出し側で明示） | `colorScheme.onSurface` |
| タスク行タイトル | `AppTaskRow` のタイトル | `titleMedium` | Inter | w600（テーマ既定） | 未完了=`onSurface` / 完了=`onSurfaceVariant`+取り消し線 |
| タスク詳細タイトル | Task detail見出し | `headlineSmall` | Inter | w700（テーマ既定） | `colorScheme.onSurface`（上書きなし） |
| タスク詳細メモ | note本文 | `bodyLarge` | Inter | 既定 | `colorScheme.onSurfaceVariant`（line-height 1.35） |
| メタデータ文字 | `TaskMetadata`のplain label | `labelMedium` | Inter | w600（テーマ既定） | `colorScheme.onSurfaceVariant`、期限超過のみcoral |
| Subtasks小見出し | 詳細画面の「Subtasks」 | `titleMedium` | Inter | w600（テーマ既定） | 既定色（上書きなし） |
| 作成日キャプション | 詳細画面のcreated at | `bodySmall` | Inter | 既定 | `colorScheme.onSurfaceVariant` |

- 基準フォントは`Inter`とし、displayを含む通常画面の全roleへ適用する。Newsreader / Source Serif 4 / Loraは比較履歴assetに残してよいが、production themeとproduction widgetから参照しない。
- 日本語グリフはInterにバンドルされないため、`fontFamilyFallback`を経由してプラットフォームの角ゴシック系へ委ねる（新規日本語フォント同梱はしない）。通常画面へ明朝系fallbackを指定しない。
- 本文と主要操作はビューポート幅に応じて文字サイズを縮小せず、プラットフォームのテキストスケーリングと折返しに委ねる。常設mobile navigationの短いdestination labelだけは、icon + labelを欠落させず1行で保つため最大1.3倍へclampできる。省略だけでdestinationを判別させず、tooltip / semanticsはclampしない完全なlabelを持つ。

### 角丸（Radius）

| 用途 | 値 | 出典 |
|---|---:|---|
| input / button / menu等の操作面 | 8 | `AppRadius.sm` / `AppRadius.md` |
| sheet / dialog等の分離面 | 12 | `AppRadius.lg` / `AppRadius.xl` |
| 通常row / section | 0（面を持たない） | warm canvas上のtransparent stream + hairline |
| 円形checkbox / capture | 完全な円 | 形状自体が操作意味を持つcontrol |
| 選択filter / duration preset | pillを許可 | compactな選択操作に限定 |

新しいradiusを追加して通常rowや情報metadataへ面を復活させない。既存widget固有のradiusが上表と異なる場合は、意味のある操作形状かを確認し、単なる移行残りなら既知の逸脱として扱う。

### 間隔（AppSpacing、`theme.dart`で定義された5段階のみを使う）

| トークン | 値 |
|---|---:|
| `AppSpacing.xs` | 4 |
| `AppSpacing.sm` | 8 |
| `AppSpacing.md` | 16 |
| `AppSpacing.lg` | 24 |
| `AppSpacing.xl` | 32 |

- 画面横padding: 通常画面とHomeは `AppSpacing.md`（16）。行内部で48pxタップ領域を確保し、利用可能な本文幅を優先する。
- 行内padding: 実装は縦`AppSpacing.xs`（4）〜`AppSpacing.sm`（8）程度、横は通常行で左端インデント（`AppSpacing.md` + 深さ×`AppSpacing.md`以下）＋右端`AppSpacing.sm`。Home行は本文幅を優先し、通常rowへ独立surface paddingを加えない。
- セクション間: `AppSpacing.lg`（24）〜`AppSpacing.xl`（32）。Home主見出しとセクション群の間は `AppSpacing.lg`（24）を基準とする。
- メタデータ内の間隔（dot、icon、plain label同士）: `AppSpacing.xs`（4）。
- `AppSpacing`にない中間値を一般化して新規トークンにしない。task-99裁定の固定コンポーネント値として、Home行leading 11、Quick Add縦padding 12、Task detail surface下padding 18、空状態padding 28/30だけを例外として許容する。他の用途へ横展開しない。

### 色（用途の拘束。パレット本体は`visual-direction.md`参照）

- production paletteはcanvas `#F8F5EC`、ink `#182019`、muted `#73786F`、forest `#1D6048`、sage `#BFD7C8`、subtle sage `#E9EFE8`、hairline `#D9DDD3`を正とする。
- `AppColors.coral`（`#C96357`）: 期限切れの強調と通常light画面の破壊的操作だけに使う。`AppColors.amber`（`#C08B3E`）は小さな注意表現だけに使い、大面積の背景色にはしない。
- Focusもproduction paletteのcanvas、ink、muted、forest、sage、subtle sage、hairlineを使う。active / paused / break / finished / system stateのために別の背景paletteを設けず、破壊的操作は通常light画面と同じcoral tokenを使う。
- Priority dot色（固定・現行実装値）:
  - high (`priority == 3`) = `#E8755A`（coral）
  - medium (`priority == 2`) = `#EDB73E`（amber）
  - low (`priority == 1`) = `#A8BEA8`（softSage）
  - none (`priority <= 0`) = dot自体を描画しない（非表示。色を透明にするのではなくウィジェットを出さない）
- Priority専用のcoral / amberは通常paletteのcoral / amberと同一値ではない。用途を混同して転用しない。
- 1画面のアクセント色は原則1系統（coral or amber）に絞る。両方を同時に主張させない。

### サイズ

- Priority dotの直径: 11px（`Container(width: 11, height: 11)`、`task_components.dart` `PriorityDot`）。旧仕様案の8pxではなく11pxが現行実装値であり、これをcanonとする。
- チェックボックス/完了アイコンのタップ領域: 48×48（`AppTaskCheckbox`の`SizedBox(width: 48, height: 48)`）。
- 行右端のシェブロン/並び替えコントロールの領域: 高さ48（`SizedBox(height: 48)`で中央揃え）。
- Homeセクション折畳み行: 最小高さ48。見出し、件数、chevronを行全体で同じタップ領域に含める。
- メタデータicon: 15px以下。iconなしのplain labelを優先する。
- 一覧metadataは2要素まで。3個目が必要になったら詳細画面へ送る（セクション3参照）。

## セクション3: コンポーネント解剖図

### タスク行（`AppTaskRow`）

構成順序（左から右）:

1. 円形チェック/完了アイコン（48×48タップ領域）
2. タイトル（`titleMedium`、折返し可）
3. メタデータ行（タイトルの下、最大2つのplain label + priority dot。priority dotはpriorityが1以上のときのみ表示する）
4. 右端: 通常表示では何も置かない。手動並び替えモードでも上下移動ボタンは置かず、長押しドラッグ&ドロップで順序を変更する

**整列規則（重要）**: チェックボックス（先頭コントロール）は「タイトルの1行目」と垂直センター整列させる。行全体（複数行になったメタデータ込みの高さ）とのセンター整列ではない。priority dotはタイトル脇へ置かず、メタデータ行の先頭で日付labelと同じ行の中央に揃える。

メタデータの順序: priority dot（priority noneの場合は非表示）→ 日付label（相対表記: Today/Tomorrow/短い月日）→ 進捗label（`1/3`形式）。3個目のメタデータが必要になった場合は一覧へ増やさず詳細画面へ送る。

datetime dueの一覧metadataは、相対日付 + 保存済みtimezoneでのwall-clock時刻までをcompactに表示する。IANA timezone IDとUTC offsetはtask streamを圧迫するため一覧へ出さず、Task detailとCalendarで完全な値を確認できるようにする。date-only dueへ時刻またはtimezoneを補わない。

完了行の表現: checkboxは未完了ringと同心のmuted fill + 細いcheck path、タイトルはstrikethrough + `onSurfaceVariant`とする。通常行と同じtransparent streamを保ち、完了専用のsurface、外周border、`check_circle`へのglyph差し替えを使わない。priorityや緊急metadataはmuteする。

Closed（`done` / `wont_do`）状態のルートタスク行の先頭コントロールをタップすると、確認ダイアログなしで `todo` へ再オープンする。これは2026-07-07ドッグフーディング由来の規則であり、既存の完了時Undoスナックバー動線とは独立した操作である。

チェックボックスは表示される場所すべて（一覧のルート行、ネストされたサブタスク行、詳細画面のSubtasks行、アーカイブ済みリストを開いた画面内）で常にトグルとして機能する。未完了（`todo` / `in_progress`）をタップした場合は `done` へ、Closed（`done` / `wont_do`）をタップした場合は `todo` へ遷移する。未完了子孫を持つタスクを完了する場合の確認ダイアログは維持する。閲覧専用のチェックボックスまたは見た目だけの完了アイコンを作らない。この規則は2026-07-07ドッグフーディング第2回由来である。

チェックボックス表現: 未チェックringはstroke 1.0px級のmuted green、check pathは1.4px級とする。チェックON時はセクション0のpress → fill → check path → 単一halo → strikethrough → 500ms保持 → 420ms collapseを使う。haloはcheck本体と同じCanvas中心から描き、多色particleは出さない。チェックOFF時は祝祭motionなしに静かに戻す。OSのReduce Motionが有効な場合は装飾motionと保持遅延を無効化し、状態を即時反映する。静的な完了表示と遷移終了frameはピクセル一致させる。この規則は2026-07-08裁定をInteractive Design Labの2026-07-12調整で置き換えたものである。

チェック完了モーションの精度補足: 48px級hit target、ring、check path、halo、rippleは同心にする。取り消し線は終了frameと完了後の静止状態をピクセル一致させ、複数行でも線の高さ・太さ・位置をjumpさせない。行ごとに独立してpending状態を管理し、複数行の同時完了、連打、motion中のreopenに耐える。Homeと通常Listでopen streamからCompletedへ移るroot rowは、widget identityとtask snapshotを保持したまま500ms保持後、420msのheightFactorでfadeしながら最大4px上へ退場し、後続行を滑らかに詰める。親配下に残るnested rowは同じcheck / halo / strikeをその場で再生し、階層位置をcollapseさせない。Reduce Motion時は遅延せず即時に再構成する。

アニメーション再生中のリスト保持は、ウィジェット部分木の差し替えではなくデータの凍結で行う（条件付きラッパー挿入による再マウント禁止。2026-07-08確立）。

### タスク一覧構造

Homeのタスク行群はTodayの1セクションとする。今日予定（`scheduled_at`）、今日が期限のdate-only / datetime due、期限超過taskを1本のstreamへ統合し、期限超過だけを行内のcoral metadataで示す。Tomorrow / UpcomingはCalendarで扱い、期日も予定もないroot taskは通常Listで扱う。全体を囲うpanelは置かず、各task rowはwarm canvas上のtransparent streamとし、必要最小限のhairlineで区切る。taskが1件もない場合は0件sectionを置かず、短い見出し、説明、必要なら控えめなマスコットだけのempty stateを表示する。

Todayは見出し + 未完了件数 + 開閉chevronで構成する。期限超過件数を別の大見出しやbadgeとして重複表示しない。CompletedはTodayより弱い小見出し + 件数 + 開閉chevronとし、`completed_at`がローカルの今日に入る成果だけを表示する。`done` / `wont_do`というstatusだけでCompletedの日付を推定しない。

Homeでは各taskを最大1回だけ表示する。自分のdueまたはscheduleでTodayへ該当する未完了taskは単独行として1回表示する。自分では該当しない子孫は、Homeに表示される直近祖先の下に同伴表示する。同伴subtreeの構築時は、既に単独表示される未完了子孫とその配下を剪定し、親配下と単独行の重複を作らない。完了taskはTodayへ単独表示せず、表示中祖先がある場合だけその下へmuted + strikethroughで同伴する。今日完了したroot taskはCompletedへ表示し、表示中祖先がない完了subtaskはHomeに単独表示しない。この規則は2026-07-08の重複抑止を維持しつつ、task-104で4期日区分をTodayへ統合した現行契約である。

Home行は、左からチェック、タイトル / 小さな文脈label、右寄せmetadataの順に構成する。親を持たないroot taskでは、タイトル下にlist名をplain labelとして表示する。単独表示されたsubtaskではlist名の代わりに階層icon + 直近の親task名（1行省略）を表示し、semanticsにも親contextを含める。priority dot + 日付labelは右側へ寄せ、外周pillや面色を使わない。期限超過はcoralの短いtext、今日 / 明日以降はmuted / primary textで区別し、完了行では緊急色をmuteする。root checkboxの左端はsection labelの左端と揃え、48×48 hit targetを維持する。subtaskは各階層12〜16px級の相対indentとし、3階層以上でも本文幅を確保する。この規則は2026-07-08の構造裁定をsingle-canvas向けに置き換える。

Completed disclosureに単独表示するのは今日完了したroot taskだけとする。subtaskは状態に関わらず、表示中の親または直近祖先がある場合だけその下に表示し、閉じたsubtaskはmuted + strikethroughで親にぶら下がる。ツリーごとCompletedへ移るのは親自身が今日完了したときだけ。通常List画面のClosedは全closed taskを扱う別の一覧契約であり、HomeのCompletedと同一視しない。

サブタスクの階層ガイドは、縦線を親チェックボックスの水平中心から降ろし、子の横棒はその縦線から子チェックボックスの垂直中心へ向かうが、円リングの手前4px程度で終端してリングへ接触/貫入させない。各深さの子のチェックボックス中心は同一のx座標列に整列する。最後の子はL字（└）として縦線を横棒で終端し、同じ親の後続兄弟がある子はT字（├）として縦線を継続する。3階層以上のネストでは、未完了の祖先階層の縦線が子孫行まで正しく続く。この規則は2026-07-07ドッグフーディング第2回、2026-07-08ドッグフーディング第5回、および2026-07-08ドッグフーディング第6回由来である。

Completed見出しは控えめな1行とする。左寄せの小さな見出し + 件数 + 開閉chevron 1つで構成し、見出し自体を大きなcardや強いbuttonにしない。

手動並び替えはドラッグ&ドロップ（長押し）で行う。並び替えは同一親内の兄弟間のみ許可し、別親の間や階層をまたぐ位置にはドロップできない。上下移動ボタンは置かず、アクセシビリティはreorder semanticsアクション（Move up / Move down）で担保する。この規則は2026-07-07ドッグフーディング第3回由来である。

### チップ/pill

- 情報表示の既定表現にしない。due、status、priority、countはplain label、dot、property rowで示す。
- プレフィックス付き冗長ラベル（`Due:` `Status:` `Priority:`）を一覧へ出さない。詳細のproperty rowではlabelとvalueを別columnへ分ける。
- 完全な丸は選択中filter、duration preset、中央captureなど形状に操作意味がある場合だけ許可する。非interactive metadataをpillで囲まない。

### 画面規範

- **Home**: ルート画面はHomeである。小さなInterの日付キッカー + Interのcompact titleを同じheaderへまとめ、検索edge actionを見出し行の右端へ置く。検索だけのtoolbar rowを作らない。Todayへ今日予定・今日due・Overdueを統合し、Tomorrow / UpcomingはCalendarへ送る。通常task rowの独立cardと右端chevronを禁止し、行タップで詳細へ遷移できることはsemanticsで明示する。Home横断ビューでは手動並び替えを行わない。本文はモバイルで画面幅を使い、ワイド画面では920pxを上限として中央配置する。
- **Homeセクション**: Todayの未完了件数だけを見出しに表示し、Overdueは各行のcoral metadataで示す。Completedは`completed_at`が今日のroot taskだけを控えめに開閉表示する。各task最大1回、単独表示される子孫の剪定、直近祖先下へのsubtree同伴、親contextを含むsemanticsを維持する。
- **Capture**: mobile navigation中央の円形captureからroot navigator上のtask作成sheetを開く。sheetはhome indicatorまでwarm面を連続させ、Title / Note / List / Due / Plan / Priorityをhairline property rowで提供する。Dueはdate-only / datetime / clear、Planは予定日時と5分刻みの見積（25 / 45 / 60分preset）、Priorityはnone / low / medium / highを扱う。選択値を同一sheet内で保持し、作成は全属性を1回のcommandとして確定する。横スクロールpillや属性ごとの独立cardを作らない。
- **Search**: `/search`はShell外のimmersive routeとし、入力、clear、blank、debounce中、結果、0件、error + retryを同じwarm canvasへ表示する。対象はtitle / note、全status、archive済みlist内taskで、deleted taskは除外する。結果行から詳細へ遷移し、戻ったときquery・結果・scroll contextを保持する。検索icon、hit target、ripple、semanticsの中心を一致させる。
- **Calendar**: top-level destinationとしてWeek / Monthを提供する。WeekはTodayと同じtask row、checkbox、subtask tree、完了motionを使う。Monthは7列grid + 選択日のagendaとし、1024px以上は2 pane、720px幅はsingle paneを維持する。date-only due、datetime due、scheduled、completedを別occurrenceとして表示し、同じtaskのdueとscheduledを統合しない。Completedは`completed_at`基準の控えめなdisclosureとする。dragまたは同等のアクセシブルな日付変更menuは、掴んだoccurrenceだけを変更する。週の開始曜日は端末の地域設定を既定とし、Menu配下のCalendar settingsで月曜または日曜へ明示的に上書きできる。Weekの範囲、Monthの列順、occurrence取得範囲は同じ設定に従う。
- **Focus**: `/focus/:listId/:taskId`はShell外の専用routeとし、setup / running / paused / break / finished / restore / error / conflictをすべて同じwarm canvasで扱う。中央は開始角135度・描画範囲270度の細いopen dialとし、外周card、円形surface、heavy shadowを置かない。Pomodoroはhairline track上のforest arcを残り時間に応じて減少させ、pausedは値を保持したままsageへ弱める。Stopwatchは静的arcとelapsed clockを使い、存在しない完了率を表示しない。work / short break / long breakはphase labelとaccentで区別し、色だけへ依存しない。Pomodoro初期値はwork 25分 / short break 5分 / 4 workごとのlong breakとし、設定は端末ローカルで保持する。running中のPomodoro work / breakがwall-clock targetへ到達したら、foregroundのdisplay tickから既存settlementを実行して自動的にfinishedへ遷移する。workはtarget時刻までの実績を保存してbreak pendingへ進み、breakはwork実績を追加せず`Break complete`へ進む。settlement失敗時はdurable active sessionを残し、次のtick / resume / restartで再試行する。setupはtask title、compactなPomodoro / Stopwatch selector、preview dial、時間・設定、最大幅280pxのStartを1本の縦軸へ置く。activeの常設操作は64px級の円形Pause / Resumeと`Session options`だけにし、Add 5 min、finish、task complete、save exit、discardは状態別のwarm bottom sheetへ送る。close / system backも同じsheetへ到達し、sheet dismissalだけではsessionを終了しない。finishedはdial構図を維持し、記録時間、Start break、Doneだけを表示する。setup→runningは260msのfade + 0.985→1.0 scale、pause / resumeは180ms、finishedは260msでdialを記録結果へ収束させ、Reduce Motionでは即時切替する。全taskへ常設CTAを置かず、open taskのtrailing swipeとTask detailから入る。見積時間と合計実績はTask detailの小さなproperty rowで比較できるようにする。
- **スワイプ/モーション**: open taskのleading swipeはcomplete、trailing swipeはFocus revealとする。closed taskのleading swipeはreopenで、trailing paneは表示しない。Due変更はTask detailのproperty sheetへ集約する。完了motionはセクション0のcheck path + 単一halo + strikethrough + hold + collapseを使い、多色particle、画面全体のconfetti、トロフィー、音、全画面演出を禁止する。
- **リスト一覧**: Listsはグローバルナビゲーションから直接開くトップレベル領域とする。旧戻る矢印、Home行、Account overflowを置かない。Interのcompact見出しの下に、最大760pxの連続rowを置き、短いindex mark、文字階層、hairlineで区切る。外周card、count pill、行内chevronを置かない。New listはactive listの直後、Archivedはその下の低強度sectionとする。リスト単位操作は、そのlistを開いた画面の右上overflowに置く。
- **Task detail**: headerはbackとoverflowだけに限定し、`Task detail`という重複見出しを表示しない。最大760pxのdocument canvasへ、親リンク → 円形チェック + Inter title → note → 罫線ベースのproperty rows → created → Subtasksを直接配置する。外周cardと属性pillを禁止する。既存属性は48px級操作領域で編集し、タイトルとnoteの閲覧 / 編集で同一TextStyleとbaselineを使う。Subtasksは子孫tree全体を同じcanvas上に表示し、connectorをcheckbox ringへ接触させない。ロック / 暗号化表現を常設しない。
- **Menu / Account**: Menuを最大620pxのtop-level borderless canvasとし、実在するAccount / Calendar settings / Templatesだけを連続rowとhairlineで表示する。AccountとCalendar settingsはMenu配下の戻れる画面とする。AccountはInterのcompact見出し → account identity / sign-in action → sync state → hairline → Server URLの順にする。各設定はcardやpillではなくrowとhairlineで分ける。Server URLを最初の巨大formにせず、保存操作はfield末尾iconへ統合する。
- **Dialog**: 文章主体、装飾なし。destructiveのみcoralを使う。

### Task statusとTimer state

- `todo` / `in_progress` / `done` / `wont_do`はKanbanまたはユーザーの明示的なtask操作だけで変更する。`in_progress`をFocus中・Timer作動中の表示語または自動遷移先として使わない。
- Focus / Pomodoro / Stopwatchのstart、pause、resume、finish、discardはtask statusを変更しない。running / pausedはsessionのruntime stateでありtask propertyではない。
- Focus中の「Complete task」は、現在のwork sessionを保存終了できた後にだけtaskを`done`へ変更する。session保存が失敗した場合はtask statusを維持し、再試行可能なerrorを表示する。
- Complete task後のUndoはtaskをreopenするだけとし、Timerを自動再開しない。task完了以外のFocus finishでも、保存した実績とtask statusを混同しない。

### グローバルナビゲーションと遷移

- Home / Calendar / Lists / Menuは同格のトップレベル領域とする。幅720px未満では低いcustom navigation面、720px以上では同じ情報設計のcompact railを用い、各領域へ1操作で移動できるようにする。AccountはMenuの子画面とする。
- mobile navigationはwarm canvasにLucide icon + 小さなlabel + active underlineを置き、pill形の選択indicatorを使わない。大きなtext scaleでも全destinationのiconとlabelを残し、labelは最大1.3倍にclampして1行省略できる。中央captureだけを緑の円形primary actionとする。wide railへsprout / bird / ブランド名を常設しない。
- Home / Calendar / Lists / Menuの切替は220ms級のfade + 2%未満の縦移動、MenuからAccountとListsからリスト内タスク一覧は260ms級の短い右→左slide + fade、タスク詳細は240ms級のfade + 0.985→1.0 scaleとする。
- Search、Task detail、Focusではグローバルナビゲーションを隠し、back / closeで元の文脈へ戻る没入画面とする。リスト内タスク一覧ではグローバルナビゲーションを維持する。
- Captureと期日選択のmodal bottom sheetはroot navigatorへ表示し、global navigationによって利用可能高が狭まらないようにする。

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

- task-108のproduction / Design Lab実装とVisual QAで、全面dark inverse、旧button hierarchy、旧Timer表現の既知逸脱は解消した。iPhone 17 / iOS 26.5のproduction録画と独立検証で、warm canvasの連続性、color flashなし、setup / pause / resume / sheetのmotionも確認済みである。

## 裁定済み事項

- **2026-07-06 人間裁定（履歴）**: Design Lab の Today/Task 体験は当初の3案比較（calm/dense/smart lists）から、人間がAIと共同で探索した結果、calm発展形の単一方向へ集約された。dense案・smart lists単独案はclosed。比較mockはproduction採用後に撤去し、task文書とgit履歴へ保存した。以後のセッションはこの3案比較を再開しない。
- **2026-07-06 人間裁定**: 本番アイコンセットとして `lucide_icons_flutter` を採用する。本番反映時は全画面で Lucide に統一し、Material Icons と同一画面で混在させない。tooltip/semanticsは維持する。反映は別タスクの指示書で行う。
- **2026-07-06 人間裁定（タイポグラフィ、履歴）**: Design Labの4案比較（A: Newsreader範囲制限 / B: Lora現行 / C: オールInter / D: A+和文明朝）の結果、当時は**D案の構成を採用**した。これは2026-07-13 single-canvas本番採用で通常画面をall Interへ変更したため、現在の拘束規範ではない。比較実装と外部font取得scriptは採用済みmock撤去時に削除し、履歴はtask文書とgitに残す。具体構成:
  - ディスプレイ書体: Newsreader（欧文、既存同梱アセット）＋ システム和文セリフフォールバック
  - セリフの適用範囲: **28px級以上かつ1画面1〜2箇所のみ**（現行画面ではToday見出しのみ。将来のタイマー数字も対象）
  - AppBarタイトル・セクション見出し（Tasks等）・タスク/詳細タイトル・本文: すべてInter
  - Loraは本番から退役（decommission）。アセットはDesign Lab比較用にリポジトリへ残すが、pubspecのfonts定義から外し、アプリには同梱しない
  - Zen Old Minchoは当時のLab実験専用で、productionへ同梱しなかった
- **2026-07-06 人間裁定（ダークモード）**: ダークモードは対応方針だが直近スコープ外。Phase 1リリースはライトモードのみを正式サポートし、リリース前にthemeModeをlight固定する。dark系トークン・コードは残置し、正式対応の再開はBACKLOGで管理する。それまで新規UI実装はライトモードでの検証のみを必須とする。
- **2026-07-07 人間裁定（北極星アプリ）**: 操作感・体験品質の参照基準は TickTick および Todoist とする。デザイン批評・実装判断で迷った場合は「TickTick/Todoistならどうするか」を判断補助に使う（ビジュアルトーンは既存のTodoriブランド＝深緑/セージ/セリフ見出しを維持し、両アプリの操作感・密度・応答性・モーションの水準を参照する）。
- **2026-07-07 人間裁定（データ保持原則）**: 完了済みタスク（done/wont_do）は振り返りのための記録資産であり、リスト削除を含むいかなる整理操作でも暗黙に失われてはならない。リスト削除はリストの論理削除とし、完了済みタスクは削除済みリストに紐付いたまま保全する（未完了タスクはゴミ箱へ、復元時は既定インボックスへremap）。振り返り（ログブック）UIはPhase 3検討。ゴミ箱の完全削除機能を将来実装する場合も、この原則との整合（完了済み履歴を巻き込まない設計）を確認すること。
- **2026-07-07 人間裁定（削除モデル）**: ゴミ箱を廃止し、削除は恒久削除とする。削除導線は詳細画面のサブメニュー＋不可逆警告の追加確認（一覧のスワイプ等の即時削除導線は設けない）。削除Undoなし。完了・編集Undoは維持する。保全経路はアーカイブとする。データ保持原則（同日裁定、上記）の「暗黙に失われてはならない」は、警告つき明示的削除を妨げない。詳細は `docs/05_設計判断記録.md` ADR-009参照。
- **2026-07-07 人間裁定（Home改善サイクル第1回）**: `assets/brand/explorations/home-20260707/` の3案（A: TickTick方向、B: Todoist方向、C: 現行構造polish）を比較し、A案の構造（効率重視・Overdue/Todayグルーピング・常設quick add・swipe前提）とC案の行表現を組み合わせたハイブリッドを採用する。人間調整として、横幅の外マージンと内paddingを圧縮し、トップ部分を圧縮し、Tomorrow/Upcomingセクションを含める。これによりルートは「Today」ではなく「Home」と再定義する。`flutter_animate` / `flutter_slidable` の追加はこの裁定で承認済みだが、実装は個別タスク指示書の範囲に従う。
- **2026-07-08 人間裁定（Home重複表示の解消）**: task-55の「子がより早いセクションに該当する場合は親配下と該当セクションの両方に表示」規則は、3階層それぞれに期日が付くケースで同一タスクが最大3回表示されノイズになるため廃止する。以後Homeでは各タスクを最大1回だけ表示する。自分の期日でセクションに該当するタスクは単独行として表示し、自分では該当しない子孫だけをHomeに表示される直近祖先の下に同伴する。同伴サブツリー構築時は、既に単独表示される子孫とその配下を剪定する。単独表示されたサブタスクはリスト名ラベルではなく階層アイコン + 直近の親タスク名を表示し、semanticsにも親コンテキストを含める。
- **2026-07-08 人間裁定（Home完了タスクの単独表示抑止）**: 完了済みなのに期日超過のサブサブタスクがOverdueへ単独表示され続けるドッグフーディング指摘を受け、日付セクションへの単独表示を未完了タスクのみに限定する。完了（`done` / `wont_do`）タスクは期日に関わらず日付セクションへ単独表示しない。Homeに表示される直近祖先がいれば、その下にmuted + 取り消し線で同伴する。表示中祖先がない完了ルートタスクはClosedセクションへ表示し、表示中祖先がない完了サブタスクはHomeに表示しない。セクション件数は未完了の該当タスクのみを数える。
- **2026-07-08 人間裁定（チェック完了モーション、履歴）**: 当時はチェック起点の局所particleを許容した。このparticle裁定は2026-07-12 Design Lab調整とセクション0の単一halo契約で置き換え済みであり、現在のproductionへparticleを復活させる根拠にしない。画面全体のconfetti、トロフィー、音、全画面演出の禁止は維持する。
- **2026-07-08 人間裁定（起動時の無音原則）**: 通常のアプリ起動でOSの権限確認・パスワード入力（Keychainプロンプト等）を出してはならない。E2EEアプリとして、文脈のない権限要求は信頼を損なう。セキュリティ関連の許可が必要な場合は、初回オンボーディングで目的を説明した直後に一度だけ求める。日常の起動・通常操作は無音であることを必須要件とする。
- **2026-07-11 人間裁定（task-99 UI全面再設計）**: 既存デザインに拘束されない抜本的な再設計を許可し、Homeのタスク管理挙動、サブタスクツリー、完了モーションを保持することを必須とした。視覚構造はwarm neutralの編集面、日付キッカー + `Home` display見出し、余白で分けた期日セクション、軽い独立task surface、浮遊Quick Add、単独空状態へ更新する。ListsとTask detailも同じsurface/radius/typographyへ統一する。この裁定は2026-07-06/07の旧Home外観規則のうち、本書で具体的に置き換えた箇所に優先する。
- **2026-07-11 人間裁定（task-99 IA / 画面遷移追補）**: 初回成果が既存の情報設計と遷移を保守的に残しすぎたというプロダクトオーナー指摘を受け、見た目だけでなくアプリシェル、画面階層、遷移演出も抜本変更の対象であることを明確化した。Home / Lists / Accountをレスポンシブなグローバルナビゲーションへ統合し、旧ハンバーガー、戻る矢印、Home重複行、Account overflowを撤去する。Homeのタスク選別、ツリー、完了体験だけを不変条件とする。
- **2026-07-11 人間裁定（task-100 プロダクトUI再設計）**: task-99後も「プロトタイプ感が拭えず、エレガントにするには抜本変更が必要」と評価された。巨大見出し、全行独立カード、pill過多、Quick AddとNavigationBarの二重帯、モバイル構造を引き伸ばしたワイド画面を廃止対象とする。主要画面はcontent最大幅を持つ直接的なcanvasへ変更し、Homeの選別・ツリー・完了体験だけを不変条件とする。この裁定はtask-99外観規則のうち本書で置き換えた箇所に優先する。
- **2026-07-13 人間裁定（Interactive Design Lab single-canvas本番採用）**: Interactive Design Labのsingle-canvas方向をproductionへ採用する。通常画面はInter主体、warm canvas、hairline、低角丸とし、serif、白panel、通常card、情報pillを常用しない。dark inverseはFocus専用とする。Design Labはfake data専用で独立させ、productionからimportしない。task-100時点ではCalendar完成までHomeの4期日sectionを維持し、Search / Calendar / Focusをscope外としたが、この暫定範囲はtask-103〜106の完了で解消済みである。現在の拘束契約はセクション0〜5を正とする。
- **2026-07-18 人間裁定（Menu-first Account IA）**: グローバルナビゲーションのYou / Account直行をMenuへ置き換え、AccountはMenu一覧から開く子画面とする。Menuへ実在しない設定項目のdead-end rowを置かず、当初はAccount / Templatesだけを表示する。
- **2026-07-18 人間裁定（Calendar week start）**: Calendarの週開始曜日を設定可能にする。端末の地域設定を既定とし、Menuの実在するCalendar settingsから月曜始まり / 日曜始まりを選べるようにする。設定はWeek / Monthの列順と取得範囲へ一貫して反映する。
- **2026-07-14 人間裁定（Focus warm open-dial再設計）**: setupからrunning / pausedへの全面dark inverse切替を廃止し、Focus全状態をproduction共通のwarm canvasへ統一する。没入感はShell外route、情報量の削減、135度開始・270度のopen dial、単一のPause / Resume主操作で作る。Session終了系操作は状態別bottom sheetへ集約し、Focusへマスコットを置かない。task-106/107のdark inverse記述は当時の実装履歴として保持し、現行拘束契約はセクション0〜5を正とする。

## セクション6: 未決事項（要人間判断。勝手に本番へ入れない）

- 現時点で本書に記録された未決事項はない。新しい未決事項は実装で仮決めせず、設計taskへ追加して人間裁定を得る。
