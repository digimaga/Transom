# Contributing / 開発参加・不具合報告

[English](#english) | [日本語](#日本語)

## English

### Bug reports

Use [GitHub Issues](https://github.com/digimaga/Transom/issues) for reproducible bugs or compatibility reports. Japanese and English are both welcome. Include:

- macOS version, Apple Silicon or Intel, and the affected app's name/version.
- Transom commit or build date, plus the Swift/Xcode version if the problem is a build failure.
- Minimal steps using a disposable test document, expected behavior, and actual behavior.
- Whether the original macOS menu/control works, and whether the issue occurs with one or multiple windows/displays.
- If useful, **TR → Copy Diagnostics (No Document Names)** and the first relevant error.

Review anything you attach. Remove document contents, names, paths, email addresses, credentials, and unrelated windows from logs or screenshots. Do not post credentials or private documents in an issue, including when reporting a security concern. TransomLab can reproduce window/menu behavior without using personal documents.

### Code changes

Read [AGENTS.md](AGENTS.md), [the architecture](docs/ARCHITECTURE.md), [handoff](docs/HANDOFF.md), [review notes](docs/REVIEW.md), [validation records](docs/VALIDATION.md), and [acceptance checklist](docs/ACCEPTANCE.md). Keep changes focused and preserve the project's safety rules:

- Do not cover the original controls or content when external space is unavailable.
- Require exact window identity, process/window generations, and target/context validation. Do not guess by title or geometry.
- Keep synchronous Accessibility work on each app's serial worker queue. Send each AXPress through `OperationPermit` once; never retry an uncertain operation automatically.
- Keep private APIs inside `TransomBridge`. Do not add document titles, URLs, menu labels, or selected text to logs.

For behavior or architecture changes, describe the problem, scope, and validation plan before a large implementation. Keep the English and Japanese READMEs consistent when changing user-facing behavior.

On macOS, run `bash scripts/verify.sh`, then `bash scripts/build-app.sh` and `bash scripts/build-app.sh --lab`. For relevant GUI changes, follow the acceptance checklist using test data. Record actual results and the OS, CPU, Swift/Xcode versions in `docs/VALIDATION.md`; explicitly mark anything not tested. A successful build or unit test is not a GUI acceptance result.

For documentation-only changes, check links, commands, consistency with the implementation, and `git diff --check`. Do not claim new runtime verification from a documentation edit.

A pull request should explain the problem, resulting behavior, checks performed, and remaining limitations. Do not commit build output, signing material, personal diagnostics, or unrelated changes. The project is licensed under [MIT](LICENSE); preserve notices and document the source/license of any third-party material you introduce.

## 日本語

### 不具合報告

再現できる不具合や互換性の報告には[GitHub Issues](https://github.com/digimaga/Transom/issues)を利用してください。日本語・英語のどちらでも構いません。以下を添えてください。

- macOSのバージョン、Apple Silicon／Intel、対象アプリの名前とバージョン。
- Transomのcommitまたはビルド日。ビルド失敗ならSwift／Xcodeのバージョン。
- 使い捨てのテスト文書での最小限の再現手順、期待した動作、実際の動作。
- Mac本来のメニュー・ボタンで操作できるか、単一／複数ウィンドウ・ディスプレイのどちらで起きるか。
- 必要に応じて **TR → 診断情報をコピー（文書名を含まない）** の結果と、最初の関連エラー。

添付する内容を確認し、ログやスクリーンショットから文書の本文・名前・パス、メールアドレス、認証情報、無関係な窓を取り除いてください。セキュリティ上の問題を報告する場合も、認証情報や非公開の文書をIssueへ投稿しないでください。窓やメニューの再現には、個人文書を使わずに済むTransomLabを利用できます。

### コードの変更

[AGENTS.md](AGENTS.md)、[アーキテクチャ](docs/ARCHITECTURE.md)、[引き継ぎ](docs/HANDOFF.md)、[レビュー記録](docs/REVIEW.md)、[検証記録](docs/VALIDATION.md)、[受入チェックリスト](docs/ACCEPTANCE.md)を読んでください。変更の目的を絞り、以下の安全条件を維持します。

- 外付けの空間がなければ、元の操作部や本文に重ねない。
- 正確なウィンドウID、プロセス・窓の世代、対象と文脈の照合を維持する。タイトルや位置・サイズから推定しない。
- 同期アクセシビリティ処理はアプリごとのシリアルワーカーキュー内に置く。AXPressは`OperationPermit`経由で1回だけ送り、応答不明時に自動再試行しない。
- 非公開APIは`TransomBridge`に限定する。文書名・URL・メニューラベル・選択文字列をログへ追加しない。

挙動・設計の変更では、大きな実装を始める前に問題、影響範囲、検証方法を説明してください。利用者向けの動作を変えた場合は、英語・日本語READMEの内容を揃えます。

macOSで `bash scripts/verify.sh`、続いて `bash scripts/build-app.sh` と `bash scripts/build-app.sh --lab` を実行します。関連するGUI変更はテストデータで受入チェックリストを実施します。実際の結果とOS・CPU・Swift／Xcodeのバージョンを `docs/VALIDATION.md` に記録し、未実施の項目は明記してください。ビルドや単体テストの成功をGUI受入の成功として扱わないでください。

文書だけの変更では、リンク、コマンド、実装との整合性、`git diff --check`を確認します。文書の更新を、新しい実機検証として記載しないでください。

Pull requestには、問題、変更後の動作、実施した検証、残る制限を記載してください。ビルド成果物、署名用の情報、個人の診断ログ、無関係な変更をcommitに含めないでください。ライセンスは[MIT](LICENSE)です。第三者の素材を導入する場合は必要な表示を維持し、出典とライセンスを記録してください。
