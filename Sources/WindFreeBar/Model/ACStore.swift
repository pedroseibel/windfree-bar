import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ACStore {
    enum Phase: Equatable {
        case needsClient
        case signedOut
        case signingIn
        case loading
        case noDevice
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var state = ACState()
    private(set) var devices: [DeviceSummary] = []
    private(set) var deviceId: String?
    private(set) var lastUpdated: Date?
    private(set) var isOnline = true
    var errorMessage: String?

    /// Polls faster while the panel is on screen.
    var isPanelVisible = false {
        didSet {
            guard isPanelVisible != oldValue else { return }
            startPolling(refreshNow: isPanelVisible)
        }
    }

    var deviceName: String { devices.first { $0.deviceId == deviceId }?.displayName ?? String(localized: "Air conditioner") }

    @ObservationIgnored private let tokens = TokenProvider()
    @ObservationIgnored private var api: SmartThingsAPI { SmartThingsAPI(tokens: tokens) }
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var rereadTask: Task<Void, Never>?
    @ObservationIgnored private var setpointTask: Task<Void, Never>?
    @ObservationIgnored private var commandChain: Task<Void, Never>?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var lastHealthCheck = Date.distantPast
    @ObservationIgnored private var rateLimitedUntil = Date.distantPast
    @ObservationIgnored private var systemAsleep = false
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// Optimistic values the device hasn't confirmed yet. A poll that still reports the old value
    /// mustn't flip the UI back, so each pending edit is re-applied until it matches or times out.
    private struct Pending {
        let apply: (inout ACState) -> Void
        let confirmed: (ACState) -> Bool
        let deadline: Date
    }
    @ObservationIgnored private var pending: [String: Pending] = [:]

    init() {
        observeSystem()
        Task { await bootstrap() }
    }

    // MARK: Lifecycle

    func bootstrap() async {
        guard CredentialStore.loadClient() != nil else { phase = .needsClient; return }
        guard await tokens.isSignedIn else { phase = .signedOut; return }
        phase = .loading
        await loadDevices()
        startPolling(refreshNow: false)
    }

    func signIn() async {
        phase = .signingIn
        errorMessage = nil
        do {
            try await tokens.signIn()
            await bootstrap()
        } catch AuthError.cancelled {
            phase = .signedOut
        } catch {
            errorMessage = error.localizedDescription
            phase = .signedOut
        }
    }

    func cancelSignIn() {
        BrowserAuthenticator.shared.cancel()
    }

    func signOut() async {
        pollTask?.cancel()
        await tokens.signOut()
        devices = []
        deviceId = nil
        state = ACState()
        phase = .signedOut
    }

    func saveClient(id: String, secret: String) async {
        do {
            try CredentialStore.saveClient(OAuthClient(clientId: id, clientSecret: secret, redirectURI: "windfreebar://oauth"))
            await bootstrap()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectDevice(_ id: String) {
        deviceId = id
        pending = [:]
        CredentialStore.savePrefs(.init(deviceId: id))
        Task { await refresh() }
    }

    private func loadDevices() async {
        do {
            devices = try await api.airConditioners()
            let saved = CredentialStore.loadPrefs().deviceId
            deviceId = devices.first { $0.deviceId == saved }?.deviceId ?? devices.first?.deviceId
            if deviceId == nil { phase = .noDevice; return }
            await refresh()
        } catch {
            handle(error)
        }
    }

    // MARK: Polling

    /// 15 s with the panel open, 2 min in the background, 5 min when the unit is off, twice as
    /// long in Low Power Mode, and nothing while the Mac sleeps or is locked.
    private var pollInterval: TimeInterval {
        var interval: TimeInterval = isPanelVisible ? 15 : (state.isOn ? 120 : 300)
        if ProcessInfo.processInfo.isLowPowerModeEnabled { interval *= 2 }
        return interval
    }

    private func startPolling(refreshNow: Bool) {
        pollTask?.cancel()
        guard !systemAsleep, phase == .ready || phase == .loading else { return }
        pollTask = Task { [weak self] in
            if refreshNow { await self?.refresh() }
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval / 5))
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard let deviceId, phase == .ready || phase == .loading, !refreshing, Date() > rateLimitedUntil else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            var fresh = ACState(try await api.status(of: deviceId))
            let now = Date()
            pending = pending.filter { _, p in !p.confirmed(fresh) && p.deadline > now }
            for p in pending.values { p.apply(&fresh) }
            if fresh != state { state = fresh }

            if now.timeIntervalSince(lastHealthCheck) > 300 || errorMessage != nil {
                lastHealthCheck = now
                let online = try await api.isOnline(deviceId)
                if online != isOnline { isOnline = online }
            }
            lastUpdated = now
            if phase != .ready { phase = .ready }
            if errorMessage != nil { errorMessage = nil }
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if case AuthError.notSignedIn = error { phase = .signedOut; return }
        if let auth = error as? AuthError, auth.requiresSignIn { phase = .signedOut; return }
        if case APIError.rateLimited(let until) = error { rateLimitedUntil = until }
        if (error as? URLError)?.code == .cancelled { return }
        errorMessage = error.localizedDescription
        if phase == .loading, !devices.isEmpty { phase = .ready }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ asleep: Bool) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.systemAsleep = asleep
                    if asleep { self.pollTask?.cancel() } else { self.startPolling(refreshNow: true) }
                }
            }
            observers.append((center, token))
        }
        on(workspace, NSWorkspace.willSleepNotification, true)
        on(workspace, NSWorkspace.screensDidSleepNotification, true)
        on(workspace, NSWorkspace.sessionDidResignActiveNotification, true)
        on(distributed, .init("com.apple.screenIsLocked"), true)
        on(workspace, NSWorkspace.didWakeNotification, false)
        on(workspace, NSWorkspace.screensDidWakeNotification, false)
        on(workspace, NSWorkspace.sessionDidBecomeActiveNotification, false)
        on(distributed, .init("com.apple.screenIsUnlocked"), false)
    }

    // MARK: Commands

    var isEnabled: Bool { state.isOn && isOnline }

    func setPower(_ on: Bool) {
        send([DeviceCommand(capability: "switch", command: on ? "on" : "off")], key: "power",
             apply: { $0.isOn = on }, confirmed: { $0.isOn == on })
    }

    func setMode(_ mode: String) {
        // Setting a mode doesn't power the unit on by itself.
        var commands = [DeviceCommand(capability: "airConditionerMode", command: "setAirConditionerMode", arguments: [.string(mode)])]
        if !state.isOn { commands.insert(DeviceCommand(capability: "switch", command: "on"), at: 0) }
        send(commands, key: "mode", apply: { $0.mode = mode; $0.isOn = true }, confirmed: { $0.mode == mode && $0.isOn })
    }

    func setFan(_ fan: String) {
        send([DeviceCommand(capability: "airConditionerFanMode", command: "setFanMode", arguments: [.string(fan)])], key: "fan",
             apply: { $0.fanMode = fan }, confirmed: { $0.fanMode == fan })
    }

    func setSwing(_ swing: String) {
        send([DeviceCommand(capability: "fanOscillationMode", command: "setFanOscillationMode", arguments: [.string(swing)])], key: "swing",
             apply: { $0.swing = swing }, confirmed: { $0.swing == swing })
    }

    func setPreset(_ preset: String) {
        send([DeviceCommand(capability: "custom.airConditionerOptionalMode", command: "setAcOptionalMode", arguments: [.string(preset)])],
             key: "preset",
             apply: {
                 $0.optionalMode = preset
                 // WindFree only runs with the fan on auto.
                 if preset.hasPrefix("windFree") { $0.fanMode = "auto"; $0.availableFanModes = ["auto"] }
                 else { $0.availableFanModes = $0.supportedFanModes }
             },
             confirmed: { $0.optionalMode == preset })
    }

    func setWindFree(_ on: Bool) {
        setPreset(on ? (state.optionalMode == "sleep" ? "windFreeSleep" : "windFree") : "off")
    }

    func setDisplayLight(_ on: Bool) {
        send([DeviceCommand(capability: "samsungce.airConditionerLighting", command: "setLightingLevel", arguments: [.string(on ? "on" : "off")])],
             key: "light", apply: { $0.displayLight = on }, confirmed: { $0.displayLight == on })
    }

    func setAutoClean(_ on: Bool) {
        send([DeviceCommand(capability: "custom.autoCleaningMode", command: "setAutoCleaningMode", arguments: [.string(on ? "on" : "off")])],
             key: "autoClean", apply: { $0.autoClean = on }, confirmed: { $0.autoClean == on })
    }

    /// Updates the UI immediately; the command goes out once the value stops changing.
    func setSetpoint(_ value: Double) {
        let clamped = min(max(value, state.setpointRange.lowerBound), state.setpointRange.upperBound)
        let stepped = (clamped / state.setpointStep).rounded() * state.setpointStep
        guard stepped != state.setpoint else { return }
        let apply: (inout ACState) -> Void = { $0.setpoint = stepped }
        apply(&state)
        pending["setpoint"] = Pending(apply: apply, confirmed: { $0.setpoint == stepped }, deadline: .now + 15)
        setpointTask?.cancel()
        setpointTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.send([DeviceCommand(capability: "thermostatCoolingSetpoint", command: "setCoolingSetpoint", arguments: [.number(stepped)])],
                      key: "setpoint", apply: apply, confirmed: { $0.setpoint == stepped })
        }
    }

    func nudgeSetpoint(by delta: Double) {
        setSetpoint(state.setpoint + delta * state.setpointStep)
    }

    /// Applies the change locally, then sends commands one at a time so they reach the unit in order.
    private func send(_ commands: [DeviceCommand], key: String,
                      apply: @escaping (inout ACState) -> Void, confirmed: @escaping (ACState) -> Bool) {
        guard let deviceId else { return }
        let previous = state
        apply(&state)
        pending[key] = Pending(apply: apply, confirmed: confirmed, deadline: .now + 12)

        let prior = commandChain
        commandChain = Task { [weak self] in
            await prior?.value
            guard let self else { return }
            do {
                try await self.api.execute(commands, on: deviceId)
                self.scheduleReread()
            } catch {
                self.pending[key] = nil
                self.state = previous
                self.handle(error)
            }
        }
    }

    /// Samsung units report changes back within ~1–6 s. Read twice, shared by all recent commands.
    private func scheduleReread() {
        rereadTask?.cancel()
        rereadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.refresh()
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
