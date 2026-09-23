# iOSアプリ

`Cowlog.swiftpm` がSwiftUIのアプリ本体です。MacではXcodeで `Cowlog.swiftpm/Package.swift` を開き、iOSシミュレータまたは実機向けにビルドします。iPadではSwift Playgroundsで開けます。

初期設定はサンプルモードです。優先一覧・最新位置の地図・日別経路・活動量を試せます。実データにはHTTPSのAPI URLと閲覧用トークンを接続設定画面に入力します。トークンは端末のKeychainに保存します。

WindowsではSwiftソースの構文確認まで実施済みで、Xcodeでのコンパイルと実機での操作確認はこれからです。
