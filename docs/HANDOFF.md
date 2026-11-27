# Cowlog 作業の引き継ぎ（Codex・Claude 共通）

この文書は、Codex と Claude Code のどちらでこのフォルダを開いても、前回中断したところから同じように作業を再開するための共通メモです。**作業を始める前に必ず読み、作業を終える前に必ず更新してください。**

- 最終更新：2026-11-27（Claude）
- 対象フォルダ：`/Users/murakami/Desktop/Cowlog-Flutter`
- 作業リポジトリ：**https://github.com/Hiiragi102/Cowlog**（非公開、`main`）。ローカルの `origin` はここ。旧リポジトリ nanato0818/Cowlog は `nanato` という名前のリモートとして残している（push しない）

## 1. 再開するときに読む順番

1. この文書（`docs/HANDOFF.md`）：ルール、直近の作業、次にやること
2. `docs/current-state-2026-11-11.md`：画面仕様・配色・ファイル構成・検証結果の詳細。**見た目の仕様はこれが最新**
3. 必要に応じて：`docs/current-spec.md`（状態判定・API・番号ルール。配色・ナビの記述は古い）、`infra/aws/README.md`（AWS）、`tools/gps-debug/README.md`（GPSデバッグサイト）

## 2. 守るルール

### 作業の進め方
- **Gitのコミット・push・ブランチ操作は、利用者が明示的に頼んだときだけ**。push 先は `origin`（Hiiragi102/Cowlog）。`nanato` には push しない。stash・checkout・reset で未コミットの変更を消さない（11/25に11/9以降の変更をまとめてコミット・push 済み）
- 大きな変更の前に、作業フォルダのバックアップ（`apps docs infra firmware tools` の tar.gz）を取る
- 利用者とのやりとりは日本語。報告は「何をしたか → 確認したこと → 確認していないこと」の順で簡潔に
- 終わったら `flutter analyze`・`flutter test`・iOSシミュレーター向けビルドを通し、可能ならシミュレーターで表示を確認する

### デザイン
- 画面にロゴ・説明文・注意書き・大きな装飾を出さない。**見やすさ最優先**
- コンセプト色は `#D9473D`（`AppColors.accent`）。色は `lib/app_theme.dart` の `AppColors` に名前付きで定義し、画面に16進数を直書きしない
- グラフ・移動距離のバーはコンセプト色とその同系色で統一
- 下部ナビはピル型のリキッドグラス。レンズは移動中・押下中に膨らみ、移動中は後ろ側が細く伸びる
- 動きはiPhone標準アプリのような、わずかに弾む滑らかなもの
- 牛の絵は「3DCG風の普通の牛」。画像生成で作った静止画（`assets/models/cow_*.png`）。3Dモデルを組み立てる方式はやめた

### 変えてはいけないもの（頼まれない限り）
- 状態判定・API契約・番号ルール・データ処理：`lib/state/`、`lib/services/`、`lib/models.dart`、`lib/activity_summary.dart`、`apps/api/`
- データ経路は「首輪 → AWS → アプリ」

## 3. よく使うコマンド

```bash
cd /Users/murakami/Desktop/Cowlog-Flutter/apps/mobile/cowlog_flutter
flutter analyze
flutter test
flutter build ios --simulator --debug
```

- シミュレーター：iPhone 18 Pro。ビルド後 `build/ios/iphonesimulator/Runner.app` を起動
- デモモードが既定（架空データ8頭）。実データは `--dart-define=COWLOG_DEMO=false` と `COWLOG_API_URL`・`COWLOG_READ_TOKEN`
- GPSデバッグサイト：`python3 tools/gps-debug/serve.py` → http://127.0.0.1:8790
- 牛の画像の作り直し：`tools/cow-image-prompts.md`（プロンプト）、`tools/prepare_cow_images.py`（透過・大きさ揃え）
- Codex をこのMacで非対話実行する場合：`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex exec -C <このフォルダ> -s workspace-write ...`。Codexのサンドボックスでは iOS ビルドが失敗することがある（SwiftPMキャッシュの書き込み制限）。その場合ビルド確認は Claude 側か手元で行う

## 4. 直近の作業ログ（新しい順）

| 日付 | 担当 | 内容 |
|---|---|---|
| 11/27 | Codex | 刷新版の下部ナビを、画面下の内容が透ける小ぶりなガラスのバーと淡い選択レンズに調整。地図上ではラベルのコントラストを保ち、v2 のレンズの動きも継続。優先一覧の状態フィルターは刷新版で折り返し、通常版で横スクロールの枠内に収める。flutter analyze 指摘なし・flutter test 59件成功。幅320・文字2倍で「データ不足」の表示と選択を確認。iOS シミュレーターは未確認。 |
| 11/27 | Claude | 利用者の指示で、v2＋刷新UIの作業内容をコミットし nanato0818/Cowlog の `main` に push（今回だけの例外）。不要ファイルを削除：Codex依頼メモ `docs/codex-task-2026-11-1*.md`（5つ）・`docs/codex-3d-cow-request.md`、使っていない3D牛モデル `assets/models/*.glb`・`model_manifest.json`・`tools/generate_cow_models.py`・`tools/cow-model-requirements.txt`。削除前バックアップ `~/Desktop/Cowlog-backups/cowlog-20261127-1501-before-cleanup.tar.gz`。analyze 問題なし・test 58件成功。Hiiragi102/Cowlog（origin）には未push |
| 11/27 | Claude | Codexの `Cowlog-v2-refresh-2026-11-27.patch` を `git apply --check` で確認（衝突なし）してから適用。analyze 問題なし・test 58件成功。iPhone 18 Pro で `flutter run --dart-define=COWLOG_UI_REFRESH=true` を実行し、刷新版のホーム（灰色の地・縁取りの白いカード・活動リング・電池・歩行バー・ナビの「設定」タブ）が表示され、起動ログに例外がないことを確認。スイッチやタブ切り替えの操作は未確認。コミット・pushなし |
| 11/27 | Codex | 添付の v2 を土台に刷新 UI と `LiquidSwitch` を統合。両モードで v2 の活動リング、小さな電池表示、歩行ピクトグラム、タブのぼかしとレンズの浮き上がり・後ろ側の伸びを維持。刷新版は `--dart-define=COWLOG_UI_REFRESH=true` で起動し、首輪・番号は歯車の「設定」から管理する。flutter analyze 指摘なし・flutter test 58件成功。Linux で検証したため iOS シミュレーターは未確認。Mac 用の差分は v2 から作成。 |
| 11/27 | Claude | Codexの `Cowlog-2026-11-27.patch`（刷新UI・`LiquidSwitch`）は 14dd25b から作られていて 11/25 の v2 を含まず、9ファイル20か所で衝突したため未適用。利用者の判断で Codex に作り直しを依頼。作業フォルダは「14dd25b ＋ v2（`cowlog-ui-14dd25b.patch`）」に戻した（Claude の `GlassSwitch` は削除、それを使っていた3画面も v2 の状態）。analyze 問題なし・test 52件成功・iOSシミュレータービルド成功。戻す前の状態は `~/Desktop/Cowlog-backups/cowlog-20261127-*-before-1127-patch.*`。Codex 用の土台の差分は `~/Downloads/Cowlog-base-v2-2026-11-27.diff`。コミット・pushなし |
| 11/27 | Claude | リキッドグラスのスイッチ `GlassSwitch`（`lib/widgets/glass_switch.dart`）を追加。触れるとつまみが透明な水滴のガラスになって少しふくらみ（縁で下を屈折・ぼかし、鏡面の光）、動かすと速度に応じて進行方向へ伸び（面積は保つ）、離すと .bouncy で揺れて白に戻る。ドラッグ・端のゴム抵抗・触覚・モーション軽減に対応。優先一覧「位置あり」、地図「全頭の経路」、詳細「航空写真」をスイッチに置き換え（地図上は見出し付きガラスのピル `GlassSwitchChip`）。test 3件追加で計55件成功、analyze・iOSビルド成功。シミュレーターの録画でガラス化と赤い地への変化を確認したが、同じシミュレーターを別セッションが操作していて画面が勝手に切り替わり、オンへの切り替えと着地の揺れは目視確認できていない。作業前バックアップ `~/Desktop/Cowlog-backups/*-before-glass-switch.tar.gz`。コミット・pushなし |
| 11/25 | Claude | Codexのパッチ `cowlog-ui-14dd25b.patch` の差し替え版（16:18、+843/−396）を適用。先に入れた旧版は `git diff` とフォルダの tar.gz を `~/Desktop/Cowlog-backups/cowlog-20261125-1622-*` に退避してから7ファイルを 14dd25b に戻し、`git apply --check` 成功後に適用。analyze 問題なし・test 52件成功・iOSシミュレータービルド成功。iPhone 16 Pro シミュレーター（18 Pro は別セッションが使用中）で、地図タブの航空写真上のナビ、ホームの新しい配置、牛の切り替え（0199→0204でリングが20%→22%）を切り替え後の状態で確認。ぼかしとレンズが浮く途中の動きは撮れておらず未確認。コミット・pushなし |
| 11/25 | Codex | ホームの小さい活動率カードを削除。電池残量を最終計測の横に移し、残量に応じて塗りが変わる小さな電池と％にした。移動距離は歩行ピクトグラムがバー上を移動するカードへ変更。ナビのレンズが移動すると後ろ側が細く伸びるようにした。Flutter 3.44.9 で analyze・test 52件成功。スマホ幅のブラウザで表示と動きを確認。iOSシミュレーター・実機は未確認。コミット・pushなし |
| 11/25 | Codex | ホームを開く・ホームに戻る・牛を切り替えるとき、活動・非活動の2本のリングを同時に描画。動画を参考に、タブ切り替え中は画面をぼかして重ね、ガラスのレンズはナビの縁から少し浮き上がって着地するよう調整。モーション軽減時は即時切り替え。Flutter 3.44.9 で analyze・test 51件成功。スマホ幅のブラウザでホームへ戻るときのぼかし・レンズと、牛を切り替えたときのリングを確認。iOSシミュレーターと実機は未確認。コミット・pushなし |
| 11/25 | Codex | Hiiragi102/Cowlog の `14dd25b` を基準に、下部ナビのばね、連続タップ、ドラッグ中断、画面のフェードを調整。航空写真上ではガラスの白と文字のコントラストを上げた。拡大文字、モーション軽減、押下範囲を調整。Flutter 3.44.9 で analyze・test 48件成功。スマホ幅のブラウザでホーム→首輪・番号の動きと航空写真上の表示を確認。LinuxのためiOSシミュレーターのビルド・表示は未確認。コミット・pushなし |
| 11/25 | Claude | 利用者の GitHub（Hiiragi102）に非公開リポジトリ `Hiiragi102/Cowlog` を作成し、Codex・Claude 共通の作業リポジトリに決定。`origin` を付け替え（旧 nanato0818/Cowlog は `nanato`）。11/9以降の未コミットの変更をまとめてコミットして `main` を push。`.claude/settings.local.json` を .gitignore に追加。push 前に鍵・トークンの混入がないか検索して問題なし |
| 11/25 | Claude | Apple参考の続き（Codexで未完了だった分）。①押下の手応え `Pressable`（押すと縮み .snappy、離すと .bouncy で戻る）を一覧のカード・首輪カード・ピルに。②リキッドグラスのボタン `GlassButton`（押すとガラスが12%ふくらみ縁と表面が明るくなる、SwiftUI の `.glassEffect(.interactive())` 相当）を地図・経路全画面の丸ボタンに。`Glass` に `lift` を追加。③テーマの文字を Apple HIG の文字サイズ既定値（Large Title 34〜Caption 2 11、字間も）に。analyze・test 44件・シミュレーターでカード押下中の縮みを撮影して確認。ガラスボタン押下中の見た目は未撮影 |
| 11/25 | Claude | ①淡い背景をやめて地を白に（`background`・ホーム上半分とも `#FFFFFF`、下地は無彩色 `#F2F2F4`）。ピル・検索欄は薄いグレーの塗り。②下部ナビのレンズを指で触れる・動かす間、透明なガラス玉になり下のアイコンと文字が最大1.3倍に拡大して見える（Flutter標準の `RawMagnifier`。影と縁の光・鏡面の反射は `_LensGloss` で上から描く）。③レンズの移動を SwiftUI の `.snappy`（応答0.4秒・減衰0.85）と同じばね `AppleSpring` に。離した勢いを引き継ぎ、勢い×0.18タブ分を先読みして着地。タブをまたぐたび触覚。④アイコンを Material から Cupertino（SF Symbols相当）へ置き換え。⑤カード見出しを15pt（Apple の Subheadline 相当）に。※途中で作った「画面が窓から広がる遷移」は利用者の意図と違ったため取り消し、画面切替は従来のフェード。analyze・test 44件・シミュレーターでドラッグ途中を撮影して確認。作業前バックアップ `~/Desktop/Cowlog-backups/cowlog-20261125-1414-before-lens-transition.tar.gz` |
| 11/25 | Codex | VS Codeで開かれていた日本語コードの黄色いUnicode強調枠に対応。ユーザー設定の `editor.unicodeHighlight.allowedLocales.ja=true` と `editor.unicodeHighlight.nonBasicASCII=false` を設定。画面上の消失は未確認。アプリ本体の変更・ビルド・Git操作なし |
| 11/20 | Claude | 利用者の指示で白い配色に戻した（参考は「細かいUI・質感のイメージ」だけ）。黒地はやめ、地は淡い無彩色 `#F4F3F1`、カードは白＋柔らかい影（`AppColors.cardShadow`）、角丸26〜28。`LiveCard`・`SegmentGauge`・細いカプセルの棒・アイコン付き見出しは残した。墨色の塗りの上の文字は `AppColors.onInk`。ガラスとナビは11/14までの明るい設定に戻した。analyze・test 44件・シミュレータービルド成功、ホームと優先一覧を目視確認 |
| 11/20 | Claude | （上で白に戻した）利用者が示したXの参考（黒地のライブアクティビティ風小カード）に合わせ、全画面を暗い配色へ。項目とコンセプト色 `#D9473D` は変更なし。`AppColors` を黒地・墨色カード（`surface`/`surfaceHigh`/`night`）に変更、共通部品 `LiveCard`（色付きアイコン＋見出し入りカード）・`SegmentGauge`（区切りゲージ）を追加。ホームの3ゲージを区切りゲージに、見出しをカード内へ、7日の棒を細いカプセルに。ガラスは暗めの色味＋暗い影で地図上の文字が読みやすくなった。analyze・test 44件・シミュレータービルド成功、4タブと詳細を目視確認。作業前バックアップ `~/Desktop/Cowlog-backups/cowlog-20261120-1552-before-dark-widgets.tar.gz` |
| 11/14 | Codex | GPSデバッグに因島中庄町4335周辺版（?site=innoshima）、地域切替、周辺へ戻る、ファイル選択を追加。READMEに公開・静止/歩行/USB/APIの検証手順を追記。ブラウザでサンプル3点（使用2/除外1）・基準点統計・両地域表示を確認。flutter analyze・test（44件）・iOSシミュレータービルド成功。公開は未実行 |
| 11/14 | Codex | GPSデバッグサイトの場所・起動方法・機能を引き継ぎ文書とREADMEで確認して案内。コード変更・起動確認はなし |
| 11/14 | Claude | Codexデスクトップは新しい会話ごとに空のフォルダ（`Documents/Codex/<日付>/<名前>`）で始まり、このフォルダの `AGENTS.md` を読まないと判明。全体設定 `~/.codex/AGENTS.md` と `~/.claude/CLAUDE.md` に、Cowlogの話題ならこの文書を読む指示を追加。空のフォルダからの再開を確認 |
| 11/14 | Claude | この引き継ぎ文書と `AGENTS.md`・`CLAUDE.md` を作成。現状文書のゲージ色の記述を修正 |
| 11/14 | Codex | 画像生成で3DCG風の普通の牛（全身・丸アイコン、白黒・茶色・グレー）を作成し6枚を差し替え |
| 11/14 | Claude | ホームのゲージ3つを緑・赤茶・青灰からコンセプト色に戻した（利用者の指示） |
| 11/14 | Codex | 3Dモデルの作り直しを数回（最終的に画像生成方式へ切り替えたため未使用） |
| 11/14 | Claude | 地図・GPSデバッグサイト `tools/gps-debug/` を作成（API中継・貼り付け・USB・基準点のずれ統計） |
| 11/11 | Codex | リキッドグラスを透明化、押下反応を速く |
| 11/11 | Claude＋Sonnet | ホームタブ追加（横スワイプで個体切替）、コンセプト色 `#D9473D`、地図の全頭経路切替、出典削除、優先一覧の見出し削除 |
| 11/11 | Claude＋Sonnet | 配色・ガラスのタブ・ロゴ削除・不具合修正10件 |

## 5. 次にやること・未解決

### 利用者の判断待ち・確認待ち
- 因島4335-3の正確な位置を現地で確認（現在は4335番地周辺の中心）。因島の区画境界は未設定
- 公開方法はREADMEに記載。外部公開は未実行、常設・API実データ公開時はホスティングと認証方式を決める

### 残っている課題
- 11/27：Mac の「14dd25b ＋ v2」で統合パッチの適用を確認し、iPhone 18 Pro で通常版と `flutter run --dart-define=COWLOG_UI_REFRESH=true` の両方を起動する。スイッチと v2 のアニメーションを iOS 26 で確認する
- 11/25：VS CodeのUnicode強調設定は変更済み。黄色い枠が残る場合はウインドウ再読み込み後に確認する
- 地図の出典表示を削除したが、国土地理院の規約では出典の明示が必要。配布前に表示場所を決める
- 11/25：ぼかし遷移、レンズの変形、活動リングと移動距離の再生はiOSシミュレーター・実機で未確認。特に航空写真の上でレンズの見え方と滑らかさを確認する。SF Pro Rounded（数字の丸い字体）は Flutter から指定できないため未使用
- 11/20のカード化で、日付選択・番号編集シート・首輪追加・経路の全画面の見た目は未確認
- 11/25：地図タブのナビは白の下地と濃い文字でコントラストを補強。実機の航空写真で読みやすさを確認する
- 起動直後にナビをタップしたら詳細画面が開いたことが1回あった（再現せず）。今回、切り替え直後の薄い画面はタップを受けないようにした。実機で再発するかは未確認
- 実機iPhone・Android・実データ（AWS・ローカルAPI）での確認は未実施
- GPSデバッグサイトの実物の首輪USB接続、牧場でのスマホ現在地は未確認
- 仕様書 `current-spec.md`・`ui-update-2026-11-09.md` の配色・ナビ・タブ構成は未更新
- AWSへの配置、首輪からAWSへの送信、加速度センサーによる活動量計測、首輪の省電力は未実装

## 6. 作業を終えるときの更新手順

1. 「4. 直近の作業ログ」の一番上に1行追加（日付・担当・内容）
2. 「5. 次にやること・未解決」を更新（終わったものは消す、途中のものは「どこまでやったか」を書く）
3. 画面や仕様を変えたら `docs/current-state-2026-11-11.md` の該当章も更新
4. 冒頭の「最終更新」を書き換える
5. **作業が途中で終わる場合**は、「5.」に「中断中の作業」として、目的・変更済みのファイル・残りの手順・確認方法を書く
