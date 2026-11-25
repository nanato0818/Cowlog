# 親機・USB試験用ブリッジ

LoRa受信ファームウェアは未実装です。`serial_bridge.py` はUSB試験用で、首輪の1行JSONを読み、SQLite送信待ちキューへ保存してからHTTPS APIに送信します。Wi-Fi/LoRaの首輪送信機能を実装したという意味ではありません。

```sh
# 使用するPython環境にpyserialを用意する（USB入力の場合のみ）。
# COWLOG_API_URL=https://your-api.example と COWLOG_INGEST_TOKEN は環境変数で設定。
python3 serial_bridge.py --port /dev/cu.usbmodemXXXX --outbox cowlog-outbox.sqlite3
```

`--input records.jsonl` または `--input -` で再生入力も可能。送信失敗時は保存し、再起動後も再送します。サーバー受理または重複の確認後に削除します。400応答等の不正データはキューに残るため、運用時には隔離と監視を追加してください。USB未接続中の首輪内保存は未実装です。

首輪側の `cowlog_usb_telemetry` 環境をPlatformIOでビルド・書き込みすると、GNSSが有効な場合に約15秒ごとにJSONが出ます。固定IDはMAC由来、時刻はUTC。HDOPはメートル精度に変換せず、加速度未接続時はcoverage=0です。`python3 -m unittest -q test_serial_bridge.py` でキューの再送試験を実行できます。
