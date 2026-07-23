# Product requirements

> 状態: 2026-07-23 product owner承認済みbaseline（未実装）

## 1. Product statement

Taskveilは、個人が日々のtaskと行ったことの記録を安心して蓄積し、選んだlistだけを家族・友人と共同管理できるlocal-first E2EE TODOアプリである。

E2EEは追加optionではなく常時有効な基盤とする。一般的なTODOの便利さを大きく諦めず、server-side plaintext searchやserver-side schedulingに依存する機能はclientで実現する。

## 2. Design principles

優先順位は次のとおりとする。

1. **利用者の記録を失わない**: offline編集、競合、quota、subscription失効、server障害でlocal dataを黙って捨てない。
2. **内容をserverへ渡さない**: task、date、reminder、recurrence、timer linkage、list構造を常にE2EEにする。
3. **TODOとして妥協しない**: privacyを理由に基本的なtask管理、検索、通知、recurrence、calendar、timerを省かない。
4. **完了を成果として残す**: completed taskと完了したwork sessionを通常の整理で削除しない。
5. **暗号を日常操作へ露出しすぎない**: recovery、identity change、member removal等、結果が重要な場面だけを平易に説明する。
6. **標準と単純さを優先する**: 実績のあるprimitiveを組み合わせ、message protocolやenterprise機構を流用しない。
7. **privacyの限界を正直に示す**: server-visible metadata、endpoint compromise、共有相手によるcopyを隠さない。

## 3. Target

### 3.1 初期対象

- 私生活と仕事のtaskを1つのappで管理したい個人。
- plaintext cloud TODOへ内容を預けたくない人。
- 複数端末を使い、offlineでも確実に記録したい人。
- 買い物、家事、旅行、育児、event準備等を家族・partner・友人と共有したい人。
- completed taskと費やした時間を後から振り返りたい人。

### 3.2 初期対象外

- SSO、SCIM、organization policy、admin recovery、監査、法的保全、eDiscoveryを必要とする企業。
- 勤怠承認、請求、manager reportingを必要とするtime tracking。
- 匿名性network、membership hiding、国家規模のtargeted endpoint攻撃を必須要件とする人。
- realtime chat、共同文書編集、公開project management。

Data modelではAccount、Space、membership、roleを分離し、将来organizationを別layerとして追加できるようにする。ただし初期UI、server policy、key hierarchyへorganization概念を先取りしない。

## 4. Product modes

### 4.1 Local-only

- Accountなしで開始できる。
- task、search、view、recurrence、notification、template、timer、exportを利用できる。
- dataとsearch indexをlocal encrypted DBへ保存し、鍵をOS secure storageで保護する。
- 端末を失い、encrypted exportもない場合は復旧できない。
- 後からAccountへ移行するとき、local dataをPersonal Spaceへ明示的に取り込む。

### 4.2 Account-backed

- E2EE multi-device sync、encrypted server replica、共有を利用するためAccountを作る。Current-head同期はversioned backupではない。
- login、MFA、sessionはserverが認証するが、content decryption keyはclientだけが得る。
- Accountがoffline、subscription expired、quota exceededでもlocal閲覧、編集、search、exportを禁止しない。
- upload不能時のmutationはdurable outboxへ残し、利用者へ状態を知らせる。

## 5. Personal task management

### 5.1 Task fields

初期製品のdata modelは少なくとも次を表現できる。

| 領域 | Field / behavior |
|---|---|
| 基本 | title、plain text note、URL、created/updated timestamp |
| 状態 | `todo`、`in_progress`、`done`、`wont_do`、再open |
| 計画 | priority、date-only due、time-specific due、scheduled start、duration estimate |
| 整理 | list、section、multiple tags、parent/subtask、manual rank、archive |
| 通知 | 1 taskに複数reminder、absolute/relative reminder、snooze、local notification |
| 繰り返し | common RRULE相当、completion-based recurrence、skip/reschedule、series edit |
| 共同利用 | assignee、comment、actor、completion attribution |
| 計測 | completed work sessionとの関連。active timer stateはtask fieldにしない |

添付file、image、audio、thumbnail、file previewは初期製品にもdata modelにも含めない。URLは文字列としてE2EEにする。

### 5.2 Task operations

- quick add、edit、duplicate、move、copy、batch edit、complete、reopen、won't do、archive、永久削除。
- subtaskの追加、任意深さのtree、subtree move、collapse、一括操作。
- drag-and-drop/manual orderと、due、priority、created、updated、completed等によるsort。
- undo/redo。安全に同期できる範囲はcommandの逆操作として新mutationを作る。
- recurring instanceのcomplete、skip、reschedule、this occurrence / following / series変更。
- keyboard shortcut、share sheet、widget等のplatform integrationは、plaintextを第三者へ渡さない範囲で段階的に提供する。

任意深さはprotocolが固定depthを課さないという意味であり、clientはcycleを拒否し、性能と理解可能性のためUI表示をvirtualizeまたは折りたためる。

### 5.3 List, section, tag, template

- Inboxと複数listを持つ。
- listはsectionを持ち、list/sectionはmanual rankとarchiveを持つ。
- tagはPersonal Space内、または各Shared Space内で再利用する。Spaceをまたいで同じtag objectを共有しない。
- task、subtree、listをtemplateとして保存できる。
- listをarchiveしてもtask、completion、time dataを保持する。
- private listを共有するときは、Shared Spaceへmoveまたはcopyする操作として明示し、暗号scope変更を隠れた副作用にしない。

### 5.4 View, search, calendar

- Inbox、Today、Upcoming、Calendar、All、Completed、Won't Do、Board/Kanban、tag view。
- field、date range、status、tag、list、assignee、has-note、estimated/actual time等によるfilter。
- filterの保存、grouping、sort、query combination。
- title、note、tag、list、commentのlocal full-text search。
- calendarへの表示と、platform calendarからのimport/subscribeはclient-side permissionと明示的mappingで行う。Taskveil plaintextをserverへ渡さない。

Search index、saved filter、calendar mappingはlocal DBまたはencrypted Recordに置く。server-side plaintext search、server-visible due index、server-side smart listは作らない。

### 5.5 Natural language and automation

- quick addでdate、time、recurrence、priority、tag等を認識する。
- 解析は端末内のdeterministic parserをbaselineとし、外部AI送信を必須にしない。
- rule-based automationを将来追加できるが、initial serverはencrypted fieldを条件判定しない。
- 外部serviceへplaintextを送るintegrationはE2EE保証外の明示的exportとして扱い、default機能にしない。

## 6. Completion as a durable record

### 6.1 Default behavior

- `done`と`wont_do`は削除ではなくcurrent stateであり、search、filter、calendar、historyから閲覧できる。
- completion時にimmutableな`Completion Record`を作り、task ID、completed time、actor、必要最小限のdisplay snapshotをE2EEで保存する。
- taskをreopenしても過去のCompletion Recordを残す。再度completeすると別のCompletion Recordを作る。
- 誤操作を直後にundoした場合は、そのcompletion mutationと対応recordを同期前なら取り消し、同期済みなら明示的なreversalとして扱う。履歴表示は誤操作を通常成果として強調しない。
- edit history全体を永久保存するevent sourcingは行わない。成果に必要なcompletionとtime data、current task stateを保存する。

### 6.2 Archive and permanent deletion

- 通常の整理はcomplete、won't do、archiveで行う。
- permanent deleteは「残したくない情報を消す」ための例外的な操作として深い導線、対象件数、不可逆警告、再確認を必須にする。
- taskを永久削除すると、同じSpaceのknown comment、Completion Record等の従属Recordもcontentを持たないTombstoneへする。Personal SpaceにあるWork Sessionのsoft external referenceは成果記録として残す。
- server backupからのcontent消去SLAは運用設計で別途定める。E2EE鍵がなくてもbackup内ciphertextは復号不能だが、これをlogical deletionの代わりにしない。

## 7. Timer, stopwatch, Pomodoro

### 7.1 Active timer

- taskを指定するか、taskなしでstopwatchを開始できる。
- start、pause、resume、finish、discard、manual time entry、後からの訂正を提供する。
- Pomodoroはwork、short break、long break、cycleを持ち、各durationとlong break間隔を設定できる。
- active timerはdevice-localでdurableに保存し、app restart、background、reboot後に復元する。
- 同一local profileのactive timerは1つだけとする。
- active timerのtick、pause、break、remaining timeを同期しない。別deviceのactive timerとdistributed lockを行わない。

### 7.2 Completed time

- finishしたwork intervalまたは明示保存したmanual entryをimmutableな`Work Session`としてPersonal Spaceへ同期する。
- Work Sessionはtask reference、encrypted display snapshot、mode、started/ended time、active duration、finish kind、noteを持てる。
- breakはdefaultで作業実績へ算入しない。
- Shared Spaceのtaskを計測しても、Work Sessionと個人集計はdefaultで本人だけが見られる。共有相手へ実績時間を公開する機能は初期scope外とする。
- Shared Taskへのrelationはsoft external referenceとし、Task削除、member removal、access喪失後もWork Sessionをcascade deleteしない。参照不能時はsnapshotとunavailable表示で成果を残す。
- task、day、week、tag、listごとのactual timeをclientで集計し、estimateと比較できる。
- session訂正は元Recordの上書きではなくreplacementまたはcorrection relationとして履歴を保つ。単純な誤開始はpermanent deleteを利用できる。

## 8. Sharing

初期製品はShared Space単位で次を提供する。

- Accountを持つ家族・友人へのone-time linkまたはQR invitation。
- `owner`、`editor`、`viewer`の3 role。
- task/list/section/tag/comment、assignee、completion actorの共同利用。
- server access controlによるmember外access拒否とrole enforcement。
- ownerによるmember add/remove、role変更、Space削除。
- targetのacceptanceを必要とするowner transfer。
- new memberによる現在および過去の未削除dataの閲覧。
- member removal時のserver revokeとSpace Key generation更新。
- removal前のdataはbulk re-encryptせず、editされたRecordだけcurrent generationで再暗号化。
- editorは全Shared contentを改変・permanent deleteできる。招待/role変更時にこの権限を明示し、signatureはactorを識別しても旧contentを復元しないことを隠さない。
- Shared Spaceをbackupと扱わず、利用者が読めるdataのencrypted/plaintext exportを提供する。

詳細と限界は[Sharing model](./sharing-model.md)をnormative supplementとする。

## 9. Account, device, recovery

- emailとpasswordによるAccount作成。passwordはOPAQUE候補protocolへだけ入力する。
- optional MFA。MFAはserver sessionの追加認証であり、content keyの代わりではない。
- device一覧、session作成/最終利用の概略、session revoke。
- passwordを知る状態でのpassword change。
- client生成Recovery Keyによるpassword忘失からの復旧。
- password change/recoveryでは、new OPAQUE recordとkey wrapperのdigest、Account ID、one-time challenge、expected security revisionをAccount signatureへbindし、serverがatomic CASする。
- signed device-to-device bootstrapを将来追加できる境界。
- Recovery Keyも既存deviceもないpassword resetでは旧dataを復号できない。supportによるsecret recoveryは提供しない。
- encrypted exportと、明示警告付きplaintext JSON/CSV/Markdown export。

## 10. Notification and realtime

- reminderはclientがlocal schedulingする。serverはreminder time、task title、notification bodyを知らない。
- server pushは「このAccount/Spaceに変更がある」というgeneric wake-upだけを送る。
- foreground sync、background polling、pushを併用し、push欠落は遅延だけを生みdata lossを生まない。
- shared editの即時性はbest effortであり、chat同等のdelivery/typing/presenceは初期要件にしない。

## 11. Quota and retention

### 11.1 Quota

- 課金利用者のserver-side encrypted structured dataは約`1 GiB`を安全上限の目安とする。
- quotaはciphertext、encrypted key material、signature、Record metadata、Tombstone等、実際に保存するbytesを基準にaccount単位で集計する。
- 添付fileがないため、通常利用で上限を意識させない。通常画面へ常時meterを表示しない。
- serverはupload前にquotaをatomicに検査し、部分的なmutation batchを受理しない。
- 80%等の予告thresholdと、上限到達時だけ設定/support画面で知らせる。正確なthresholdは運用設計で決める。
- quota超過時もdownload、pull、local read/edit、permanent delete、exportを許可する。新規uploadはoutboxへ残す。
- serviceがquota解消のために古いcompleted taskを自動削除しない。

### 11.2 Retention

- current RecordとCompletion Record、Work Sessionを利用者が消すまで保持する。
- every-edit revision historyはserverで無期限保持しない。
- Tombstoneはrecord resurrectionを単純に防ぐためSpace存続中保持する。小さいがquota対象である。
- Account/Space deletion、backup expiry、abuse/legal hold等の運用SLAは公開運用文書で別途定める。

## 12. Accessibility, portability, performance

- iOS/Androidを初期targetとし、desktopは同じcore/protocolを使える設計にする。Webはsecure key storageとcode delivery threatを別評価するまで必須にしない。
- screen reader、keyboard、dynamic type、contrast、touch target、色以外のstate表現を提供する。
- local mutationは通常100ms以内にUIへ反映し、network latencyを操作完了条件にしない。
- large completed historyはpagination、virtualization、incremental indexで扱う。
- encrypted export formatはversion、algorithm ID、integrity/authenticity情報を持ち、他clientで検証可能にする。

## 13. Initial product exclusions

- 添付fileとfile sharing。
- enterprise organization、admin、SSO/SCIM、監査、retention policy、legal hold。
- server-side plaintext search、analytics、AI、reminder scheduling。
- public/guest share、anonymous share、linkだけでcontentを読むguest mode。
- realtime chat、presence、typing indicator、live cursor。
- active timerのcross-device handoffまたはremote control。
- server/supportによるAccount Root Key recovery。
- blockchain、custom consensus、custom cryptographic primitive。

## 14. Product acceptance outcomes

利用者の観点では次が成立する必要がある。

1. offlineでtaskを作成・完了・計測でき、再起動しても失わない。
2. 2台で異なるfieldを編集しても自動mergeし、同じfieldの競合も片方を黙って捨てない。
3. server DBだけを取得してもtask内容、date、status、timer relationを読めない。
4. 家族を招待すると過去の買い物・完了dataも見える。
5. memberを外すと、そのmemberは新規または編集後dataを読めず、旧dataの一括再暗号化待ちでSpace全体が長時間停止しない。
6. ownerを移譲してもownerが0人または2人にならない。
7. quotaやsubscriptionでserver uploadが止まってもlocal dataを読め、exportできる。
8. password忘失時、Recovery Keyがあれば復旧でき、なければ運営者にも復旧できないことが事前に分かる。
