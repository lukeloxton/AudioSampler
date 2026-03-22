import AppKit
import ScreenCaptureKit

@MainActor
class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let captureEngine = CaptureEngine()
    private var recorder: WAVRecorder?

    private var isRecording = false
    private var selectedBundleID: String? = nil  // nil = all system audio
    private var lastRecordingURL: URL?
    private var recordingStart: Date?
    private var recordingTimer: Timer?

    private var outputDirectory: URL = {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Music/AudioSampler")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Menu items updated dynamically
    private let recordItem = NSMenuItem()
    private let timerItem = NSMenuItem()
    private let lastFileItem = NSMenuItem()
    private let sourceMenu = NSMenu()

    override init() {
        super.init()
        setupStatusItem()
        setupMenu()
    }

    // MARK: Setup

    private func setupStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "AudioSampler")
        statusItem.button?.imageScaling = .scaleProportionallyDown
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "AudioSampler", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Source submenu
        let sourceItem = NSMenuItem(title: "Source", action: nil, keyEquivalent: "")
        sourceItem.submenu = sourceMenu
        menu.addItem(sourceItem)
        menu.addItem(.separator())

        // Timer (shown only while recording)
        timerItem.title = "00:00"
        timerItem.isEnabled = false
        timerItem.isHidden = true
        menu.addItem(timerItem)

        // Record toggle
        recordItem.title = "Start Recording"
        recordItem.target = self
        recordItem.action = #selector(toggleRecording)
        recordItem.keyEquivalent = "r"
        recordItem.keyEquivalentModifierMask = .command
        menu.addItem(recordItem)
        menu.addItem(.separator())

        // Last recording
        lastFileItem.title = "No recordings yet"
        lastFileItem.isEnabled = false
        menu.addItem(lastFileItem)
        menu.addItem(.separator())

        // Show folder
        let folderItem = NSMenuItem(title: "Show Recordings Folder", action: #selector(showFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: NSMenuDelegate — refresh source list on open

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            await self.refreshSourceMenu()
        }
    }

    private func refreshSourceMenu() async {
        sourceMenu.removeAllItems()

        // All system audio option
        let allItem = NSMenuItem(title: "All System Audio", action: #selector(selectSource(_:)), keyEquivalent: "")
        allItem.target = self
        allItem.representedObject = nil as String?
        allItem.state = selectedBundleID == nil ? .on : .off
        sourceMenu.addItem(allItem)
        sourceMenu.addItem(.separator())

        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            return
        }

        let audioApps = content.applications
            .filter { isAudioApp($0) }
            .sorted { $0.applicationName < $1.applicationName }

        for app in audioApps {
            let item = NSMenuItem(title: app.applicationName, action: #selector(selectSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleIdentifier
            item.state = selectedBundleID == app.bundleIdentifier ? .on : .off
            sourceMenu.addItem(item)
        }
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        selectedBundleID = sender.representedObject as? String
        // Update checkmarks
        for item in sourceMenu.items {
            item.state = (item.representedObject as? String) == selectedBundleID ? .on : .off
        }
        // "All System Audio" has nil representedObject
        if let first = sourceMenu.items.first, (sender.representedObject as? String) == nil {
            first.state = .on
        }
    }

    // MARK: Recording

    @objc private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        Task {
            do {
                fputs("AudioSampler: startRecording called\n", stderr)
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                fputs("AudioSampler: got content, displays=\(content.displays.count)\n", stderr)
                guard let display = content.displays.first else {
                    fputs("AudioSampler: no display found\n", stderr)
                    return
                }

                fputs("AudioSampler: building filter, selectedBundleID=\(selectedBundleID ?? "nil")\n", stderr)
                let filter: SCContentFilter
                if let bundleID = selectedBundleID,
                   let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) {
                    filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                } else {
                    filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                }
                fputs("AudioSampler: filter built\n", stderr)

                let filename = "Sample-\(dateString()).wav"
                let outputURL = outputDirectory.appendingPathComponent(filename)
                fputs("AudioSampler: writing to \(outputURL.path)\n", stderr)
                let recorder = WAVRecorder(outputURL: outputURL)
                try recorder.start()
                fputs("AudioSampler: recorder started\n", stderr)
                self.recorder = recorder

                captureEngine.onAudioBuffer = { [weak recorder] buffer in
                    recorder?.append(buffer)
                }

                fputs("AudioSampler: starting capture\n", stderr)
                try await captureEngine.startCapture(filter: filter)
                fputs("AudioSampler: capture started\n", stderr)

                isRecording = true
                recordingStart = Date()
                recordItem.title = "Stop Recording"
                timerItem.isHidden = false
                statusItem.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")

                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.updateTimer() }
                }
                RunLoop.main.add(timer, forMode: .common)
                recordingTimer = timer

            } catch {
                fputs("AudioSampler startRecording error: \(error)\n", stderr)
                showError(error)
            }
        }
    }

    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        Task {
            do {
                try await captureEngine.stopCapture()
            } catch {
                // Non-fatal — continue to finalise the file
            }

            let rec = recorder
            recorder = nil

            rec?.stop { [weak self] url in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let url {
                        self.lastRecordingURL = url
                        self.lastFileItem.title = url.lastPathComponent
                        self.lastFileItem.isEnabled = true
                        self.lastFileItem.target = self
                        self.lastFileItem.action = #selector(Self.revealLastFile)
                    }
                }
            }

            isRecording = false
            timerItem.isHidden = true
            recordItem.title = "Start Recording"
            statusItem.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "AudioSampler")
        }
    }

    // MARK: Helpers

    private func updateTimer() {
        guard let start = recordingStart else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let m = elapsed / 60
        let s = elapsed % 60
        timerItem.title = String(format: "%02d:%02d", m, s)
    }

    @objc private func revealLastFile() {
        guard let url = lastRecordingURL else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    @objc private func showFolder() {
        NSWorkspace.shared.open(outputDirectory)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "AudioSampler Error"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func isAudioApp(_ app: SCRunningApplication) -> Bool {
        let name = app.applicationName
        let id = app.bundleIdentifier

        guard !name.isEmpty else { return false }
        // Exclude ourselves
        guard id != "com.apple.AudioSampler" && !id.hasSuffix(".AudioSampler") else { return false }
        // Exclude entries with "(Service)" — these are OS helpers, not user apps
        guard !name.contains("Service") else { return false }
        // Exclude known non-audio system processes
        let systemExclusions: Set<String> = [
            "com.apple.dock",
            "com.apple.finder",
            "com.apple.Spotlight",
            "com.apple.loginwindow",
            "com.apple.notificationcenterui",
            "com.apple.controlcenter",
            "com.apple.screenshotui",
            "com.apple.accessibility.heard",
            "com.apple.universalcontrol",
            "com.apple.wallpaper.agent",
            "com.apple.PasswordsUI",
            "com.apple.ShareSheet",
            "com.apple.Accessibility-Inspector",
        ]
        guard !systemExclusions.contains(id) else { return false }
        return true
    }

    private func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}
