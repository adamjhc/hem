import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel")
}

@MainActor
final class AppController: NSObject, NSWindowDelegate {
    let store = Store()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var panel: PanelWindow?
    private var settingsWindow: NSWindow?
    private var completedWindow: NSWindow?
    private var keyMonitor: Any?
    private var settingsWindowDelegate: SettingsWindowCloser?
    private var completedWindowDelegate: CompletedWindowCloser?
    private var ignoreResignUntil: Date?

    override init() {
        super.init()
        installMainMenu()
        configureStatusItem()
        store.onChange = { [weak self] in
            self?.refreshIcon()
            self?.resizePanelIfVisible()
        }
        refreshIcon()
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel()
            }
        }
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
            }
        }
        if CommandLine.arguments.contains("--show-completed") {
            DispatchQueue.main.async { [weak self] in
                self?.openCompletedTasks()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleKey(event) else { return event }
            return nil
        }
    }

    func prepareToQuit() {
        store.compact()
    }

    @objc func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @objc func openSettings() {
        hidePanel(deactivate: false)
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func openCompletedTasks() {
        hidePanel(deactivate: false)
        let window = completedWindow ?? makeCompletedWindow()
        completedWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func quit() {
        store.compact()
        NSApp.terminate(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        DispatchQueue.main.async { [weak self] in
            self?.hideIfClickedAway()
        }
    }

    private func hideIfClickedAway() {
        if let until = ignoreResignUntil, Date() < until { return }
        guard panel?.isVisible == true else { return }
        if settingsWindow?.isVisible == true || completedWindow?.isVisible == true {
            hidePanel(deactivate: false)
            return
        }
        if statusItemButtonContainsMouse() {
            return
        }
        hidePanel()
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        store.ensureBlankIfEmpty()
        store.focusedID = store.visibleItems.first?.id
        store.pendingCaret = .end
        resizePanel(panel)
        positionPanel(panel)
        ignoreResignUntil = Date().addingTimeInterval(0.4)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func hidePanel(deactivate: Bool = true) {
        store.compact()
        panel?.orderOut(nil)
        if deactivate, settingsWindow?.isVisible != true, completedWindow?.isVisible != true {
            NSApp.hide(nil)
        }
    }

    private func makePanel() -> PanelWindow {
        let panel = PanelWindow()
        panel.store = store
        panel.delegate = self
        let root = TodoListView(store: store, onHide: { [weak self] in
            self?.hidePanel()
        })
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.cornerCurve = .continuous
        panel.contentView = hosting
        return panel
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hem"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.center()
        let closer = SettingsWindowCloser()
        settingsWindowDelegate = closer
        window.delegate = closer
        return window
    }

    private func makeCompletedWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Completed Tasks"
        window.contentViewController = NSHostingController(rootView: CompletedTasksView(store: store))
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 480))
        window.center()
        let closer = CompletedWindowCloser()
        completedWindowDelegate = closer
        window.delegate = closer
        return window
    }

    private func resizePanelIfVisible() {
        guard let panel, panel.isVisible else { return }
        ignoreResignUntil = Date().addingTimeInterval(0.3)
        resizePanel(panel)
        positionPanel(panel)
    }

    private func resizePanel(_ panel: NSPanel) {
        let screen = panel.screen ?? statusItem.button?.window?.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) * 0.75
        let height = Layout.panelHeight(forItemCount: store.visibleItems.count, maxHeight: maxHeight)
        var frame = panel.frame
        let top = frame.maxY
        frame.size = NSSize(width: Layout.panelWidth, height: height)
        if frame.maxY != 0 {
            frame.origin.y = top - height
        }
        panel.setFrame(frame, display: true)
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? buttonRect
        let width = Layout.panelWidth
        let height = panel.frame.height
        var x = buttonRect.midX - width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - width - 8))
        let y = buttonRect.minY - height - 5
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "Hem"
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(remaining: 0)
        button.imagePosition = .imageOnly
        button.toolTip = "Hem"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusMenu()
            return
        }
        togglePanel()
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Completed Tasks", action: #selector(openCompletedTasks), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hem", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }

        if let button = statusItem.button {
            let point = NSPoint(x: 0, y: button.bounds.height + 2)
            menu.popUp(positioning: nil, at: point, in: button)
        }
    }

    private func refreshIcon() {
        let remaining = store.realCount
        statusItem.button?.image = StatusIcon.image(remaining: remaining)
        if remaining == 0 {
            statusItem.button?.toolTip = "Hem"
        } else if remaining == 1 {
            statusItem.button?.toolTip = "1 left"
        } else {
            statusItem.button?.toolTip = "\(remaining) left"
        }
    }

    private func statusItemButtonContainsMouse() -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let location = NSEvent.mouseLocation
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return rect.contains(location)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel?.isKeyWindow == true else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let keyCode = event.keyCode

        if keyCode == 53 {
            hidePanel()
            return true
        }

        if flags == .command, keyCode == 36, let id = store.focusedID {
            store.checkOff(id)
            return true
        }

        if flags == .command, keyCode == 51, let id = store.focusedID {
            store.delete(id)
            return true
        }

        if flags == .option, keyCode == 126, let id = store.focusedID {
            store.moveUp(id)
            return true
        }

        if flags == .option, keyCode == 125, let id = store.focusedID {
            store.moveDown(id)
            return true
        }

        return false
    }

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Hem")
        appMenu.addItem(withTitle: "Completed Tasks", action: #selector(openCompletedTasks), keyEquivalent: "")
        appMenu.items.last?.target = self
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.items.last?.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hem", action: #selector(quit), keyEquivalent: "q")
        appMenu.items.last?.target = self
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}

final class PanelWindow: NSPanel {
    weak var store: Store?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override var undoManager: UndoManager? {
        store?.undoManager
    }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelWidth, height: 80),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow
    }
}

private final class SettingsWindowCloser: NSObject, NSWindowDelegate {}

private final class CompletedWindowCloser: NSObject, NSWindowDelegate {}
