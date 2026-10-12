import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // `windfreebar://oauth?code=…` comes back from the browser as a Get URL Apple Event.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        Task { @MainActor in BrowserAuthenticator.shared.handle(url) }
    }
}

@main
struct WindFreeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var store = ACStore()

    /// `--window` opens the panel in a regular window, handy for development.
    private static let debugWindow = CommandLine.arguments.contains("--window")

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(store)
        } label: {
            MenuBarLabel(state: store.state, ready: store.phase == .ready)
        }
        .menuBarExtraStyle(.window)

        Window("WindFree", id: "debug") {
            RootView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(Self.debugWindow ? .presented : .suppressed)
    }
}

struct MenuBarLabel: View {
    let state: ACState
    let ready: Bool

    var body: some View {
        Group {
            if ready && state.isOn {
                Image(systemName: "air.conditioner.horizontal.fill")
                Text(Format.degrees(state.setpoint))
            } else {
                Image(systemName: "air.conditioner.horizontal")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ready && state.isOn ? "Air conditioner, \(Format.degrees(state.setpoint))" : "Air conditioner, off")
    }
}
