import AppKit
import SwiftUI

enum CaretTarget: Equatable {
    case end
    case char(Int)
    case x(CGFloat)
}

enum CaretCommand {
    case moveLeftAtStart
    case moveRightAtEnd
    case moveUp(x: CGFloat)
    case moveDown(x: CGFloat)
    case enter(caret: Int)
    case smartBackspace
}

enum CaretMetrics {
    static var font: NSFont {
        NSFont.systemFont(ofSize: Layout.fontSize)
    }

    static func width(of text: String) -> CGFloat {
        if text.isEmpty { return 0 }
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    static func index(in text: String, closestToX x: CGFloat) -> Int {
        let ns = text as NSString
        if x <= 0 || ns.length == 0 { return 0 }

        var previousWidth: CGFloat = 0
        for i in 0..<ns.length {
            let prefix = ns.substring(to: i + 1)
            let width = width(of: prefix)
            if width <= x {
                previousWidth = width
                continue
            }
            let distancePrevious = abs(x - previousWidth)
            let distanceNow = abs(x - width)
            return distancePrevious < distanceNow ? i : i + 1
        }
        return ns.length
    }

    static func index(for target: CaretTarget, in text: String) -> Int {
        let length = (text as NSString).length
        switch target {
        case .end:
            return length
        case .char(let index):
            return min(max(index, 0), length)
        case .x(let x):
            return index(in: text, closestToX: x)
        }
    }
}

struct CaretField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Bool
    var pendingCaret: CaretTarget?
    var onFocus: () -> Void
    var onCaretApplied: () -> Void
    var onCommand: (CaretCommand) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CaretNSTextField {
        let field = CaretNSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = "New task"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = CaretMetrics.font
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.usesSingleLineMode = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.watch(field)
        return field
    }

    func updateNSView(_ field: CaretNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.scheduleApply(on: field)
    }

    static func dismantleNSView(_ field: CaretNSTextField, coordinator: Coordinator) {
        coordinator.stopWatching()
        field.delegate = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CaretField
        private var applyGeneration = 0
        private var observers: [NSObjectProtocol] = []
        private var lastCaret: Int = 0

        init(_ parent: CaretField) {
            self.parent = parent
        }

        func watch(_ field: CaretNSTextField) {
            stopWatching()
            field.onAttachedToWindow = { [weak self, weak field] in
                guard let self, let field else { return }
                self.scheduleApply(on: field)
            }
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self, weak field] notification in
                    guard let self, let field, field.window === notification.object as? NSWindow else { return }
                    self.scheduleApply(on: field)
                }
            )
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSTextView.didChangeSelectionNotification,
                    object: nil,
                    queue: .main
                ) { [weak self, weak field] notification in
                    guard let self, let field, field.currentEditor() === notification.object as? NSTextView else { return }
                    self.lastCaret = field.currentEditor()?.selectedRange.location ?? self.lastCaret
                }
            )
        }

        func stopWatching() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
        }

        func scheduleApply(on field: CaretNSTextField) {
            applyGeneration += 1
            let generation = applyGeneration
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, generation == self.applyGeneration else { return }
                self.applyFocusAndCaret(on: field)
            }
        }

        func applyFocusAndCaret(on field: CaretNSTextField) {
            guard parent.isFocused else { return }
            guard let window = field.window else { return }

            let lostEditor = field.currentEditor() == nil
            if window.firstResponder !== field && window.firstResponder !== field.currentEditor() {
                window.makeFirstResponder(field)
            }

            guard let textView = field.currentEditor() as? NSTextView else { return }
            if let target = parent.pendingCaret {
                let index = CaretMetrics.index(for: target, in: field.stringValue)
                textView.setSelectedRange(NSRange(location: index, length: 0))
                lastCaret = index
                parent.onCaretApplied()
            } else if lostEditor {
                let length = (field.stringValue as NSString).length
                textView.setSelectedRange(NSRange(location: min(lastCaret, length), length: 0))
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocus()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let range = textView.selectedRange
            let text = textView.string as NSString
            let caret = range.location
            let atStart = caret == 0
            let atEnd = caret == text.length
            let x = CaretMetrics.width(of: text.substring(to: min(caret, text.length)))

            switch commandSelector {
            case #selector(NSResponder.moveLeft(_:)):
                guard atStart else { return false }
                parent.onCommand(.moveLeftAtStart)
                return true
            case #selector(NSResponder.moveRight(_:)):
                guard atEnd else { return false }
                parent.onCommand(.moveRightAtEnd)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onCommand(.moveUp(x: x))
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onCommand(.moveDown(x: x))
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onCommand(.enter(caret: caret))
                return true
            case #selector(NSResponder.deleteBackward(_:)):
                guard atStart, range.length == 0 else { return false }
                parent.onCommand(.smartBackspace)
                return true
            default:
                return false
            }
        }
    }
}

final class CaretNSTextField: NSTextField {
    var onAttachedToWindow: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Layout.fontSize + 8)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let coordinator = delegate as? CaretField.Coordinator {
            coordinator.parent.onFocus()
        }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onAttachedToWindow?()
        }
    }
}
