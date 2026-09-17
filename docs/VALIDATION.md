# 検証結果 — 作成環境

日付：2026-09-10

|項目|結果|
|---|---|
|作成環境|Linux x86_64|
|Swift|6.2.1、Swift言語モード5|
|WindowBarCoreのコンパイル|実行済み・成功|
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

## 34件の内訳

Geometry 10件、HeaderLayout 4件、Identity/Focus 7件、OperationPermit 4件、Presence 3件、Ordering 6件。

同名窓や同一窓の別文書の拒否、タイムアウト後を想定した実行の一回性、取消、期限切れ、100並列要求に対する1回だけのcommit、AXエラーと窓終了の区別、誤った重なり順、複数ディスプレイの負座標、元の操作部に重ならない配置を共通ロジックで確認した。

これらは実際のAppKit・AX・WindowServerをモックしてその互換性を証明するテストではない。実機側で `HANDOFF.md` に従い、コンパイルおよび `ACCEPTANCE.md` を実施する必要がある。

## 引き継ぎ後の追記欄

OS/CPU/Xcode/Swift：macOS 26（Darwin 25.6.0）／Apple Silicon（arm64）／Xcode未インストール（Command Line Toolsのみ、SDK MacOSX27.0）／Swift 6.4（swiftlang-6.4.0.34.1）。日付 2026-09-16。

追記（2026-09-17）：Xcodeをインストールし `sudo xcodebuild -license accept` 後、Xcodeツールチェーン（同じくSwift 6.4）で `bash scripts/verify.sh` を再実行し、ビルドと34件のテストが成功した。以降の `dist/WindowBar.app` は自己署名証明書 `windowsbar`（`CODESIGN_IDENTITY`）で署名している。アドホック署名では再ビルドごとにアクセシビリティ許可が失効し、AppControllerが走査を行わずアイドルになることを `sample` で確認したため。

実行したコマンド：`bash scripts/verify.sh`（WindowBar・WindowBarLabのビルドと34件のテストが成功）、`.build/out/Products/Debug/WindowBar --capabilities`（`exact-window-id=true`、`private-relative-ordering=true`）、`bash scripts/build-app.sh`、`bash scripts/build-app.sh --lab`（`dist/WindowBar.app`、`dist/WindowBarLab.app` を生成、アドホック署名の検証成功）。

型・リンクエラーの修正：Mac SDKでの型エラー・リンクエラーは発生しなかった。修正したのは (1) XCTest不在によるテストのSwift Testing移行、(2) macOS 14で非推奨かつ無効な `activateIgnoringOtherApps` の除去とAX `kAXFrontmostAttribute` によるフォーカス経路の追加（`docs/REVIEW.md`）、(3) `SLSGetWindowLevel` の第3引数型を `int64_t *` から `int *` へ訂正（yabai extern.h準拠）。

実機で合格したテスト番号（2026-09-17）：P0-01（ビルド＋34件）、P0-02（許可後にAX走査とバー表示を確認）、P0-03（元の操作部を覆わず上に30ptのバー、幾何学的に確認）、P0-04（同名2窓に独立バー）、P0-06（Aのバーのコピーでクリップボード＝Aの行）、P0-07（Aのバーの検証保存で `window=A`）、P0-08（Bのバーの検証保存で `window=B`）。P0-05は前面窓が前のとき背面窓のバーが浮かないことを確認（多数窓の網羅は未実施）。

未合格・未実行：P1全項目（追従、ドラッグ移動、フルスクリーン、複数画面、Spaces、Mission Control、動的メニュー、多数窓の負荷等）は未実施。アプリのアクティブ化経路（activate／activate(from:)／AX frontmost）の単体プローブは実行許可が下りず未計測だが、実アプリでのメニュー実行は成功しているためAX frontmost＋raiseの経路は機能している。

観測した重要事項：非公開のZ-order経路（SkyLightのSLSTransactionSetWindowLevel）はmacOS 26でコード -5（setLevel失敗）を返し使用できなかった。バー表示は公開相対order＋メタデータ照合で正しく機能する。3回失敗で非公開経路を自動停止するよう修正済み（ログ氾濫の解消）。`--capabilities` の `private-relative-ordering=true` は関数の存在を示すのみで、動作可否とは別であることが実機で裏付けられた。
