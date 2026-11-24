import SwiftUI

/// ランドマーク描画ビュー（Android 版 LandmarkPlotView の Canvas 移植）。
///
/// - カメラプレビュー重ね用（isPlotInstance=false）と、下部プロット専用（true）の2用途
/// - シルエットは Android v0.3.1 と同じくプロット専用インスタンスでのみ描く
/// - 手の色: 左手=緑 / 右手=赤ピンクをベースに、掌=暖色 / 甲=冷色へティント
/// - 指先マーカーは指ごとの色＋白リング、ピンチ成立中の指は拡大＋発光リング
struct LandmarkPlotView: View {
    let snapshot: TrackingSnapshot
    var isPlotInstance: Bool = false
    var silhouetteEnabled: Bool = false

    private static let handConnections: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8),
        (5, 9), (9, 10), (10, 11), (11, 12), (9, 13), (13, 14), (14, 15), (15, 16),
        (13, 17), (17, 18), (18, 19), (19, 20), (0, 17),
    ]
    private static let poseConnections: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 10), (9, 10),
        (11, 12), (11, 13), (13, 15), (15, 17), (15, 19), (15, 21), (17, 19),
        (12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20),
        (11, 23), (12, 24), (23, 24), (23, 25), (24, 26), (25, 27), (26, 28),
        (27, 29), (28, 30), (29, 31), (30, 32), (27, 31), (28, 32),
    ]
    private static let fingerTips = [4, 8, 12, 16, 20]
    private static let fingerChains: [[Int]] = [
        [0, 1, 2, 3, 4], [0, 5, 6, 7, 8], [0, 9, 10, 11, 12], [0, 13, 14, 15, 16], [0, 17, 18, 19, 20],
    ]

    var body: some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size)
        }
    }

    // MARK: - 座標変換（レターボックス: フレーム全体を収め、切り抜かない）

    private struct Transform {
        let scale: CGFloat
        let ox: CGFloat
        let oy: CGFloat
        let iw: CGFloat
        let ih: CGFloat
        func point(_ arr: [Float], _ i: Int) -> CGPoint {
            CGPoint(x: ox + CGFloat(arr[i * 3]) * iw * scale,
                    y: oy + CGFloat(arr[i * 3 + 1]) * ih * scale)
        }
        func norm(_ p: CGPoint) -> CGPoint {
            CGPoint(x: ox + p.x * iw * scale, y: oy + p.y * ih * scale)
        }
    }

    private func makeTransform(size: CGSize) -> Transform {
        let iw = snapshot.imageWidth > 0 ? CGFloat(snapshot.imageWidth) : 4
        let ih = snapshot.imageHeight > 0 ? CGFloat(snapshot.imageHeight) : 3
        let scale = min(size.width / iw, size.height / ih)
        return Transform(scale: scale,
                         ox: (size.width - iw * scale) / 2,
                         oy: (size.height - ih * scale) / 2,
                         iw: iw, ih: ih)
    }

    // MARK: - 本体

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let t = makeTransform(size: size)
        let snap = snapshot

        if isPlotInstance {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)))
            var grid = Path()
            for i in 1...3 {
                let gx = size.width * CGFloat(i) / 4
                let gy = size.height * CGFloat(i) / 4
                grid.move(to: CGPoint(x: gx, y: 0)); grid.addLine(to: CGPoint(x: gx, y: size.height))
                grid.move(to: CGPoint(x: 0, y: gy)); grid.addLine(to: CGPoint(x: size.width, y: gy))
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
        }

        // シルエット（プロット専用・最背面）
        if isPlotInstance && silhouetteEnabled {
            drawSilhouette(in: &ctx, t: t)
        }

        // 顔ポイントクラウド
        let face = snap.faceLandmarks
        if face.count >= 3 {
            var i = 0
            while i + 1 < face.count {
                let p = t.point(face, i / 3)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.8, y: p.y - 1.8, width: 3.6, height: 3.6)),
                         with: .color(PlotColors.face))
                i += 3
            }
        }

        // 姿勢スケルトン
        drawSkeleton(in: &ctx, points: snap.poseLandmarks, connections: Self.poseConnections,
                     color: PlotColors.pose, t: t)

        // 両手（掌/甲ティント＋手首バッジ）
        drawHand(in: &ctx, points: snap.leftHandLandmarks, base: PlotColors.leftBase, side: snap.leftHandSide, t: t)
        drawHand(in: &ctx, points: snap.rightHandLandmarks, base: PlotColors.rightBase, side: snap.rightHandSide, t: t)

        // 指先マーカー（指ごとの色）
        drawFingertipMarkers(in: &ctx, points: snap.leftHandLandmarks,
                             indexPinch: snap.leftIndexPinch, middlePinch: snap.leftMiddlePinch, t: t)
        drawFingertipMarkers(in: &ctx, points: snap.rightHandLandmarks,
                             indexPinch: snap.rightIndexPinch, middlePinch: snap.rightMiddlePinch, t: t)

        // 平滑化済み人差し指先（白リング）
        for tip in [snap.smoothedLeftIndexTip, snap.smoothedRightIndexTip] {
            if let tip = tip {
                let p = t.norm(tip)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)),
                           with: .color(.white), lineWidth: 2)
            }
        }

        if isPlotInstance && !snap.facePresent && !snap.posePresent && !snap.leftHandPresent && !snap.rightHandPresent {
            let text = Text("トラッキングデータなし").font(.system(size: 14)).foregroundColor(.gray)
            ctx.draw(ctx.resolve(text), at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
        }
    }

    // MARK: - 部品

    private func drawSkeleton(in ctx: inout GraphicsContext, points: [Float],
                              connections: [(Int, Int)], color: Color, t: Transform) {
        guard points.count >= 3 else { return }
        var path = Path()
        for (a, b) in connections {
            guard (b * 3 + 1) < points.count else { continue }
            path.move(to: t.point(points, a))
            path.addLine(to: t.point(points, b))
        }
        ctx.stroke(path, with: .color(color), lineWidth: 2)
        let n = points.count / 3
        for i in 0..<n {
            let p = t.point(points, i)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(color))
        }
    }

    private func tintForSide(base: Color, side: HandSide) -> Color {
        switch side {
        case .palm: return blend(base, PlotColors.palmTint, 0.55)
        case .back: return blend(base, PlotColors.backTint, 0.55)
        case .unknown: return base
        }
    }

    private func blend(_ a: Color, _ b: Color, _ t: CGFloat) -> Color {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t)
    }

    private func drawHand(in ctx: inout GraphicsContext, points: [Float], base: Color, side: HandSide, t: Transform) {
        guard points.count >= 21 * 3 else { return }
        let tinted = tintForSide(base: base, side: side)
        drawSkeleton(in: &ctx, points: points, connections: Self.handConnections, color: tinted, t: t)
        // 手首バッジ（掌 / 甲）
        if side != .unknown {
            let wrist = t.point(points, 0)
            let badge = CGRect(x: wrist.x - 13, y: wrist.y + 8, width: 26, height: 20)
            ctx.fill(Path(roundedRect: badge, cornerRadius: 6), with: .color(tinted.opacity(0.8)))
            let text = Text(side.rawValue).font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            ctx.draw(ctx.resolve(text), at: CGPoint(x: badge.midX, y: badge.midY), anchor: .center)
        }
    }

    private func drawFingertipMarkers(in ctx: inout GraphicsContext, points: [Float],
                                      indexPinch: Float?, middlePinch: Float?, t: Transform) {
        guard points.count >= 21 * 3 else { return }
        for (finger, tipIndex) in Self.fingerTips.enumerated() {
            let color = PlotColors.fingerColors[finger]
            let active: Bool
            switch finger {
            case 1: active = (indexPinch ?? 1) <= JudgmentEngine.pinchEnter
            case 2: active = (middlePinch ?? 1) <= JudgmentEngine.pinchEnter
            default: active = false
            }
            let p = t.point(points, tipIndex)
            let r: CGFloat = active ? 8 : 6
            if active {
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)),
                           with: .color(color.opacity(0.75)), lineWidth: 3)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(.white), lineWidth: 2)
        }
    }

    // MARK: - シルエット（Android v0.3.1: 首つなぎ・太め・半透明グレー）

    private func drawSilhouette(in ctx: inout GraphicsContext, t: Transform) {
        let pose = snapshot.poseLandmarks
        if pose.count >= 29 * 3 {
            func dist(_ a: Int, _ b: Int) -> CGFloat {
                let pa = t.point(pose, a), pb = t.point(pose, b)
                return hypot(pa.x - pb.x, pa.y - pb.y)
            }
            let shoulderW = max(dist(11, 12), 10)
            let limbW = min(90, max(9, shoulderW * 0.30))   // v0.3.1: 係数 0.30（約1.5倍に太く）
            let ls = t.point(pose, 11), rs = t.point(pose, 12)
            let lh = t.point(pose, 23), rh = t.point(pose, 24)
            let centroid = CGPoint(x: (ls.x + rs.x + lh.x + rh.x) / 4, y: (ls.y + rs.y + lh.y + rh.y) / 4)
            func expand(_ p: CGPoint) -> CGPoint {
                CGPoint(x: centroid.x + (p.x - centroid.x) * 1.15, y: centroid.y + (p.y - centroid.y) * 1.15)
            }
            // 胴体ポリゴン（重心から約15%拡張）
            var torso = Path()
            torso.move(to: expand(ls)); torso.addLine(to: expand(rs))
            torso.addLine(to: expand(rh)); torso.addLine(to: expand(lh))
            torso.closeSubpath()
            ctx.fill(torso, with: .color(PlotColors.silhouetteFill))

            // 四肢（太いストローク＋関節円）
            let limbSegs: [(Int, Int)] = [(11, 13), (13, 15), (12, 14), (14, 16), (23, 25), (25, 27), (24, 26), (26, 28)]
            for (a, b) in limbSegs {
                var path = Path()
                path.move(to: t.point(pose, a)); path.addLine(to: t.point(pose, b))
                ctx.stroke(path, with: .color(PlotColors.silhouetteStroke),
                           style: StrokeStyle(lineWidth: limbW, lineCap: .round, lineJoin: .round))
            }
            for joint in [13, 15, 14, 16, 25, 27, 24, 26, 28] {
                let p = t.point(pose, joint)
                let r = limbW * 0.55
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(PlotColors.silhouetteFill))
            }

            // 首（台形）＋頭部円 — v0.3.1 の「首つなぎ」仕様
            let shoulderMid = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
            let earMid = CGPoint(x: (t.point(pose, 7).x + t.point(pose, 8).x) / 2,
                                 y: (t.point(pose, 7).y + t.point(pose, 8).y) / 2)
            let headR = max(dist(7, 8) * 0.8, shoulderW * 0.19)
            let headCenter = CGPoint(x: earMid.x, y: earMid.y - headR * 0.25)
            let neckHalf = limbW * 0.5
            var neck = Path()
            neck.move(to: CGPoint(x: shoulderMid.x - neckHalf, y: shoulderMid.y))
            neck.addLine(to: CGPoint(x: shoulderMid.x + neckHalf, y: shoulderMid.y))
            neck.addLine(to: CGPoint(x: headCenter.x + neckHalf * 1.2, y: headCenter.y + headR * 0.6))
            neck.addLine(to: CGPoint(x: headCenter.x - neckHalf * 1.2, y: headCenter.y + headR * 0.6))
            neck.closeSubpath()
            ctx.fill(neck, with: .color(PlotColors.silhouetteFill))
            ctx.fill(Path(ellipseIn: CGRect(x: headCenter.x - headR, y: headCenter.y - headR,
                                            width: headR * 2, height: headR * 2)),
                     with: .color(PlotColors.silhouetteFill))
        }

        // 手のシルエット（掌 blob＋太い指ストローク）
        for hand in [snapshot.leftHandLandmarks, snapshot.rightHandLandmarks] {
            guard hand.count >= 21 * 3 else { continue }
            let iw = Float(snapshot.imageWidth), ih = Float(snapshot.imageHeight)
            let palmLen = HandGeometry.palmLengthPx(hand: hand, iw: iw, ih: ih) * Float(t.scale)
            guard palmLen > 1 else { continue }
            var cx: CGFloat = 0, cy: CGFloat = 0
            for i in [0, 5, 9, 13, 17] {
                let p = t.point(hand, i); cx += p.x; cy += p.y
            }
            let blobCenter = CGPoint(x: cx / 5, y: cy / 5)
            let blobR = CGFloat(palmLen) * 0.50
            ctx.fill(Path(ellipseIn: CGRect(x: blobCenter.x - blobR, y: blobCenter.y - blobR,
                                            width: blobR * 2, height: blobR * 2)),
                     with: .color(PlotColors.silhouetteFill))
            for chain in Self.fingerChains {
                var path = Path()
                for (j, idx) in chain.enumerated() {
                    let p = t.point(hand, idx)
                    if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                ctx.stroke(path, with: .color(PlotColors.silhouetteStroke),
                           style: StrokeStyle(lineWidth: CGFloat(palmLen) * 0.24, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
