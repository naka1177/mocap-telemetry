import Foundation

/// 手の向き（掌 / 甲）。Android 版 HandGeometry.HandSide の移植。
enum HandSide: String {
    case palm = "掌"
    case back = "甲"
    case unknown = "—"
}

/// 1フレーム分の統合トラッキング結果。Android 版 TrackingSnapshot に対応。
///
/// ランドマークは Android と同じフラット配列レイアウト [x0,y0,z0, x1,y1,z1, …]。
/// 座標は解析フレーム（ミラー済み前面カメラ画像）の正規化座標（x 右・y 下）。
struct TrackingSnapshot {
    var timestampMs: Int = 0
    var imageWidth: Int = 0
    var imageHeight: Int = 0

    var faceLandmarks: [Float] = []        // 478 × 3
    var poseLandmarks: [Float] = []        // 33 × 3
    var poseWorldLandmarks: [Float] = []   // 33 × 3 (m)
    var leftHandLandmarks: [Float] = []    // 21 × 3（本人の解剖学的な左手）
    var leftHandWorldLandmarks: [Float] = []
    var rightHandLandmarks: [Float] = []   // 21 × 3（本人の解剖学的な右手）
    var rightHandWorldLandmarks: [Float] = []

    /// ブレンドシェイプ上位（名前, スコア）。
    var topBlendshapes: [(name: String, score: Float)] = []
    var blendshapeScores: [String: Float] = [:]

    /// 頭部姿勢（FaceGeometry の概算、-1…1、0 = 正面）。
    var headYaw: Float? = nil
    var headPitch: Float? = nil

    /// One Euro 平滑化済みの人差し指先（正規化座標）。判定・表示の基準点。
    var smoothedLeftIndexTip: CGPoint? = nil
    var smoothedRightIndexTip: CGPoint? = nil

    var leftHandSide: HandSide = .unknown
    var rightHandSide: HandSide = .unknown

    /// ハイブリッドピンチ比（プロット上のマーカー発光と統計表示用）。
    var leftIndexPinch: Float? = nil
    var leftMiddlePinch: Float? = nil
    var rightIndexPinch: Float? = nil
    var rightMiddlePinch: Float? = nil

    var fps: Float = 0
    var handInferenceMs: Float = 0
    var faceInferenceMs: Float = 0
    var poseInferenceMs: Float = 0
    var poseVisibility: Float? = nil
    var architecture: String = "—"
    var delegateName: String = "—"
    var error: String? = nil

    var facePresent: Bool { !faceLandmarks.isEmpty }
    var posePresent: Bool { !poseLandmarks.isEmpty }
    var leftHandPresent: Bool { !leftHandLandmarks.isEmpty }
    var rightHandPresent: Bool { !rightHandLandmarks.isEmpty }
}
