import Foundation
import AVFoundation
import CoreMedia

/// テレメトリ画面の状態管理。カメラ → TrackingEngine → JudgmentEngine をつなぐ。
@MainActor
final class TelemetryViewModel: ObservableObject {
    @Published private(set) var snapshot = TrackingSnapshot()
    @Published private(set) var feedEntries: [FeedEntry] = []
    @Published private(set) var bannerText: String? = nil
    @Published private(set) var isRunning = false
    @Published var statusMessage = "停止中"

    /// 判定バナー＋クールダウンのON/OFF（UserDefaultsに保存、既定ON）
    @Published var bannerEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(bannerEnabled, forKey: "bannerEnabled")
            judgment.bannerEnabled = bannerEnabled
        }
    }
    /// バナー表示時間（秒、UserDefaultsに保存、既定2.5）
    @Published var bannerDurationSec: Double = 2.5 {
        didSet {
            UserDefaults.standard.set(bannerDurationSec, forKey: "bannerDurationSec")
            judgment.bannerDurationSec = bannerDurationSec
        }
    }

    let camera = CameraFeedService()
    private let engine = TrackingEngine()
    private let judgment = JudgmentEngine()

    init() {
        // バナー設定を UserDefaults から復元し、判定エンジンへ反映する
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "bannerEnabled") != nil {
            bannerEnabled = defaults.bool(forKey: "bannerEnabled")
        }
        if defaults.object(forKey: "bannerDurationSec") != nil {
            bannerDurationSec = defaults.double(forKey: "bannerDurationSec")
        }
        judgment.bannerEnabled = bannerEnabled
        judgment.bannerDurationSec = bannerDurationSec
        camera.onFrame = { [weak self] sampleBuffer in
            self?.engine.detect(sampleBuffer: sampleBuffer)
        }
        engine.onSnapshot = { [weak self] snap in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.judgment.process(snap)
                self.snapshot = snap
                self.feedEntries = self.judgment.feed.entries
                self.bannerText = self.judgment.bannerText
                if let error = snap.error {
                    self.statusMessage = "実行中（エラー: \(error)）"
                }
            }
        }
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard granted else {
                    self.statusMessage = "カメラ許可が必要です（設定アプリで許可してください）"
                    return
                }
                do {
                    try self.camera.configure()
                    try self.engine.start()
                    self.judgment.reset()
                    self.camera.start()
                    self.isRunning = true
                    self.statusMessage = "実行中（\(self.engine.delegateName) / \(self.engine.architecture)）"
                } catch {
                    self.statusMessage = "開始に失敗: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        camera.stop()
        engine.stop()
        isRunning = false
        bannerText = nil
        statusMessage = "停止中"
    }

    func clearFeed() {
        judgment.feed.clear()
        feedEntries = []
    }
}
