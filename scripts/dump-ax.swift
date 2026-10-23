#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(el, key as CFString, &value)
    return value
}

func sizeOf(_ el: AXUIElement) -> String {
    guard let raw = attr(el, kAXSizeAttribute) else { return "?" }
    let v = raw as! AXValue
    var s = CGSize.zero
    AXValueGetValue(v, .cgSize, &s)
    return "\(Int(s.width))x\(Int(s.height))"
}

func posOf(_ el: AXUIElement) -> String {
    guard let raw = attr(el, kAXPositionAttribute) else { return "?" }
    let v = raw as! AXValue
    var p = CGPoint.zero
    AXValueGetValue(v, .cgPoint, &p)
    return "(\(Int(p.x)),\(Int(p.y)))"
}

func dump(_ el: AXUIElement, indent: String, depth: Int) {
    if depth > 6 { return }
    let role = attr(el, kAXRoleAttribute) as? String ?? "?"
    let name = attr(el, kAXTitleAttribute) as? String ?? (attr(el, kAXDescriptionAttribute) as? String ?? "")
    print("\(indent)\(role) \(name) \(sizeOf(el)) @\(posOf(el))")
    var children: AnyObject?
    AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children)
    guard let list = children as? [AXUIElement] else { return }
    for child in list.prefix(20) {
        dump(child, indent: indent + "  ", depth: depth + 1)
    }
}

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "app.lexicon.archive")
guard let app = apps.first else {
    let all = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "app.lexicon.archive" || $0.localizedName == "求索" }
    guard let found = all.first else {
        fputs("app not running\n", stderr)
        exit(1)
    }
    let ax = AXUIElementCreateApplication(found.processIdentifier)
    dump(ax, indent: "", depth: 0)
    exit(0)
}
dump(AXUIElementCreateApplication(app.processIdentifier), indent: "", depth: 0)
