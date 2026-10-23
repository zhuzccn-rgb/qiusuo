#!/usr/bin/env swift
import AppKit
import Foundation

func dumpWindows() {
    guard let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return }
    print("=== CGWindows 求索 ===")
    for w in info {
        let owner = w["kCGWindowOwnerName"] as? String ?? ""
        guard owner == "求索" else { continue }
        let bounds = w["kCGWindowBounds"] as? [String: Any] ?? [:]
        let width = (bounds["Width"] as? Double) ?? 0
        let height = (bounds["Height"] as? Double) ?? 0
        guard width > 200, height > 80 else { continue }
        print("  \(bounds)")
    }
    if let vis = NSScreen.main?.visibleFrame {
        print("  visibleFrame \(Int(vis.width))x\(Int(vis.height))")
    }
}

dumpWindows()
