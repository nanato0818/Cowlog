# Cowlog AWS HTTPSバックエンド

2026-11-09作成。DynamoDB + Lambda + API Gateway HTTP API用の実装とSAMテンプレートです。AWSリソースの作成・配置はまだ実施していません。

## 実装したこと

- 送信用・閲覧用・管理用を分離した認証。Secrets Managerに別々のランダムな資格情報を作るテンプレート。
- 首輪ID・番号・牛アイコンの手動登録。既存ID・番号の競合防止、同じ内容の登録の再試行に対応。
- 番号とアイコンの変更。番号予約とメタデータの変更をDynamoDBトランザクションで一体化。
- 測定記録を受け付け、時刻・座標・活動秒数などを検査して保存。
- 同じ固定ID・系列ID・通し番号の再送を重複保存しない。同じIDで異なる内容なら409。
- 遅れて届いた古いGPSで最新位置を上書きしない。履歴保存後のキャッシュ更新に失敗しても、再送で修復する。
- 一覧・日本時間の日別履歴・首輪一覧・牧場GeoJSONの読み取り。DynamoDB Queryのページ分割を最後まで読む。
- 位置なし／活動未測定／電池不明は不明のまま返し、架空データへ切り替えない。
- AWSの内部エラーは503。要求本文・認証ヘッダーをログへ出さない。

## 構成とDB

```text
首輪 --HTTPS--> API Gateway --> Lambda --> DynamoDB
アプリ <--HTTPS API--> 同じLambda
```

この版はHTTPSを使う単一牧場向けの試作です。MQTT／IoT Core、実際の首輪ファームウェアのAWS通信は未実装です。

| テーブル | キー | 内容 |
|---|---|---|
| Registry | pk=FARM#牧場ID、sk=COLLAR#固定ID／NUMBER#番号／LIMITS | 首輪、表示番号、アイコン、最新測定と最新有効位置のキャッシュ、番号予約、登録件数 |
| Measurements | device_id=牧場＋首輪、record_key=T#UTC時刻#系列ID#通し番号 または D#系列ID#通し番号 | 時系列履歴と重複判定用の小さな項目 |
| Areas | farm_id=牧場ID、area_id=BOUNDARIES | 5区画のGeoJSON文書と版ハッシュ |

以前の案にあった時刻用GSIは使っていません。時系列用のソートキーと、重複防止用の別項目を一緒に保存し、GSIの反映待ちに依存せず日付で検索できる形にしました。

## API

| メソッド・パス | 権限 | 結果 |
|---|---|---|
| POST /v1/collars | 管理 | 首輪ID・番号・アイコンの登録。新規201、同内容の再試行200 |
| PUT /v1/collars/{device_id}/number | 管理 | 番号・アイコン更新 |
| POST /v1/measurements | 送信 | 1〜100件の測定を保存 |
| GET /v1/collars | 閲覧 | 首輪一覧 |
| GET /v1/dashboard | 閲覧 | アプリ用の一覧 |
| GET /v1/cows/{id}/history?date=YYYY-MM-DD | 閲覧 | 日本時間の日別履歴 |
| GET /v1/farm/areas | 閲覧 | 取り込み済みの牧場区画 |

すべて `Authorization: Bearer ...`。アプリへ送信用資格情報を入れません。登録例は `{"device_id":"collar-ABC123","number":"0007","cow_style":"brown"}`。固定IDは半角英数字で始まり、英数字・`_ . : -` の1〜64文字。番号は半角数字1〜12桁。アイコンは `unknown`／`holstein`／`brown`。

**DBに首輪IDを登録することと、実物の首輪をAWSへ接続することは別です。** 登録した直後は未受信です。AWS版では、測定を受け付ける前に登録が必要です。

測定形式は `docs/data-contract.md` と既存 `apps/api/app.py` の検査関数を共用しています。番号が変わっても固定IDに紐づくAWS履歴は維持します。既存SQLiteの内部ID・装着履歴をDynamoDBへ自動移行するツールは含みません。

## ローカル検証

リポジトリルートで実行します。テストはMotoの模擬DynamoDBを使い、実際のAWSに書き込みません。

```sh
python3.12 -m venv .venv
.venv/bin/pip install -r infra/aws/requirements-dev.txt
.venv/bin/python -m unittest discover -s infra/aws/tests -v
.venv/bin/python -m unittest discover -s apps/api -q
.venv/bin/cfn-lint infra/aws/template.yaml
```

SDKは `apps/api/requirements.txt` で固定しています。デプロイ成果物には `Makefile` で `app.py` と `aws_backend.py` とSDKだけをコピーします。ローカルDB・設定JSON・テストを一括アップロードしません。

今回確認済み：模擬AWSテスト9件、既存APIテスト20件、CloudFormationテンプレート検査、Makefileの成果物作成とimport。SAM CLIによる `sam build`、AWSへの配置、AWS環境のIAM・HTTPS通信は未実行です。

## 配置手順（未実行）

AWS SAM CLIとAWSの認証設定がある環境で、リポジトリルートから以下を実行する想定です。

```sh
sam build --template-file infra/aws/template.yaml
sam deploy --guided --template-file .aws-sam/build/template.yaml --region ap-northeast-1
```

スタック名は例として `cowlog-dev`、FarmIdは `daigo`。テンプレートはDynamoDB3表、Lambda、API Gateway、Secrets Manager3件、ロググループ、実行ロールを作ります。配置後は利用料金が発生するAWSリソースです。現在こちらでは作成していません。

DynamoDBはオンデマンド、ポイントインタイムリカバリ有効。スタック削除時もDBを保持する設定です。データの保存期間は未確定のためTTLによる自動削除は設定していません。

配置後、アプリの接続設定をプライベートファイルへ作成できます。標準出力にトークンは出しません。ファイルは0600で作成し、既存ファイルは上書きしません。

```sh
.venv/bin/python infra/aws/configure_app.py --stack cowlog-dev --output .private/cowlog.json
cd apps/mobile/cowlog_flutter
flutter run --dart-define-from-file=../../../.private/cowlog.json
```

このツールが取得するのは閲覧・管理用だけです。送信用は首輪側の担当が別途取得・設定します。

## 牧場区画の取り込み（未実行）

```sh
.venv/bin/python infra/aws/import_areas.py --stack cowlog-dev --geojson docs/daigo-boundaries.geojson
```

既存文書を置き換える場合だけ `--replace` を指定します。取り込み対象は添付画像から復元した境界で、測量値ではありません。アプリの地図は現在もローカルの5区画を描画します。AWS区画の自動取得・同期はまだ接続していません。

## 残る確認と制約

- 現在は固定Bearer資格情報による試作認証。アプリに埋めた資格情報は取り出せる前提です。一般配布用の利用者認証・端末ごとの失効・首輪ごとの証明書は未実装。
- 資格情報を更新した場合、Secrets Managerの変更だけでLambdaの環境変数は更新されません。`CredentialRevision` を変更して再配置し、アプリ・首輪側の資格情報も更新します。
- 首輪は最大100件を試作上限として登録時に制限。大量の首輪での負荷試験は未実施。一覧は首輪ごとに直近2時間と過去7日の比較時間帯を読みます。増設時には日次集計・一覧キャッシュ等で最適化します。
- 日別履歴の読み取りは最大10,000件。超過時は途中を黙って切らず413を返します。短周期で大量に測る場合は集約・ページ取得APIが必要です。
- 100件の受信本文は全件の入力を先に検査しますが、DB保存は記録単位のトランザクションです。途中の一時障害では503となり、送信側が同じIDで再送する前提です。
- 送信側の再送待ち保存、圏外中の首輪内保存、電池・加速度の実測、首輪本体への番号書き込みは未実装。
- 公開前に実際のIAM、API URL、権限別の通信、実機GPS、障害復旧、使用料金・運用監視を確認する必要があります。

参考：
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html
- https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html
- https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway.html
- https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/building-custom-runtimes.html
