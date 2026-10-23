#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

let names = ["作业", "错题本", "课堂录音", "收件箱", "设置"]

func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(el, key as CFString, &value)
    return value
}

func axSize(_ el: AXUIElement) -> CGSize {
    guard let raw = attr(el, kAXSizeAttribute) else { return .zero }
    var s = CGSize.zero
    AXValueGetValue(raw as! AXValue, .cgSize, &s)
    return s
}

func axPos(_ el: AXUIElement) -> CGPoint {
    guard let raw = attr(el, kAXPositionAttribute) else { return .zero }
    var p = CGPoint.zero
    AXValueGetValue(raw as! AXValue, .cgPoint, &p)
    return p
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func walk(_ el: AXUIElement, _ fn: (AXUIElement) -> Void) {
    fn(el)
    for c in children(el) { walk(c, fn) }
}

func pid() -> pid_t {
    NSWorkspace.shared.runningApplications.first {
        $0.bundleIdentifier == "app.lexicon.archive" || $0.localizedName == "求索"
    }?.processIdentifier ?? 0
}

func fmt(_ s: CGSize) -> String { "\(Int(s.width))x\(Int(s.height))" }

let app = AXUIElementCreateApplication(pid())
NSWorkspace.shared.runningApplications.first {
    $0.bundleIdentifier == "app.lexicon.archive" || $0.localizedName == "求索"
}?.activate()
Thread.sleep(forTimeInterval: 0.3)
let windows = children(app).filter { (attr($0, kAXRoleAttribute) as? String) == "AXWindow" }
print("windows:", windows.count)
guard let window = windows.max(by: { axSize($0).width < axSize($1).width }) else { exit(1) }
print("WINDOW \"\(attr(window, kAXTitleAttribute) as? String ?? "")\" \(fmt(axSize(window)))")

func snapshot(_ label: String) {
    print("--- \(label) ---")
    let ws = axSize(window)
    print("  window \(fmt(ws))")
    if ws.width > 1080 || ws.height > 740 { print("  FAIL window too large") }
    else { print("  window size OK") }
    var splitterOK = false
    walk(window) { el in
        let role = attr(el, kAXRoleAttribute) as? String ?? ""
        if role == "AXSplitter" {
            let s = axSize(el)
            print("  AXSplitter \(fmt(s)) @\(axPos(el))")
            if s.height > ws.height * 0.65 { splitterOK = true }
        }
        if role == "AXButton" || role == "AXStaticText" {
            let name = attr(el, kAXTitleAttribute) as? String
                ?? (attr(el, kAXValueAttribute) as? String)
                ?? (attr(el, kAXDescriptionAttribute) as? String)
                ?? ""
            let s = axSize(el)
            if s.width > 50, s.height > 14, !name.isEmpty, !names.contains(name) {
                print("  \(role) \"\(name)\" \(fmt(s)) @\(axPos(el))")
            }
        }
    }
    if ["作业", "错题本", "课堂录音"].contains(label) {
        print(splitterOK ? "  splitter spans height OK" : "  WARN short splitter")
    }
}

var targets: [String: AXUIElement] = [:]
walk(window) { el in
    let value = attr(el, kAXValueAttribute) as? String ?? ""
    let role = attr(el, kAXRoleAttribute) as? String ?? ""
    if names.contains(value), role == "AXStaticText", targets[value] == nil {
        targets[value] = el
    }
}
print("targets:", names.filter { targets[$0] != nil })

func click(_ el: AXUIElement) {
    let p = axPos(el)
    let s = axSize(el)
    let loc = CGPoint(x: p.x + max(s.width / 2, 6), y: p.y + max(s.height / 2, 6))
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: loc, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: loc, mouseButton: .left)?.post(tap: .cghidEventTap)
}

for name in names {
    var target: AXUIElement?
    walk(window) { el in
        if (attr(el, kAXValueAttribute) as? String) == name,
           (attr(el, kAXRoleAttribute) as? String) == "AXStaticText",
           axPos(el).x < axPos(window).x + 220 {
            target = el
        }
    }
    guard let target else {
        print("MISSING \(name)")
        continue
    }
    click(target)
    Thread.sleep(forTimeInterval: 0.6)
    snapshot(name)
}
print("DONE")
