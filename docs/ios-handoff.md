# 次の端末での引き継ぎ

## 決まっていること

- 担当はiOSアプリと、そのためのデータ保存・読み取り。首輪の電子工作は担当外。
- 首輪→親機→API→iOSを想定。親機からの送信形式は未決定で、`docs/data-contract.md` を提案として作成。
- 第一段階は優先一覧、最新位置、日付別の経路、活動量、通信・測定の欠落表示。
- プッシュ通知、確認済み操作、観察メモは不要。
- 病名の判定は行わず、行動量の低下や長時間の動きの少なさを「要確認」とする。
- 11月28日の実演期限は前提にしない。

## 現在の実装状態

- `apps/mobile/Cowlog.swiftpm` にSwiftUI画面とサンプルデータ、HTTPS APIクライアントを作成。
- `apps/api/app.py` にSQLite保存、重複排除、優先判定、読み取りAPIを作成。
- `apps/api/seed_demo.py` はサンプル専用DBを作る。実データDBと混ぜない。
- Pythonの単体・HTTPテスト8件がWindows上で成功。Swiftソースは構文解析済み。
- iOSアプリはWindows上でビルドできず、Xcode/Swift Playgroundsでのコンパイル確認が未実施。
- クラウド上のAPI環境・実際の首輪データ接続は未実施。

## 次にすること

1. Macにこのリポジトリをcloneし、Xcodeで `apps/mobile/Cowlog.swiftpm/Package.swift` を開いてビルドする。iPadではSwift Playgroundsで `Cowlog.swiftpm` を開く。
2. サンプルデータでのビルド・表示を確認し、必要な修正を行う。iPhoneからは作業内容の確認・指示ができ、ビルドにはMacまたはiPadを使う。
3. サンプルデータで一覧・地図・経路・グラフを確認する。
4. ハード担当と `docs/data-contract.md` の項目をすり合わせる。
5. クラウドの配置先と利用者ごとの認証方式を決め、実データでつなぐ。

現在のソースはまだ配布可能な完成版ではありません。Mac/iPadでのビルドと実データでの動作確認が必要です。
