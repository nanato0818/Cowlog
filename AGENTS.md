# Cowlog（Codex 向け）

作業を始める前に `docs/HANDOFF.md` を読んでください。Codex と Claude Code で共通の引き継ぎ文書です。ルール、直近の作業、次にやること、作業を終えるときの更新手順が書いてあります。

作業リポジトリ：https://github.com/Hiiragi102/Cowlog （ローカルの `origin`、`main`）。旧 nanato0818/Cowlog（リモート名 `nanato`）には push しない。

要点：
- Gitのコミット・push・ブランチ操作は利用者が頼んだときだけ。未コミットの変更を消さない
- 画面にロゴ・説明文を出さない。コンセプト色は `#D9473D`
- データ処理（`lib/state/`、`lib/services/`、`lib/models.dart`、`lib/activity_summary.dart`、`apps/api/`）は頼まれない限り変えない
- 終わったら `apps/mobile/cowlog_flutter` で `flutter analyze` と `flutter test` を通す
- 作業を終える前に `docs/HANDOFF.md` の作業ログと「次にやること」を更新する（途中で終わる場合は中断中の作業として残す）
- 利用者とのやりとりは日本語
