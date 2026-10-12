import AppKit

/// The subset of a Samsung room AC's SmartThings status the UI cares about.
struct ACState: Equatable, Sendable {
    var isOn = false
    var mode = "cool"
    var supportedModes = ["auto", "cool", "dry", "fan"]
    var fanMode = "auto"
    var supportedFanModes = ["auto", "low", "medium", "high", "turbo"]
    /// The unit narrows this per mode (WindFree and dry allow only `auto`).
    var availableFanModes = ["auto", "low", "medium", "high", "turbo"]
    var swing = "fixed"
    var supportedSwings = ["fixed", "vertical", "horizontal", "all"]
    var optionalMode = "off"
    var supportedOptionalModes = ["off", "sleep", "quiet", "speed", "windFree", "windFreeSleep"]
    var setpoint: Double = 24
    var setpointRange: ClosedRange<Double> = 16...30
    var setpointStep: Double = 1
    var roomTemperature: Double?
    var humidity: Double?
    var powerWatts: Double?
    var displayLight: Bool?
    var autoClean: Bool?
    var cleaningNow = false
    var filterUsage: Double?
    var filterStatus: String?

    var windFree: Bool { optionalMode == "windFree" || optionalMode == "windFreeSleep" }
    var supportsWindFree: Bool { supportedOptionalModes.contains("windFree") }

    /// Preset modes other than WindFree, which gets its own toggle.
    var presets: [String] { supportedOptionalModes.filter { !$0.hasPrefix("windFree") } }

    init() {}

    init(_ status: DeviceStatus) {
        let main = status["main"] ?? [:]
        func value(_ capability: String, _ attribute: String) -> JSONValue? { main[capability]?[attribute]?.value }
        func string(_ c: String, _ a: String) -> String? { value(c, a)?.string }
        func number(_ c: String, _ a: String) -> Double? { value(c, a)?.number }
        func list(_ c: String, _ a: String) -> [String]? { value(c, a).map(\.strings).flatMap { $0.isEmpty ? nil : $0 } }

        isOn = string("switch", "switch") == "on"
        mode = string("airConditionerMode", "airConditionerMode") ?? mode
        supportedModes = list("airConditionerMode", "supportedAcModes") ?? supportedModes
        fanMode = string("airConditionerFanMode", "fanMode") ?? fanMode
        supportedFanModes = list("airConditionerFanMode", "supportedAcFanModes") ?? supportedFanModes
        availableFanModes = list("airConditionerFanMode", "availableAcFanModes") ?? supportedFanModes
        swing = string("fanOscillationMode", "fanOscillationMode") ?? swing
        supportedSwings = list("fanOscillationMode", "supportedFanOscillationModes") ?? supportedSwings
        optionalMode = string("custom.airConditionerOptionalMode", "acOptionalMode") ?? optionalMode
        supportedOptionalModes = list("custom.airConditionerOptionalMode", "supportedAcOptionalMode") ?? supportedOptionalModes
        setpoint = number("thermostatCoolingSetpoint", "coolingSetpoint") ?? setpoint
        if let range = value("thermostatCoolingSetpoint", "coolingSetpointRange"),
           let lo = range["minimum"]?.number, let hi = range["maximum"]?.number, lo < hi {
            setpointRange = lo...hi
            setpointStep = range["step"]?.number ?? 1
        } else if let lo = number("custom.thermostatSetpointControl", "minimumSetpoint"),
                  let hi = number("custom.thermostatSetpointControl", "maximumSetpoint"), lo < hi {
            setpointRange = lo...hi
        }
        roomTemperature = number("temperatureMeasurement", "temperature")
        humidity = number("relativeHumidityMeasurement", "humidity")
        powerWatts = value("powerConsumptionReport", "powerConsumption")?["power"]?.number
        displayLight = string("samsungce.airConditionerLighting", "lighting").map { $0 == "on" }
        autoClean = string("custom.autoCleaningMode", "autoCleaningMode").map { $0 == "on" }
        cleaningNow = string("custom.autoCleaningMode", "operatingState") == "autoClean"
        filterUsage = number("custom.dustFilter", "dustFilterUsage")
        filterStatus = string("custom.dustFilter", "dustFilterStatus")
    }
}

/// Human labels for SmartThings enum values.
enum Labels {
    static func mode(_ m: String) -> String {
        switch m {
        case "auto", "aIComfort": "Auto"
        case "cool": "Cool"
        case "dry": "Dry"
        case "fan", "wind": "Fan"
        case "heat": "Heat"
        default: m.capitalized
        }
    }

    static func modeSymbol(_ m: String) -> String {
        switch m {
        case "cool": "snowflake"
        case "dry": "drop"
        case "fan", "wind": "fan"
        case "heat": "sun.max"
        default: "sparkles"
        }
    }

    static func fan(_ f: String) -> String {
        switch f {
        case "auto": "Auto"
        case "low": "Low"
        case "medium": "Medium"
        case "high": "High"
        case "turbo": "Turbo"
        default: f.capitalized
        }
    }

    static func swing(_ s: String) -> String {
        switch s {
        case "fixed": "Off"
        case "vertical": "Up–down"
        case "horizontal": "Left–right"
        case "all": "All"
        default: s.capitalized
        }
    }

    static func preset(_ p: String) -> String {
        switch p {
        case "off": "None"
        case "sleep": "Sleep"
        case "quiet": "Quiet"
        case "speed": "Fast"
        case "windFree": "WindFree"
        case "windFreeSleep": "WindFree sleep"
        default: p.capitalized
        }
    }

    static func presetSymbol(_ p: String) -> String {
        switch p {
        case "sleep": "moon"
        case "quiet": "speaker.wave.1"
        case "speed": "hare"
        default: "circle.slash"
        }
    }
}

/// Accent colour per mode for the controls.
enum ModeColor {
    static func ns(_ mode: String) -> NSColor {
        switch mode {
        case "cool": NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        case "dry": NSColor(red: 0.1, green: 0.75, blue: 0.68, alpha: 1)
        case "fan", "wind": NSColor.systemGray
        case "heat": NSColor.systemOrange
        default: NSColor(red: 0.2, green: 0.75, blue: 0.45, alpha: 1)
        }
    }
}
