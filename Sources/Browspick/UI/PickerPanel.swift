import AppKit
import BrowspickCore
import SwiftUI

struct PickerEntry: Identifiable {
    let id = UUID()
    let target: Target
    let title: String
    let icon: NSImage?
    /// Pre-selected because it matches the last pick for this host/path.
    var isSuggested = false
    /// Icon is a profile avatar photo — render it clipped to a circle.
    var isAvatar = false
}

/// Borderless floating panel shown at the mouse position when no rule matches.
/// Keyboard: 1-9 / arrows / Tab / Return select, Esc cancels, ⌃ = background, ⌘ = save rule.
final class PickerPanel: NSPanel, NSWindowDelegate {
    private var keyMonitor: Any?
    private var selection: PickerSelection!
    private var onCancel: () -> Void = {}
    private var urlString = ""

    init(url: URL,
         entries: [PickerEntry],
         initialIndex: Int = 0,
         onPick: @escaping (PickerEntry, NSEvent.ModifierFlags) -> Void,
         onCancel: @escaping () -> Void) {
        let selection = PickerSelection()
        selection.entries = entries
        selection.selectedIndex = entries.indices.contains(initialIndex) ? initialIndex : 0
        selection.onPick = { entry in onPick(entry, NSEvent.modifierFlags) }
        let view = PickerView(url: url.absoluteString, selection: selection)
        let hosting = NSHostingView(rootView: view)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.selection = selection
        self.onCancel = onCancel
        self.urlString = url.absoluteString

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        delegate = self
        contentView = hosting

        let fitting = hosting.fittingSize
        setContentSize(NSSize(width: 640, height: max(fitting.height, 10)))

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    /// Centers the panel on the screen the mouse is on.
    func showCentered() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2,
                                   y: frame.midY - self.frame.height / 2))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
    }

    @discardableResult
    private func handleKey(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch event.keyCode {
        case 53: // Esc
            close()
            return true
        case 36, 76: // Return / keypad Enter
            if let entry = selection.selected { selection.onPick?(entry) }
            return true
        case 123, 126: // left / up
            selection.move(by: -1)
            return true
        case 124, 125: // right / down
            selection.move(by: 1)
            return true
        case 48: // Tab
            selection.move(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        default:
            break
        }
        if chars == "c" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urlString, forType: .string)
            selection.copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.selection.copied = false
            }
            return true
        }
        if let digit = chars.first, digit.isNumber, digit != "0" {
            let index = Int(String(digit))! - 1
            if index < selection.entries.count {
                selection.selectedIndex = index
                if let entry = selection.selected { selection.onPick?(entry) }
            }
            return true
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        onCancel()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
