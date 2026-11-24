# Mocap Controller — iPad テレメトリ版（準備済み・未ビルド）

Android 版 **Mocap Controller**（`~/workspace/native-mocap-app/`）の **テレメトリ画面だけ** を
iPad 向けに Swift/SwiftUI で移植した Xcode プロジェクトです。
このフォルダは「ビルド前の準備一式」であり、**まだビルドは実行していません**
（この作業環境には macOS / Xcode がないため。ビルドは GitHub Actions で行う想定です）。

## なぜテレメトリだけなのか

iOS では他アプリを操作する仕組み（Android の Accessibility Service 相当）が
サードパーティアプリに開放されていません。タップ・ホーム・戻る等の「スマホ操作」は
iOS 版では原理的に不可能なため、本アプリは以下の **表示・判定専用** です。

- 前面カメラ（4:3・ミラー）＋ MediaPipe 分割トラッキング
  - Hand Landmarker: 全フレーム（主経路、ワールドランドマーク付き）
  - Face Landmarker: 約10Hz（478点＋ブレンドシェイプ）
  - Pose Landmarker lite: 約5Hz（表示専用）
  - デリゲートは GPU (Metal) → 失敗時 CPU フォールバック（Android と同じ方針）
- 可視化（Android テレメトリの見た目を移植）
  - 顔ポイントクラウド / 姿勢スケルトン / 両手スケルトン
  - 指先マーカー（指ごとの色＋白リング、ピンチ中は拡大＋発光）
  - 掌/甲ティント＋手首バッジ（判定式・符号規約は Android と同一、5フレーム多数決平滑化）
  - 半透明グレーシルエット（下部プロットのみ、首つなぎ・太め — v0.3.1 仕様）
  - FPS・タスク別推論時間・ピンチ比・頭部姿勢・ブレンドシェイプ上位の統計パネル
- 判定（**表示のみ・実行しない**）
  - 人差し指/中指ピンチ（ヒステリシス 入≤0.25 / 出≥0.35、80ms保持、ハイブリッド 2D+3D 比）
  - 掌（パー）→拳 / 拳→掌 の遷移判定
  - 判定フィード（格ゲー入力履歴風、最新100件）＋ 大型バナー
  - バナー表示中（既定2.5秒）は離散認識を止めるクールダウン意味論（v0.3.0 と同じ）

## 構成

```
mocap-ios/
├── README.md                        # このファイル
├── .github/workflows/build.yml      # 署名なし .ipa を作る GitHub Actions
└── MocapTelemetry/
    ├── MocapTelemetry.xcodeproj     # 手書きプロジェクト（共有スキーム付き）
    └── MocapTelemetry/
        ├── MocapTelemetryApp.swift / ContentView.swift / TelemetryViewModel.swift
        ├── CameraFeedService.swift  # AVFoundation 前面カメラ 4:3・ミラー
        ├── PreviewView.swift
        ├── TrackingEngine.swift     # Hand/Face/Pose の LIVE_STREAM 統合
        ├── TrackingSnapshot.swift / HandGeometry.swift / OneEuroFilter.swift
        ├── JudgmentEngine.swift / ActionFeed.swift   # 判定（表示のみ）
        ├── LandmarkPlotView.swift   # Canvas 描画（プロット＋シルエット）
        ├── Theme.swift              # ダークネイビーテーマ・描画色
        ├── Assets.xcassets          # アイコン（幾何学模様を再構成した仮アイコン）
        └── Models/                  # Android と同一のモデル3点（ハッシュ一致を確認済み）
            ├── hand_landmarker.task       (7.8 MB)
            ├── face_landmarker.task       (3.8 MB)
            └── pose_landmarker_lite.task  (5.8 MB)
```

- 依存: **MediaPipeTasksVision**（Swift Package Manager）
  - URL: `https://github.com/google-ai-edge/mediapipe`、branch `master`
  - Google 公式の iOS セットアップガイド記載の方法そのまま
- 対象: iPad（TARGETED_DEVICE_FAMILY = 2）、iOS 17+
- Bundle ID: `app.muse.mocap.telemetry`（SideStore 再署名時に変わっても問題ありません）

## ビルドまでの残り手順（未実施）

> GitHub リポジトリへのアクセス権が未確認のため、リポジトリ作成・push はまだ行っていません。

1. **リポジトリを用意する**
   - GitHub で新規リポジトリ（例: `mocap-ios`、Public/Private どちらでも可）を作成
   - この `mocap-ios/` フォルダの中身をそのまま push する
     （`.github/workflows/build.yml` がリポジトリ直下に来る構成）
2. **Actions を実行する**
   - push すれば自動で走る。手動なら Actions タブ →「Build unsigned IPA」→ Run workflow
   - 初回は mediapipe リポジトリが大きいため SPM 解決＋ビルドに時間がかかる見込み
     （ワークフローの timeout は 90 分に設定済み）
3. **成果物をダウンロードする**
   - 完了した Run の Artifacts から **`MocapTelemetry-unsigned-ipa`** を取得
   - 中身は署名なしの `MocapTelemetry-unsigned.ipa`
   - 失敗した場合は `xcodebuild-log` アーティファクトにログが残る

ワークフローの中身: `macos-latest` 上で `xcodebuild build`
（`CODE_SIGNING_ALLOWED=NO`）→ `.app` を `Payload/` に入れて zip し `.ipa` 化。

## iPad へのインストール（SideStore）と7日更新

この .ipa は **署名なし** です。SideStore / AltStore が、あなたの Apple ID で
再署名してインストールします。

- **SideStore の初期設定**（初回のみ）: PC（Windows 可）で SideStore 公式手順に従い
  ペアリングファイル等を用意する。以後の更新は iPad 単体で可能
- **無料 Apple ID の制限**
  - 署名の有効期限は **7日**。期限切れ前に SideStore で「Refresh」すると再署名されて延びる
    （同じ Wi-Fi 内で自動更新の設定も可能）
  - 無料枠では同時インストールできるサイドロードアプリは最大3つまで
  - 期限が切れてもアプリとデータは消えない。再度 Refresh すればそのまま使える
- **有料 Apple Developer アカウント（年 $99）** なら署名は1年有効になり、この制限はほぼ消える
- インストール手順の要点: SideStore を開く →「+」→ ダウンロードした
  `MocapTelemetry-unsigned.ipa` を選ぶ → 再署名＆インストール完了を待つ
- 初回起動時にカメラ許可ダイアログが出るので許可する

## 既知の制限・注意（正直な注記）

- **未コンパイル**: この環境では Xcode が使えないため、コンパイル自体は未検証です。
  実施した検証は「Swift ソースの括弧バランス / pbxproj の参照整合（53オブジェクト）/
  スキーム XML / ワークフロー YAML / モデルのハッシュ一致」まで。
  初回 CI で型名や API の細部（例: 結果型のプロパティ名）の修正が必要になる可能性があります
- **向きは横向き前提**: カメラ接続の向きを landscapeRight に固定しています。
  iPad を横置きして使う想定で、縦向きではプレビューと重ね描画が回転します
- **掌/甲の符号規約** は Android で実績のある規約をそのまま移植しましたが、
  iPad 実機での確認はまだです。反対だった場合は `HandGeometry.palmSign` を反転します
- **推論時間の表示** は「コールバック時刻 − フレームタイムスタンプ」の概算です（Android と同じ定義）
- アイコンは Muse の幾何学模様アバターをモチーフに図形で再構成した仮アイコンです

## Android 版との対応表（抜粋）

| Android | iPad 版 |
|---|---|
| SplitTrackingEngine.kt | TrackingEngine.swift |
| CameraPipeline.kt（CameraX） | CameraFeedService.swift（AVFoundation） |
| LandmarkPlotView.kt | LandmarkPlotView.swift（SwiftUI Canvas） |
| HandGeometry.kt / FaceGeometry | HandGeometry.swift |
| GestureEngine.kt（判定部のみ） | JudgmentEngine.swift |
| ActionFeed.kt | ActionFeed.swift |
| CaptureService / Accessibility 実行系 | **なし（iOS では不可能なため）** |

## Git リポジトリとバイナリ資産の扱い（CI 方式）

GitHub 連携（Muse コネクタ）のスナップショット push は UTF-8 テキスト専用のため、
バイナリはそのままではリポジトリに入れられません。そこで次の方式にしています
（欠落ではなく、CI で正本と同一物を復元します）。

- **モデル 3 点（.task）**: リポジトリに格納しません。CI（build.yml）が
  Google 公式 URL から取得し、SHA-256 が手元の正本と一致することを検証してから
  ビルドします（検証用ハッシュは build.yml に固定記載）。
  - hand_landmarker.task: `https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task`
  - face_landmarker.task: `https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task`
  - pose_landmarker_lite.task: `https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task`
  - ローカルで Xcode ビルドする場合は、上記 URL から取得して
    `MocapTelemetry/MocapTelemetry/Models/` に置いてください。
- **アプリアイコン（AppIcon-1024.png）**: base64 テキスト
  `AppIcon.appiconset/AppIcon-1024.png.b64` として格納し、CI が PNG に復元します。
- **配布**: CI 成功時、`.ipa` は Actions の Artifact に加えて
  GitHub Release（タグ `build-<実行番号>`）にも添付されます。
  ダウンロードは Release ページの Assets から行えます。
