import AppKit

/// Capture Text (Shottr's "Instant Text/QR Recognition"): drag over an area and its QR code / barcode contents,
/// or else its text, go straight to the clipboard. No editor; a short notice says what was copied.
enum TextCapture {
    static func run(pasteboard: NSPasteboard = .general) async {
        guard ScreenCapture.hasPermission(),
              let rect = await RegionSelector.select(hint: "Drag over text or a QR code   ·   Esc to cancel")
        else { return }
        try? await Task.sleep(for: .milliseconds(80)) // the selection overlay must be gone before capturing
        guard let image = await ScreenCapture.frame(of: rect) else { return }
        let job = SendableImage(image: image)
        let found = await Task.detached(priority: .userInitiated) { TextRecognition.readable(in: job.image) }.value
        FloatingToast.show(copy(found, to: pasteboard), near: rect)
    }

    /// Puts what was found on the pasteboard and returns the notice to show.
    static func copy(_ found: Readable?, to pasteboard: NSPasteboard) -> String {
        guard let found else { return "No text found" }
        let value: String
        let message: String
        switch found {
        case .code(let payload):
            value = payload
            message = "Copied QR code: \(payload.count > 40 ? payload.prefix(40) + "…" : payload)"
        case .text(let text):
            value = text
            let lines = text.split(separator: "\n").count
            message = lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text"
        }
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        return message
    }
}
