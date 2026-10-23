import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()
    private weak var state: AppState?
    private var attached = false
    private var wasRecording = false

    func attach(_ state: AppState) {
        self.state = state
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        guard !attached else {
            refresh()
            return
        }
        attached = true
        refresh()
        rebuildMenu()
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let recording = state?.recorder.isRecording == true
        let stalled = state?.recorder.isStalled == true
        let captured = state?.recorder.capturedSeconds ?? 0
        item.button?.image = Self.icon(recording: recording, stalled: stalled)
        if recording {
            item.button?.title = " \(Self.clock(captured))"
            item.button?.toolTip = stalled
                ? "求索 · 写入已停止，已写入 \(Self.clock(captured))。点菜单停止并保存。"
                : "求索 · 正在录音，已写入 \(Self.clock(captured))"
        } else {
            item.button?.title = ""
            item.button?.toolTip = "求索"
        }
        if recording != wasRecording {
            wasRecording = recording
            rebuildMenu()
        } else if recording {
            item.menu?.items.first?.title = stalled
                ? "写入已停止  \(Self.clock(captured))"
                : "录音中  \(Self.clock(captured))"
        }
    }

    private func rebuildMenu() {
        let recording = state?.recorder.isRecording == true
        let stalled = state?.recorder.isStalled == true
        let captured = state?.recorder.capturedSeconds ?? 0
        let menu = NSMenu()
        if recording {
            let status = NSMenuItem(
                title: stalled
                    ? "写入已停止  \(Self.clock(captured))"
                    : "录音中  \(Self.clock(captured))",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)
            let stop = NSMenuItem(title: "停止并保存", action: #selector(stop), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        } else {
            let start = NSMenuItem(title: "开始录音", action: #selector(start), keyEquivalent: "")
            start.target = self
            menu.addItem(start)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "打开求索", action: #selector(reveal), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        item.menu = menu
    }

    @objc private func start() {
        Task { await state?.startRecording() }
    }

    @objc private func stop() {
        state?.stopRecordingAndSave()
    }

    @objc private func reveal() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private static func icon(recording: Bool, stalled: Bool = false) -> NSImage? {
        if recording {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
                .applying(.init(paletteColors: [stalled ? NSColor.systemOrange : NSColor.systemRed]))
            let name = stalled ? "pause.circle.fill" : "record.circle.fill"
            let image = NSImage(systemSymbolName: name, accessibilityDescription: stalled ? "写入已停止" : "录音中")
            let tinted = image?.withSymbolConfiguration(config)
            tinted?.isTemplate = false
            return tinted
        }
        let image = NSImage(systemSymbolName: "mic", accessibilityDescription: "求索")
        image?.isTemplate = true
        return image
    }
}
