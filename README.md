# Cowlog

牛の首輪型デバイスとアプリで、位置情報・活動量・観察記録を扱うプロジェクトです。

## 構成

```text
Cowlog/
├── apps/mobile/              Flutterアプリ
├── firmware/collar/          首輪側：GNSS、加速度、LoRa送信
├── firmware/gateway/         親機側：LoRa受信、PC・サーバー連携
├── hardware/electronics/     回路図、配線図、部品表
├── hardware/enclosure/       首輪ケースの3Dデータ
└── docs/test-results/        実験結果と写真
```

## 現在の状態

- XIAO ESP32-S3とL76K GNSSで位置を取得する検証コードを配置済み
- LoRa通信は首輪側と親機側を別々のPlatformIOプロジェクトとして追加する
- Flutterアプリは `apps/mobile/` に作成する

詳細は [システム構成](docs/architecture.md) を参照してください。
