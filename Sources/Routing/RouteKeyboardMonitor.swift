import AppKit

@MainActor
final class RouteKeyboardMonitor {
    private var token: Any?

    func install(handler: @escaping (NSEvent) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token); self.token = nil }
    }

}
