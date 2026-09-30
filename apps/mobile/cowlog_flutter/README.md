# Cowlog Flutter アプリ

Cowlogの優先確認・地図・活動履歴をiOSとAndroidの両方で使うためのFlutter版アプリです。従来のSwiftUI試作版は`../Cowlog.swiftpm/`に残してあります。

## 起動

```bash
cd apps/mobile/cowlog_flutter
flutter pub get
flutter run
```

接続したい端末を選んで実行します。iOSで動かす場合は、Macに対応したXcodeとiOS Simulatorまたは実機が必要です。

## できること

- 注意が必要な牛を優先順に表示
- 最新のGNSS位置を地図に表示
- 牛ごとの日別経路、活動量、概算移動距離を確認
- HTTPS APIと閲覧用トークンを使った実データ接続
- サンプルモードでの画面・操作確認

地図はOpenStreetMapを利用します。実データのAPI形式は[データ仕様案](../../../docs/data-contract.md)に合わせています。

## 実データを接続する

アプリの「接続設定」で、HTTPSのAPI URLと閲覧用トークンを入力します。トークンは端末の安全な領域に保存され、APIのURLは端末設定に保存されます。

想定するエンドポイントは次のとおりです。

- `GET /v1/dashboard`
- `GET /v1/cows/:id/history?date=YYYY-MM-DD`
