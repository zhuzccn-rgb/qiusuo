import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ k: String) -> AnyObject? {
    var v: AnyObject?
    AXUIElementCopyAttributeValue(e, k as CFString, &v)
    return v
}
func kids(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func role(_ e: AXUIElement) -> String { attr(e, kAXRoleAttribute) as? String ?? "" }
func rect(_ e: AXUIElement) -> CGRect {
    var o = CGPoint.zero, s = CGSize.zero
    if let r = attr(e, kAXPositionAttribute) { AXValueGetValue(r as! AXValue, .cgPoint, &o) }
    if let r = attr(e, kAXSizeAttribute) { AXValueGetValue(r as! AXValue, .cgSize, &s) }
    return CGRect(origin: o, size: s)
}
func walk(_ e: AXUIElement, _ f: (AXUIElement) -> Void) { f(e); kids(e).forEach { walk($0, f) } }
func find(_ e: AXUIElement, _ w: String) -> AXUIElement? {
    if role(e) == w { return e }
    for c in kids(e) { if let f = find(c, w) { return f } }
    return nil
}

let app = NSRunningApplication.runningApplications(withBundleIdentifier: "app.lexicon.archive").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)

func click(_ page: String) {
    app.activate()
    usleep(500_000)
    guard let outline = find(ax, "AXOutline") else { return }
    for r in kids(outline).filter({ role($0) == "AXRow" }) {
        var hit = false
        walk(r) { if let v = attr($0, kAXValueAttribute) as? String, v.contains(page) { hit = true } }
        if hit {
            let p = CGPoint(x: rect(r).midX, y: rect(r).midY)
            let src = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(1_100_000)
            return
        }
    }
}

func inspect(_ label: String) {
    app.activate()
    usleep(400_000)
    guard let win = find(ax, "AXWindow") else { print("\(label): 无窗口"); return }
    let f = rect(win)
    var splitters: [CGFloat] = []
    walk(win) { if role($0) == "AXSplitter" { splitters.append(rect($0).midX - f.minX) } }
    let out = "/tmp/sep-\(label).png"
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    t.arguments = ["-x", "-R", "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),120", out]
    try? t.run()
    t.waitUntilExit()
    guard let img = NSImage(contentsOfFile: out), let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff) else { return }
    let scale = Double(bmp.pixelsWide) / f.width
    func g(_ x: Double, _ y: Double) -> Double {
        guard let c = bmp.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return -1 }
        return c.redComponent * 255
    }
    // 工具栏下沿那条横线：在 y=50..58 里找最暗的一行
    var lineY = -1.0
    var lineDark = 255.0
    for y in stride(from: 48.0, through: 60.0, by: 1.0) {
        var darkest = 255.0
        for x in stride(from: 620.0, through: 1000.0, by: 20.0) { darkest = min(darkest, g(x, y)) }
        if darkest < lineDark { lineDark = darkest; lineY = y }
    }
    // 竖分隔线在工具栏里（y=10..44）有没有
    var vertical = "无"
    if splitters.count >= 2 {
        let x = Double(splitters[1])
        var darkest = 255.0
        for y in stride(from: 10.0, through: 44.0, by: 2.0) {
            for dx in stride(from: -2.0, through: 2.0, by: 0.5) { darkest = min(darkest, g(x + dx, y)) }
        }
        vertical = darkest < 250 ? String(format: "有(%.0f)", darkest) : "无"
    }
    let name = label.padding(toLength: 22, withPad: " ", startingAt: 0)
    print(name + String(format: "横线 y=%.0f 灰度%.0f%@   竖线穿过工具栏: %@",
                        lineY, lineDark, lineDark < 250 ? "(有)" : "(无)", vertical))
}

let steps = CommandLine.arguments.dropFirst()
for step in steps {
    click(step)
    inspect(step)
}
