# task-100: プロトタイプ感を解消するプロダクトUI再設計

> ステータス: 進行中（Interactive Design Labのsingle-canvas方向を本番採用）
> 作業日: 2026-07-11、再開: 2026-07-13

## 1. 背景とコンテキスト

task-99で配色、タイポグラフィ、レスポンシブナビゲーション、画面遷移を刷新したが、プロダクトオーナーの実機評価では「部品をきれいにしたプロトタイプ」の印象が残った。原因は、巨大見出し、全行カード、過剰なpill、Quick AddとNavigationBarの二重占有、モバイル構造を引き伸ばしたワイド画面、管理フォーム然としたAccountなど、画面の構成原理が従来のままだったことにある。

本タスクではtask-99の外観を前提にせず、Homeの選別・ツリー・完了体験だけを不変条件として、主要画面を日常利用できる静かなプロダクトUIへ再構成する。

2026-07-13にプロダクトオーナーが、Interactive Design Labで確立したsingle-canvas方向をproductionへ採用すると裁定した。通常画面はInter主体のwarm canvas 1枚を基礎とし、文字位置、余白、短いaccent、必要最小限のhairlineで階層を作る。serif見出し、白いpanel、通常行のcard、情報pillを常用せず、dark inverse surfaceはFocus専用とする。Design Labはfake data専用の独立環境として残し、productionからimportしない。

## 2. 事前に読むべきファイル

- `AGENTS.md`
- `docs/tasks/PLAYBOOK.md`
- `docs/tasks/DESIGN_PLAYBOOK.md`
- `docs/design/visual-direction.md`
- `docs/design/ui-spec.md`
- `docs/tasks/task-99-elegant-ui-redesign.md`
- `app/test/visual_qa/design_lab_interactive.dart`
- `app/test/visual_qa/design_lab_radical_direction_mock.dart`
- `app/lib/src/ui/theme.dart`
- `app/lib/src/ui/app_navigation_shell.dart`
- `app/lib/src/screens/tasks_screen.dart`
- `app/lib/src/screens/lists_screen.dart`
- `app/lib/src/screens/task_detail_screen.dart`
- `app/lib/src/screens/account_screen.dart`

## 3. ゴール

- 主要画面から「大きな見出し + 大きな角丸カードを並べたデモ」の印象をなくす。
- タスクが装飾より先に読め、件数が増えても疲れない密度を作る。
- モバイルは片手操作、ワイド画面はsidebar / content幅 / detail階層を活かしたプロダクト固有の構成にする。
- Home、Lists、Task detail、Accountを、同じ余白・線・タイポグラフィ・操作強度で統一する。
- Interactive Design Labのsingle-canvas文法を、本番データ・既存provider・既存routeへ依存方向を逆転させず昇格する。
- 通常画面はInterだけで情報階層を作り、Focusだけをdark inverseの専用routeとして扱える土台を作る。

## 4. スコープ

### やること

- Homeのhero領域、セクション、タスク行、Quick Add、下部ナビゲーションの密度再設計。
- 全行独立カードを廃止し、セクション単位の連続したtask canvasへ変更。
- モバイルNavigationBarを低く静かな構成へ変更し、Quick Addとの二重占有を解消。
- Listsを単なる行カードから、件数・選択・作成導線が整理された管理面へ変更。
- Task detailの大カードを解体し、直接編集できるdocument canvasへ変更。
- Accountを接続設定と認証操作の優先度が分かるsettings canvasへ変更。
- ワイド画面でcontent最大幅とsidebar構成を持ち、横方向の間延びを防ぐ。
- 既存モーションを再調整し、完了時のチェックpath・単一halo・取り消し線・行の滑らかな退場をproduction品質へ移す。
- widget test、visual QA、拘束仕様を新構造へ同期。
- 通常画面をwarm single-canvasへ統一し、白いpanel、section card、通常task card、serif display見出し、常用pillを撤去。
- Lucide icon + 小さなlabel + active underlineの低強度navigationと、中央captureの役割分離を本番shellへ昇格。
- HomeはCalendarが本番完成するまでOverdue / Today / Tomorrow / Upcomingの4期日セクションを維持する。Design LabのToday単一構成を先行導入しない。
- Design Labで検証済みのtree connector終端、edge icon buttonの同心hit feedback、完了motionのタイミングをproduction品質へ翻訳する。

### やらないこと

- タスク選別、サブタスク規則、完了・Undo、DB、同期、暗号、FRB APIの変更。
- Focus timer、検索、タグ、Logbook等の未実装機能追加。
- Calendar / Week / Month、Search、Focus timerの本番route・データ接続・同期基盤の追加。Design Lab上の試作表示は本タスクの本番機能契約に含めない。
- 画像やマスコットを通常画面へ常設すること。
- dark mode正式対応、新規パッケージ導入。
- Design Labのfake data、route、mock componentをproductionからimportまたは再利用すること。

## 5. 実装手順

1. `docs/design/ui-spec.md`を2026-07-13裁定へ同期し、Design Labとproductionの依存境界、通常画面とFocusのsurface境界を固定する。
2. 現在の `app/build/visual_qa/` を今回のbefore証拠として退避する。
3. themeとapp shellをInter主体、warm single-canvas、hairline、低角丸、低強度navigationへ更新する。
4. Homeの4期日セクションと既存データ構築を保ったまま、task stream、subtask tree、capture、完了motionをsingle-canvasへ置き換える。
5. Lists、list task、Task detail、Account、Onboarding、empty / loading / error、sheetを同じ本番用component文法へ置き換える。Design Labコードはimportせず、必要なtokenと挙動をproduction側へ実装する。
6. 狭幅、日本語、text scale 2.0、ワイド画面、主要interaction stateのVisual QAを生成して全PNGを目視する。
7. Flutter品質ゲートと境界checkを実行し、実装結果を記録する。
8. 実装に参加していない検証者が統合HEADとPNGを独立検証し、合格後にtaskを完了へ移す。

## 6. 受け入れ基準

- [ ] `home_tasks.png` でHomeがInter主体のwarm single-canvasとして表示され、serif hero、白いpanel、通常task cardがない。
- [ ] Homeの通常タスクが1件ずつ独立した大カードに見えず、セクション内で連続したリズムを持つ。
- [ ] Quick AddとNavigationBarが別々の大きな帯として画面下を占有しない。
- [ ] Homeの4期日セクション、各タスク最大1回表示、サブタスクツリー、完了Undoと完了モーションが維持される。
- [ ] `lists.png` が短いindex mark、文字階層、hairlineで整理され、大きな空白と単一cardだけの画面ではない。
- [ ] `task_detail.png` で大きな外周カードとpill群が主役にならず、タイトル・note・属性・subtasksがdocumentとして読める。
- [ ] `account_signed_out.png` でServer URLが最初の巨大フォームに見えず、接続設定とログイン操作の優先順位が明確である。
- [ ] ワイドHome / Listsで本文が横幅いっぱいに伸びず、読みやすい最大幅または複数pane構造になる。
- [ ] 通常画面の見出し、本文、タスク、操作はInterに統一され、Newsreader / Source Serif 4 / システム明朝をproductionの情報階層に使わない。
- [ ] 通常画面でcard / pillを階層表現として常用せず、pillは選択状態や短い一時的操作など形状に意味がある場合だけに限定する。
- [ ] Focus以外のproduction画面にdark inverse surfaceがなく、通常headerへマスコットを常設しない。
- [ ] Design Labがfake data専用のままで、production codeからDesign Lab / visual QA mockへのimportがない。
- [ ] 完了motionがpress 90ms級 → fill約200ms → 130ms後からcheck path約330ms → 単一halo約520ms → strikethrough → 500ms保持 → 420ms collapseの順で動き、Reduce Motionでは装飾遅延なしに確定する。
- [ ] 390x844、日本語、text scale 2.0でoverflowや操作不能がない。
- [ ] tooltip、semantics、48px級タップ領域、Reduce Motionを維持する。
- [ ] Flutter品質ゲート、境界check、`git diff --check` が成功する。
- [ ] before / afterの全visual QA PNGを目視し、画面単位の所見を完了報告へ記録する。
- [ ] Search / Calendar / Focusの本番機能やデータAPIを本タスクの外観変更に混入させていない。

## 7. 制約・注意事項

- Homeのデータ構築と完了非同期制御は外観変更のために書き換えない。
- 新しい装飾を足すより、カード、pill、線、文言を減らして階層を作る。
- `app/test/visual_qa/` と `app/tool/design_lab_main.dart` は設計探索用であり、本番の依存先にしない。production componentはproduction側で実データ契約に合わせて実装する。
- Calendar完成前にHomeをToday単一構成へ変えない。Overdue / Today / Tomorrow / Upcomingの選別と各タスク最大1回表示を維持する。
- dark inverse、Focus horizon、マスコットspriteは将来のFocus実装でのみ採用可能とし、本タスクでは通常画面へ流用しない。
- iOS的な模倣やTickTick/Todoistの複製ではなく、操作密度だけを北極星として参照する。
- 新規UI文字列は英日ARBへ追加し、生成物を手編集しない。
- visual QAのdebug bannerは評価対象外だが、それ以外の描画異常は残さない。

## 8. 完了報告に含めるべき内容

- 廃止したプロトタイプ的構造と、置き換えた画面構成。
- 2026-07-13裁定の5軸（Inter、warm single-canvas、hairline、低角丸、Focusのみdark inverse）を各主要画面で満たした証拠。
- Homeの不変条件と完了体験が維持された証拠。
- Design Labとproductionの依存境界を守った確認結果。
- before / after PNGの保存先、各主要画面の目視所見。
- 狭幅、日本語、text scale 2.0、ワイド画面の結果。
- 実行した品質ゲート、独立検証の判定と指摘。

## 9. 完了報告

### 実装結果

- 作業日: 2026-07-11
- 結果: Homeの巨大hero、通常行の独立カード、画面下部Quick Add帯を廃止し、compact header、最大920pxの連続task canvas、Dynamic Typeでiconへ縮退するfloating Quick Addへ置き換えた。Listsは最大760pxの線形管理面、Task detailは重複AppBar見出しと外周カードを持たないdocument canvas、Accountは最大620pxで認証を接続設定より先に置くsettings canvasへ変更した。
- 保持した挙動: Homeの4期日セクション、各タスク最大1回表示、サブタスクツリー、完了確認、Undo、チェックpath、局所パーティクル、左から右の取り消し線、Reduce Motionを維持した。
- ドッグフーディング修正: 通常リストでのtask完了・再開後にHome横断キャッシュが残る問題を修正した。`TasksNotifier`のstatus / edit / delete mutationがProvider層で`homeTasksProvider`をinvalidateし、通常リスト完了後にHomeから反映済みtaskが消える回帰testを追加した。
- 証拠: before=`app/build/visual_qa_before_v2/`、after=`app/build/visual_qa/`。visual QA 47テスト / 49 PNGの生成に成功し、Home英日・空状態・text scale 2.0、Lists、Account、Task detail、ワイドHome / Lists、完了3フレームを目視した。
- Commit: `093eb76`。
- 未解決: プロダクトオーナーによる新方向の実機評価と、実装を担当していない検証者による独立検証が未実施。

### Design Lab 次方向（2026-07-11）

- Homeを大分類セクションの一覧から `NOW` / `QUEUE` の2層へ絞り、Overdueはtask内の小さな補助情報、Tomorrow / Upcomingは`Review schedule`からCalendarへ送る構成を実装した。
- Home headerを日付 + 38px見出しに抑え、常時Focus actionは`NOW`の1件だけに限定した。Queueは独立カードではなく細い罫線で連続するtask canvasとし、subtask treeを同じ面に残した。
- Task detailをbottom navigationなしの専用routeとして再構成し、属性pillを廃止してList / Due / Plan / Priorityのproperty rowへ置き換えた。Focusは大きなFABではなく、文脈を説明するinline entryにした。
- Focusをglobal navigationなしの専用画面として実装し、task title、timer ring、Pause / Finishだけを主操作として残した。マスコットは画面下端の小さなbird mark 1箇所に限定した。
- Newsreaderの代替候補としてSource Serif 4をDesign Labにのみ導入した。Today、detail title、timer numeralだけに使い、task title・本文・操作はInterを維持する。production themeは方向承認まで変更しない。
- 追加の全面調整で、旧デザインが残っていたLists、task create sheet、Search、Account、Focus setupも同じpalette、typography、罫線、navigation、操作強度へ置き換えた。巨大見出し、外周カード、count pill、filter pill、属性pill、screenごとの装飾色を廃止し、全8画面を1つのproduct systemへ統一した。
- 生成物: `app/build/visual_qa/design_lab_task_list.png`、`design_lab_list_overview.png`、`design_lab_task_detail.png`、`design_lab_task_create_sheet.png`、`design_lab_search.png`、`design_lab_settings.png`、`design_lab_timer_setup.png`、`design_lab_focus_timer.png`。8画面を目視し、overflow、glyph欠落、専用routeへのglobal navigation混入、旧Newsreader見出しの残存がないことを確認した。

### Design Lab single-canvas再設計（2026-07-11）

- プロダクトオーナー評価で、前案は角丸cardを減らしても白いpanel面、大きなserif見出し、汎用icon navigation、円形timerが残り、prototype / template感を解消できていないと判定された。前案をproductionへ採用せず、Design Labを再度全面置換した。
- 全通常画面から白いpanel背景、section card、serif見出しを撤去した。warm canvas 1枚の上で、文字位置、余白、短いaccent line、必要最小限のhairlineだけで階層を作るsingle-canvas構成へ変更した。
- Homeは`FOCUS NEXT`と連続task stream、Listsは色付きの短いindex mark、Detailは2列metadataとsubtask tree、Searchはunderline input、Accountはborderless settings rowsへ変更した。bottom navigationは汎用icon 4個からtext navigation + 中央captureへ置き換えた。
- Focus setupは円形dialを廃止し、typographic duration controlへ変更した。Focus中はdark forestの専用画面へ遷移し、円形progressを使わず、マスコットbirdが水平な時間軸上を進むTodori固有のprogress表現へ変更した。
- default Design Lab 8画面ではSource Serif 4 / Newsreaderを使用せずInterへ統一した。Source Serif 4 assetと旧比較mockは履歴比較用に残すが、新方向の採用候補には含めない。
- 同じ8 PNGを再生成して全画面を目視し、通常画面に白panel / rounded cardがないこと、Focusだけが意図してinverse surfaceになること、overflowとglyph欠落がないことを確認した。
- Homeの通常状態から`FOCUS NEXT` / `NEXT`を削除した。アプリが先頭taskを「最優先」と推定せず、`TODAY`に同じ強度で並べる。`NOW`はユーザーが明示的にFocusを開始または一時停止している間だけ成立するruntime stateとし、開始前のdefault screenshotには表示しない。
- 既存のマスコットkit `assets/brand/generated/todori-mascot-kit-refined-no-border.png`をcharacter identityの正本として、Focus飛行・完了・休息の3ポーズを同じアイリング、喉色、羽色、手描き質感で再構成し、chroma key除去済みsprite sheet `todori-mascot-ui-sprites-v1.png`を作成した。通常headerのLucide bird + `TODORI`は撤去し、default Design LabではFocusの時間軸だけに実物のツグミドリ飛行poseを表示する。

### Interactive Design Lab（2026-07-12）

- 静止画ごとに独立していた8画面を、Design Lab専用entrypoint `app/tool/design_lab_main.dart` から操作できる1つの試作体へ接続した。Home / Calendar / Lists / Youのtab移動、Search、task detail、task capture sheet、Focus setup、Focus専用画面の遷移を確認できる。
- Focus setupの15 / 25 / 45 / 60分presetと5分刻みの増減をruntime stateへ接続した。開始後は選択時間を引き継ぐ1秒更新timer、Pause / Resume、Finishが動作し、飛行poseは経過率に応じて水平時間軸上を移動する。
- bottom navigationは文字だけの実験案から、控えめなLucide icon + 小さなlabel + active underlineへ変更した。中央captureだけを緑の円形主操作とし、判別性とTodoriの静かな強度を両立する。
- HomeとTask detailのsubtask connectorは、横線をcheckbox外周まで接続せず、意図的な余白を挟んで終端する形へ修正した。treeの親子関係は維持しつつ、線が円へ突き刺さって見える状態を解消した。
- HomeとTask detailの両方でsub-subtaskまで表示できる3階層treeへ拡張した。親checkboxの下にも余白を設けてから次階層の幹を開始し、深さを増やしてもconnectorが円を縦横に貫かない規則を維持した。
- 深いsubtask treeで本文幅が不足しないよう、Homeはheader・section label・Calendar導線の24px基準線を維持したまま、task streamだけ左右を6pxずつ拡張した。画面全体の整列感を崩さず、各階層へ12px分の有効幅を戻した。
- Home / Lists / Youで検索iconだけが占有していた44pxの独立toolbar rowを廃止し、各画面の見出し行右端へ検索を統合した。Homeのoverdue件数はTODAY section countへ移し、Calendarに残っていた位置合わせ用の空行も削除して、主要画面のcontent開始位置を揃えた。
- Calendarの予定一覧下に、完了件数を示す控えめな`Completed` disclosureを追加した。通常時は予定より弱い階層に留め、展開すると完了task名と完了日・listを成果として振り返れる。task capture sheetはSafe Areaをsheet面の内側へ移し、home indicator周辺まで背景色が連続するよう修正した。
- CalendarのWeekは独自agenda rowを廃止し、Todayと同じcheckbox・title・list / duration・time・subtask treeを持つtask rowへ統一した。Design Lab内では完了状態をToday / Weekで共有し、どちらのcheckboxから操作しても取り消し線とCompleted件数へ反映する。Todayにも小さなCompleted disclosureを追加し、bottom navigationのCalendarで代替できる`See the rest of the week`導線は削除した。
- production UIとの照合で不足していたlist task、task編集、signed-out account、list action、due date sheet、onboarding、empty / loading / errorを同じsingle-canvas文法で追加した。list taskはTodayと同じtask rowと3階層treeを再利用し、詳細は閲覧状態のtitleから罫線ベースの編集面へ遷移する。認証はsign in / account creationを同じ画面内で切り替え、sync server設定を主操作より下へ置いた。
- ListsからDesign list、task detail、編集／Focus、list actionからdue date、Youからsign in／account creationまでを実際のrouteとbottom sheetで接続した。list task画面では重複していたfloating addを廃止し、bottom navigation中央のcaptureへ追加操作を一本化した。破壊操作は通常rowと同じ形を保ちながらcoralだけで識別し、sheet外側の未着色領域を残さない。
- durationを持つtask rowを左へswipeした時だけ、右端からtimer actionが現れるようにした。Today / Week / list taskで同じgestureと強度を使い、task detailを経由せずFocus setupへ遷移し、閉じると元の一覧へ戻る。全taskへFocus CTAを常時表示せず、一覧の静けさと直接操作を両立する。
- header端のsearch / back / more / close / filterで、44px hit targetの中央と端寄せしたiconの中央がずれていた問題を修正した。共通edge icon buttonが44px領域全体を外側へ11.5px移動し、見た目の端位置を維持したままicon、tap判定、rippleの中心を一致させる。LTR / RTLのleading / trailingもDirectionalityに従う。
- Design Labのtask完了を、90msのpress、約200msの先行fill、130ms後から330msかけて描くcheck path、520msの単一halo、105ms後から315ms進むstrikethroughへ引き上げた。完了taskは500msだけ通常位置に留まって操作の結果を見せた後、420msかけて行高を連続的に縮め、fadeしながら4px上へ抜けてCompletedへ移る。後続taskは同じheightFactorへ追従して滑らかに詰まる。Reduce Motionでは装飾motionを省略して即時確定する。
- completion motion導入後に静止時のcheckが太く主張して見えたため、外周を1.0px、check pathを1.4pxへ抑え、fillを低彩度のgreenへ変更した。多色particleは通常完了には祝祭感が強く中心ずれも目立つため撤去し、check本体と同一Canvas中心から広がる細いhaloへ変更した。端末ではlight hapticを添える。
- task capture sheetをList / Due / Plan / Priorityの2×2 property面へ拡張した。各値はsheet内で変更でき、外周cardや横スクロールpillを増やさずhairlineとlabel階層で整理した。task一覧ではpriority 1 / 2 / 3をsage / amber / coralの6px dotで表示し、完了時はmuteする。色だけに依存しないTooltip / Semantics labelも付与した。
- Design Labはfake dataだけを使い、production route / DB / providerから独立したまま維持する。採用したcomponentとtokenだけを個別にproductionへ昇格させ、productionからDesign Labへの依存は作らない。
- 実行方法: `cd app && flutter run -t tool/design_lab_main.dart -d <device>`。
- 検証結果: Interactive Design Lab widget test 2件、Flutter全体133件が成功（visual QA harness 1件は設計どおりskip）。Design Lab 16画面・21 PNGを再生成し、icon + label navigation、CalendarのCompleted開閉、task capture sheetの4属性、completion draw / collapse midframe、Focus horizon、connectorとcheckboxの間の余白に加え、list task通常／menu press／timer reveal、task editing、account access、action / due sheet、system states、onboardingを目視確認した。専用entrypointのiOS Simulator debug build、`flutter analyze`、hardcoded strings check、client boundary check / test、`git diff --check`も成功した。

### 品質ゲート

- `cargo fmt --all -- --check`: 成功。
- `cargo clippy --workspace -- -D warnings`: 成功。
- `cargo test --workspace`: 成功。sandbox内ではDocker接続が拒否されたため、承認付き環境でserver統合testを含め再実行した。
- `cd app && flutter analyze`: 成功。
- `cd app && flutter test --concurrency=1`: 133件成功、visual QA harness 1件は設計どおりskip。
- `sh app/tool/visual_qa.sh`: 47件成功、49 PNG生成。
- `sh app/tool/check_hardcoded_strings.sh`: 成功。
- `sh app/tool/check_client_boundaries.sh`: 成功。
- `sh app/tool/test_client_boundaries.sh`: 成功。
- `git diff --check`: 成功。

### 独立検証

- 判定: 未実施（プロダクトオーナーの方向確認後に実施）。
- 根拠: 実装者による品質ゲートとVisual QAは成功しているが、合否は独立判定していない。
- 検証者: 未定。
