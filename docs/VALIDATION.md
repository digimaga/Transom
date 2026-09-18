# 検証結果 — 作成環境

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
