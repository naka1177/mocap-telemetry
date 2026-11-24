import SwiftUI

/// テレメトリ画面（Android 版 TelemetryActivity に対応）。
/// 上: カメラプレビュー＋ランドマーク重ね＋判定バナー
/// 中: プロット専用ビュー（シルエット表示はこちらだけ）
/// 下: 統計パネル＋判定フィード
struct ContentView: View {
    @StateObject private var viewModel = TelemetryViewModel()
    @AppStorage("silhouetteEnabled") private var silhouetteEnabled = true

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    previewPanel
                    plotPanel
                    statsPanel
                    feedPanel
                }
                .padding(16)
            }
            // バージョン表示（画面右上に小さく）
            Text("2.3.1.i")
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mocap Controller")
                .font(.largeTitle.bold())
                .foregroundColor(Theme.textPrimary)
            Text("手と顔のトラッキング テレメトリ（iPad版・判定は表示のみ）")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
            HStack(spacing: 12) {
                Button(viewModel.isRunning ? "キャプチャ停止" : "キャプチャ開始") {
                    viewModel.toggle()
                }
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(viewModel.isRunning ? Color.red.opacity(0.75) : Theme.accentBlue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                Toggle("シルエット", isOn: $silhouetteEnabled)
                    .toggleStyle(.switch)
                    .tint(Theme.accentGreen)
                    .fixedSize()
                Spacer()
            }
            Toggle("判定バナー＋クールダウン", isOn: $viewModel.bannerEnabled)
                .toggleStyle(.switch)
                .tint(Theme.accentGreen)
                .fixedSize()
            HStack(spacing: 12) {
                Text("バナー表示 \(viewModel.bannerDurationSec, specifier: "%.1f")秒")
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                Slider(value: $viewModel.bannerDurationSec, in: 1...5, step: 0.5)
                    .disabled(!viewModel.bannerEnabled)
            }
            Text("状態: \(viewModel.statusMessage)")
                .font(.footnote)
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - プレビュー（ランドマーク重ね＋バナー）

    private var previewPanel: some View {
        ZStack {
            PreviewView(previewLayer: viewModel.camera.previewLayer)
            LandmarkPlotView(snapshot: viewModel.snapshot, isPlotInstance: false)
            if let banner = viewModel.bannerText {
                VStack {
                    Spacer()
                    Text(banner)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.panelStroke))
                    Spacer().frame(height: 18)
                }
                .transition(.opacity)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.panelStroke))
    }

    // MARK: - プロット（シルエットはこちらだけ）

    private var plotPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("プロット（シルエット表示）")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            LandmarkPlotView(snapshot: viewModel.snapshot, isPlotInstance: true,
                             silhouetteEnabled: silhouetteEnabled)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.panelStroke))
            // 指先カラーの凡例
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 4) {
                        Circle().fill(PlotColors.fingerColors[i]).frame(width: 9, height: 9)
                        Text(PlotColors.fingerNamesJa[i]).font(.caption2).foregroundColor(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.panelStroke))
    }

    // MARK: - 統計

    private var statsPanel: some View {
        let s = viewModel.snapshot
        return VStack(alignment: .leading, spacing: 6) {
            Text("統計")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Group {
                statRow("FPS", String(format: "%.1f", s.fps))
                statRow("推論 (手 / 顔 / 姿勢)",
                        String(format: "%.0f / %.0f / %.0f ms", s.handInferenceMs, s.faceInferenceMs, s.poseInferenceMs))
                statRow("構成 / デリゲート", "\(s.architecture) / \(s.delegateName)")
                statRow("顔", s.facePresent ? "✓" : "—")
                statRow("姿勢", s.posePresent
                        ? "✓（可視度 \(s.poseVisibility.map { String(format: "%.2f", $0) } ?? "—")）" : "—")
                statRow("頭部姿勢 (yaw / pitch)",
                        "\(s.headYaw.map { String(format: "%+.2f", $0) } ?? "—") / \(s.headPitch.map { String(format: "%+.2f", $0) } ?? "—")")
                statRow("左手", handStat(present: s.leftHandPresent, side: s.leftHandSide,
                                         index: s.leftIndexPinch, middle: s.leftMiddlePinch))
                statRow("右手", handStat(present: s.rightHandPresent, side: s.rightHandSide,
                                         index: s.rightIndexPinch, middle: s.rightMiddlePinch))
            }
            if !s.topBlendshapes.isEmpty {
                Text("ブレンドシェイプ上位")
                    .font(.subheadline.bold())
                    .foregroundColor(Theme.textPrimary)
                    .padding(.top, 4)
                ForEach(Array(s.topBlendshapes.enumerated()), id: \.offset) { _, item in
                    statRow(item.name, String(format: "%.2f", item.score))
                }
            }
            if let error = s.error {
                Text("エラー: \(error)").font(.caption).foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.panelStroke))
    }

    private func handStat(present: Bool, side: HandSide, index: Float?, middle: Float?) -> String {
        guard present else { return "—" }
        let idx = index.map { String(format: "%.2f", $0) } ?? "—"
        let mid = middle.map { String(format: "%.2f", $0) } ?? "—"
        return "✓ \(side.rawValue)（ピンチ 人差し \(idx) / 中指 \(mid)）"
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value).font(.footnote.monospacedDigit()).foregroundColor(Theme.textPrimary)
        }
    }

    // MARK: - 判定フィード（最新が下、自動スクロール）

    private var feedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("判定フィード")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button("クリア") { viewModel.clearFeed() }
                    .font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(viewModel.feedEntries) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(entry.result.color).frame(width: 8, height: 8).padding(.top, 4)
                            Text(entry.displayLine)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(Theme.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .defaultScrollAnchor(.bottom)
        }
        .padding(14)
        .background(Theme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.panelStroke))
    }
}
