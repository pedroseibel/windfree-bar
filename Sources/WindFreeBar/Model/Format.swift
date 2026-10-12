import Foundation

/// The language macOS picked for the app from its localizations (English or Brazilian
/// Portuguese). Dates and numbers use it too, so a sentence never mixes languages.
enum AppLanguage {
    static let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
}

enum Format {
    /// "21°" with the unit's own scale; the locale doesn't convert it.
    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    static func temperature(_ value: Double, unit: String = "C") -> String {
        Measurement(value: value, unit: unit == "F" ? UnitTemperature.fahrenheit : .celsius)
            .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(AppLanguage.locale))
    }
}
