# 親機 → アプリ側API データ仕様案 v0.1

ハード側の実装方法は自由です。親機がインターネットへ接続できる時に、測定記録をHTTPSでまとめて送る境界だけ決めます。圏外中の首輪・親機での保持、LoRaのACK、中継器はハード側の設計事項です。

## 送信

`POST /v1/measurements`、ヘッダー `Authorization: Bearer <送信用トークン>`、本文はJSON。1回に1〜100件を送れます。

```json
{
  "records": [
    {
      "device_id": "collar-01",
      "stream_id": 7,
      "seq": 123,
      "measured_at": "2026-09-24T03:15:00Z",
      "received_at": "2026-09-24T03:15:09Z",
      "latitude": 35.0,
      "longitude": 139.0,
      "gps_accuracy_m": 15.0,
      "activity_seconds": 240,
      "coverage_seconds": 880,
      "interval_seconds": 900,
      "battery_percent": 76
    }
  ]
}
```

| 項目 | 意味 |
|---|---|
| `device_id` | 首輪の固定ID。牛との対応はアプリ側DBで管理 |
| `stream_id` | 通し番号を初期化したときに変える番号。通常は維持 |
| `seq` | 記録ごとに増える番号。再送時も同じ番号 |
| `measured_at` | 測定時刻、UTC、タイムゾーン必須 |
| `received_at` | 親機が受けた時刻。省略可 |
| `latitude` / `longitude` | GPSが無い回は両方 `null` または省略 |
| `gps_accuracy_m` | 精度の目安。提供できなければ省略可 |
| `activity_seconds` | その区間で「動きあり」と集計した秒数 |
| `coverage_seconds` | 加速度を実際に測れた秒数 |
| `interval_seconds` | 集計区間の秒数。最初は900秒を想定 |
| `battery_percent` | 残量%。得られなければ省略可 |

`activity_seconds <= coverage_seconds <= interval_seconds` とします。活動の定義やセンサーの閾値はハード担当との調整事項です。加速度の生波形はこのAPIへ送りません。時刻の出所と測位品質の詳細は今後の拡張項目です。

同じ `(device_id, stream_id, seq)` を再送してもDBは重複登録しません。成功時は `{"accepted":1,"duplicates":0}` のように返します。親機は送信失敗時に再試行できます。

## アプリ読み取り

- `GET /v1/dashboard`: 牛の優先一覧、理由、最新測定、最後の測位点
- `GET /v1/cows/{cow_id}/history?date=YYYY-MM-DD`: 指定日（日本時間）の経路点と活動値

読み取りには送信用とは別の閲覧用トークンを使います。APIには牛IDと首輪IDの対応登録が必要です。初版は管理コマンドで登録し、アプリでの編集画面は作りません。
