#!/usr/bin/env swift
// 走真用户路径：按名字点侧栏，截图存到 /tmp/qiusuo-ui。
import AppKit
import ApplicationServices

func attr(_ el: AXUIElement, _ key: String) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(el, key as CFString, &value)
    return value
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func role(_ el: AXUIElement) -> String { attr(el, kAXRoleAttribute) as? String ?? "" }

func label(_ el: AXUIElement) -> String {
    (attr(el, kAXTitleAttribute) as? String)
        ?? (attr(el, kAXDescriptionAttribute) as? String)
        ?? (attr(el, kAXValueAttribute) as? String)
        ?? ""
}

func frame(_ el: AXUIElement) -> CGRect {
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let raw = attr(el, kAXPositionAttribute) { AXValueGetValue(raw as! AXValue, .cgPoint, &origin) }
    if let raw = attr(el, kAXSizeAttribute) { AXValueGetValue(raw as! AXValue, .cgSize, &size) }
    return CGRect(origin: origin, size: size)
}

func walk(_ el: AXUIElement, _ visit: (AXUIElement) -> Void) {
    visit(el)
    children(el).forEach { walk($0, visit) }
}

func texts(in el: AXUIElement) -> [String] {
    var out: [String] = []
    walk(el) { node in
        let text = label(node)
        if !text.isEmpty { out.append(text) }
    }
    return out
}

func click(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func capture(_ rect: CGRect, to path: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))", path]
    try? task.run()
    task.waitUntilExit()
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "app.lexicon.archive").first else {
    fputs("求索 没在跑\n", stderr)
    exit(1)
}
app.activate()
usleep(700_000)

let ax = AXUIElementCreateApplication(app.processIdentifier)
let outDir = "/tmp/qiusuo-ui"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func mainWindow() -> AXUIElement? {
    var found: AXUIElement?
    walk(ax) { node in
        if found == nil, role(node) == "AXWindow", frame(node).height > 200 { found = node }
    }
    return found
}

func sidebarRows() -> [AXUIElement] {
    guard let window = mainWindow() else { return [] }
    var outline: AXUIElement?
    walk(window) { node in
        if role(node) == "AXOutline", outline == nil { outline = node }
    }
    guard let outline else { return [] }
    return children(outline).filter { role($0) == "AXRow" }
}

let sections = CommandLine.arguments.count > 1
    ? Array(CommandLine.arguments.dropFirst())
    : ["作业", "错题本", "课堂录音", "收件箱", "设置"]

for name in sections {
    guard let row = sidebarRows().first(where: { texts(in: $0).contains { $0.contains(name) } }) else {
        print("\(name): 侧栏没找到")
        continue
    }
    let box = frame(row)
    click(CGPoint(x: box.midX, y: box.midY))
    usleep(900_000)
    guard let window = mainWindow() else {
        print("\(name): 没有窗口")
        continue
    }
    let wf = frame(window)
    let path = "\(outDir)/\(name).png"
    capture(wf, to: path)
    var columns: [String] = []
    walk(window) { node in
        if role(node) == "AXSplitGroup" {
            columns = children(node).filter { role($0) == "AXGroup" }.map { "\(Int(frame($0).width))" }
        }
    }
    print("\(name): 窗口 \(Int(wf.width))x\(Int(wf.height)) 列宽 [\(columns.joined(separator: ", "))] -> \(path)")
}
