# 2026-11-09 バックエンド更新

地図のCowlog表示を削除し、アプリの首輪追加を実装しました。DynamoDB + Lambda + API GatewayのHTTPSバックエンドと配置設定を追加。AWSへの配置・実機接続は未実施です。[AWSバックエンドの手順](infra/aws/README.md)を参照してください。

# Cowlog 現行仕様の案内（2026-10-28）

現在の改修対象はFlutter版です。首輪 → AWS → アプリの経路を前提に、個体台帳を廃止し、番号表示・番号設定を実装しました。AWS接続・配置と首輪本体への番号書き込みは未実施です。

[現行仕様](docs/current-spec.md) / [構成](docs/architecture.md) / [Flutter起動](apps/mobile/cowlog_flutter/README.md)

以下には初期試作の記録が含まれます。現在の仕様は上記を優先してください。

# Cowlog

牛の首輪から届く位置・活動データを保存し、確認を優先したい牛をiOSで表示する試作プロジェクトです。現時点ではサンプルデータで画面を確認できます。実機・クラウドとの接続は今後の作業です。

## 構成

| 場所 | 内容 |
| --- | --- |
| `apps/mobile/cowlog_flutter/` | iOS・Android向けFlutterアプリ。優先一覧、地図、日別経路、活動量、接続設定 |
| `apps/mobile/Cowlog.swiftpm/` | Flutter移行前のiOS 17以降向けSwiftUI試作版 |
| `apps/api/` | Python 3.11以降・SQLiteの試作API。データ保存、重複排除、優先判定 |
| `firmware/collar/` | 既存のXIAO ESP32-S3とGNSSの検証コード |
| `firmware/gateway/` | 親機の作業場所 |
| `hardware/` | 電子回路・筐体関連 |
| `docs/` | [構成](docs/architecture.md)、[データ仕様案](docs/data-contract.md)、[Macでの引き継ぎ](docs/ios-handoff.md) |

## Flutterアプリを起動する

1. `git clone https://github.com/nanato0818/Cowlog.git` で取得します。
2. `apps/mobile/cowlog_flutter/` で `flutter pub get`、続けて `flutter run` を実行します。
3. 初回はアプリ内のサンプルデータで画面を確認します。実際のデータを読むにはHTTPSのAPI公開先と閲覧用トークンが必要です。

詳細は[Flutter版のREADME](apps/mobile/cowlog_flutter/README.md)を参照してください。以前のSwiftUI版は `apps/mobile/Cowlog.swiftpm/` に残してあります。

APIの起動方法は [apps/api/README.md](apps/api/README.md) を参照してください。APIは初期状態でローカルホストにだけバインドします。iPhoneからの実データ接続にはHTTPSで公開できる配置先を別途決めます。
