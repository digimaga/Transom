# API・先行実装の参照

確認日：2026-09-10。以下は設計・APIの確認先であり、このプロジェクトを実機検証した根拠ではない。コードはこのプロジェクト向けに記述したもので、JankyBorders/Hammerspoonのソース全体や実装関数をコピーして組み込んではいない。両プロジェクトは実行依存にもしていない。

## Appleの公開API

- AXUIElementSetMessagingTimeout — 各IPCのタイムアウトを指定するAPI。
  https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout
- AXUIElementPerformAction — AXオブジェクトにアクションを要求するAPI。
  https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction
- NSPanel.becomesKeyOnlyIfNeeded — パネルのキーウィンドウ化に関する機構。
  https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded
- NSMenu.popUp(positioning:at:in:) — 指定位置での標準ポップアップ表示。
  https://developer.apple.com/documentation/appkit/nsmenu/popup(positioning:at:in:)

## 実装上の参考

- JankyBorders：別ウィンドウで装飾を表示し、対象のレベル・sublevel・相対orderを調整する例。
  https://github.com/FelixKratz/JankyBorders
  https://raw.githubusercontent.com/FelixKratz/JankyBorders/main/src/misc/extern.h
  https://raw.githubusercontent.com/FelixKratz/JankyBorders/main/src/border.c
  WindowBarBridgeの任意のSkyLight関数について、関数名・ABI宣言を確認する際に参照した。非公開関数の存在と宣言はAppleの互換性保証ではない。
- Hammerspoon：AXのメニューツリー、チェック状態・ショートカット属性、AXPressによる実行の例。
  https://raw.githubusercontent.com/Hammerspoon/hammerspoon/master/extensions/application/libapplication.m
- Menuwhere：独自のメニュー表示と選択・フォーカスに依存した項目の有効状態の干渉が、実用品でも課題になった例。
  https://manytricks.com/menuwhere/releasenotes/

作成時に利用したソースを将来そのまま引用・取り込みする場合は、その時点のライセンスと必要な表示を別途確認する。参照したという理由だけでそれらの著作権表示をこの独自コードの著作権表示へ置き換えない。
