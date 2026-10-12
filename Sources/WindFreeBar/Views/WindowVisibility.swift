import AppKit
import SwiftUI

/// Reports whether the hosting window is actually on screen. A `MenuBarExtra` window is ordered
/// out rather than destroyed when it closes, so `onAppear`/`onDisappear` alone aren't reliable.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { report(false); return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated { self?.report(note.name == NSWindow.willCloseNotification ? false : nil) }
                })
            }
            report(nil)
        }

        private func report(_ forced: Bool?) {
            let visible = forced ?? (window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false)
            guard visible != lastReported else { return }
            lastReported = visible
            onChange?(visible)
        }
    }
}
