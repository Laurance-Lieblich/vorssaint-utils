// SPDX-License-Identifier: GPL-3.0-or-later
// Custom (Laurance): bridge between Vorssaint and Laurance's separate
// App Switcher app (bundle id com.laurance.appswitcher).
//
// Everything for the integration lives in this one file so upstream updates
// rarely touch it. Vorssaint reads and writes App Switcher's own preferences
// domain, then tells the running switcher to reload them through a
// distributed notification. Commands (pause, open settings, launch at login)
// and live state (paused, launch at login) travel the same way.
//
// Protocol (must match AppSwitcher/VorssaintBridge.swift):
//   com.laurance.appswitcher.prefsChanged  object: "vorssaint" | "appswitcher"
//   com.laurance.appswitcher.command       userInfo: action (String), value (Bool)
//   com.laurance.appswitcher.state         userInfo: paused, launchAtLogin (Bool)
//   com.laurance.appswitcher.requestState

import AppKit
import SwiftUI

extension DefaultsKey {
    static let panelShowLaurAppSwitcher = "panelShowLaurAppSwitcher"
}

final class AppSwitcherLink: ObservableObject {
    static let shared = AppSwitcherLink()

    static let bundleID = "com.laurance.appswitcher"
    private static let prefsChanged = Notification.Name("com.laurance.appswitcher.prefsChanged")
    private static let command = Notification.Name("com.laurance.appswitcher.command")
    private static let state = Notification.Name("com.laurance.appswitcher.state")
    private static let requestState = Notification.Name("com.laurance.appswitcher.requestState")
    private static let sender = "vorssaint"

    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var isInstalled = false
    /// Reported by the running switcher; not stored in its preferences.
    @Published private(set) var paused = false
    @Published private(set) var launchAtLogin = false

    @Published var size: Size = .medium
    @Published var includeMinimized = false
    @Published var showAllDesktops = false
    @Published var showPreviews = true
    @Published var previewDelay: Double = 0.08
    @Published var showDesktopNameInSwitcher = false
    @Published var showDesktopNameInMenuBar = false
    @Published var showDesktopPopup = true
    @Published var showInMenuBar = false

    private let store = UserDefaults(suiteName: AppSwitcherLink.bundleID)
    private let center = DistributedNotificationCenter.default()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private init() {
        refreshRunning()
        reload()
        observe(center, Self.prefsChanged) { [weak self] note in
            guard (note.object as? String) != Self.sender else { return }
            self?.reload()
        }
        observe(center, Self.state) { [weak self] note in
            self?.apply(note.userInfo)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard Self.isSwitcher(note) else { return }
            self?.refreshRunning()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.requestStateUpdate() }
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard Self.isSwitcher(note) else { return }
            self?.refreshRunning()
            self?.paused = false
        }
        requestStateUpdate()
    }

    deinit {
        observers.forEach { $0.0.removeObserver($0.1) }
    }

    private func observe(_ nc: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping (Notification) -> Void) {
        observers.append((nc, nc.addObserver(forName: name, object: nil, queue: .main, using: handler)))
    }

    private static func isSwitcher(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
            .bundleIdentifier == bundleID
    }

    // MARK: State

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID)
    }

    func refreshRunning() {
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        isInstalled = isRunning || appURL != nil
    }

    /// Re-reads App Switcher's preferences from disk.
    func reload() {
        CFPreferencesAppSynchronize(Self.bundleID as CFString)
        guard let d = store else { return }
        size = Size(rawValue: d.string(forKey: "switcherSize") ?? "") ?? .medium
        includeMinimized = d.bool(forKey: "includeMinimized")
        showAllDesktops = d.bool(forKey: "showAllDesktops")
        showPreviews = d.object(forKey: "showPreviews") as? Bool ?? true
        let delay = d.object(forKey: "previewDelay") as? Double
        previewDelay = (delay == nil || delay == 0.25) ? 0.08 : delay!   // mirrors App Switcher's default
        showDesktopNameInSwitcher = d.bool(forKey: "showDesktopNameInSwitcher")
        showDesktopNameInMenuBar = d.bool(forKey: "showDesktopNameInMenuBar")
        showDesktopPopup = d.object(forKey: "showDesktopPopup") as? Bool ?? true
        showInMenuBar = d.bool(forKey: "showInMenuBar")
    }

    private func apply(_ info: [AnyHashable: Any]?) {
        if let value = info?["paused"] as? Bool { paused = value }
        if let value = info?["launchAtLogin"] as? Bool { launchAtLogin = value }
    }

    // MARK: Writing

    private func write(_ value: Any, _ key: String) {
        store?.set(value, forKey: key)
        CFPreferencesAppSynchronize(Self.bundleID as CFString)
        center.postNotificationName(Self.prefsChanged, object: Self.sender,
                                    userInfo: nil, deliverImmediately: true)
    }

    func binding(_ keyPath: ReferenceWritableKeyPath<AppSwitcherLink, Bool>, key: String) -> Binding<Bool> {
        Binding(get: { self[keyPath: keyPath] },
                set: { self[keyPath: keyPath] = $0; self.write($0, key) })
    }

    var sizeBinding: Binding<Size> {
        Binding(get: { self.size },
                set: { self.size = $0; self.write($0.rawValue, "switcherSize") })
    }

    var previewDelayBinding: Binding<Double> {
        Binding(get: { self.previewDelay },
                set: { self.previewDelay = $0; self.write($0, "previewDelay") })
    }

    var pausedBinding: Binding<Bool> {
        Binding(get: { self.paused },
                set: { self.paused = $0; self.send($0 ? "pause" : "resume") })
    }

    var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { self.launchAtLogin },
                set: { self.launchAtLogin = $0; self.send("setLaunchAtLogin", value: $0) })
    }

    // MARK: Commands

    private func send(_ action: String, value: Bool? = nil) {
        var info: [String: Any] = ["action": action]
        if let value { info["value"] = value }
        center.postNotificationName(Self.command, object: Self.sender,
                                    userInfo: info, deliverImmediately: true)
    }

    func requestStateUpdate() {
        center.postNotificationName(Self.requestState, object: Self.sender,
                                    userInfo: nil, deliverImmediately: true)
    }

    func launch(then action: (() -> Void)? = nil) {
        guard let url = appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.refreshRunning()
                action?()
            }
        }
    }

    func openSettings() {
        if isRunning {
            send("openSettings")
        } else {
            launch { self.send("openSettings") }
        }
    }
}

// MARK: - Icon

/// Three app outlines in a row: the same mark as App Switcher's menu bar icon.
/// `size` works like an SF Symbol's point size: the whole mark is about as wide
/// as a wide symbol at that size (1.45×), so it lines up with the icons beside it.
struct AppSwitcherGlyph: View {
    var size: CGFloat = 13

    var body: some View {
        let width = size * 1.45
        let side = width / 3.6              // three boxes plus two gaps of 0.3 × side
        let gap = side * 0.3
        let line = max(1, side * 0.2)
        HStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .strokeBorder(lineWidth: line)
                    .frame(width: side, height: side)
            }
        }
        .frame(width: width, height: size)
        .accessibilityElement()
        .accessibilityLabel("App Switcher")
    }
}

/// A panel section's icon: the App Switcher glyph for its section, the SF
/// Symbol for everything else.
struct PanelSectionIcon: View {
    let id: PanelSectionID
    var size: CGFloat = 13
    var weight: Font.Weight = .semibold

    var body: some View {
        if id == .appSwitcher {
            AppSwitcherGlyph(size: size)
        } else {
            Image(systemName: id.symbolName)
                .font(.system(size: size, weight: weight))
        }
    }
}

// MARK: - Menu bar panel section

struct AppSwitcherPanelSection: View {
    @ObservedObject private var link = AppSwitcherLink.shared
    var collapsible = true

    var body: some View {
        PanelSection(.appSwitcher, title: "App Switcher", collapsible: collapsible) {
            Group {
                if link.isRunning {
                    controls
                } else {
                    notRunning
                }
            }
            .panelCard()
            .onAppear {
                link.refreshRunning()
                link.reload()
                link.requestStateUpdate()
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Pause switcher", caption: link.paused ? "⌘Tab uses macOS's switcher" : nil,
                isOn: link.pausedBinding)
            Divider()
            HStack {
                Text("Size")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.74))
                Spacer(minLength: 8)
                Picker("", selection: link.sizeBinding) {
                    ForEach(AppSwitcherLink.Size.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
            }
            row("Apps from all desktops", isOn: link.binding(\.showAllDesktops, key: "showAllDesktops"))
            row("Window previews", isOn: link.binding(\.showPreviews, key: "showPreviews"))
            row("Include minimized windows",
                isOn: link.binding(\.includeMinimized, key: "includeMinimized"))
            row("Desktop name popup", isOn: link.binding(\.showDesktopPopup, key: "showDesktopPopup"))
            Divider()
            Button {
                link.openSettings()
            } label: {
                HStack {
                    Text("App Switcher Settings…")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var notRunning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(link.isInstalled ? "App Switcher isn't running." : "App Switcher isn't installed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if link.isInstalled {
                Button("Open App Switcher") { link.launch() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.74))
                if let caption {
                    Text(caption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

// MARK: - Settings page

struct AppSwitcherLinkSettings: View {
    @ObservedObject private var link = AppSwitcherLink.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AppSwitcherGlyph(size: 21)   // ~30 pt wide: sits inside the 44 pt tile
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Switcher").font(.headline)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if link.isInstalled && !link.isRunning {
                        Button("Open") { link.launch() }
                    }
                }
            }

            if link.isRunning {
                Section {
                    Toggle("Pause switcher", isOn: link.pausedBinding)
                    Toggle("Launch at login", isOn: link.launchAtLoginBinding)
                } footer: {
                    Text("Pausing hands ⌘Tab back to macOS's own switcher until you resume or App Switcher relaunches.")
                }
            }

            Section("Switcher") {
                Picker("Size", selection: link.sizeBinding) {
                    ForEach(AppSwitcherLink.Size.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show apps from all desktops",
                       isOn: link.binding(\.showAllDesktops, key: "showAllDesktops"))
                    .help("Off: only apps with windows on this desktop. On: every open app, like the macOS switcher.")
                Toggle("Include minimized windows",
                       isOn: link.binding(\.includeMinimized, key: "includeMinimized"))
            }

            Section("Window previews") {
                Toggle("Show window previews", isOn: link.binding(\.showPreviews, key: "showPreviews"))
                LabeledContent("Preview delay") {
                    HStack {
                        Slider(value: link.previewDelayBinding, in: 0...1, step: 0.02)
                            .frame(maxWidth: 220)
                        Text(String(format: "%.2f s", link.previewDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(!link.showPreviews)
            }

            Section {
                Toggle("Desktop name popup when switching desktops",
                       isOn: link.binding(\.showDesktopPopup, key: "showDesktopPopup"))
                Toggle("Show desktop name in the switcher",
                       isOn: link.binding(\.showDesktopNameInSwitcher, key: "showDesktopNameInSwitcher"))
                Toggle("Show desktop name in the menu bar",
                       isOn: link.binding(\.showDesktopNameInMenuBar, key: "showDesktopNameInMenuBar"))
            } header: {
                Text("Desktops")
            } footer: {
                Text("Desktop names themselves are edited in App Switcher's own Settings.")
            }

            Section("Menu bar") {
                Toggle("Show App Switcher's own menu bar icon",
                       isOn: link.binding(\.showInMenuBar, key: "showInMenuBar"))
            }

            Section {
                Button("Open App Switcher Settings…") { link.openSettings() }
                    .disabled(!link.isInstalled)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            link.refreshRunning()
            link.reload()
            link.requestStateUpdate()
        }
    }

    private var statusText: String {
        if link.isRunning { return link.paused ? "Running — paused" : "Running" }
        return link.isInstalled ? "Not running" : "Not installed"
    }
}
