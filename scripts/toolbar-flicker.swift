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

let bundle = CommandLine.arguments[1]
let target = CommandLine.arguments[2]
let tag = CommandLine.arguments[3]
let frames = 16

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { exit(1) }
app.activate()
usleep(700_000)
let ax = AXUIElementCreateApplication(app.processIdentifier)
guard let win = find(ax, "AXWindow") else { fputs("无窗口\n", stderr); exit(2) }
let wf = rect(win)
let band = CGRect(x: wf.minX, y: wf.minY, width: wf.width, height: 54)
let dir = "/tmp/flick"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

guard let outline = find(ax, "AXOutline") else { exit(3) }
var row: AXUIElement?
for r in kids(outline).filter({ role($0) == "AXRow" }) {
    var hit = false
    walk(r) { if let v = attr($0, kAXValueAttribute) as? String, v.contains(target) { hit = true } }
    if hit { row = r; break }
}
guard let row else { fputs("侧栏没有 \(target)\n", stderr); exit(4) }

func shot(_ i: Int) {
    let t = Process()
    t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    t.arguments = ["-x", "-R", "\(Int(band.minX)),\(Int(band.minY)),\(Int(band.width)),\(Int(band.height))",
                   "\(dir)/\(tag)-\(String(format: "%02d", i)).png"]
    try? t.run()
    t.waitUntilExit()
}

shot(0)
let p = CGPoint(x: rect(row).midX, y: rect(row).midY)
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
for i in 1..<frames { shot(i) }

func pixels(_ i: Int) -> NSBitmapImageRep? {
    guard let img = NSImage(contentsOfFile: "\(dir)/\(tag)-\(String(format: "%02d", i)).png"),
          let tiff = img.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}
/// 和最终稳定帧比：差异大的中间帧就是肉眼看到的那一下闪。
guard let last = pixels(frames - 1) else { exit(5) }
for i in 0..<frames {
    guard let cur = pixels(i), cur.pixelsWide == last.pixelsWide, cur.pixelsHigh == last.pixelsHigh else { continue }
    var diff = 0
    var total = 0
    for y in stride(from: 0, to: cur.pixelsHigh, by: 3) {
        for x in stride(from: 0, to: cur.pixelsWide, by: 3) {
            total += 1
            let a = cur.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            let b = last.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            let d = abs((a?.redComponent ?? 0) - (b?.redComponent ?? 0))
            if d > 0.08 { diff += 1 }
        }
    }
    let pct = Double(diff) * 100 / Double(max(total, 1))
    let bar = String(repeating: "#", count: min(Int(pct), 40))
    print(String(format: "帧%02d 与末帧差异 %5.1f%% %@", i, pct, bar))
}
