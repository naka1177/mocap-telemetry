import Foundation

/// One Euro Filter（Casiez et al.）— Android 版 OneEuroFilter.kt の移植。
/// 既定値も Android と同一（minCutoff 1.0 / beta 0.007 / dCutoff 1.0）。
final class OneEuroFilter {
    private let minCutoff: Float
    private let beta: Float
    private let dCutoff: Float
    private var xPrev: Float? = nil
    private var dxPrev: Float = 0
    private var tPrev: Int = 0

    init(minCutoff: Float = 1.0, beta: Float = 0.007, dCutoff: Float = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1 / (2 * Float.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    func filter(_ x: Float, timestampMs: Int) -> Float {
        guard let prev = xPrev else {
            xPrev = x; tPrev = timestampMs; dxPrev = 0
            return x
        }
        let dt = Float(max(1, timestampMs - tPrev)) / 1000
        tPrev = timestampMs
        let dx = (x - prev) / dt
        let aD = alpha(cutoff: dCutoff, dt: dt)
        let dxHat = aD * dx + (1 - aD) * dxPrev
        dxPrev = dxHat
        let cutoff = minCutoff + beta * abs(dxHat)
        let a = alpha(cutoff: cutoff, dt: dt)
        let xHat = a * x + (1 - a) * prev
        xPrev = xHat
        return xHat
    }

    func reset() {
        xPrev = nil; dxPrev = 0; tPrev = 0
    }
}

/// 2次元版（指先座標用）。x/y 独立にフィルタする。
final class OneEuroFilter2D {
    private let fx = OneEuroFilter()
    private let fy = OneEuroFilter()

    func filter(x: Float, y: Float, timestampMs: Int) -> CGPoint {
        CGPoint(x: CGFloat(fx.filter(x, timestampMs: timestampMs)),
                y: CGFloat(fy.filter(y, timestampMs: timestampMs)))
    }

    func reset() {
        fx.reset(); fy.reset()
    }
}
