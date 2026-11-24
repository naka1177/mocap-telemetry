import SwiftUI

/// 判定結果の種別（Android 版 FeedResult に対応。本アプリは実行系を持たないため
/// 「実行」は「判定」に読み替え、練習モード相当の表示のみ）。
enum FeedResult: String {
    case judged = "判定"       // ジェスチャとして確定（バナー表示＋クールダウン入り）
    case info = "情報"         // 状態メモ（ピンチ成立・スクロール相当など）
    case rejected = "棄却"     // 短すぎる・曖昧などで不成立
    case suppressed = "抑制"   // バナークールダウン中に発生し抑止された

    var color: Color {
        switch self {
        case .judged: return Color(red: 0x2E / 255, green: 0xA0 / 255, blue: 0x43 / 255)
        case .info: return Color(red: 0x58 / 255, green: 0xA6 / 255, blue: 0xFF / 255)
        case .rejected: return Color(red: 0xCF / 255, green: 0x66 / 255, blue: 0x79 / 255)
        case .suppressed: return Color(red: 0xD2 / 255, green: 0x99 / 255, blue: 0x22 / 255)
        }
    }
}

/// 判定フィードの1行（Android 版 FeedEntry に対応）。
struct FeedEntry: Identifiable {
    let id: Int
    let wallTime: Date
    let input: String      // 認識した入力（例: 中指ピンチ）
    let action: String     // 対応する操作名（例: 確定タップ相当 ※表示のみ）
    let basis: String      // 根拠値（ピンチ比・保持時間など）
    let result: FeedResult
    let reason: String

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var displayLine: String {
        var s = "\(Self.timeFormat.string(from: wallTime))  \(input) → \(action)"
        if !basis.isEmpty { s += "  [\(basis)]" }
        s += "  ⇒ \(result.rawValue)"
        if !reason.isEmpty { s += " (\(reason))" }
        return s
    }
}

/// プロセス全体の判定履歴（最新100件、新しいものが下）。Android 版 ActionFeed に対応。
final class ActionFeed {
    static let maxEntries = 100

    private(set) var entries: [FeedEntry] = []
    private var nextId = 1

    @discardableResult
    func post(input: String, action: String, basis: String, result: FeedResult, reason: String = "") -> FeedEntry {
        let entry = FeedEntry(id: nextId, wallTime: Date(), input: input, action: action,
                              basis: basis, result: result, reason: reason)
        nextId += 1
        entries.append(entry)
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
        return entry
    }

    func clear() { entries.removeAll() }
}
