import XCTest
import LexiconInbox
import LexiconCore

final class InboxTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-inbox-\(UUID().uuidString)", isDirectory: true)
        AppPaths.ensureInboxLayout(at: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testOCROnlyFillsEmptyNotes() {
        XCTAssertTrue(DocumentTextRecognizer.shouldFillEmptyNotes(""))
        XCTAssertTrue(DocumentTextRecognizer.shouldFillEmptyNotes("   \n"))
        XCTAssertFalse(DocumentTextRecognizer.shouldFillEmptyNotes("已有手写备注"))
    }

    func testKindUsesFolderAndExtension() {
        let root = URL(fileURLWithPath: "/tmp/LexiconInbox")
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("录音/class.caf"), inboxRoot: root), .audio)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("notes.m4a"), inboxRoot: root), .audio)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("错题/q.jpg"), inboxRoot: root), .mistakePhoto)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("笔记/week.md"), inboxRoot: root), .note)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("作业/hw.pdf"), inboxRoot: root), .homework)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("课件/CS61A/lec.pdf"), inboxRoot: root), .slides)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("课件/课程主页.md"), inboxRoot: root), .slides)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("课件/CS61A/deck.pptx"), inboxRoot: root), .slides)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("作业/课件.pdf"), inboxRoot: root), .homework)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("作业/录音作业.pdf"), inboxRoot: root), .homework)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("每周导入/week.zip"), inboxRoot: root), .archive)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("每周总结/2026-09-25/分类.md"), inboxRoot: root), .other)
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("dump.zip"), inboxRoot: root), .archive)
        XCTAssertTrue(InboxWatcher.isArchive(root.appendingPathComponent("a.zip")))
        XCTAssertEqual(InboxWatcher.kind(for: root.appendingPathComponent("random.bin"), inboxRoot: root), .other)
        XCTAssertEqual(InboxWatcher.inboxFolder(for: root.appendingPathComponent("课件/CS61 A/lec.pdf"), inboxRoot: root), "课件")
        XCTAssertEqual(InboxItem(url: root.appendingPathComponent("课件/CS61A/lec.pdf"), kind: .slides, modified: Date()).kindLabel, L10n.text("课件"))
        XCTAssertEqual(InboxItem(url: root.appendingPathComponent("每周导入/w.zip"), kind: .archive, modified: Date()).kindLabel, L10n.text("待分类"))
    }

    func testScanSkipsReadmeICloudZeroByteAndHidden() throws {
        let hw = folder.appendingPathComponent("作业/pset.pdf")
        try Data("pdf".utf8).write(to: hw)
        let emptyAudio = folder.appendingPathComponent("录音/empty.m4a")
        try Data().write(to: emptyAudio)
        let icloud = folder.appendingPathComponent("作业/photo.jpg.icloud")
        try Data("x".utf8).write(to: icloud)
        let note = folder.appendingPathComponent("笔记/week.md")
        try Data("# notes".utf8).write(to: note)
        let slidesDir = folder.appendingPathComponent("课件/CS61A", isDirectory: true)
        try FileManager.default.createDirectory(at: slidesDir, withIntermediateDirectories: true)
        let slide = slidesDir.appendingPathComponent("lec.pdf")
        try Data("pdf".utf8).write(to: slide)

        let items = InboxWatcher().scan(path: folder.path)
        let names = Set(items.map { $0.url.lastPathComponent })
        XCTAssertTrue(names.contains("pset.pdf"))
        XCTAssertTrue(names.contains("week.md"))
        XCTAssertTrue(names.contains("lec.pdf"))
        XCTAssertEqual(items.first(where: { $0.url.lastPathComponent == "lec.pdf" })?.kind, .slides)
        XCTAssertFalse(names.contains("empty.m4a"))
        XCTAssertFalse(names.contains("photo.jpg.icloud"))
        XCTAssertFalse(names.contains("放到这里.txt"))
        XCTAssertFalse(names.contains("课程主页.md"))
    }

    func testSearchMatchesFilenameAndKindLabel() {
        let item = InboxItem(
            url: URL(fileURLWithPath: "/tmp/LexiconInbox/录音/R1A.caf"),
            kind: .audio,
            modified: Date()
        )
        XCTAssertTrue(item.matchesSearch("r1a"))
        XCTAssertTrue(item.matchesSearch("录音"))
        XCTAssertTrue(item.matchesSearch("audio"))
        XCTAssertFalse(item.matchesSearch("错题"))
        XCTAssertEqual(item.kindLabel, L10n.text("录音"))
    }

    func testEnsureInboxLayoutCreatesFolders() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("作业").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("课件").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("每周导入").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("每周总结").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("课件/课程主页.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("放到这里.txt").path))
        let readme = try String(contentsOf: folder.appendingPathComponent("放到这里.txt"), encoding: .utf8)
        XCTAssertTrue(readme.contains("authorized"))
        XCTAssertFalse(readme.contains("OneDrive"))
    }

    func testAirDropRoutesZipAndAudio() {
        let zip = folder.appendingPathComponent("week.zip")
        let audio = folder.appendingPathComponent("clip.m4a")
        let pdf = folder.appendingPathComponent("pset.pdf")
        XCTAssertEqual(
            AirDropInbox.destination(for: zip, inboxRoot: folder).deletingLastPathComponent().lastPathComponent,
            "每周导入"
        )
        XCTAssertEqual(
            AirDropInbox.destination(for: audio, inboxRoot: folder).deletingLastPathComponent().lastPathComponent,
            "录音"
        )
        XCTAssertEqual(AirDropInbox.destination(for: pdf, inboxRoot: folder).deletingLastPathComponent().path, folder.path)
    }

    func testAdoptMovesMatchingFiles() throws {
        let drop = FileManager.default.temporaryDirectory.appendingPathComponent("lexicon-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: drop) }
        let air = drop.appendingPathComponent("week.zip")
        let safari = drop.appendingPathComponent("chrome.pdf")
        try Data("zip".utf8).write(to: air)
        try Data("pdf".utf8).write(to: safari)

        let moved = AirDropInbox.adopt(from: drop, into: folder) { $0.lastPathComponent == "week.zip" }
        XCTAssertEqual(moved.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("每周导入/week.zip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: safari.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: air.path))
    }
}
