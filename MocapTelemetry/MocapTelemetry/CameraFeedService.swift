import AVFoundation
import CoreMedia

/// 前面カメラのキャプチャ（Android 版 CameraPipeline の縮約移植）。
///
/// - 前面カメラ、4:3 フォーマット優先（センサー全域、16:9 クロップなし）
/// - データ出力・プレビューともミラー反転（自撮り表示 = MediaPipe への入力もミラー済み。
///   これにより handedness ラベルが本人の解剖学的な左右と一致する。Android と同じ前提）
/// - 向きは横向き（landscapeRight）固定。iPad を横置きするテレメトリ用途を想定
///   （縦向き対応は既知の制限として README に記載）
final class CameraFeedService: NSObject {
    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()

    /// フレーム受信コールバック（専用キューで呼ばれる）。
    var onFrame: ((CMSampleBuffer) -> Void)?

    /// 直近フレームのピクセルサイズ（TrackingEngine がスナップショットへ転記）。
    static var lastFrameSize: (width: Int, height: Int) = (0, 0)

    private let sessionQueue = DispatchQueue(label: "app.muse.mocap.camera.session")
    private let videoQueue = DispatchQueue(label: "app.muse.mocap.camera.frames")
    private var configured = false

    func configure() throws {
        guard !configured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw NSError(domain: "MocapTelemetry", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "前面カメラが見つかりません"])
        }
        pickFourThreeFormat(device: device)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "MocapTelemetry", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "カメラ入力を追加できません"])
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "MocapTelemetry", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "映像出力を追加できません"])
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            connection.isVideoMirrored = true
            if connection.isVideoOrientationSupported { connection.videoOrientation = .landscapeRight }
        }

        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect   // FIT_CENTER 相当（レターボックス、切り抜きなし）
        if let connection = previewLayer.connection {
            connection.isVideoMirrored = true
            if connection.isVideoOrientationSupported { connection.videoOrientation = .landscapeRight }
        }
        configured = true
    }

    /// 4:3 に最も近く、幅 1280 以下の最大フォーマットを選ぶ（無ければ最大の 4:3、
    /// それも無ければ既定プリセット .vga640x480=4:3 に落とす）。
    private func pickFourThreeFormat(device: AVCaptureDevice) {
        var best: AVCaptureDevice.Format? = nil
        var bestWidth: Int32 = 0
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.height > 0 else { continue }
            let aspect = Double(dims.width) / Double(dims.height)
            if abs(aspect - 4.0 / 3.0) > 0.02 { continue }
            if dims.width <= 1280 && dims.width > bestWidth {
                best = format; bestWidth = dims.width
            }
        }
        if let best = best {
            do {
                try device.lockForConfiguration()
                device.activeFormat = best
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                device.unlockForConfiguration()
                return
            } catch {
                // フォールバックへ
            }
        }
        session.sessionPreset = .vga640x480
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

extension CameraFeedService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
            Self.lastFrameSize = (Int(dims.width), Int(dims.height))
        }
        onFrame?(sampleBuffer)
    }
}
