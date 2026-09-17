# Mac実機への引き継ぎ

## 0. 現在地点

アプリ本体のソース、ビルド、テスト、検証用アプリは用意済み。ただしLinuxで作成したため、MacのSDKでの型チェック・リンク・GUI操作は未実施。まずビルド結果を確認し、必要なSDK差分を直す。これは既に完成・実証済みのAppKitアプリを運用へ載せる工程ではなく、実装済みの開発版を実機で検証して完成させる工程。

## 1. Macで最初に実行する

ZIPを展開してTransomフォルダへ移動する。

```bash
xcrun swift --version
bash scripts/verify.sh
bash scripts/build-app.sh
open dist/Transom.app
```

Swift 6未満なら対応するXcode／Command Line Toolsを用意する。XcodeのGUIで編集する場合は `open Package.swift`。`verify.sh` はMacではTransomとTransomLabをコンパイルする。Linuxで実施済みなのはCoreの34件だけなので、Macで最初の型エラーが出た場合はそのログから修正する。

`build-app.sh` はプロジェクト内の `dist/Transom.app` だけを作る。/Applicationsへのコピー、ログイン登録、SIP設定の変更は行わない。開発中は固定のパスから起動する。再ビルドする前に古いTransomを終了する。

## 2. 許可と能力確認

「プライバシーとセキュリティ → アクセシビリティ」で、起動しているTransom.appを許可する。再署名・パス変更で許可対象が古い場合は、その古いエントリーを除去して現在のアプリを再登録する。TCCデータベースを直接編集しない。

```bash
./dist/Transom.app/Contents/MacOS/Transom --capabilities
```

期待する表示は `exact-window-id=true`。`private-relative-ordering=true` は任意の私有経路の関数が存在する意味であり、動作確認の合格ではない。falseなら公開相対order経路を使用するが、メタデータで順序を確認できるまではバーを表示しない。IDがfalseなら幾何学的に推定して操作せず、ブリッジを調査する。

TRメニュー「診断情報をコピー」で、権限、能力、窓数、表示数、並び順未確認の窓数を取得できる。文書名・メニュー内容・文書URLは含まれない。

## 3. 最小の実機検証

まずCotEditor・Finder・Chromeのいずれかで、上端に40ポイント以上の余白がある通常窓を1枚使う。表示できたら、同アプリの複数窓、別アプリとの重なりに広げる。バーが出ない場合は上端の空間不足なのか、WindowServer順序が未確認なのかを診断値で切り分ける。

画面上端に寄せた窓は、そのままではバーを出さない。TR →「最前面の1枚にバー用の空間を確保」を選ぶと明示的にその窓だけを移動・必要なら縮小する。元の操作部に重ねる「修正」はしない。

## 4. 同名2窓の検証用アプリ

```bash
bash scripts/build-app.sh --lab
open dist/TransomLab.app
```

タイトルが両方とも「同名.txt」の窓AとBが開く。本文内のA/B表示で見分けられる。

Aの文を選択し、その外付けバーから「編集 → コピー」。別の場所に貼り付けてAの内容であることを確認する。Bでも繰り返す。その後、Aの外付けメニューから「ファイル → 検証保存」、次にBで実施する。

```bash
cat "$HOME/Library/Application Support/TransomLab/events.log"
```

ログに `SAVE window=A`、`SAVE window=B` と対象窓番号が記録される。保存データは同フォルダのA.txt/B.txtだけ。通常の個人文書を試験に使わない。

「検証用シートを開く」で、その親窓のバーが消えて操作できなくなるか確認する。メニューを開いたまま別窓へ切り替えた場合、閉じた場合、名前が変わった場合、操作が拒否されることも確認する。

## 5. 最優先で調査する場所

|症状|最初に見るコード|
|---|---|
|ビルドできない|最初のSDK/Swiftエラー。MainActor境界、AXのCFブリッジ、NSPanel/NSMenuのimport差を確認|
|ID取得がfalse|TransomBridge.c。_AXUIElementGetWindowの解決元と対象OSでの存在|
|追跡数は増えるが表示が0|画面上端・サイズの対象外条件、透明バーのCG一覧への掲載、WindowServer.orderとOrderingPolicy|
|バーが他窓の前に浮く|SkyLight ABI、sublevel、AppKitの管理状態、相対order。入力を有効にして誤魔化さない|
|メニューを選んでも動かない|NSMenu前後のfrontmost PID/AXFocusedWindow/AXFocusedUIElementの変化。参照の厳密比較がどこで不一致か|
|メニューが空／無効|AX公開範囲・遅延生成・元アプリの有効化タイミング。予算超過と本当の非対応を区別|
|Spaces/Mission Controlで残る|AppController.transitionと表示投影方式。現行コードは完全なアニメーション追従ではない|
|CPU・ラグが大きい|メタデータ照合周期、AXメッセージ数、1プロセスに多数窓がある場合の取得順|

詳細な調査ログを追加する場合でも、文書名・URL・選択文字列をデフォルトで出さない。LabのA/B識別子で再現する。

## 6. 作業を終える条件

`ACCEPTANCE.md` のP0項目をすべて実施し、OS・CPU・Xcode・Swift版と結果を記録する。コンパイルだけ成功した場合は「ビルド確認済み」、GUI操作まで行った場合だけその項目を「実機確認済み」とする。CIファイルは同梱しているが、この環境から実行した事実はない。

引き継ぎ用プロンプト例：

> このリポジトリのAGENTS.mdとdocs/HANDOFF.md、REVIEW.md、VALIDATION.mdを読んでください。まずMac上でscripts/verify.shを実行してSDK/型エラーを修正し、次にTransomLabで同名2窓のメニュー操作を検証してください。Mac本来の操作部への重ね描き、IDの推定、AXPressの自動再試行は禁止です。未検証を確認済みと扱わず、実行した結果だけを記録してください。
