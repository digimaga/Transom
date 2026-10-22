# テスト価値・本番接続の監査台帳

監査日：2026-10-23（JST）。基準コミット：`a94548ef42891b53a5c825376c581b0a6a5297bf`。
対象はこのコミットの全追跡テストコード、検証スクリプト、Lab、受入項目、および作業ディレクトリに現存した過去の補助試験。テストと製品コードは変更せず、改善候補を記録する監査。

## 結論と集計

- 通常実行対象は **5ファイル・57テスト・12 suite**。Core 53件／10 suite、macOS App 4件／2 suite。全57件を個別に照合した。
- **低価値・置換／統合候補は5件**：G09、G10、G13、H03、A02。守るべき仕様を不要としたものではなく、現在のassertionの検出力・追加価値への評価。
- 「57件成功」から実GUI・AX送信・追跡の正常動作は推定できない。FrameTracker 2件は空IDで計測入口までしか進まず、履歴の独立性テストは本番の2辞書を触らない。
- 共有Coreロジックは実際に本番から呼ばれている。FocusPolicyも未使用の模造品ではない。ただし実AX状態の取得・照合は別の境界であり、Core単体の合格で代替できない。
- 完全重複と断定して即時削除するテストはなし。一部重複、弱い期待値、未接続の統合経路を区別した。
- 過去の補助試験7ファミリーも確認した。Space transition時の一括取消を要求する6ケースは、既に不採用となった方針を期待しており、現行回帰テストとして採用できない。

|ファイル|suite|テスト数|台帳ID|
|---|---:|---:|---|
|`Tests/TransomCoreTests/TransomCoreTests.swift`|7|44|G01–G13、L01–L06、F01–F07、P01–P04、J01–J04、N01–N03、O01–O07|
|`Tests/TransomCoreTests/GestureRegressionTests.swift`|1|4|R01–R04|
|`Tests/TransomCoreTests/MaximizeHistoryTests.swift`|1|3|H01–H03|
|`Tests/TransomCoreTests/PresenceRefreshTests.swift`|1|2|N04–N05|
|`Tests/TransomAppTests/TrackingTests.swift`|2|4|A01–A04|
|合計|12|57|全行を下表に収録|

静的チェックは8種類（実行対象plistが2つある確認も1種類として集計）、手動受入は29項目。これらやループ内のassertion、補助試験、過去の旧版／修正版比較を57件に加算しない。`Package.swift:8` と `Package.swift:21` が自動テストの入口。AppテストはmacOS限定。`.build`、`.swiftpm`、生成バイナリはテスト定義として数えない。

## 判定基準

「高」は固有の安全条件・動作契約を直接検査、「中」は有用だが範囲・期待値が限定的、「低」は誤実装を見逃す／既存検査への追加価値が小さいもの。短い・速い・純粋関数という理由だけで下げない。優先度は改善順のP1／P2／P3であり、製品不具合の重大度とは別。全候補の状態は**未着手（監査のみ）**。

証拠の種類は、現コードの呼出し・assertionを確認した「静的」、今回隔離コピーで実行した「実行」、過去の保存物を確認した「保存済み」を区別する。mutationは故意に誤実装へ置き換える局所試験であり、製品側の実在バグを報告するものではない。

## 低価値テスト台帳

|候補|対象|優先度・根拠|次の扱い／完了条件|
|---|---|---|---|
|LV-01|G09 `testCoordinateConversionRoundTrip`|P1・実行。`flip(flip(rect)) == rect` のみ。変換を恒等関数にしても合格（M01）|往復性は補助として残し、`Rect(100,200,731,422)`、primaryHeight=900 → `Rect(100,278,731,422)` のような独立の片道期待値と負座標を検査。恒等変換が失敗すること|
|LV-02|G10 `testPointerConversionRoundTrip`|P1・実行。同じ関数を2回呼ぶため、恒等関数でも合格（M01）|`Point(-300,1500)`、primaryHeight=900 → `Point(-300,-600)` を検査。Rectとは高さ減算の有無が違うので、両overloadを保持|
|LV-03|G13 `testInvalidRectRejected`|P2・静的。両入力のy=50は、バー上端20がscreen上端25を下回る。不正値チェック以前に空間不足でもnilになるため、拒否理由を識別できない|上に十分な余白がある正常fixtureから1属性ずつNaN／無限大／非正サイズへ変更する。正常対照は成功、不正対照は失敗すること。単なるnil確認の削除ではなく入力の修正|
|LV-04|H03 `fullAndVerticalHistoriesRemainIndependent`|P2・静的。独立したローカル値2個を手で作り、H01/H02と同じ復元関数を連結する。本番の`restoreFrames`と`verticalRestoreFrames`の混線を検出しない|本番の履歴選択・更新を通る「縦最大化→通常最大化→通常復元→縦復元」を用意した後、既存は単体合成例へ改名または統合。2窓の履歴も混ざらないこと|
|LV-05|A02 `newerSnapshotDoesNotChangePreviouslyReadMetadata`|P3・静的。ローカル配列を空にして別の値型を生成。SwiftのArray/struct値セマンティクスへの依存が大きく、assertionもPID・件数中心|即削除の費用対効果は小さい。A01と統合するなら旧snapshot全フィールドの保持と、新snapshotの同じIDの変更値を比較して追加価値を作る|

LV-03は関数全体が無価値という意味ではない。G02の空間不足条件が混入し、不正値という独立した契約を十分に切り分けていない。LV-04にも純粋関数を組み合わせる価値はあるが、現在の名前が示す本番履歴の独立性には届かない。

## 重要だが補強が必要なテスト／経路

|ID|優先度|根拠と具体的な不足|推奨する受入条件|
|---|---|---|---|
|GAP-01|P1|A03/A04は`windowIDs`が常に`[]`。`FrameTracker.swift:37`でreturnし、`sample`・CG metadata・`onFrames`・`AppController.follow`を通らない|非空IDの読み取りから実followまでをfixtureで通し、対象PID、位置、対象だけの非表示・メニュー取消を確認。M02/M03を検出すること。既存2件の起動・停止契約は残す|
|GAP-02|P1|F06はmodal/minimized=trueをCoreへ渡すが、本番の`AXMenuStore.swift:63`は両方false固定。実判定は`AXAppWorker.validateFocus`にある|Coreの契約テストは保持しつつ、AXのmodal/minimized/sheet/fullscreen取得をfixture化し、実workerの拒否と副作用0回を検査|
|GAP-03|P1|P01/P04はpermit単体。成功／失敗／応答不明をAXへ返す試験でも、実UIの二重クリック試験でもない|実`execute`／`pressWindowButton`のAX actionを記録し、成功・cannotComplete・エラーの各応答後に同一要求の再送0回。read中取消も既存worker制御フローで検査|
|GAP-04|P1|2026-10-18の取消15ケース、配色7ケース、10-22の追跡8ケース・bash互換性2条件は通常CIに含まれない|採用済み仕様の回帰だけを恒久的入口へ移す。古い期待値のtransition試験は混ぜない。保存済み結果の再掲で現行テストの代わりにしない|
|GAP-05|P2|G04の「指定窓のみ」はframe1個だけ。元の`let`の不変性は別窓不変の証拠にならない。H01/H02も実際のAX受理枠・完了処理は通らない|幾何学計算として名称を正確化し、対象tokenと別窓の両方を置くfixtureで送信先・更新先を確認|
|GAP-06|P2|L群は既定height=30・合成幅。`HeaderView`の文字幅測定、overflowに渡す見出し、実ボタン、24/28/30/34/38ptの設定を通らない|可変高さで矩形とhit areaを確認し、overflowの項目順・欠落／重複なしを実HeaderViewから確認。狭幅のcountは具体的期待値を持つ|
|GAP-07|P2|J/R01は同じ状態機械を使用するが、上端5pt判定、titleSurfaceからのイベント配送、初期座標、非表示後のmouseUpは通らない|HeaderViewのcallbackを観測し通常／縦最大化の分岐とdrag排他を確認。J02の2.9pt、J03の3ptで閾値直下・等値は既に検査済み|
|GAP-08|P2|メニューのfocusedElement/selectionRange、AX参照・役割・経路・有効状態、古いrequest完了、MainRunLoop common mode、世代更新の実結線が57件にない|現在の安全条件を削らず、実関数を使うfixtureで別窓・別文書・古い応答・再入を拒否すること。UI/OS差はLab受入で別に確認|
|GAP-09|P2|N群はreconcile単体。本番scanがlisted/refreshedを正しく分けて渡すか、record削除・incarnation採番までは通らない|実scanへ完全一覧・部分属性失敗・一覧失敗・再出現を注入し、隠す／残す／消す対象と世代を検査|

## 全57件の個別台帳

ファイル名と開始行は基準コミットに対するもの。各表の「本番経路」は、その表の全テストの共通接続先。`高・維持`も実GUIまで合格したという意味ではない。

### GeometryTests：13件

テスト：`Tests/TransomCoreTests/TransomCoreTests.swift`。本番経路：`AppController.swift:333`／`:407` → `Geometry.externalHeader`、`:595`／`:889` → `reserveSpace`、`:521`／`:557` → `maximizedFrame`、`RuntimeModels.swift:94` → `flip`、`:97` → `flip`でAppKitへ、`AppController.swift:340` → `panelFrame`。以下App側の短縮名は `Sources/TransomApp/` 以下、Core側は `Sources/TransomCore/` 以下。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|G01|`testExternalHeaderDoesNotOverlapNativeWindow` :10|下端が窓上端に一致、高さ30、非交差|高・維持。実パネルのz-orderは別|
|G02|`testNoSpaceMeansNoOverlayAndNoMutation` :17|上端ぴったり／余白不足はnil|高・維持。`window.y`不変のassertionは値型の再確認にすぎず、AX移動禁止の試験ではない|
|G03|`testHeaderFollowsWindowOverflowingScreenEdges` :24|左右／下端はみ出しでもx/幅を維持、完全横外はnil|高・維持。4入力は別境界。G01と部分重複だがクランプ退行を追加検出|
|G04|`testReserveOnlyChangesRequestedWindow` :38|y=55・height=820へ計算しバー空間を得る|中・名称／範囲を補強。別窓はfixtureに存在しない（GAP-05）|
|G05|`testReserveIsIdempotent` :46|予約済みframeへ再適用しても同じ|高・維持。反復明示操作での位置漂流を防ぐ|
|G06|`testMaximizedFrameLeavesHeaderSpaceOnly` :51|使用可能幅・下端を維持し高さ分だけ上を空ける。小画面はnil|高・維持。AXでの適用・復元は別|
|G07|`testReserveRejectsImpossibleScreen` :58|不可能な画面ではnil|中・入力改善。窓幅600>画面500と高さ120の2拒否理由が同時に成立し、個別条件を区別しない|
|G08|`testNegativeCoordinateSecondaryDisplay` :62|負座標画面のバーy=-230|高・維持。実NSScreen収集・flipは通らない|
|G09|`testCoordinateConversionRoundTrip` :67|Rectの15入力で自己逆性|低・LV-01。変換の向き・高さ項を保証しない|
|G10|`testPointerConversionRoundTrip` :75|Pointの1入力で自己逆性|低・LV-02。G09とは別overloadなので単純重複ではない|
|G11|`testBestScreenUsesLargestIntersection` :79|交差面積の大きい右画面を選択|中・維持。画面外nil・同率は未検査|
|G12|`testPanelBackfillStaysInsideTargetFrame` :85|帯の幅・上端・高さ、最小対象高を越えない、backfill=0/NaNで無追加|高・維持。定数式との一致に加え窓下端という独立不変条件あり|
|G13|`testInvalidRectRejected` :98|NaNのx／負幅入力にnil|低・LV-03。空間不足が交絡|

### LayoutTests：6件

テスト：同ファイル。本番は `Header/HeaderView.swift:331` の `HeaderLayout.make` → app/menu/titleSurface/overflow/controlのframeへ直接使用。`title`は現UIでは主にドラッグ用の余白で、文書名はtooltip（同`:269`）。テスト名の「タイトルが表示」は文字描画の保証ではない。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|L01|`testWideHeaderShowsAllMenus` :105|幅1200で4メニュー・overflowなし・余白>100|中・維持。L04と入力共通、assertionは異なる|
|L02|`testNarrowHeaderProvidesOverflow` :111|幅320でoverflowあり・可視数<4|中・補強。可視数0でも通る。L04とoverflow存在のassertionが重複|
|L03|`testNoOverlappingOrOutOfBoundsControls` :116|幅280〜1800を上限とする13刻み117入力（最終1788）で非負幅・右端内・隣接非重複|高・維持。x>=0を直接は検査しない。全幅総当たりでもない|
|L04|`testMenusAreLeftAlignedAfterAppButton` :127|app後4pt、メニュー隙間なし、title/overflow順序|中・維持。L03の不変条件とは別に配置仕様を固定|
|L05|`testWindowControlsSitFlushAtRightEdge` :138|3ボタン・右端密着・幅40/高さ30・余白と衝突なし|高・維持。実button actionや設定高さは未検査|
|L06|`testNoMenusStillShowsTitle` :149|空メニューでも幅>300のtitle領域、overflowなし|中・維持。空集合の独立境界。文字描画の試験ではない|

### IdentityAndFocusTests：7件

テスト：同ファイル。`WindowToken`は `Accessibility/AXAppWorker.swift:107` の生成と`:156`の照合で使用。`FocusPolicy.permits`は `Accessibility/AXMenuStore.swift:62` で呼ばれる。witnessは先に実`validateFocus`を呼び、後でfocusedElement/selectionRangeを比較する。この前後処理は以下のテスト対象外。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|F01|`testReusedWindowIDIsNotSameIdentity` :162|同一PID/IDでもincarnation違いは別token|高・維持。実際のincarnation採番は別|
|F02|`testRestartedProcessIsNotSameIdentity` :163|同一PID/IDでもprocessInstance違いは別token|高・維持。F01と別の再利用軸|
|F03|`testSameTitleDifferentWindowsRejected` :166|同名でもwindowID違いを拒否|高・維持。実AX参照を比べる試験ではない|
|F04|`testSameWindowDifferentTabDocumentRejected` :171|同token/同タイトルでも文書URL差を拒否|高・維持。タイトル変更単独・片方nilは未検査|
|F05|`testInactiveAppRejected` :176|別PID／nil前面アプリを拒否|高・維持。実frontmostPIDのAX→NSWorkspace経路は別|
|F06|`testModalAndMinimizedRejected` :181|Policyへtrueを渡せば拒否|中・範囲を限定。本番呼出しは両フラグfalse、実modal/minimizedはvalidateFocusで検証（GAP-02）|
|F07|`testExactContextAllowed` :186|正常な完全一致を許可|高・維持。常時falseで安全側に壊す退行を検出する正常対照|

### PermitTests：4件

テスト：同ファイル。同じ `OperationPermit.commitOnce` が `Accessibility/AXMenuStore.swift:125`／`Accessibility/AXAppWorker.swift:296` のAXPress直前に接続。実IPC・後続処理の回数は検査しない。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|P01|`testAtMostOnceAfterSuccessOrUnknownOutcome` :193|同一permitの2回目commit拒否、commit後isValid=false|高・維持。「応答不明」は名前のみで応答自体を入力しない（GAP-03）|
|P02|`testCancelledOperationCannotCommit` :199|cancel済みpermitのcommit拒否|高・維持。read中取消・lifetime取消・cancel/commit競合は別|
|P03|`testExpiredOperationCannotCommit` :204|期限超過でcommit拒否|高・維持。期限直前・等値、isValidの期限判定は未検査|
|P04|`testConcurrentDoubleClickHasOnlyOneCommit` :208|100並行commitで成功1回|高・維持。実二重クリック／複数permitを使う別要求の試験ではない|

### TitleBarGestureTests：4件

テスト：同ファイル。本番 `Header/HeaderView.swift:238` → 同じ `TitleBarGesture` → `dispatch` (`:251`)。DragCoordinatorやAppKit配送はfixtureに含まない。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|J01|`testSingleClickDragBeginsImmediately` :220|downでbegin、dragでmove、upでend|高・維持。即時にAXが動く保証ではない|
|J02|`testStationaryDoubleClickRunsOnlyOnMouseUp` :227|2回目downと2.9pt移動では待機、upでdoubleClick|高・維持。閾値直下の境界あり|
|J03|`testDragOnSecondClickWinsOverDoubleClick` :234|3ptちょうどでdragへ、継続move、upでendのみ|高・維持。閾値等値と排他を検査|
|J04|`testNewMouseDownResetsIncompleteGesture` :242|未完のdouble-click待機を新downでリセット、end後move無視|高・維持。通常イベント列とは異なる状態遷移|

### PresenceTests／PresenceRefreshTests：計5件

N01–N03は主テストファイル、N04–N05は `Tests/TransomCoreTests/PresenceRefreshTests.swift`。本番は `Accessibility/AXAppWorker.swift:142` から同じ `PresenceTracker.reconcile` へlisted/refreshedを渡し、hidden/removedを使用。メニューやパネルの最終非表示までは通らない。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|N01|`testTransientFailureDoesNotMeanClosed` :253|observed=nilを10回受けてもhiddenのみ、削除なし|高・維持。N05と部分重複。10回という数字に仕様上の境界はない|
|N02|`testTwoConfirmedAbsencesRemoveWindow` :261|既定thresholdで1回不在は維持、2回で削除|高・維持。独立した閾値契約|
|N03|`testReappearanceResetsCounter` :266|不在→再出現→不在で削除しない|高・維持。N05にも同じ状態列の一部がある|
|N04|`partialRefreshRemovesOnlyConfirmedAbsentWindow` :12|列挙された属性未読窓は隠して保持、不在窓だけ2回で削除、回復で表示対象へ|高・維持。N01/N02では守れない複数窓・listed/refreshed分離|
|N05|`unknownListDoesNotCountAsAbsence` :30|先行不在→unknown3回→再出現→再不在でも誤削除しない|高・維持。unknown中に既存counterを保持するかリセットするかはこの期待値では区別できない|

### OrderingTests：7件

テスト：主ファイル。同じ `OrderingPolicy.isDirectlyBehind` を `WindowServer/WindowServer.swift:121`／`App/AppController.swift:436` が呼ぶ。本番は背面帯を含むパネルframeを渡す一方、fixtureのheaderは高さ30。帯だけに重なる他窓というケースは未検査。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|O01|`testHeaderDirectlyBehindTargetAllowed` :280|target直後のheaderを許可|高・維持。正常対照|
|O02|`testHeaderInFrontOfTargetRejected` :284|逆順を拒否|高・維持。背面帯がネイティブ操作部を覆うことの防止条件|
|O03|`testInterveningForeignWindowRejected` :289|重なる他PID窓の挟み込みを拒否|高・維持。実CG順序の取得は別|
|O04|`testForeignWindowInFrontOfBothIsCorrect` :293|両方より前の他窓は許容|高・維持。O03と位置関係が異なる|
|O05|`testNonIntersectingIntermediateWindowAllowed` :297|非交差の中間窓を許容|高・維持。交差判定を省いて全拒否する退行を防ぐ|
|O06|`testOwnWindowBetweenAllowed` :301|自PIDの中間窓を許容|中・維持。ownPID条件を独立に検査|
|O07|`testMissingIDsRejected` :306|対象／バーそれぞれ欠損なら拒否|高・維持。双方欠損・重複ID・実order結果は未検査|

### GestureRegressionTests：4件

テスト：`Tests/TransomCoreTests/GestureRegressionTests.swift`。R01は上記HeaderView、R02–R04は `Header/DragCoordinator.swift:61` → `Geometry.dragPoint`。配列はテストで直接作り、NSScreenの取得・変換は通さない。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|R01|`testThirdClickIsARegularDragAfterOneDoubleClick` :5|1→2→3クリックでdoubleClickは2回目だけ、3回目はdrag|高・維持。J01/J02を含むが3クリック目という固有退行あり|
|R02|`testMenuBarPointerUsesItsPhysicalScreensVisibleTop` :19|メニューバー内のpointerも物理画面に所属し、y=55へ制約|高・維持。full/visibleの選択差を検出|
|R03|`testNegativeCoordinateScreenUsesCorrespondingVisibleFrame` :27|負座標副画面に対応するvisible上端を使用|高・維持。G08はバー配置、こちらはdrag制約で別経路|
|R04|`testPointerOutsideAllScreensDoesNotFallbackOrClamp` :38|全画面外では希望位置を保持|高・維持。別画面推定の禁止を直接検査|

### MaximizeHistoryTests：3件

テスト：`Tests/TransomCoreTests/MaximizeHistoryTests.swift`。本番は `App/AppController.swift:527`／`:564` の履歴参照と`:538`／`:577`の保存から `MaximizeHistory.matches/restorationFrame`。テストはその値型だけを呼ぶ。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|H01|`constrainedMaximizeStillRestoresOriginalFrame` :7|受理枠にmatch、元枠へ復元、x変更は非match|高・維持。受理枠を実応答から履歴へ保存する結線は別|
|H02|`verticalRestorePreservesLaterHorizontalChanges` :15|横移動・幅変更後も縦matchし、横を維持して縦だけ復元|高・維持。縦方向変更の非match対照あり|
|H03|`fullAndVerticalHistoriesRemainIndependent` :25|手で作った2履歴の復元を順に合成|低・LV-04。本番辞書や別窓の独立性は未検査|

### ServerSnapshotTests／FrameTrackerTests：計4件

テスト：`Tests/TransomAppTests/TrackingTests.swift`。A01/A02は実 `WindowServer/WindowServer.swift:39` のstructを直接使用。本番生成は同`:93`、参照は `App/AppController.swift:380`／`:391`。A03/A04は実FrameTrackerだが、計測先のIDは空。

|ID|テスト名・行|実際に守ること|価値・扱い／限界|
|---|---|---|---|
|A01|`duplicateIDsKeepFirstDescriptionAndOriginalOrdering` :7|同IDのbyIDは先勝ち、orderingは入力順、readAt保持|中・維持。全フィールドではなくPID/frame中心。本番readは`:82`でIDを重複除去してからsnapshot生成するため、重複fixtureは現在の通常入力より広い|
|A02|`newerSnapshotDoesNotChangePreviouslyReadMetadata` :20|別snapshotの生成で旧byID/orderingが消えない|低・LV-05。実metadata置換時の利用者の振る舞いではない|
|A03|`firstSampleDoesNotWaitForTimerAndRepeatedStartDoesNotResample` :34|start同期呼出し内でID選択1回、再startで増えない|中・維持＋補強。初回frameの計測は未実行。Timerの周期・実発火・common modeも未検査|
|A04|`stoppedTrackerCanRestartWithAFreshTargetSelection` :46|stopでisRunning=false、再startで選択回数増加、二重stop可能|中・維持＋補強。対象集合は変えず常に空。停止後のcallbackなし／Timer invalidateも待って確認していない|

## 重複と「実装の写し」の扱い

|組合せ|重なりと独自性|判断|
|---|---|---|
|G01／G03／G12|非交差を共通確認。画面端維持・背面帯は別契約|残す。重複assertionがあるだけで削除しない|
|L01／L02／L04|同じwide/narrow入力、overflow存在が重複。全項目表示・count・整列は別|fixtureや入力表の統合余地あり。L02単独削除ならcount期待を移す|
|N01／N03／N05|unknown非削除と復帰counterリセットが重複。N05は先行不在とunknownの組合せ|表形式へまとめる余地はあるが高価値の状態遷移を残す|
|J01／J02／R01|最初の2クリックが重複。3回目の退行はR01固有|R01を残す|
|H01／H02／H03|同じ復元関数の合成。H03だけでは辞書独立性を追加保証しない|LV-04として本番経路の試験に置換後に統合判断|
|G09／G10|同じ往復式だがRectとPointの別overload|両方を独立期待値へ改善。片方だけに統合しない|
|G06／G12／L04／L05|SUTの定数を期待値にも使用する箇所あり|単なる実装コピーではない。画面端・窓非重複など独立不変条件を併設。ユーザー設定値の取り違えは別途検査|

## 静的チェック・実行入口

|ID・開始行|守るもの|評価／本番との限界|
|---|---|---|
|S01 `scripts/check-source.py:10`|2 plistの構文とCFBundleExecutable|高。実bundle内のファイル存在・署名はbuild-appで別検査|
|S02 同`:16`|通常アプリのLSUIElement=true|高。アクセサリアプリの設定契約。実起動は検査しない|
|S03 同`:18`|CFBundleLocalizationsにen|中。翻訳表示・fallback言語の実挙動は別|
|S04 同`:22`|10個の必須文書／manifest類の存在|低コストの梱包smoke。内容・リンク・日付整合性は見ない。単独で品質指標に数えない|
|S05 同`:27`|App/Header/Menu/WindowServer直下で特定3種の生AX IPC呼出しを禁止|中。正規表現・非再帰glob。AXラッパー経由、他の同期AX API、MainActorからAccessibility関数の直呼びは検出しない。ワーカーキュー隔離の証明ではない|
|S06 同`:34`|日本語literalをNSLocalizedString等へ通す|中。同一行にNSLocalizedString/Loggerがあると全行除外。`//`分割・複数行literal等を完全解析しない|
|S07 同`:48`|抽出できたキーに英語entryがある|中。空訳・重複・誤訳・placeholder整合性・実bundleへの収録は未検査|
|S08 `scripts/verify.sh:5`|全shell scriptのbash構文|中。空配列のset -u等、実行時互換性は検出しない|

`scripts/verify.sh:6`がS01–S07を実行する。macOSでは両製品build＋全57テスト、LinuxではCoreのみ＋App/Labの構文parse。LinuxでAppKit型チェック・App4件の成功とは扱わない。`.github/workflows/macos.yml:11`も同じverify.shを使い、`:13`は通常アプリのbundleのみ生成する。Labのbundle生成・起動・受入はCIにない。

`scripts/build-app.sh`はbuild・plist lint・署名verify・bundle配置の検証入口であり、単体テストではない。`Sources/TransomLab/main.swift:14`は同名A/B窓、`:65`はmainWindowに対応する保存先とログ、`:83`はシートを作る。自動assertionはなく、受入時に対象窓・内容・回数をreadbackするfixture。本番バイナリへはリンクされない。

## ローカルに保存された補助試験

以下はすべてGit非追跡の`dist/`配下。生成された旧版・修正版のコピーは独立した新規テストに数えず、7ファミリー単位で読んだ。過去の合格値は保存済み証拠であり今回の再実行値ではない。絶対パスと`/tmp`を含む実行例は別端末でそのまま再現できず、通常CIもこれらを収集しない。

|ID・場所|入力とassertion／測定|価値・乖離・扱い|
|---|---|---|
|X01 `dist/review-20261022/tracking/`|実FrameTracker・実follow・ServerWindow・Coreを抽出。8ケース：通常移動、異PIDの変更枠／同枠、同PID同枠、正常2窓、無関係menu保護、異PID＋正常併存、欠損sample。表示・枠・時刻・取消を比較|高・恒久化優先。保存結果は旧4/8→修正8/8。WindowServer/画面/panelはstub、OSでのID再利用ではない。`run.py`の旧2ケースは旧挙動の再現用で、`compare.py`の8ケースと重複計上しない|
|X02 `dist/review-20261022/verify/`|実verify.shをBash 3.2でplugin有／無の2条件。shimのxcrun呼出順・引数・exitをassert|高・恒久化候補。build/test本体はshimが成功を返すだけ。保存fixed 2/2はシェル互換性の証拠。baseline失敗を期待するrunのexit 0も製品の成功ではない|
|X03 `dist/review-20261022/transition/`|実workerと抽出transition。focus/close/minimize × queued/reading/normal=9ケース。先頭6件は取消＋副作用0回を要求|**現行回帰として低価値／仕様不一致**。`main.swift:16`でextraPermitsへ登録するが本番transitionは一括取消しない。`docs/REVIEW.md:12`で案は不採用。保存6失敗/9件を未修正バグと数えず、研究用記録として保持。通常3件とAX fixture自体は再利用余地あり|
|X04 `dist/tracking-improvements-20261018/evidence/startup-probe/`|実observeMouseInteraction/recordInteraction/suspend冒頭・FrameTrackerを抽出。所有NSWindowへNSEvent配送。即時sample、重複開始、停止後0、再開1、同じeventが配送先へ届くことをassert|高・A03/A04より広い。WindowServerはstub、global monitorへ外部入力を送らない。50ms Timer対照は旧AppController全体ではない。過去生成物は現在のコードとは別snapshot|
|X05 同`coordinate-probe/`|実型・CG読取・callbackを抽出。所有NSWindow/NSPanelを60段階動かし、論理完了を8ms先行。両枠を同時CG取得してずれをJSONへ記録|中〜高・原因検証の測定。自動の合否assertionより測定中心。旧最大8pt→修正0ptはfixture条件内。AX、実ブラウザ、full follow/orderは含まない。現在のFrameTracker callback型変更に対して過去コピーを現行版扱いしない|
|X06 同`metadata-benchmark/`|旧commitと生成時のServerSnapshotを抽出。空／重複／全fields/readAt/orderのprecondition、checksum一致。16/80/240窓×0/1/16参照、構築込み400 snapshotsを測定|中・性能根拠として保持。A01/A02より意味検査が広いが、全体アプリ高速化の証明ではない。固定旧commitと生成時の新ソースを区別する|
|X07 `dist/attachment-probe-20261018/`|独立AppKit/C fixture。同／別プロセス、public child／private group等の8自動条件、CG相対位置。手動2回は対象不動で無効と記録|現行回帰として低、技術選定証拠として中。製品が採用していない経路であり本番coverageに数えない。API戻り値0≠連動。`run5`/`run6`を成功にしない。再実行はGUI窓を作るので今回未実施|

補助ソースの確認範囲：X01の`run.py`／`compare.py`／`main.swift`／`comparison-harness.swift`と生成・frozen系、X02の`test.py`とbaseline/fixedのverify.shコピー、X03の`prepare.py`／`run.sh`／`main.swift`／`Doubles.swift`／RuntimeModels・baselineコピー、X04/X06の`generate.py`／`main.swift`／`Extracted.swift`、X05の`prepare.py`／`main.swift`／Server・FrameTracker・Callbackのコピー、X07の`run.sh`／`AttachmentProbe.swift`／`TransomBridge.c`／`symbols.c`／`event-access.swift`。`evidence/inspect-windows.swift`は窓メタデータの観測補助で、合否を判定するテストではない。

保存済みソースを将来の回帰へ昇格する場合は、実行時に現行ソースへ結び付くこと、変更箇所だけをstub化すること、正常対照、失敗時の非zero exit、独立した出力先を条件にする。旧版が失敗することを期待するハーネスと、製品の合格を要求するハーネスを同じ成功件数に混ぜない。

## 手動受入29項目との対応

出典は`docs/ACCEPTANCE.md`。今回はP0-01の自動部分（verify.sh）を再確認し、**残る28項目のGUI・実機受入は未再実施**。過去の結果欄は各日付・OS・試した条件に限る。特に冒頭の「すべて未実行」や旧34件という表現と後日の追記が併存するため、現時点の試験結果には転用しない。

|項目|守る動作|自動テストとの関係・不足|
|---|---|---|
|P0-01|両製品コンパイルと単体テスト|今回verify成功。項目本文の「34件」は旧件数、現57件|
|P0-02|起動・AX許可・追跡開始|buildでは代替不可。権限状態・起動は未操作|
|P0-03|実バーが元の操作部を覆わない|G01/G12は計算のみ。実panel配置と入力透過が必要|
|P0-04|同名A/Bへ独立バー|F01–F04は識別部品。実window生成・結線は別|
|P0-05|他アプリとの重なりで奥行きを維持|O群は人工metadata。実order/readbackが必要|
|P0-06|コピー元がA、選択状態を維持|F群にselectionRange・clipboard試験なし|
|P0-07|Aの保存がAだけへ作用|permit単体では対象・保存完了を保証しない|
|P0-08|Bの保存がBだけへ作用|P0-07の逆対象。対象取り違えのため残す|
|P0-09|メニュー中の対象切替で取消／拒否|F05はPolicyだけ。MenuCoordinatorの実取消が必要|
|P0-10|対象close／title変更で操作中止|N群は不在判定だけ。メニュー・タイトル変化は別|
|P0-11|sheet中は表示・操作停止|F06のtrue入力でAX.hasSheetは検査できない|
|P0-12|無応答でも他アプリを固めず再送なし|P群・S05でタイムアウト／キュー隔離は実証不可|
|P1-01|ネイティブ移動・リサイズ追従|A群だけでは不十分。X04/X05も実マウスの代替ではない|
|P1-02|外付けバーdragで対象移動|J/R群は状態・座標だけ。初期座標・AX送信が別|
|P1-03|画面上端ではバー非表示|G02は強い部品試験。パネル非表示・入力保全は実機|
|P1-04|空間確保は指定1枚だけ|G04は1 frame計算。別窓非変更を観測する必要あり|
|P1-05|最小化・非表示・終了・復元へ追従|N群とF群の組合せだけでライフサイクル全体は保証しない|
|P1-06|native fullscreenでバーなし・復帰|自動の全経路試験なし|
|P1-07|複数画面・負座標・拡大率|G08–G11/R03は人工座標。実画面は未検証|
|P1-08|Spaces切替で古いバーを残さない|X03の操作取消方針とは別。実表示投影の試験が必要|
|P1-09|Mission Control／Stage Manager|適格サイズ部品・実thumbnail差異・入力は未自動化|
|P1-10|Esc・矢印・Returnのメニュー実行先|自動のNSMenu配送試験なし|
|P1-11|動的・深いメニューを誤実行しない|L群は幅計算のみ。AXMenuReaderの予算・階層・経路照合は別|
|P1-12|同一セッションの要求は1回|P04は同一permitへの並行commit。実session生成と再送を別途検査|
|P1-13|停止・終了・権限取消・lock／復帰|A04はtimer handle、X04は監視解除の一部。古い応答での復活は別|
|P1-14|多数窓のCPU／メモリー／遅延|X06はstructのmicrobenchmark。全体性能に換算不可|
|P1-15|Chrome/Finder/CotEditor/Safari等|自動fixtureは第三者アプリのAX差を再現しない|
|P1-16|最小化・最大化・closeが指定1枚へ1回|G06/H01/P群は部品。実AX受理・未保存dialog・制約は別|
|P1-17|上端5ptで縦最大化・復元、横維持|H02/R群で上端hit判定や実2辞書の順序は検査できない|

## 今回の実行証拠

環境：macOS 27.0.1（26A434）／arm64／Xcode 27.1（27A9275）／Swift 6.4（swiftlang-6.4.0.34.1）、言語モード5。

`/bin/bash scripts/verify.sh`：両製品build、S01–S08、Core 53件・App 4件が成功。ログ：Git非追跡 `dist/test-audit-20261023/verify.log`。

局所mutationは同ディレクトリの`audit_mutations.py`が追跡ファイルだけを`snapshot/`へコピーし、変更を1種類ずつ適用して全57件を実行する。各実行後に元へ戻し、実checkoutの製品・テストソースへは変更しない。baselineのコンパイル成功と、テスト完走を確認してから評価する。compile失敗をmutation検出には数えない。

|実験|隔離コピーだけの変更|結果／意味|
|---|---|---|
|M00|変更なし|57/57成功。比較基準|
|M01|Rect/Pointの`Geometry.flip`を入力そのまま返す恒等関数へ|57/57成功。座標変換そのものを壊してもG09/G10は検出できない|
|M02|`FrameTracker.sample`の`WindowServer.describe(ids)`を`describe([])`へ|57/57成功。要求IDを実読み取りへ渡さない退行をA03/A04は検出できない|
|M03|`AppController.follow`の所有PID比較を常にtrueへ|57/57成功。過去に修正した所有者照合の退行を通常suiteは検出できない|
|M04|`OperationPermit.commitOnce`の`committed = true`を除去|55/57成功、P01/P04の2件が計3 assertion失敗、exit 1。高価値テストが意図した退行を検出する正常な対照|

実験の適用差分・exit code・完走要約は `dist/test-audit-20261023/mutation-results.json`、各ログは同ディレクトリの`M*.log`に保存。これは選択した数個の誤実装の検査であり、網羅的mutation scoreやbranch coverageの測定ではない。補助試験7ファミリーの再実行・実GUI／AX／第三者アプリ・Intel・他OS・複数画面の受入は未実施。

mutation後は隔離コピーの全追跡ファイルが元の内容に戻ったことをハッシュ比較で確認し、同コピーで`/bin/bash scripts/build-app.sh`と`--lab`を実行。両bundle生成・署名verifyが成功した。成果物は`dist/test-audit-20261023/snapshot/dist/`のみで、通常版の差し替え・起動・設定変更は行っていない。ログは`app-bundle.log`／`lab-bundle.log`。

台帳の57行とソースの`@Test`名を機械照合し、未収録0・重複収録0。独立レビュー2件と親レビューで、誤った入力件数・受入実施範囲・参照行を訂正した。

## 台帳を使う順番

1. LV-01/LV-02の独立期待値とGAP-01の非空ID→実follow検査を優先する。小さな試験追加で、今回実証した見逃しを閉じられる。
2. X01/X02と採用済みのworker取消試験を恒久化する。X03の不採用仕様は回帰へ持ち込まない。
3. LV-03/LV-04とGAP-02/GAP-03を改善し、名称が約束する範囲と実際のassertionを揃える。
4. LV-05や部分重複の整理は最後。数を減らすことより、固有の安全条件と正常動作の両方を残す。

今回の変更は監査文書だけ。上記は修正済み項目ではなく、今後の改善候補である。
