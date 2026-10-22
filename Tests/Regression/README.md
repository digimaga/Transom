# 本番経路の隔離回帰テスト

macOSの通常入口は `bash scripts/verify.sh`。Swift Testingの後に `python3 scripts/run-regression-tests.py` を実行する。XcodeまたはCommand Line Tools、Swift 6、Python 3.9以降を使用し、追加パッケージは不要。Linuxでは既存のCoreテストと構文検査だけを実行する。

個別実行：

```sh
python3 scripts/run-regression-tests.py --suite accessibility
python3 scripts/run-regression-tests.py --suite controller
python3 scripts/run-regression-tests.py --suite menu
python3 scripts/run-regression-tests.py --suite gesture
python3 scripts/run-regression-tests.py --suite shell
```

既定では毎回 `.build/regression-<random>/` に生成ソース・コンパイルログ・結果・本番ソースのSHA-256を保存する。`--output-dir <新しいディレクトリ>` で保存先を指定できる。生成物はcommitしない。失敗は非zero exit、未取得の完了結果や0件実行は成功にしない。AX/Controllerの数値はassertion数、Menuは関数単位6ケース、Gesture/Shellは各2条件であり、Swift Testingの件数に加算しない。

## この方式を選ぶ理由

監査で見つかった原因は、空ID・純粋関数の合成だけを使うfixtureと、通常検証に含まれない過去のソースコピーだった。本番コードへテスト専用API・依存注入層を追加する代わりに、現在の実装を実行ごとに読み込み、外部I/Oだけを差し替える。初回監査のM01〜M03を含む局所mutationで、誤実装がassertion失敗になることも確認する。

|suite／テストファイル|実行する本番コード|差し替える境界・対象外|
|---|---|---|
|accessibility／`AccessibilityTests.swift` + `AccessibilityFixture.swift`|AXAppWorker、AXMenuStore、RuntimeModels全文、Core。実workerのシリアルキュー・permit・scan・witness・メニューツリー・二段階配置・MainRunLoop|AX属性・setter・action、WindowServerをインメモリー化。AXUIElementCreateApplicationは参照の生成のみ。actionは記録用関数へ置換し、observer IPCは呼ばれたら失敗。未知のAX APIを生成時に拒否する。AXUtilitiesのIPC・権限・タイムアウト動作は対象外|
|controller／`ControllerTests.swift.in`|実FrameTracker、ServerWindow/Snapshot、WorkerState、Controllerの追跡／配置／履歴／scan／transition／監視登録・suspendメソッド、対応するstorageとcallback結線|CG metadata・画面・panel・worker完了・イベント監視の登録先を制御。AppControllerの起動全体・描画・実NSWorkspace・実イベント配送・retire内部は対象外|
|menu／`MenuTests.swift`|MenuCoordinator全文と実選択target/action、Core permit|NSMenu/Item、アプリ活性化、panel座標変換、worker応答。popupの再入順序を制御し、実NSMenuのkeyboard/AX操作はしない|
|gesture／`GestureTests.swift`|HeaderView全文（DragSurface含む）、RuntimeModels、Core gesture|2箇所のマウスポインタ読取だけを固定値へ置換。mouseDown→移動で値を変え、down時の位置がcallbackへ渡ることを確認。所有する非表示NSWindow上のメソッド直接配送であり、OSがhidden viewへmouseUpを届ける証明ではない|
|shell／runner内|現行verify.sh、check-source.py、`/bin/bash`|xcrunを引数記録shimへ、再帰するrunner呼出しを記録へ置換。plugin有無・空白入りパス・引数と順序を検査する。Swift build/testの成功証拠には数えない|

Controllerの抽出は宣言名の一意性・brace対応・コンパイルを要求する限定的な抽出器で、Swift AST parserではない。対象宣言・storage・callbackが変われば、fixtureも意図をレビューして更新する。古い生成物へのfallbackはない。非採用の「Space transition時にextraPermitsを一括取消」は期待仕様にしない。

## 何を守るか

|グループ|契約|
|---|---|
|AX focusCases|正常focusとmodal/minimized/fullscreen/sheet、PID・window ID・processInstance・incarnation・AX参照の拒否|
|AX actionCases / cancellationCases|成功・cannotComplete・failure後も同じ操作は1回。読取中のpermit／worker lifetime取消でwriteしない。正常対照はwriteする|
|AX placementCases|拡大はposition→size、縮小はsize→position。実workerがCG受理枠を返し、違うPIDのreadbackでは後続writeしない|
|AX mainRunLoopCase|実MainRunLoop.performがeventTracking common mode内で完了を配送|
|AX scanCases|完全更新／部分属性失敗／一覧失敗／連続不在／再出現で、保持・非表示・削除とincarnation更新を使い分ける|
|AX menuCases|prepare中の文書変化、focusedElement/selectionRange、root/path参照・role/title/enabled変化を拒否。正常executeも同一sessionで再送しない|
|Controller trackerCases / monitorCases|非空ID→読取→follow、所有PID一致、他窓の独立性、CG座標優先、即時計測／重複start／timer common登録／stop、local event同一性、監視解除とlate event抑止|
|Controller placementCases|縦最大化→通常最大化→通常復元→縦復元、2窓の履歴分離、受理枠、指定1枚へのreserve|
|Controller completionCases / scanAndTransitionCases|旧focus/reserve/scan完了が新しい要求・worker・instanceを壊さない。現行transitionの取消範囲を保持|
|Menuの6関数|popup中は実行せず閉じてから1回、準備前／popup後の文脈変化、古いfocus/prepare/execute応答、popup再入、安全なdisabled/notice/子項目/mark/shortcut|
|Gestureの2条件|HeaderView本体とDragSurface双方で、遅延drag開始の初期座標とbegin→move→endの排他性|
|Shellの2条件|標準bashのset -u下でpluginなし／あり、空白入りtoolchainパスを壊さず通常検証へ進む|

本番コードの全分岐・実IPC・第三者アプリ・Spaces・表示順序・物理マウス・OS差は保証しない。実機受入は `docs/ACCEPTANCE.md`、今回の証拠と制約は `docs/VALIDATION.md`、監査IDとの対応は `docs/TEST_AUDIT.md` を参照。
