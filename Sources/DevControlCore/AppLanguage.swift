import Foundation

/// User-facing language of generated text. It follows the system's preferred
/// language: any "es*" preference selects Spanish; everything else selects
/// English.
public enum AppLanguage: String, Sendable {
    case spanish
    case english

    /// Resolves the language from the system's preferred languages.
    public static var current: AppLanguage {
        let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return code.hasPrefix("es") ? .spanish : .english
    }

    /// Picks the Spanish or English variant for a generated string.
    public func pick(es: String, en: String) -> String {
        self == .spanish ? es : en
    }

    /// Simple plural helper: 1 → singular, anything else → plural.
    public static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        count == 1 ? singular : plural
    }
}
