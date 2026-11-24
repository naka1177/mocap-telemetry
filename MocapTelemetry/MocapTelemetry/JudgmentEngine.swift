import Foundation

/// テレメトリ専用の判定エンジン（Android 版 GestureEngine の判定部分を縮約移植）。
///
/// 実行系（タップ・ホーム等）は iOS では存在しないため、判定はすべて表示のみ。
/// 実装する判定:
/// - 人差し指ピンチ / 中指ピンチ（ヒステリシス 入≤0.25 / 出≥0.35、80ms保持で成立）
/// - 中指ピンチ成立 = 確定タップ相当、人差し＋中指が両方近い場合は曖昧として棄却
/// - 短すぎるピンチ（<300ms）は「無効」として記録
/// - 手形状 掌（パー）→拳 / 拳→掌（パー） の遷移（1.2秒ウィンドウ）
/// - バナー＋認識クールダウン（v0.3.0 の意味論）: 判定確定でバナーを表示し、
///   表示中（既定2.5秒）は離散認識そのものを停止する（追尾・表示は継続）
///   ON/OFFトグルあり（bannerEnabled、Web版と同義）: OFF時はバナーもクールダウンも発生しない
final class JudgmentEngine {
    // Android と同じしきい値
    static let pinchEnter: Float = 0.25
    static let pinchExit: Float = 0.35
    static let pinchHoldMs = 80
    static let shortPinchMs = 300
    static let shapeTransitionWindowMs = 1200

    /// バナー表示時間（秒）。Android v0.3.0 の既定 2.5 秒。
    var bannerDurationSec: Double = 2.5

    /// 判定バナー＋クールダウンの有効/無効（Web版のトグルと同義、既定 ON）。
    /// OFF のとき確定判定はフィードに記録するだけで、バナー表示も認識停止もしない。
    var bannerEnabled: Bool = true

    let feed = ActionFeed()

    /// 現在表示中のバナー（nil = 非表示）。テキストは「入力 → 操作」。
    private(set) var bannerText: String? = nil
    private var bannerUntil: Date? = nil

    var isCoolingDown: Bool {
        if let until = bannerUntil { return Date() < until }
        return false
    }

    private struct PinchState {
        var active = false
        var sinceMs: Int = 0       // しきい値を下回り始めた時刻
        var established = false    // 80ms保持を満たした
    }

    private struct HandState {
        var indexPinch = PinchState()
        var middlePinch = PinchState()
        var shape: String? = nil   // 直近の確定形状 "パー" / "拳"
        var shapeSinceMs: Int = 0
    }

    private var left = HandState()
    private var right = HandState()
    private var lastBannerPostAt = Date.distantPast

    func reset() {
        left = HandState(); right = HandState()
        bannerText = nil; bannerUntil = nil
        feed.clear()
    }

    /// スナップショットを1件処理する。新しいフィード行が増えたら true。
    @discardableResult
    func process(_ snap: TrackingSnapshot) -> Bool {
        // バナー期限切れの処理（認識再開）
        if let until = bannerUntil, Date() >= until {
            bannerText = nil; bannerUntil = nil
        }
        let cooling = isCoolingDown
        var posted = false

        if snap.leftHandPresent {
            posted = processHand(&left, snap: snap, isLeft: true, cooling: cooling) || posted
        } else { left = HandState() }
        if snap.rightHandPresent {
            posted = processHand(&right, snap: snap, isLeft: false, cooling: cooling) || posted
        } else { right = HandState() }

        return posted
    }

    private func processHand(_ state: inout HandState, snap: TrackingSnapshot, isLeft: Bool, cooling: Bool) -> Bool {
        var posted = false
        let handLabel = isLeft ? "左手" : "右手"
        let iw = Float(snap.imageWidth), ih = Float(snap.imageHeight)
        let hand = isLeft ? snap.leftHandLandmarks : snap.rightHandLandmarks
        let indexRatio = isLeft ? snap.leftIndexPinch : snap.rightIndexPinch
        let middleRatio = isLeft ? snap.leftMiddlePinch : snap.rightMiddlePinch
        let now = snap.timestampMs

        // --- ピンチ（人差し指 / 中指） ---
        posted = updatePinch(&state.indexPinch, ratio: indexRatio, now: now,
                             input: "\(handLabel) 人差し指ピンチ", action: "ドラッグ／スクロール相当",
                             isConfirm: false, cooling: cooling,
                             otherActive: state.middlePinch.established) || posted
        posted = updatePinch(&state.middlePinch, ratio: middleRatio, now: now,
                             input: "\(handLabel) 中指ピンチ", action: "確定タップ相当",
                             isConfirm: true, cooling: cooling,
                             otherActive: state.indexPinch.established) || posted

        // --- 手形状の遷移（掌→拳 / 拳→掌） ---
        if let shape = HandGeometry.handShape(hand: hand, iw: iw, ih: ih) {
            if shape != state.shape {
                if let prev = state.shape, now - state.shapeSinceMs <= Self.shapeTransitionWindowMs {
                    if prev == "パー" && shape == "拳" {
                        posted = fireJudgment(input: "\(handLabel) 掌→拳", action: "ホーム相当",
                                              basis: "遷移 \(now - state.shapeSinceMs)ms", cooling: cooling) || posted
                    } else if prev == "拳" && shape == "パー" {
                        posted = fireJudgment(input: "\(handLabel) 拳→掌", action: "最近のアプリ相当",
                                              basis: "遷移 \(now - state.shapeSinceMs)ms", cooling: cooling) || posted
                    }
                }
                state.shape = shape
                state.shapeSinceMs = now
            }
        }
        return posted
    }

    private func updatePinch(_ pinch: inout PinchState, ratio: Float?, now: Int,
                             input: String, action: String, isConfirm: Bool,
                             cooling: Bool, otherActive: Bool) -> Bool {
        guard let ratio = ratio else {
            pinch = PinchState()
            return false
        }
        var posted = false
        if !pinch.active {
            if ratio <= Self.pinchEnter {
                pinch.active = true
                pinch.sinceMs = now
                pinch.established = false
            }
        } else {
            if !pinch.established && now - pinch.sinceMs >= Self.pinchHoldMs {
                pinch.established = true
                if isConfirm && otherActive {
                    // 人差し＋中指が両方親指に近い = 曖昧。Android と同じく発火しない。
                    feed.post(input: input, action: action, basis: String(format: "比 %.2f", ratio),
                              result: .rejected, reason: "曖昧（両ピンチ近接）")
                    posted = true
                } else if isConfirm {
                    posted = fireJudgment(input: input, action: action,
                                          basis: String(format: "比 %.2f", ratio), cooling: cooling) || posted
                } else {
                    feed.post(input: input, action: action, basis: String(format: "比 %.2f", ratio),
                              result: .info, reason: "保持中は連続判定")
                    posted = true
                }
            }
            if ratio >= Self.pinchExit {
                let held = now - pinch.sinceMs
                if pinch.established && held < Self.shortPinchMs && isConfirm {
                    feed.post(input: input, action: "（無効）", basis: "保持 \(held)ms",
                              result: .rejected, reason: "短すぎるピンチ")
                    posted = true
                }
                pinch = PinchState()
            }
        }
        return posted
    }

    /// 確定判定: バナーを出し、表示中は認識クールダウンに入る。
    /// クールダウン中の確定は「抑制」として記録だけする（バナーは延長しない）。
    /// バナーOFF（bannerEnabled == false）のときはフィード記録のみで、バナーもクールダウンも発生しない。
    private func fireJudgment(input: String, action: String, basis: String, cooling: Bool) -> Bool {
        if cooling {
            feed.post(input: input, action: action, basis: basis, result: .suppressed, reason: "バナー表示中")
            return true
        }
        feed.post(input: input, action: action, basis: basis, result: .judged, reason: "表示のみ（iOS版）")
        if bannerEnabled {
            bannerText = "\(input) → \(action)"
            bannerUntil = Date().addingTimeInterval(bannerDurationSec)
            lastBannerPostAt = Date()
        }
        return true
    }
}
