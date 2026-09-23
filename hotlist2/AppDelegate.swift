import AppKit

@main
enum Hotlist2Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        adoptHotlist2Shortcut()
        controller = AppController()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.prepareToQuit()
    }
}

private func adoptHotlist2Shortcut() {
    let key = "KeyboardShortcuts_togglePanel"
    guard UserDefaults.standard.object(forKey: key) == nil else { return }
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.adamcox.hotlist2.plist")
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let shortcut = plist[key] else { return }
    UserDefaults.standard.set(shortcut, forKey: key)
}
