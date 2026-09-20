import AppKit
import BrowspickCore
import SwiftUI

private final class Flag: @unchecked Sendable { var value = false }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let router = Router()
    private var appObserver: NSObjectProtocol?

    /// Fallback for source-app detection when the GURL event has no usable sender PID
    /// (e.g. links opened via /usr/bin/open).
    private var lastFrontmost: SourceApp?

    func applicationWillFinishLaunching(_ notification: Notification) {
        registerURLHandler()
        observeFrontmostApp()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.apply()
        showOnboardingIfNeeded()
    }

    /// Double-clicking the app in Finder/Spotlight shows onboarding until setup is
    /// complete, then Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if needsOnboarding {
            showOnboarding()
        } else {
            showSettings()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - URL interception

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let source = SourceAppResolver.resolve(from: event) ?? lastFrontmost
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        router.handle(url: url, source: source)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            router.handle(url: url, source: lastFrontmost)
        }
    }

    // MARK: - Source app fallback

    private func observeFrontmostApp() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           let id = front.bundleIdentifier {
            lastFrontmost = SourceApp(bundleId: id, name: front.localizedName ?? id)
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier else { return }
            let name = app.localizedName ?? id
            MainActor.assumeIsolated {
                self?.lastFrontmost = SourceApp(bundleId: id, name: name)
            }
        }
    }

    // MARK: - Default browser

    var isDefaultBrowser: Bool {
        guard let url = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundle = Bundle(url: handler) else { return false }
        return bundle.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    // MARK: - Onboarding

    /// Setup is incomplete while Browspick isn't the default browser or any
    /// installed profile-capable browser's data is TCC-blocked.
    private var needsOnboarding: Bool {
        !isDefaultBrowser || BrowserCatalog.detect().contains {
            ProfileCatalog.accessStatus(for: $0.bundleId) == .denied
        }
    }

    func showOnboardingIfNeeded() {
        if needsOnboarding { showOnboarding() }
    }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let state = AppState()
        let view = OnboardingView().environmentObject(state)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Browspick Setup"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }

    func setAsDefaultBrowser() {
        let failed = Flag()
        let group = DispatchGroup()
        for scheme in ["http", "https"] {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpenURLsWithScheme: scheme
            ) { error in
                if error != nil { failed.value = true }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if failed.value {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
            }
        }
    }

    // MARK: - Settings window

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let state = AppState()
        let view = SettingsView().environmentObject(state)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Browspick"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 1060, height: 560))
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        } else if notification.object as? NSWindow === onboardingWindow {
            onboardingWindow = nil
        } else {
            return
        }
        if !router.isPickerVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
