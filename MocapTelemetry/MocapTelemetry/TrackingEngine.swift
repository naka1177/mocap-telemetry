import Foundation
import MediaPipeTasksVision
import CoreMedia
import UIKit

/// 分割トラッキングエンジン（Android 版 SplitTrackingEngine の移植）。
///
/// - Hand Landmarker: 全フレーム（主経路、ワールドランドマーク付き、最大2手）
/// - Face Landmarker: 約10Hz（478点＋ブレンドシェイプ）
/// - Pose Landmarker lite: 約5Hz（表示専用）
/// の3タスクを LIVE_STREAM で並行実行し、手の結果コールバックのたびに
/// 最新の顔・姿勢結果をマージして TrackingSnapshot を発行する。
/// デリゲートは GPU（Metal）を試し、失敗したら CPU にフォールバックする。
final class TrackingEngine: NSObject {
    /// スナップショット発行コールバック（任意のキューで呼ばれる。UI 側で main へ）。
    var onSnapshot: ((TrackingSnapshot) -> Void)?

    private var handLandmarker: HandLandmarker?
    private var faceLandmarker: FaceLandmarker?
    private var poseLandmarker: PoseLandmarker?
    private(set) var delegateName = "—"
    private(set) var architecture = "—"

    private let lock = NSLock()
    private var latestFace: FaceLandmarkerResult?
    private var latestPose: PoseLandmarkerResult?
    private var faceInferenceMs: Float = 0
    private var poseInferenceMs: Float = 0
    private var lastError: String?

    private var frameIndex = 0
    private var lastTimestampMs = 0
    private var handCallbackTimes: [Int] = []   // FPS（1秒スライディング）用

    private let leftIndexFilter = OneEuroFilter2D()
    private let rightIndexFilter = OneEuroFilter2D()
    // 掌/甲の多数決平滑化（Android と同じ5フレーム）
    private var leftSideHistory: [HandSide] = []
    private var rightSideHistory: [HandSide] = []

    private static let faceEveryNFrames = 3   // 30fps想定で約10Hz
    private static let poseEveryNFrames = 6   // 30fps想定で約5Hz

    // MARK: - セットアップ

    func start() throws {
        stop()
        do {
            try createTasks(useGPU: true)
            delegateName = "GPU (Metal)"
        } catch {
            // Android 版と同じく GPU → CPU フォールバック
            try createTasks(useGPU: false)
            delegateName = "CPU"
        }
        architecture = "分割 (Hand全フレーム / Face約10Hz / Pose約5Hz)"
        frameIndex = 0
        lastTimestampMs = 0
    }

    func stop() {
        handLandmarker = nil
        faceLandmarker = nil
        poseLandmarker = nil
        lock.lock()
        latestFace = nil; latestPose = nil
        lock.unlock()
        leftIndexFilter.reset(); rightIndexFilter.reset()
        leftSideHistory = []; rightSideHistory = []
    }

    private func modelPath(_ name: String) throws -> String {
        guard let path = Bundle.main.path(forResource: name, ofType: "task") else {
            throw NSError(domain: "MocapTelemetry", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "モデルが見つかりません: \(name).task"])
        }
        return path
    }

    private func createTasks(useGPU: Bool) throws {
        // Hand（主経路）
        let handOptions = HandLandmarkerOptions()
        handOptions.baseOptions.modelAssetPath = try modelPath("hand_landmarker")
        handOptions.baseOptions.delegate = useGPU ? .GPU : .CPU
        handOptions.runningMode = .liveStream
        handOptions.numHands = 2
        handOptions.handLandmarkerLiveStreamDelegate = self
        handLandmarker = try HandLandmarker(options: handOptions)

        // Face（ブレンドシェイプ付き）
        let faceOptions = FaceLandmarkerOptions()
        faceOptions.baseOptions.modelAssetPath = try modelPath("face_landmarker")
        faceOptions.baseOptions.delegate = useGPU ? .GPU : .CPU
        faceOptions.runningMode = .liveStream
        faceOptions.numFaces = 1
        faceOptions.outputFaceBlendshapes = true
        faceOptions.faceLandmarkerLiveStreamDelegate = self
        faceLandmarker = try FaceLandmarker(options: faceOptions)

        // Pose lite（表示専用）
        let poseOptions = PoseLandmarkerOptions()
        poseOptions.baseOptions.modelAssetPath = try modelPath("pose_landmarker_lite")
        poseOptions.baseOptions.delegate = useGPU ? .GPU : .CPU
        poseOptions.runningMode = .liveStream
        poseOptions.numPoses = 1
        poseOptions.poseLandmarkerLiveStreamDelegate = self
        poseLandmarker = try PoseLandmarker(options: poseOptions)
    }

    // MARK: - フレーム投入

    /// CameraFeedService から毎フレーム呼ばれる。
    /// sampleBuffer は前面カメラのミラー済みバッファ（接続側で反転済み）。
    func detect(sampleBuffer: CMSampleBuffer) {
        guard handLandmarker != nil else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var ts = Int(CMTimeGetSeconds(pts) * 1000)
        if ts <= lastTimestampMs { ts = lastTimestampMs + 1 }  // 単調増加を保証
        lastTimestampMs = ts
        frameIndex += 1

        do {
            let mpImage = try MPImage(sampleBuffer: sampleBuffer, orientation: .up)
            try handLandmarker?.detectAsync(mpImage: mpImage, timestampInMilliseconds: ts)
            if frameIndex % Self.faceEveryNFrames == 0 {
                try faceLandmarker?.detectAsync(mpImage: mpImage, timestampInMilliseconds: ts)
            }
            if frameIndex % Self.poseEveryNFrames == 0 {
                try poseLandmarker?.detectAsync(mpImage: mpImage, timestampInMilliseconds: ts)
            }
        } catch {
            lock.lock(); lastError = error.localizedDescription; lock.unlock()
        }
    }

    // MARK: - スナップショット合成（手コールバック = 主経路）

    private func composeSnapshot(handResult: HandLandmarkerResult?, timestampMs: Int, handInferenceMs: Float,
                                 imageWidth: Int, imageHeight: Int) -> TrackingSnapshot {
        var snap = TrackingSnapshot()
        snap.timestampMs = timestampMs
        snap.imageWidth = imageWidth
        snap.imageHeight = imageHeight
        snap.architecture = architecture
        snap.delegateName = delegateName
        snap.handInferenceMs = handInferenceMs

        lock.lock()
        let face = latestFace, pose = latestPose
        snap.faceInferenceMs = faceInferenceMs
        snap.poseInferenceMs = poseInferenceMs
        snap.error = lastError
        lock.unlock()

        // FPS: 手コールバックの1秒スライディングウィンドウ
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        handCallbackTimes.append(nowMs)
        handCallbackTimes.removeAll { nowMs - $0 > 1000 }
        snap.fps = Float(handCallbackTimes.count)

        // 顔
        if let face = face, let landmarks = face.faceLandmarks.first {
            snap.faceLandmarks = Self.flatten(landmarks)
            if let classifications = face.faceBlendshapes?.first {
                let cats = classifications.categories
                    .map { (name: $0.categoryName ?? "?", score: $0.score) }
                    .sorted { $0.score > $1.score }
                snap.topBlendshapes = Array(cats.prefix(5))
                snap.blendshapeScores = Dictionary(cats.map { ($0.name, $0.score) }, uniquingKeysWith: { a, _ in a })
            }
            let pose2 = FaceGeometry.headPose(face: snap.faceLandmarks)
            snap.headYaw = pose2.yaw
            snap.headPitch = pose2.pitch
        }

        // 姿勢
        if let pose = pose, let landmarks = pose.landmarks.first {
            snap.poseLandmarks = Self.flatten(landmarks)
            if let world = pose.worldLandmarks.first { snap.poseWorldLandmarks = Self.flattenWorld(world) }
            let vis = landmarks.compactMap { $0.visibility }.map { Float(truncating: $0) }
            if !vis.isEmpty { snap.poseVisibility = vis.reduce(0, +) / Float(vis.count) }
        }

        // 両手（handedness ラベル = 本人の解剖学的な左右。入力はミラー済み前面カメラ）
        if let hand = handResult {
            for i in hand.landmarks.indices {
                let label = hand.handedness[safe: i]?.first?.categoryName ?? ""
                let flat = Self.flatten(hand.landmarks[i])
                let world = hand.worldLandmarks[safe: i].map { Self.flattenWorld($0) } ?? []
                let iw = Float(imageWidth), ih = Float(imageHeight)
                if label == "Left" {
                    snap.leftHandLandmarks = flat
                    snap.leftHandWorldLandmarks = world
                    snap.leftHandSide = smoothSide(HandGeometry.handSide(hand: flat, isRightHand: false), history: &leftSideHistory)
                    snap.leftIndexPinch = HandGeometry.pinchRatio(hand: flat, world: world, fingerTip: 8, iw: iw, ih: ih)
                    snap.leftMiddlePinch = HandGeometry.pinchRatio(hand: flat, world: world, fingerTip: 12, iw: iw, ih: ih)
                    if flat.count >= 9 * 3 {
                        snap.smoothedLeftIndexTip = leftIndexFilter.filter(x: flat[8 * 3], y: flat[8 * 3 + 1], timestampMs: timestampMs)
                    }
                } else if label == "Right" {
                    snap.rightHandLandmarks = flat
                    snap.rightHandWorldLandmarks = world
                    snap.rightHandSide = smoothSide(HandGeometry.handSide(hand: flat, isRightHand: true), history: &rightSideHistory)
                    snap.rightIndexPinch = HandGeometry.pinchRatio(hand: flat, world: world, fingerTip: 8, iw: iw, ih: ih)
                    snap.rightMiddlePinch = HandGeometry.pinchRatio(hand: flat, world: world, fingerTip: 12, iw: iw, ih: ih)
                    if flat.count >= 9 * 3 {
                        snap.smoothedRightIndexTip = rightIndexFilter.filter(x: flat[8 * 3], y: flat[8 * 3 + 1], timestampMs: timestampMs)
                    }
                }
            }
        }
        if !snap.leftHandPresent { leftIndexFilter.reset(); leftSideHistory = [] }
        if !snap.rightHandPresent { rightIndexFilter.reset(); rightSideHistory = [] }
        return snap
    }

    private func smoothSide(_ side: HandSide, history: inout [HandSide]) -> HandSide {
        history.append(side)
        if history.count > 5 { history.removeFirst(history.count - 5) }
        let known = history.filter { $0 != .unknown }
        guard !known.isEmpty else { return .unknown }
        let palmCount = known.filter { $0 == .palm }.count
        return palmCount * 2 >= known.count ? .palm : .back
    }

    private static func flatten(_ landmarks: [NormalizedLandmark]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(landmarks.count * 3)
        for lm in landmarks { out.append(lm.x); out.append(lm.y); out.append(lm.z) }
        return out
    }

    private static func flattenWorld(_ landmarks: [Landmark]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(landmarks.count * 3)
        for lm in landmarks { out.append(lm.x); out.append(lm.y); out.append(lm.z) }
        return out
    }
}

// MARK: - MediaPipe ライブストリーム デリゲート

extension TrackingEngine: HandLandmarkerLiveStreamDelegate {
    func handLandmarker(_ handLandmarker: HandLandmarker, didFinishDetection result: HandLandmarkerResult?,
                        timestampInMilliseconds: Int, error: Error?) {
        if let error = error {
            lock.lock(); lastError = error.localizedDescription; lock.unlock()
        }
        // 画像サイズは直近フレームのバッファから得る代わりに、結果からは取れないため
        // CameraFeedService が保持する直近サイズを参照する。
        let size = CameraFeedService.lastFrameSize
        let inference = Float(Int(Date().timeIntervalSince1970 * 1000) - timestampMs)
        let snap = composeSnapshot(handResult: result, timestampMs: timestampMs,
                                   handInferenceMs: inference,
                                   imageWidth: size.width, imageHeight: size.height)
        onSnapshot?(snap)
    }
}

extension TrackingEngine: FaceLandmarkerLiveStreamDelegate {
    func faceLandmarker(_ faceLandmarker: FaceLandmarker, didFinishDetection result: FaceLandmarkerResult?,
                        timestampInMilliseconds: Int, error: Error?) {
        lock.lock()
        if let result = result { latestFace = result }
        faceInferenceMs = Float(Int(Date().timeIntervalSince1970 * 1000) - timestampInMilliseconds)
        if let error = error { lastError = error.localizedDescription }
        lock.unlock()
    }
}

extension TrackingEngine: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds: Int, error: Error?) {
        lock.lock()
        if let result = result { latestPose = result }
        poseInferenceMs = Float(Int(Date().timeIntervalSince1970 * 1000) - timestampInMilliseconds)
        if let error = error { lastError = error.localizedDescription }
        lock.unlock()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
