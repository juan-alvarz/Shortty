import AppKit
import OSLog

/// Catches bugs that can't be made on demand. The last events in the editor are always kept in memory; Report in the
/// recent-captures strip records from there until it's stopped, then saves both to a text file.
@Observable final class BugReport {
    static let shared = BugReport()
    /// Events kept from before a recording starts.
    static let kept = 100
    static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("com.shortty.Shortty/Reports")

    private(set) var recording = false
    @ObservationIgnored private var lines: [String] = []
    @ObservationIgnored private let log = Logger(subsystem: "com.shortty.Shortty", category: "events")
    @ObservationIgnored private let clock: DateFormatter = {
        let clock = DateFormatter()
        clock.dateFormat = "yyyyMMdd-HHmmss.SSS"
        return clock
    }()

    func note(_ text: String) {
        lines.append("\(clock.string(from: .now)) \(text)")
        if !recording, lines.count > Self.kept { lines.removeFirst(lines.count - Self.kept) }
        log.notice("\(text, privacy: .public)") // the system log has it too, should Shortty crash
    }

    /// Presses and keys always; drags and scrolling only while recording, since they'd flush everything else out.
    func note(_ event: NSEvent, in window: NSWindow) {
        let names: [NSEvent.EventType: String] = [.leftMouseDown: "down", .leftMouseUp: "up", .rightMouseDown: "right down", .rightMouseUp: "right up",
                                                  .keyDown: "key", .leftMouseDragged: "drag", .scrollWheel: "scroll"]
        guard let name = names[event.type], recording || (event.type != .leftMouseDragged && event.type != .scrollWheel) else { return }
        let focus = "key \(window.isKeyWindow), active \(NSApp.isActive), keyboard \(AppPresence.holdsKeyboard)"
        if event.type == .keyDown { return note("key \(event.keyCode), modifiers \(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue), \(focus)") }
        let hit = window.contentView?.hitTest(event.locationInWindow).map { String(describing: type(of: $0)) } ?? "nothing"
        note("\(name) on \(hit) at \(Int(event.locationInWindow.x)),\(Int(event.locationInWindow.y)), clicks \(event.type == .scrollWheel ? 0 : event.clickCount), \(focus)")
        if recording, event.type == .leftMouseDown { layout(of: window).forEach(note) }
    }

    func start(in window: NSWindow?) {
        note("recording starts")
        recording = true
        layout(of: window).forEach(note)
    }

    /// Ends the recording and writes the report; nil if the file can't be written.
    func stop(in window: NSWindow?, to folder: URL = BugReport.folder) -> URL? {
        layout(of: window).forEach(note)
        note("recording ends")
        recording = false
        let stamp = clock.string(from: .now)
        let head = "Shortty \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?"), macOS \(ProcessInfo.processInfo.operatingSystemVersionString), report \(stamp)"
        let file = folder.appendingPathComponent("report-\(stamp).txt")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { lines.removeFirst(max(0, lines.count - Self.kept)) }
        return (try? ([head] + lines).joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)) != nil ? file : nil
    }

    /// Where the window and every drag source are, and what a click on each one's center would reach.
    private func layout(of window: NSWindow?) -> [String] {
        guard let window, let content = window.contentView else { return ["no window"] }
        func sources(in view: NSView) -> [DragSourceView] { (view as? DragSourceView).map { [$0] } ?? view.subviews.flatMap(sources) }
        return ["window \(window.frame), pointer \(window.mouseLocationOutsideOfEventStream)"] + sources(in: content).map { source in
            let frame = source.convert(source.bounds, to: nil)
            let hit = content.hitTest(CGPoint(x: frame.midX, y: frame.midY)).map { $0 === source ? "itself" : String(describing: type(of: $0)) } ?? "nothing"
            return "  source \(frame), shown \(source.convert(source.shownRect, to: nil)), hovering \(source.hovering), handle \(source.isEditorPicture), center hits \(hit)"
        }
    }
}
