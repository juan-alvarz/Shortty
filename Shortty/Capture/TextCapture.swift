import AppKit

/// Capture Text (Shottr's "Instant Text/QR Recognition"): drag over an area and its QR code / barcode contents,
/// or else its text, go straight to the clipboard. No editor; a short notice says what was copied.
enum TextCapture {
    static func run() async {
        guard let rect = await RegionSelector.select(hint: "Drag over text or a QR code   ·   Esc to cancel"),
              let image = await ScreenCapture.frame(of: rect)
        else { return }
        let found = await Task.detached(priority: .userInitiated) { TextRecognition.readable(in: image) }.value
        FloatingToast.show(copy(found, to: .general), near: rect)
    }

    /// Puts what was found on the pasteboard and returns the notice to show.
    static func copy(_ found: Readable?, to pasteboard: NSPasteboard) -> String {
        guard let found else { return "No text found" }
        pasteboard.clearContents()
        switch found {
        case .code(let payload):
            pasteboard.setString(payload, forType: .string)
            return "Copied QR code: \(payload.count > 40 ? payload.prefix(40) + "…" : payload)"
        case .text(let text):
            pasteboard.setString(text, forType: .string)
            let lines = text.split(separator: "\n").count
            return lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text"
        }
    }
}
