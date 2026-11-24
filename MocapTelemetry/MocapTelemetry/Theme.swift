import SwiftUI

/// Android 版 v0.3.x のダークテーマ（深ネイビー #0B1220 → 黒）と
/// LandmarkPlotView の描画色をそのまま移植した定数集。
enum Theme {
    static let backgroundTop = Color(red: 0x0B / 255, green: 0x12 / 255, blue: 0x20 / 255)
    static let backgroundBottom = Color.black
    static let panelFill = Color.white.opacity(0.06)
    static let panelStroke = Color.white.opacity(0.14)
    static let accentBlue = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
    static let accentGreen = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// LandmarkPlotView（Android）の Paint 色に対応する Canvas 用カラー。
enum PlotColors {
    /// 顔ポイントクラウド: argb(140, 0, 229, 255)
    static let face = Color(red: 0, green: 229 / 255, blue: 1).opacity(140 / 255)
    /// 姿勢スケルトン: rgb(255, 213, 79)
    static let pose = Color(red: 1, green: 213 / 255, blue: 79 / 255)
    /// 左手ベース: rgb(105, 240, 174) 緑
    static let leftBase = Color(red: 105 / 255, green: 240 / 255, blue: 174 / 255)
    /// 右手ベース: rgb(255, 138, 128) 赤ピンク
    static let rightBase = Color(red: 1, green: 138 / 255, blue: 128 / 255)
    /// 掌（PALM）ティント: rgb(255, 176, 66) 暖色アンバー
    static let palmTint = Color(red: 1, green: 176 / 255, blue: 66 / 255)
    /// 甲（BACK）ティント: rgb(92, 156, 255) 冷色ブルー
    static let backTint = Color(red: 92 / 255, green: 156 / 255, blue: 1)
    /// シルエット: argb(100〜110, 165, 165, 178) 半透明グレー
    static let silhouetteFill = Color(red: 165 / 255, green: 165 / 255, blue: 178 / 255).opacity(100 / 255)
    static let silhouetteStroke = Color(red: 165 / 255, green: 165 / 255, blue: 178 / 255).opacity(110 / 255)
    /// 指先マーカー色（両手共通・指ごと）: 親指=赤 / 人差し指=青 / 中指=緑 / 薬指=オレンジ / 小指=紫
    static let fingerColors: [Color] = [
        Color(red: 1, green: 82 / 255, blue: 82 / 255),          // 親指 #FF5252
        Color(red: 68 / 255, green: 138 / 255, blue: 1),         // 人差し指 #448AFF
        Color(red: 105 / 255, green: 240 / 255, blue: 174 / 255), // 中指 #69F0AE
        Color(red: 1, green: 171 / 255, blue: 64 / 255),         // 薬指 #FFAB40
        Color(red: 179 / 255, green: 136 / 255, blue: 1),        // 小指 #B388FF
    ]
    static let fingerNamesJa = ["親指", "人差し指", "中指", "薬指", "小指"]
}
