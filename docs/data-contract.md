# Cowlogサーバー API データ契約（2026-10-28）

現行の経路は **首輪 → AWS → アプリ**。以下はAWS側で提供する受信・読み取りAPIの境界と、ローカル参考実装の契約。親機やLoRaは必須としない。首輪のAWS接続、AWSへの配置、DBサービスの選定は未完了。

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
| `device_id` | 首輪の固定ID。牛との対応はサーバーDBの装着期間で管理 |
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

## 2026-10-19 拡張

- `hdop`（0〜100、単位なし）、`satellites`（0〜200）を任意で受信・保存。
- 精度が分からないときは `gps_accuracy_m: null`。HDOPをmとして送らない。
- GNSSのみの段階は `activity_seconds: 0, coverage_seconds: 0`。加速度を測定したように扱わない。
- 首輪と牛の対応は装着開始・終了時刻で判定する。送信時刻や到着時刻ではなく `measured_at` で振り分ける。
- ダッシュボードに `profile.herd_number`、`profile.individual_number` を追加。番号は文字列。未装着の `device_id` はnull。
- 受信可能な首輪数・牛数は8頭に固定しない。デモの8頭は画面確認用。

## 番号管理（2026-10-28）

個体台帳のUIは廃止。番号だけを表示・検索する。ダッシュボードは `number` を文字列で返す。旧 `profile` は互換用で、画面には表示しない。

- `GET /v1/collars`、閲覧権限。`{"collars":[{"device_id":"collar-01","number":null,"last_seen_at":"2026-10-28T00:00:00Z"}]}`。
- `PUT /v1/collars/{device_id}/number`、閲覧・送信とは別の番号管理権限。本文 `{"number":"0007","expected_number":null}`。
- 変更の場合 `expected_number` は現在画面にある番号。省略不可。不一致・重複409。再送で既に同じ番号になっていれば200。
- 番号は半角数字1〜12桁。先頭0を保持。`7` と `0007` は別番号。
- 応答 `{"device_id":"collar-01","number":"0007","saved_to":"server"}`。
- 番号未設定の新規首輪は首輪一覧で採番してから優先一覧・地図に加わる。データ受信前の任意ID新規作成画面は設けない。
- 保存先はサーバーの対応表。首輪本体に送信・書き込み・受領確認するAPIではない。
- 番号を変更しても内部の履歴IDを維持。別の牛へ装着しても、アプリでは牛の交代として履歴分割しない。旧個体管理用CLIは互換用に残す。
- SQL実装では未装着の旧登録に残る番号も重複チェック対象。番号の削除・解放・首輪削除・付け替え専用画面は未実装。


## 表示アイコン（2026-11-09）

ダッシュボードの牛と `GET /v1/collars` の各項目に `cow_style` を返す。`unknown`（未設定）/ `holstein`（白黒）/ `brown`（茶色）の表示用メタデータで、品種の推定結果ではない。

`PUT /v1/collars/{device_id}/number` に任意の `cow_style` と取得時点の `expected_style` を追加できる。指定する場合は両方とも上記のいずれか。成功応答にも保存した `cow_style` を返す。他端末が先に変更していれば409。旧クライアントが両方省略した場合は既存の見た目を維持する。首輪本体への送信はしない。


## 手動首輪登録（2026-11-09）

`POST /v1/collars`、管理用Bearer。本文は `{"device_id":"collar-ABC123","number":"0007","cow_style":"brown"}`。新規登録201、既に同じ内容で登録されている場合200、IDや番号の競合409、入力不正400。応答に `saved_to: "server"` と `created` を含める。登録だけでは測定を作らず「未受信」。機器のネットワーク接続やAWS証明書のプロビジョニングは行わない。

AWS版は `infra/aws/README.md` に記載。先に登録したIDだけから測定を受け付けるHTTPS試作であり、未登録首輪を測定だけで自動発見する旧SQLite方式とは異なる。
