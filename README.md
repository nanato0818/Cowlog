# Cowlog

牛の首輪から届く位置・活動データを保存し、確認を優先したい牛をiOSで表示する試作プロジェクトです。現時点ではサンプルデータで画面を確認できます。実機・クラウドとの接続は今後の作業です。

## 構成

| 場所 | 内容 |
| --- | --- |
| `apps/mobile/Cowlog.swiftpm/` | iOS 17以降向けSwiftUIアプリ。優先一覧、地図、日別経路、活動量、接続設定 |
| `apps/api/` | Python 3.11以降・SQLiteの試作API。データ保存、重複排除、優先判定 |
| `firmware/collar/` | 既存のXIAO ESP32-S3とGNSSの検証コード |
| `firmware/gateway/` | 親機の作業場所 |
| `hardware/` | 電子回路・筐体関連 |
| `docs/` | [構成](docs/architecture.md)、[データ仕様案](docs/data-contract.md)、[Macでの引き継ぎ](docs/ios-handoff.md) |

## Macでアプリを開く

1. `git clone https://github.com/nanato0818/Cowlog.git` で取得します。
2. MacのXcodeで `apps/mobile/Cowlog.swiftpm/Package.swift` を開きます。iPadではSwift Playgroundsで `Cowlog.swiftpm` を開けます。
3. 初回はアプリ内のサンプルデータで画面を確認します。実際のデータを読むにはHTTPSのAPI公開先と閲覧用トークンが必要です。

このコードはWindowsで作成したため、Xcodeでのビルド・実機動作はまだ確認できていません。Macで最初にビルドし、問題があれば修正します。

APIの起動方法は [apps/api/README.md](apps/api/README.md) を参照してください。APIは初期状態でローカルホストにだけバインドします。iPhoneからの実データ接続にはHTTPSで公開できる配置先を別途決めます。
