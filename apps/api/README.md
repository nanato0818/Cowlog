# 2026-11-09 追加

SQLite版に `POST /v1/collars` による管理用の手動首輪登録を追加しました。AWS用のDynamoDBバックエンド・SAMテンプレートと検証手順は [AWS版](../../infra/aws/README.md) を参照してください。SQLite HTTPサーバー自体は引き続き標準ライブラリのみで動きます。AWS版には別途boto3が必要です。

# Cowlog 試作API

Python 3.11以降の標準ライブラリだけで動きます。SQLiteへ測定記録を保存し、重複排除、牛の優先判定、アプリ用データの取得を行います。

## ローカルで確認

`apps/api` に移動して、次を実行します。

```sh
python3 app.py init --db cowlog.sqlite3
python3 app.py add-cow --db cowlog.sqlite3 --id cow-01 --name "牛1" --device collar-01
export COWLOG_READ_TOKEN='閲覧用の長いランダム文字列'
export COWLOG_INGEST_TOKEN='送信用の別の長いランダム文字列'
python3 app.py serve --db cowlog.sqlite3
```

サンプルDBが必要なら `python3 seed_demo.py --db demo.sqlite3` で作れます。`python3 -m unittest -q test_app.py` でテストを実行できます。DBファイルとトークンはGitに含めません。

初期状態では `127.0.0.1:8080` で待ち受けます。iOSアプリはHTTPSのみ受け付けるため、端末から接続する際はTLSを持つ配置先が必要です。認証は試作用の固定トークンで、実運用時には利用者ごとの認証、鍵管理、バックアップ、運用監視を追加します。

送信と読み取りのJSON形式は [データ仕様案](../../docs/data-contract.md)を参照してください。

## 個体番号と首輪の付け替え

牛の `--id` は不変の内部IDです。`--herd-number` と `--individual-number` は任意の文字列で、先頭の0を保持します。

```sh
python3 app.py add-cow --db cowlog.sqlite3 --id cow-uuid-A --name '牛 A-0007' --herd-number 'A-0007' --individual-number '0012345678' --device collar-01 --effective-at 2026-10-19T00:00:00Z
```

同じ内部IDで番号・名前を変更できます。首輪を維持する際は同じ `--device` を指定してください。省略すると未装着です。別の牛へ同じ首輪を割り当てると、指定時刻で付け替わります。時刻省略時は実行時刻です。過去の記録は測定時点の牛に属し、遅延受信でも混ざりません。未来の予約と履歴の逆転は拒否します。

旧DBは `init` または `serve` 起動時に移行します。実データ更新前にはバックアップしてください。旧登録の開始時刻は不明なので、従来の対応を過去全体へ適用して移行します。`python3 -m unittest discover -s apps/api -q` をリポジトリルートから実行すると移行・付け替え・USBブリッジとのHTTP結合試験も走ります。

## 2026-10-28 現行の番号管理

通常のアプリ操作では牛のプロフィール登録や付け替え管理はしません。上の `add-cow` は旧データと開発用の互換コマンドです。現在は首輪の固定IDに表示番号を割り当て、番号変更時も同じ内部ID・履歴を維持します。

`COWLOG_MANAGE_TOKEN` をサーバーに設定すると番号変更APIが利用できます。閲覧用・送信用・番号管理用には異なる値が必要です。管理用を設定しなければ番号変更は拒否します。

- `GET /v1/collars`（閲覧トークン）: 受信済みまたは旧登録済みの固定ID、番号、最新測定時刻。未採番の首輪も返す。
- `PUT /v1/collars/{device_id}/number`（番号管理トークン）: `{"number":"0007","expected_number":null}`。既存番号を変更する場合は `expected_number` に画面で取得した旧番号を指定。
- 半角数字1〜12桁。重複・他端末の変更は409、不正入力400、未知の固定ID404、権限なし401。
- 初回採番時は、その固定IDで既に受信した記録を引き継ぐ。履歴は測定日の日本時間で取得。
- 成功時 `{"device_id":"...","number":"0007","saved_to":"server"}`。これはサーバー保存の確認であり、首輪の設定受領確認ではない。
- `7` と `0007` は異なる文字列。旧CLIで設定された英字入り番号は読めるが、アプリから新たに保存する番号は数字のみ。

このコードはPython HTTPサーバー＋SQLiteのローカル参考実装です。AWS向けのリソース作成・デプロイは含みません。首輪→AWS間の通信、DB、認証方式を決め、同じAPI契約をAWS側に実装・配置する必要があります。
