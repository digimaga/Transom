# 検証結果 — 作成環境

## 2026-10-02：外付けバーのクリック時の前後順変更を抑制

環境：macOS 27.0.1（26A434）／M1 MacBook Pro・arm64／Xcode 27.0（27A266a）／Swift 6.4（swiftlang-6.4.0.34.1）、Swift言語モード5。

診断ビルドでは、前後順の照合が失敗してバーを透明化した直後に、そのバーへmouse-down／mouse-upが届き、ボタンの実行処理が呼ばれない状態を記録した。これは報告されたちらつきと整合するが、macOS更新で変更された内部処理までは特定していない。

`ActionButton`・`DragSurface`・`HeaderView`の各ヒット対象で、AppKitの`shouldDelayWindowOrdering(for:)`と`preventWindowOrdering()`を使用し、クリックによるバー自身の自動前面化を抑える。ボタンは最初のクリックを明示的に受け付け、通常のNSButtonの処理へ渡す。対象窓の正確なID・フォーカス・文脈の照合、アプリ別AXキュー、OperationPermitによるAXPressの一回実行は変更していない。

確認した結果：

- 作業ツリーで`bash scripts/verify.sh`成功。Transom・TransomLabのビルドと44件（7 suite）のテストが成功。
- 今回のクリック処理の差分だけを含む一時コピーでも`verify.sh`成功。同じコピーで`bash scripts/build-app.sh`と`--lab`成功。既存の未commitの縦方向最大化の変更は配布物に含めていない。
- 固定パスの`dist/Transom.app`・`dist/TransomLab.app`を更新。`Authority=Transom`と`codesign --verify --strict`成功を確認。新しい権限の付与や設定変更は実施していない。
- CUAによるAX操作で、TransomLabの外付けアプリメニューと「ファイル」メニューの展開、Escによるアプリメニューの取消を確認。
- 外付けの「検証保存」を1回選択し、`~/Library/Application Support/TransomLab/events.log`に`2026-10-02T06:53:19Z SAVE window=A id=1428`の1件だけが記録されたことを確認。
- 外付けの閉じるボタンを1回操作し、B（window ID 1430）が閉じ、A（1428）が残ることをAXの本文表示とWindowServerのIDで確認。閉じる操作の再試行はしていない。

未確認・制限：自動操作でも操作前後にバーの再配置・一時非表示が発生したため、通常のマウスで「1回で毎回開く」「ちらつきが解消した」ことの合格にはしていない。2窓が開いている間、Aのメニュー操作は`focused-window`の不一致で拒否された。Bを閉じた後のAではメニュー展開と保存が成功した。このフォーカス拒否の原因、実マウスでの連続クリック、ドラッグ、ダブルクリック、他アプリでの再現解消、Spacesの回帰確認は未完了。既存の合格記録は当時のOSと手順に限定され、macOS 27での合格を意味しない。

今回のログ：`/tmp/transom-final-verify-20261002.log`、`/tmp/transom-final-snapshot-verify-20261002.log`、`/tmp/transom-final-build-20261002.log`、`/tmp/transom-final-lab-build-20261002.log`、`/tmp/transom-interaction-20261002.log`、`/tmp/transom-fixed-interaction-20261002.log`。これらは一時ファイルであり、Gitには含めていない。診断用の追加ログコードは配布物に含めていない。

## 作成時（2026-09-10）の記録

日付：2026-09-10

|項目|結果|
|---|---|
|作成環境|Linux x86_64|
|Swift|6.2.1、Swift言語モード5|
|TransomCoreのコンパイル|実行済み・成功|
|XCTest共通ロジック|34件を実行、失敗0|
|AppKitソースとLabのSwift構文パース|実行済み・成功。SDKの型チェックではない|
|シェルスクリプトのbash構文|実行済み・成功|
|Info.plist / LabInfo.plistの構造|実行済み・成功|
|必須ファイル・AX境界の構成チェック|実行済み・成功|
|Mac版のSwift型チェック|未実行|
|CブリッジのMac SDKコンパイル|未実行|
|Macアプリのリンク・署名・起動|未実行|
|AX権限・メニュー・フォーカスの実機確認|未実行|
|Z-order・Spaces・複数画面の実機確認|未実行|
|GitHub Actions|設定ファイルのみ作成。実行していない|
|公開配布向け公証|未実行|

実行ログは `test-results-core.txt` と `verification-log.txt`。上記はLinux作成時点のXCTestによる結果である。

2026-09-16のMac実機引き継ぎで、テストはXCTestからSwift Testing(`import Testing`、`@Suite`/`@Test`/`#expect`)へ移行した。理由は、Xcode未インストールのCommand Line Tools環境にXCTestが含まれず `xcrun swift test` が失敗するため。テスト名・件数(34件)・検証内容は変えていない。Command Line Toolsのみの環境では既定ビルドシステムがTestingマクロのプラグインパスをフロントエンドへ渡さないため、`scripts/verify.sh` が `-Xswiftc -plugin-path` で明示指定する。

## 34件の内訳（2026-09-17の追加・書き換えを経て、現在は40件）

Geometry 10件（現在11件）、HeaderLayout 4件、Identity/Focus 7件、OperationPermit 4件、Presence 3件、Ordering 6件。

同名窓や同一窓の別文書の拒否、タイムアウト後を想定した実行の一回性、取消、期限切れ、100並列要求に対する1回だけのcommit、AXエラーと窓終了の区別、誤った重なり順、複数ディスプレイの負座標、元の操作部に重ならない配置を共通ロジックで確認した。

これらは実際のAppKit・AX・WindowServerをモックしてその互換性を証明するテストではない。実機側で `HANDOFF.md` に従い、コンパイルおよび `ACCEPTANCE.md` を実施する必要がある。

## 引き継ぎ後の追記欄

OS/CPU/Xcode/Swift：macOS 26（Darwin 25.6.0）／Apple Silicon（arm64）／Xcode未インストール（Command Line Toolsのみ、SDK MacOSX27.0）／Swift 6.4（swiftlang-6.4.0.34.1）。日付 2026-09-16。

追記（2026-09-17）：Xcodeをインストールし `sudo xcodebuild -license accept` 後、Xcodeツールチェーン（同じくSwift 6.4）で `bash scripts/verify.sh` を再実行し、ビルドと34件のテストが成功した。以降の `dist/Transom.app` は自己署名証明書 `windowsbar`（`CODESIGN_IDENTITY`）で署名している。アドホック署名では再ビルドごとにアクセシビリティ許可が失効し、AppControllerが走査を行わずアイドルになることを `sample` で確認したため。

実行したコマンド：`bash scripts/verify.sh`（Transom・TransomLabのビルドと34件のテストが成功）、`.build/out/Products/Debug/Transom --capabilities`（`exact-window-id=true`、`private-relative-ordering=true`）、`bash scripts/build-app.sh`、`bash scripts/build-app.sh --lab`（`dist/Transom.app`、`dist/TransomLab.app` を生成、アドホック署名の検証成功）。

型・リンクエラーの修正：Mac SDKでの型エラー・リンクエラーは発生しなかった。修正したのは (1) XCTest不在によるテストのSwift Testing移行、(2) macOS 14で非推奨かつ無効な `activateIgnoringOtherApps` の除去とAX `kAXFrontmostAttribute` によるフォーカス経路の追加（`docs/REVIEW.md`）、(3) `SLSGetWindowLevel` の第3引数型を `int64_t *` から `int *` へ訂正（yabai extern.h準拠）。

実機で合格したテスト番号（2026-09-17）：P0-01（ビルド＋34件）、P0-02（許可後にAX走査とバー表示を確認）、P0-03（元の操作部を覆わず上に30ptのバー、幾何学的に確認）、P0-04（同名2窓に独立バー）、P0-06（Aのバーのコピーでクリップボード＝Aの行）、P0-07（Aのバーの検証保存で `window=A`）、P0-08（Bのバーの検証保存で `window=B`）、P0-09（メニュー中の別アプリ切替で0.25秒以内に取消）、P0-10（メニュー中の対象クローズで0.25秒以内に取消、修正後）、P0-11（シート表示中はバー非表示、修正後）、P0-12（AX応答停止プロセスに巻き込まれず、他窓の追従継続）。P0-05は前面窓が前のとき背面窓のバーが浮かないことを確認（多数窓の網羅は未実施）。P0-10とP0-11で見つかった2件の不具合（NSMenu追跡中の完了通知停止、NSAlertシートの未検知）は修正済み（`docs/REVIEW.md`）。

P1の実機結果（2026-09-17、`docs/ACCEPTANCE.md` に詳細）：合格 P1-01（移動追従）、P1-02（外付けタイトルのドラッグ）、P1-03（上端でバー非表示）、P1-04（空間確保）、P1-05（非表示・最小化・終了）、P1-06（フルスクリーン）、P1-10（キーボード操作）、P1-11（多階層・動的メニュー）、P1-12（連続クリックで要求1回）。追加で合格 P1-08（Space切替と窓の別Space移動で残存なし）、P1-14（33・62・100窓でも全バー一致・浮きなし。CPUは100窓で平均約17%）、P0-05（100窓の重なりで前後順違反0件）。合格 P1-09（Mission Control中はバーが対象窓と共に縮小表示、残存なし。Stage Managerではサムネイルへの誤表示を修正し、中央窓だけにバーが付き切替に追従）。一部合格 P1-13は合格（無効化/再有効化、終了/再起動、画面ロック、ディスプレイ消灯、許可の取り消し/再許可で、保留メニューの取消と保存の不実行、バーの復帰を確認。システムスリープは本機で無効のため未実施）。一部合格 P1-15（バー表示は7アプリ、メニュー展開はテキストエディット・Finder・Claude・Chrome・Safari、実行はTransomLab）。未実施 P1-07（単一ディスプレイのため。Sidecar/AirPlay等で第2ディスプレイを用意すれば検証可能）、P1-13の画面ロック・スリープ・許可取消。検証はアクセシビリティ許可を付与したClaudeアプリ配下のヘルパーから、TransomのAXツリー読み取りと実マウス・キーイベント生成で行った。

未合格・未実行：上記の未実施項目。アプリのアクティブ化経路（activate／activate(from:)／AX frontmost）の単体プローブは実行許可が下りず未計測だが、実アプリでのメニュー実行は成功しているためAX frontmost＋raiseの経路は機能している。

観測した重要事項：非公開のZ-order経路（SkyLightのSLSTransactionSetWindowLevel）はmacOS 26でコード -5（setLevel失敗）を返し使用できなかった。バー表示は公開相対order＋メタデータ照合で正しく機能する。3回失敗で非公開経路を自動停止するよう修正済み（ログ氾濫の解消）。`--capabilities` の `private-relative-ordering=true` は関数の存在を示すのみで、動作可否とは別であることが実機で裏付けられた。

追記（2026-09-17、バー下端の角の隙間埋め）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。`screencapture -l` で撮った窓画像の透明画素を行ごとに数え、テキストエディットとClaude（Electron）の窓の上角が同一の形状で、CALayerの `cornerCurve = .continuous`・半径16ptの描画と行ごとの誤差1px以内（2x）で一致することを確認した。円弧（半径17pt）では端付近で最大6pxずれる。修正後、バー直下の角領域（窓端から20pt四方）に壁紙の画素が0件（修正前は1600画素中255件）。`bash scripts/verify.sh` はビルドと35件のテストが成功。クリックの透過は、システム全体AXの `AXUIElementCopyElementAtPosition` でバー本体はTransomのボタン、帯の透明部分（窓上端から2〜24pt）はテキストエディットの窓、角の塗り部分（窓端から2pt）はTransomの窓と返ることで確認し、窓の移動後も同じ結果だった。検証用の非不透明パネルで `ignoresMouseEvents` をfalseに設定すると透明部分の透過が失われ、`invalidateShadow`・再描画・`isOpaque`/背景色の再設定・枠の再設定・orderOut/orderFrontのいずれでも回復しなかったため、HeaderPanelは `ignoresMouseEvents` を使わず内容ビューの非表示で非表示中の入力を防ぐ方式に変更した。alphaValueの0/1切り替えだけでは透過は失われない。未確認：複数ディスプレイ、Retina以外の1xディスプレイでの角の見え方、将来のOSで角丸半径が変わった場合の追従（`Geometry.windowCornerRadius` の定数）。

追記（2026-09-17、ウィンドウ追従の遅延解消と画面外はみ出し時の表示）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4／表示 1920x1080（2x）60Hz。`bash scripts/verify.sh` はビルドと36件（Geometryにはみ出し配置の1件を追加）のテストが成功。計測は、アクセシビリティ許可のあるClaudeアプリ配下のSwiftヘルパーで、TransomLabの窓（680x448）を対象に、CGEventの実マウスイベントで元のタイトルバーまたは外付けバーの文書タイトル領域を240×160pt／40段階／8ms間隔（約750pt/秒）でドラッグし、その間に `CGWindowListCreateDescriptionFromArray` で対象窓とバーの枠を1ms間隔で採取して「バー下端と窓上端」「x」のずれを求めた。結果はP1-01・P1-02の欄に記載。CPUは、ドラッグ中（1.6秒）に約12〜24%、アイドル時約2.7%（`top` 1秒間隔、対象5窓）。

原因として確認した事実：(1) 修正前はバー位置がCGメタデータの50ms周期の取得でしか更新されず、ドラッグ終了後は0.5秒周期に落ちるため最後の位置合わせが遅れた。(2) 外付けバーのドラッグでは1回の移動ごとに約14回のAX往復（完全なフォーカス検証）を行い、さらに移動要求と同じシリアルキューでAX走査（タイトル等）が走って移動を待たせていた。(3) 背景キューの `CGWindowListCopyWindowInfo` が `SLSConnectionSynchronizeSLSCATransaction` で自プロセスの直前のCAトランザクション完了を接続ロックを握ったまま待ち、メインスレッドの次のコミットがそのロックを待つため、0.5秒のタイムアウトまで両方が停止していた（`sample` でメイン側 `SLSConnectionSetLastSLSCATransaction → _os_unfair_lock_lock_slow`、背景側 `_SLSTransactionWaitSource` を確認）。`CGWindowListCreate` と `CGWindowListCreateDescriptionFromArray` も同じ同期を行うため、呼び出しをメインスレッドへ移し `CATransaction.flush()` 後に読む形で解消（以後、20ms超の読み取り0件、500ms停止0件）。なお `CGWindowListCreate` はSwiftから直接呼べないため、公開APIの薄いCラッパー `WBCopyOnScreenWindowIDs` をTransomBridgeに追加した（非公開APIではない）。

画面外はみ出し：対象窓をAXで x=-650（画面内に30pt）、x=1890（画面内に30pt）、y=962（下端）へ置いたとき、バーが窓と同じx・幅で窓直上（y=窓上端-30）に表示されることをCG枠で確認。y=30（メニューバー直下）では従来どおりバーなし。AppKitによる枠の画面内クランプは起きなかった。

未確認：複数ディスプレイ境界をまたぐ窓のバー表示、120Hz表示での追従、Electron等の応答が遅いアプリでのバー側ドラッグの体感、100窓環境でのドラッグ中CPU。窓を前面化した直後にバーが約0.1秒消えて再表示される挙動（アプリのアクティブ化で全窓がバーより前に出て並べ直すため）は、以前の最大0.5秒から短縮したが残っている。

追記（2026-09-17、Windows風ウィンドウボタン）：macOS 26.6／Apple Silicon／Xcodeツールチェーン Swift 6.4。`bash scripts/verify.sh` はビルドと39件のテスト（ウィンドウボタンの配置と最大化枠の2件を追加）が成功。実機では、バーのAX子要素からラベル「最小化」「最大化／元のサイズに戻す」「閉じる」のボタン座標を取り、CGEventの実クリックで操作した。結果は `docs/ACCEPTANCE.md` P1-16。文書名ラベルの削除後、バーの窓画像で最後のメニューより右に文字相当の画素が0件であることも確認済み。

追記（2026-09-17、角の隙間埋めを背面方式へ変更）：半径16ptのマスクで塗る前回の方式では、角丸が大きいSafari（連続曲線で半径約30pt、上端行の不透明開始が63px＝31.5pt）に三日月状の隙間が残った（角領域1600画素中371画素が壁紙）。ユーザーの提案どおり角丸の形に合わせるのをやめ、バーのパネルを対象窓の直後（背面）に `order(.below, relativeTo:)` で並べて、窓の上端より48pt下まで不透明に描く方式へ変更した。窓に隠れて角丸から透ける部分だけが埋まるため半径に依存しない。実機（macOS 26.6）でSafari・Claude・テキストエディットの角領域の壁紙画素が0件、CGWindowListの前後順は対象→バーの順、AXの位置問い合わせでバー本体はTransomのボタン、帯の上のSafariツールバーはSafari、角の塗り部分はSafariの窓（窓の透明画素越しに前面の窓が返る）と返った。SafariとClaudeのアクティブ化で前後順を入れ替えた後もバーが対象の直後に戻ることを確認した。Safariのツールバー（ガラス表現）に帯の色が透ける等の見た目の変化は目視で認められなかった。`bash scripts/verify.sh` はビルドと40件のテストが成功（Ordering 6件を背面前提へ書き換え、自窓が間に挟まる場合の1件を追加）。非公開のSkyLight経路（WBOrderAboveWindow）は前面へ並べるものなので `WindowServer.order` から外した（`--capabilities` の表示は残る）。未確認：Mission Control・Stage Manager・複数ディスプレイでの背面配置の見え方、対象窓の影が帯に落ちる量の詳細。

追記（2026-09-18、英語ローカライズの取りこぼし修正）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。`AXUtilities.swift` の `TransomError.unavailable("正確なウィンドウIDを取得できません。")` がNSLocalizedString未通過でen.lprojにも未登録だったため、英語環境でも日本語が出る状態だった。NSLocalizedString化し `"Can't get the exact window ID."` を追加。`scripts/check-source.py` に、Sources/TransomAppのNSLocalizedStringキーがen.lprojに全て存在すること、および日本語リテラルがNSLocalizedString・ログ呼出・明示許可リスト以外に残っていないことを確認するチェックを追加した。`bash scripts/verify.sh` はビルドと40件のテストが成功。`CODESIGN_IDENTITY=windowsbar bash scripts/build-app.sh` で再構築し、`Contents/Resources/en.lproj/Localizable.strings` が同梱されることを確認。ビルド済みバンドルを `Bundle(path:)` で読み、`localizedString(forKey:)` が全キー（新規キー含む）を英語へ解決することを確認した。実アプリのメニュー項目をSystem Events経由で取得する確認は、このシェルからosascriptが応答せず（自動化の許可を得られないため）未実施。ja環境での表示はキー＝日本語文言のフォールバックであり、解決経路は前回実機確認済みのものを変更していない。

追記（2026-09-18、署名IDを `windowsbar` から `Transom` へ変更）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。旧名のままだった署名用の自己署名証明書を、opensslで生成した新しい `Transom` 証明書（RSA 2048、KU=digitalSignature、EKU=codeSigning、SKID付き、有効期間10年）に置き換え、`security import` でログインキーチェーンへ登録した（`windowsbar` 証明書は削除せず残置）。`scripts/build-app.sh` は `CODESIGN_IDENTITY` 未指定かつキーチェーンに `Transom` 証明書があればそれで署名し、なければ従来どおりアドホック署名にフォールバックするよう変更（`CODESIGN_IDENTITY` 指定は引き続き優先）。`security find-identity -v -p codesigning` は新証明書を列挙しないが、`codesign --sign Transom` でテストバイナリへの署名が成功し `Authority=Transom` を確認した（初回署名時にキー使用の許可ダイアログが1回出て、許可後は通った）。`bash scripts/build-app.sh` と `--lab` を環境変数なしで実行し、`dist/Transom.app`・`dist/TransomLab.app` がともに `Authority=Transom`・タイムスタンプ付きで署名され、`codesign --verify --strict` を通ることを確認。未確認：署名ID変更に伴うアクセシビリティ許可の再登録（`windowsbar` に紐付いた許可は引き継げないため、次回起動時にTCCの再許可が必要）、起動中の旧ビルドとの差し替え時の挙動。

追記（2026-09-18、アクティブ時バーの色カスタマイズ）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。TRメニューに「アクティブ時のバー」サブメニューを追加し、アクティブ色（システムアクセントまたはNSColorPanelで選んだ任意色）と表示方式（上端2pxライン／バー全体塗り）をUserDefaults `activeBarColor`（NSKeyedArchiver）・`activeBarFill` に保存する機能を実装した。バー全体塗りでは、HeaderViewが背景色の輝度から文字色（黒/白）を選んでタイトルとシンボルボタンへ適用する。`bash scripts/verify.sh` はビルドと40件のテストが成功。`bash scripts/build-app.sh` で `dist/Transom.app` を再構築し `Authority=Transom`・`codesign --verify --strict` 通過を確認、旧プロセスを終了して新ビルドを起動した（PID 74451、プロセス稼働を `pgrep` で確認）。未確認：実機での見た目全般（カラーパネルの起動、色の即時反映、文字色の可読性、ライン／全体の切替、再起動後の設定復元）、NSColorPanelがアクセサリアプリでキーになる挙動、ダークモードでの配色。

追記（2026-09-18、アクティブラインの太さ選択）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。「アクティブ時のバー」サブメニューに「ラインの太さ」を追加し、上端ラインの太さを0（なし）〜5pxの6段階で選べるようにした。値はUserDefaults `activeBarLineWidth`（既定2、読み込み時0〜5にクランプ）に保存し、`HeaderView.setAccent` の引数として全パネルへ即時反映する。バー全体塗りモードでは太さは無効（描画分岐上ラインを描かない）。`bash scripts/verify.sh` はビルドと40件のテストが成功。`bash scripts/build-app.sh` で `dist/Transom.app` を再構築し、旧プロセスを終了して新ビルドを起動した（PID 76498、プロセス稼働を `pgrep` で確認）。未確認：実機での各太さの見た目、太さ0での非表示、モード切替との組み合わせ、再起動後の設定復元。

追記（2026-09-18、バーの地色カスタマイズ）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。TRメニューに「バーの色」サブメニューを追加し、全バーの地の色をシステム標準（windowBackgroundColor）またはNSColorPanelで選んだ任意色にできるようにした。値はUserDefaults `barBaseColor`（NSKeyedArchiver）に保存し、起動時に復元する。カスタム地色ではHeaderViewが輝度から文字色（黒/白）を常時選択し、アクティブ全体塗りと併用した場合はアクティブ側の色判定が優先される。`HeaderView.setAccent` は `setAppearance(accent:base:fill:lineWidth:)` へ改名した。`bash scripts/verify.sh` はビルドと40件のテストが成功。`bash scripts/build-app.sh` で `dist/Transom.app` を再構築し、旧プロセスを終了して新ビルドを起動した（PID 80394、プロセス稼働を `pgrep` で確認）。未確認：実機での見た目（地色の発色、文字の可読性、全体塗りとの併用、再起動後の設定復元）、ダークモードでの配色。

追記（2026-09-18、ログイン起動・ダブルクリック最大化・右クリックメニュー・除外一覧・ホバー強調・バー高さ）：macOS 26.6（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。6件の機能を追加した。(1) TRメニューに「ログイン時に起動」を追加し、`SMAppService.mainApp` の登録・解除を切り替える。登録後にstatusが `.enabled` でない場合はシステム設定での許可を促すメッセージを出す。メニューを開くたびに `menuNeedsUpdate` で最新のstatusへチェックを同期する。(2) バーの空き部分（DragSurfaceとHeaderView本体）で `clickCount >= 2` のmouseDownをドラッグ開始ではなく最大化トグルへ振り分け。(3) バー全域（HeaderView・DragSurface・全ボタン）の `.menu` にコンテキストメニューを設定し、最小化・最大化／復元・閉じる・このウィンドウにバー用の空間を確保・このアプリを除外を右クリックで実行できるようにした。空間確保は最前面限定だった従来処理を `reposition`（activate→AXフォーカス検証→位置・サイズ設定、自動再試行なし）へ共通化し、右クリックしたバーの窓へ非フォーカス状態からでも適用できるようにした（最大化側も同じ経路へ変更。旧コードでフォーカス失敗時に `reserveTarget` が残る問題もクリアするよう修正）。(4) 「除外中のアプリ」サブメニューを追加し、除外bundle IDごとに実行中ならアプリ名で項目を作り、選択で個別解除する。(5) ActionButtonにNSTrackingAreaを追加し、ホバーでグレー（閉じるのみWindows風の赤＋白グリフ）を描く。文字色の上書きは `normalTint`/`hoverTextTint` 分離で既存の塗り分けと競合しないようにした。(6) 「バーの高さ」サブメニューで24・28・30（標準）・34・38pxを選択し、UserDefaults `barHeight` に保存（起動時24〜40にクランプ）。高さは `Geometry.externalHeader`・`maximizedFrame`・`reserveSpace`・ドラッグ中の画面上端クランプへ引数で渡し、HeaderViewの文字・グリフ・アイコンサイズも連動させた。`bash scripts/verify.sh` はビルドと40件のテストが成功。`bash scripts/build-app.sh` で `dist/Transom.app` を再構築し `Authority=Transom`・`codesign --verify --strict` 通過を確認、旧プロセスを終了して新ビルドを起動した（PID 95703、プロセス稼働を `pgrep` で確認）。未確認：ホバー色・コンテキストメニュー・ダブルクリック・高さ切替の実機での見た目と動作、SMAppService登録が実際のログインで起動すること、解除後に起動しないこと、「除外中のアプリ」サブメニューの表示、ダブルクリックの1回目クリックが先行するドラッグbeginと最大化処理の実機での競合、en環境での新規文言の表示。

追記（2026-09-20、連続クリック中のドラッグ開始）：macOS 26.6.2（Darwin 25.6.0）／Apple Silicon／Xcodeツールチェーン Swift 6.4。システム設定の外付けバーで移動できる回とできない回が混在する問題について、失敗時はAX移動ステップが1件も開始されず、成功時だけ移動ログが残ることを実機で確認した。原因は、macOSが連続クリックと判定した2回目の `mouseDown` を即時に最大化へ振り分け、そのままポインタを動かしてもドラッグセッションを開始しなかったことだった。ダブルクリックは `mouseUp` まで保留し、移動量が3ptに達した場合はドラッグを優先する状態機械に変更。遅延開始時に初動の移動量を失わないよう、`mouseDown` 時点のグローバル座標を `DragCoordinator` へ渡す。indexから切り出した対象差分のみの一時ディレクトリで `bash scripts/verify.sh` を実行し、Transom・TransomLabのビルドと44件（7 suite）のテストが成功。同じスナップショットから `bash scripts/build-app.sh` で `Transom.app` を生成し、`Authority=Transom`の署名と `codesign --verify --strict` 通過を確認して固定パスから起動した。未確認：修正後のシステム設定で、1回クリック後すぐのドラッグが毎回開始すること、移動しないダブルクリックが引き続き最大化／復元を1回だけ実行することの実マウス確認。
