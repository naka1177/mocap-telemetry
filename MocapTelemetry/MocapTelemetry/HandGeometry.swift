import Foundation

/// Android 版 HandGeometry.kt / FaceGeometry の Swift 移植。
/// 掌/甲判定の符号規約・ハイブリッドピンチ比・指の曲げ判定は Android と同一。
enum HandGeometry {
    // MediaPipe ハンドトポロジのランドマーク番号
    static let wrist = 0
    static let thumbTip = 4
    static let indexMCP = 5
    static let middleMCP = 9
    static let pinkyMCP = 17

    /// 指先ランドマーク番号（親指, 人差し指, 中指, 薬指, 小指）
    static let tipIndices = [4, 8, 12, 16, 20]
    /// PIP 関節（親指は IP=3）
    static let pipIndices = [3, 6, 10, 14, 18]
    /// MCP 関節（親指は CMC 寄りの 2 を使用 — Android の Finger 定義と同等）
    static let mcpIndices = [2, 5, 9, 13, 17]

    // MARK: - 掌 / 甲 判定

    /// Android と同じ規約: palmFacing ⇔ (cz < 0) == isRightHand
    /// （ミラー済み画像空間で a = indexMCP − wrist, b = pinkyMCP − wrist の外積 z 成分）。
    /// 実機で反対になったら PALM_SIGN を反転する（Android 版と同じ運用）。
    private static let palmSign = 1

    static func handSide(hand: [Float], isRightHand: Bool) -> HandSide {
        guard hand.count >= 21 * 3 else { return .unknown }
        let ax = hand[indexMCP * 3] - hand[wrist * 3]
        let ay = hand[indexMCP * 3 + 1] - hand[wrist * 3 + 1]
        let bx = hand[pinkyMCP * 3] - hand[wrist * 3]
        let by = hand[pinkyMCP * 3 + 1] - hand[wrist * 3 + 1]
        let cz = ax * by - ay * bx
        if abs(cz) < 1e-6 { return .unknown }
        let palmFacing = ((cz < 0) == isRightHand) == (palmSign > 0)
        return palmFacing ? .palm : .back
    }

    // MARK: - ハイブリッドピンチ比（2D 0.70 + ワールド3D 0.30）

    static let w3d: Float = 0.30

    private static func dist2dPx(_ hand: [Float], _ a: Int, _ b: Int, iw: Float, ih: Float) -> Float {
        let dx = (hand[a * 3] - hand[b * 3]) * iw
        let dy = (hand[a * 3 + 1] - hand[b * 3 + 1]) * ih
        return hypot(dx, dy)
    }

    private static func dist3d(_ world: [Float], _ a: Int, _ b: Int) -> Float {
        let dx = world[a * 3] - world[b * 3]
        let dy = world[a * 3 + 1] - world[b * 3 + 1]
        let dz = world[a * 3 + 2] - world[b * 3 + 2]
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /// 掌の長さ（ピクセル）: |wrist − middleMCP|。
    static func palmLengthPx(hand: [Float], iw: Float, ih: Float) -> Float {
        dist2dPx(hand, wrist, middleMCP, iw: iw, ih: ih)
    }

    /// 2D のみのピンチ比（ワールド欠落時のフォールバック）。
    static func pinchRatio2d(hand: [Float], fingerTip: Int, iw: Float, ih: Float) -> Float? {
        let palm = dist2dPx(hand, wrist, middleMCP, iw: iw, ih: ih)
        if palm < 1e-3 { return nil }
        return dist2dPx(hand, thumbTip, fingerTip, iw: iw, ih: ih) / palm
    }

    /// ハイブリッドピンチ比。world が空なら 2D のみ。
    static func pinchRatio(hand: [Float], world: [Float], fingerTip: Int, iw: Float, ih: Float) -> Float? {
        guard let r2d = pinchRatio2d(hand: hand, fingerTip: fingerTip, iw: iw, ih: ih) else { return nil }
        if world.count < 21 * 3 { return r2d }
        let palm3d = dist3d(world, wrist, middleMCP)
        if palm3d < 1e-5 { return r2d }
        let r3d = dist3d(world, thumbTip, fingerTip) / palm3d
        return (1 - w3d) * r2d + w3d * r3d
    }

    // MARK: - 指の状態（伸展 / 屈曲）

    static let extendedAngle: Float = 150
    static let curledAngle: Float = 125

    enum FingerState: Int {
        case any = 0
        case extended = 1
        case curled = 2
    }

    /// PIP 関節角度（度）。真っ直ぐ = 180。
    static func fingerAngle(hand: [Float], finger: Int, iw: Float, ih: Float) -> Float {
        let a = mcpIndices[finger], b = pipIndices[finger], c = tipIndices[finger]
        let ax = hand[a * 3] * iw, ay = hand[a * 3 + 1] * ih
        let bx = hand[b * 3] * iw, by = hand[b * 3 + 1] * ih
        let cx = hand[c * 3] * iw, cy = hand[c * 3 + 1] * ih
        let v1x = ax - bx, v1y = ay - by
        let v2x = cx - bx, v2y = cy - by
        let n1 = hypot(v1x, v1y), n2 = hypot(v2x, v2y)
        if n1 < 1e-3 || n2 < 1e-3 { return 180 }
        let cosv = min(1, max(-1, (v1x * v2x + v1y * v2y) / (n1 * n2)))
        return Float(acos(Double(cosv)) * 180 / .pi)
    }

    /// 5指ぶんの状態（親指→小指）。
    static func fingerStates(hand: [Float], iw: Float, ih: Float) -> [FingerState] {
        guard hand.count >= 21 * 3 else { return [.any, .any, .any, .any, .any] }
        return (0..<5).map { f in
            let angle = fingerAngle(hand: hand, finger: f, iw: iw, ih: ih)
            if angle > extendedAngle { return .extended }
            if angle < curledAngle { return .curled }
            return .any
        }
    }

    /// 手の形: 全指伸展 = パー / 全指屈曲 = 拳 / それ以外 = nil（途中）。
    static func handShape(hand: [Float], iw: Float, ih: Float) -> String? {
        let states = fingerStates(hand: hand, iw: iw, ih: ih)
        // 親指は誤判定が多いので人差し〜小指の4指で判定（Android の手形状表示と同趣旨）
        let four = Array(states[1..<5])
        if four.allSatisfy({ $0 == .extended }) { return "パー" }
        if four.allSatisfy({ $0 == .curled }) { return "拳" }
        return nil
    }
}

/// 顔ランドマーク形状からの頭部姿勢概算（Android FaceGeometry の移植）。
enum FaceGeometry {
    /// (yaw, pitch) を -1…1 で返す。0 = 正面。インデックスは Face Mesh トポロジ。
    static func headPose(face: [Float]) -> (yaw: Float?, pitch: Float?) {
        guard face.count >= 455 * 3 else { return (nil, nil) }
        func x(_ i: Int) -> Float { face[i * 3] }
        func y(_ i: Int) -> Float { face[i * 3 + 1] }
        let width = abs(x(454) - x(234))
        if width < 1e-4 { return (nil, nil) }
        let midX = (x(234) + x(454)) / 2
        let yaw = min(1, max(-1, ((x(1) - midX) / (width / 2)) * 1.6))
        let span = y(152) - y(10)
        if abs(span) < 1e-4 { return (yaw, nil) }
        let pitchRaw = (y(1) - y(10)) / span
        let pitch = min(1, max(-1, (pitchRaw - 0.55) / 0.30))
        return (yaw, pitch)
    }
}
