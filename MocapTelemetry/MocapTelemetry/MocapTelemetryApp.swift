import SwiftUI

/// Mocap Controller — iPad テレメトリ版エントリポイント。
///
/// Android 版（app.muse.mocap）のテレメトリ画面だけを iPad に移植したもの。
/// iOS では他アプリの操作（タップ／ホーム等）は OS の仕様上できないため、
/// 本アプリは「トラッキング＋可視化＋判定表示」専用（判定は表示のみで実行しない）。
@main
struct MocapTelemetryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
