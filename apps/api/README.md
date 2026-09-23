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
