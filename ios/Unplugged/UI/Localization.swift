import SwiftUI

// In-app language switching. English is the source language; Lithuanian
// translations live in Localizable.xcstrings. Text("...") literals localize
// through the `\.locale` environment; everything that builds a plain String
// (labels, banners, notifications) goes through `tr` / `trKey`.

enum Lang: String, CaseIterable, Identifiable, Codable {
    case en, lt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .en: "English"
        case .lt: "Lietuvių"
        }
    }

    var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_IE")
        case .lt: Locale(identifier: "lt_LT")
        }
    }
}

enum L10n {
    private static let storageKey = "unplugged.lang"

    nonisolated(unsafe) private(set) static var current: Lang = {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Lang.init(rawValue:)) ?? .en
    }()

    nonisolated(unsafe) private static var bundle: Bundle = bundle(for: current)

    static var locale: Locale { current.locale }

    static func set(_ lang: Lang) {
        current = lang
        bundle = bundle(for: lang)
        UserDefaults.standard.set(lang.rawValue, forKey: storageKey)
    }

    private static func bundle(for lang: Lang) -> Bundle {
        Bundle.main.path(forResource: lang.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }
}

/// Localize a literal or interpolated string (same keys as `Text("...")`).
func tr(_ value: String.LocalizationValue) -> String { L10n.string(value) }

/// Localize a dynamic string by looking it up as a catalog key. Unknown keys
/// (user input, proper names, already-translated text) come back unchanged.
func trKey(_ key: String) -> String { L10n.string(key) }
