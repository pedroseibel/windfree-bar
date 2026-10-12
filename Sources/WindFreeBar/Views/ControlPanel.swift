import ServiceManagement
import SwiftUI

struct ControlPanel: View {
    @Environment(ACStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: ACState { store.state }
    private var accent: Color { Color(nsColor: ModeColor.ns(state.mode)) }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(accent: accent)
                .padding(.horizontal, 18)
                .padding(.top, 16)

            VStack(spacing: 14) {
                temperatureRow
                SetpointControl(value: state.setpoint, range: state.setpointRange, step: state.setpointStep, accent: accent) {
                    store.setSetpoint($0)
                } nudge: {
                    store.nudgeSetpoint(by: $0)
                }
                tiles
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .disabled(!store.isEnabled)

            PanelFooter()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state.isOn)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: state.windFree)
    }

    private var temperatureRow: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(state.setpoint.rounded()))")
                    .font(.system(size: 46, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: state.setpoint))
                Text("°C")
                    .font(.system(size: 18, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Target temperature")
            .accessibilityValue(Format.temperature(state.setpoint))
            Spacer()
            if state.supportsWindFree {
                Toggle(isOn: Binding(get: { state.windFree }, set: { store.setWindFree($0) })) {
                    Label("WindFree", systemImage: "circle.grid.3x3.fill")
                        .font(.callout.weight(.medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(accent)
                .help("Cool through the panel's micro-holes with the blade closed, so there's no direct draft")
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            OptionTile(title: String(localized: "Mode"), symbol: Labels.modeSymbol(state.mode), options: state.supportedModes,
                       selection: state.mode, label: Labels.mode) { store.setMode($0) }
            OptionTile(title: String(localized: "Fan"), symbol: "fan", options: state.supportedFanModes, available: state.availableFanModes,
                       selection: state.fanMode, label: Labels.fan) { store.setFan($0) }
            OptionTile(title: String(localized: "Swing"), symbol: "fan.oscillation", options: state.supportedSwings,
                       selection: state.swing, label: Labels.swing) { store.setSwing($0) }
            OptionTile(title: String(localized: "Preset"), symbol: Labels.presetSymbol(state.windFree ? "off" : state.optionalMode),
                       options: state.presets, selection: state.windFree ? "off" : state.optionalMode,
                       label: Labels.preset) { store.setPreset($0) }
        }
    }
}

// MARK: - Header

private struct PanelHeader: View {
    @Environment(ACStore.self) private var store
    let accent: Color

    var body: some View {
        let state = store.state
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.deviceName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let t = state.roomTemperature {
                        Label(Format.temperature(t), systemImage: "thermometer.medium")
                            .accessibilityLabel("Room \(Format.temperature(t))")
                    }
                    if let h = state.humidity {
                        Label("\(Int(h))%", systemImage: "humidity")
                            .accessibilityLabel("Humidity \(Int(h)) percent")
                    }
                    if let w = state.powerWatts, state.isOn {
                        Label("\(Int(w)) W", systemImage: "bolt")
                            .accessibilityLabel("Drawing \(Int(w)) watts")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }
            Spacer()
            Button {
                store.setPower(!state.isOn)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(state.isOn ? accent : Color.gray.opacity(0.6))
            .disabled(!store.isOnline)
            .keyboardShortcut(.return, modifiers: .command)
            .help(state.isOn ? Text("Turn off (⌘↩)") : Text("Turn on (⌘↩)"))
            .accessibilityLabel("Power")
            .accessibilityValue(state.isOn ? String(localized: "power.on", defaultValue: "On")
                                           : String(localized: "power.off", defaultValue: "Off"))
            .accessibilityAddTraits(.isToggle)
        }
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

// MARK: - Setpoint

/// The standard slider, so it gets the system's Liquid Glass knob, tick marks, keyboard control
/// and VoiceOver for free, flanked by glass step buttons that repeat while held.
struct SetpointControl: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color
    let set: (Double) -> Void
    let nudge: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            stepButton("minus", delta: -1, label: String(localized: "Lower temperature"))
            Slider(value: Binding(get: { value }, set: set), in: range, step: step,
                   label: { Text("Target temperature") },
                   minimumValueLabel: { Text(Format.degrees(range.lowerBound)) },
                   maximumValueLabel: { Text(Format.degrees(range.upperBound)) },
                   tick: { SliderTick($0) })
            // macOS draws a slider's label beside the track; the −/+ and the big number say it
            // already, and VoiceOver still reads it.
            .labelsHidden()
            .tint(accent)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityValue(Format.temperature(value))
            stepButton("plus", delta: 1, label: String(localized: "Raise temperature"))
        }
        .sensoryFeedback(.levelChange, trigger: Int(value.rounded()))
    }

    private func stepButton(_ symbol: String, delta: Double, label: String) -> some View {
        Button { nudge(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Tiles

struct OptionTile: View {
    let title: String
    let symbol: String
    let options: [String]
    var available: [String]? = nil
    let selection: String
    let label: (String) -> String
    let choose: (String) -> Void

    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { selection }, set: choose)) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                        .selectionDisabled(available.map { !$0.contains(option) } ?? false)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .frame(height: 18)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.caption2).foregroundStyle(.secondary)
                    Text(label(selection)).font(.callout.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

// MARK: - Footer

private struct PanelFooter: View {
    @Environment(ACStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(error)
                } else if !store.isOnline {
                    Label("The unit is offline", systemImage: "wifi.slash")
                } else if let updated = store.lastUpdated {
                    TimelineView(.periodic(from: .now, by: 15)) { _ in
                        // Formatted in the app's language (set on the root), so it reads
                        // "Updated 2 minutes ago" or "Atualizado há 2 minutos", never a mix.
                        Text("Updated \(updated, format: .relative(presentation: .named))")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
            Spacer()
            SettingsMenu()
        }
    }
}

struct SettingsMenu: View {
    @Environment(ACStore.self) private var store
    @ViewState private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            if store.devices.count > 1 {
                Picker("Air conditioner", selection: Binding(get: { store.deviceId ?? "" }, set: { store.selectDevice($0) })) {
                    ForEach(store.devices) { Text($0.displayName).tag($0.deviceId) }
                }
                Divider()
            }
            if let light = store.state.displayLight {
                Toggle("Display light", isOn: Binding(get: { light }, set: { store.setDisplayLight($0) }))
            }
            if let clean = store.state.autoClean {
                Toggle("Auto clean after cooling", isOn: Binding(get: { clean }, set: { store.setAutoClean($0) }))
            }
            if let usage = store.state.filterUsage, let status = store.state.filterStatus {
                if status == "wash" {
                    Text("Filter \(Int(usage))% used, time to wash it")
                } else {
                    Text("Filter \(Int(usage))% used")
                }
            }
            Divider()
            Toggle("Open at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            Button("Refresh") { Task { await store.refresh() } }
                .keyboardShortcut("r")
            Button("Sign Out") { Task { await store.signOut() } }
            Divider()
            Button("Quit WindFree Bar") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Settings")
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            store.errorMessage = error.localizedDescription
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
