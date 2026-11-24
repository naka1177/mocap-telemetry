import SwiftUI
import AVFoundation

/// AVCaptureVideoPreviewLayer を SwiftUI で表示するラッパー。
struct PreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.bounds
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        previewLayer.frame = uiView.bounds
    }

    final class PreviewUIView: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            for sublayer in layer.sublayers ?? [] {
                if let preview = sublayer as? AVCaptureVideoPreviewLayer {
                    preview.frame = bounds
                }
            }
        }
    }
}
