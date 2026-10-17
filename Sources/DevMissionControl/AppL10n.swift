import DevControlCore

/// Picks user-interface strings from the system language (`AppLanguage`).
/// Language changes take effect on the next app launch.
enum L10n {
    static let lang = AppLanguage.current

    /// Returns the Spanish or English variant of a UI string.
    static func t(_ es: String, _ en: String) -> String {
        lang.pick(es: es, en: en)
    }
}
