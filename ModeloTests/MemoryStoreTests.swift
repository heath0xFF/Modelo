import XCTest
@testable import Modelo

final class MemoryStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Name slug

    func test_nameSlug_normalizes() {
        XCTAssertEqual(MemoryStore.nameSlug("Preferred Code Style"), "preferred-code-style")
        XCTAssertEqual(MemoryStore.nameSlug("  spaces   galore  "), "spaces-galore")
        XCTAssertEqual(MemoryStore.nameSlug("keep_under-scores"), "keep_under-scores")
    }

    func test_nameSlug_stripsTraversalAndSeparators() {
        // `/` and `.` cannot survive slugging — the confinement guarantee.
        XCTAssertEqual(MemoryStore.nameSlug("../../etc/passwd"), "etcpasswd")
        XCTAssertFalse(MemoryStore.nameSlug("a/b/c.md").contains("/"))
        XCTAssertFalse(MemoryStore.nameSlug("dot.dot.dot").contains("."))
    }

    func test_nameSlug_unicodeAndEmptyFallback() {
        XCTAssertEqual(MemoryStore.nameSlug("héllo wörld"), "hllo-wrld")
        XCTAssertEqual(MemoryStore.nameSlug(""), "memory")
        XCTAssertEqual(MemoryStore.nameSlug("🍋‍🟩///"), "memory")
    }

    func test_nameSlug_capsLength() {
        let long = String(repeating: "a", count: 200)
        XCTAssertLessThanOrEqual(MemoryStore.nameSlug(long).count, 64)
    }

    // MARK: Project slug

    func test_projectSlug_deterministicAndPathSensitive() {
        let a = MemoryStore.projectSlug(forPath: "/Users/x/Modelo")
        XCTAssertEqual(a, MemoryStore.projectSlug(forPath: "/Users/x/Modelo"))
        XCTAssertNotEqual(a, MemoryStore.projectSlug(forPath: "/Users/y/Modelo"))
        XCTAssertTrue(a.hasPrefix("modelo-"))
    }

    func test_projectSlug_neverCollidesWithGlobal() {
        XCTAssertNotEqual(MemoryStore.projectSlug(forPath: "/tmp/global"), "global")
    }

    // MARK: Serialize / parse round trip

    func test_serializeParse_roundTrip() {
        let text = MemoryStore.serialize(name: "Build Quirks", description: "How to build",
                                         body: "Run xcodegen first.", updated: Date(timeIntervalSince1970: 1_700_000_000))
        let mem = MemoryStore.parse(text, fileURL: URL(fileURLWithPath: "/x/build-quirks.md"))
        XCTAssertEqual(mem.name, "build-quirks")
        XCTAssertEqual(mem.description, "How to build")
        XCTAssertEqual(mem.body, "Run xcodegen first.")
        XCTAssertNotNil(mem.updatedAt)
    }

    func test_parse_noFrontmatter_usesFilenameAndFirstLine() {
        let mem = MemoryStore.parse("Just a raw fact.\nMore detail.", fileURL: URL(fileURLWithPath: "/x/raw-note.md"))
        XCTAssertEqual(mem.name, "raw-note")
        XCTAssertEqual(mem.description, "Just a raw fact.")
        XCTAssertEqual(mem.body, "Just a raw fact.\nMore detail.")
        XCTAssertNil(mem.updatedAt)
    }

    func test_parse_filenameStemWinsOverFrontmatterName() {
        let text = "---\nname: old-name\ndescription: d\n---\nbody"
        let mem = MemoryStore.parse(text, fileURL: URL(fileURLWithPath: "/x/renamed.md"))
        XCTAssertEqual(mem.name, "renamed")
    }

    func test_parse_garbageNeverCrashes() {
        _ = MemoryStore.parse("---\n:::\n\u{0}garbage", fileURL: URL(fileURLWithPath: "/x/g.md"))
        _ = MemoryStore.parse("", fileURL: URL(fileURLWithPath: "/x/empty.md"))
    }

    // MARK: Save / read / list / delete

    func test_saveThenRead() throws {
        try MemoryStore.save(name: "User Prefers Tabs", description: "Tabs over spaces",
                             body: "Heath prefers tabs.", scope: .global, root: root)
        let mem = MemoryStore.read(name: "user prefers tabs", scope: .global, root: root)
        XCTAssertEqual(mem?.name, "user-prefers-tabs")
        XCTAssertEqual(mem?.body, "Heath prefers tabs.")
    }

    func test_save_overwritesSameName() throws {
        try MemoryStore.save(name: "fact", description: "v1", body: "one", scope: .global, root: root)
        try MemoryStore.save(name: "fact", description: "v2", body: "two", scope: .global, root: root)
        let all = MemoryStore.list(.global, root: root)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.body, "two")
    }

    func test_save_rejectsEmptyNameAndBody() {
        XCTAssertThrowsError(try MemoryStore.save(name: "  ", description: "d", body: "b", scope: .global, root: root))
        XCTAssertThrowsError(try MemoryStore.save(name: "n", description: "d", body: "  \n ", scope: .global, root: root))
    }

    func test_save_rejectsOversizedBody() {
        let big = String(repeating: "x", count: MemoryStore.maxBodyBytes + 1)
        XCTAssertThrowsError(try MemoryStore.save(name: "n", description: "d", body: big, scope: .global, root: root))
    }

    func test_scopes_areIsolated() throws {
        try MemoryStore.save(name: "g", description: "d", body: "global fact", scope: .global, root: root)
        try MemoryStore.save(name: "p", description: "d", body: "project fact",
                             scope: .project(path: "/tmp/proj"), root: root)
        XCTAssertEqual(MemoryStore.list(.global, root: root).map(\.name), ["g"])
        XCTAssertEqual(MemoryStore.list(.project(path: "/tmp/proj"), root: root).map(\.name), ["p"])
        XCTAssertNil(MemoryStore.read(name: "p", scope: .global, root: root))
    }

    func test_list_missingDirectoryIsEmpty_andCreatesNothing() {
        XCTAssertEqual(MemoryStore.list(.global, root: root), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "global").path))
    }

    func test_list_skipsNonMarkdownAndOversized() throws {
        let dir = MemoryStore.directory(for: .global, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not a memory".write(to: dir.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        try String(repeating: "x", count: MemoryStore.maxFileBytes + 1)
            .write(to: dir.appending(path: "huge.md"), atomically: true, encoding: .utf8)
        try MemoryStore.save(name: "ok", description: "d", body: "b", scope: .global, root: root)
        XCTAssertEqual(MemoryStore.list(.global, root: root).map(\.name), ["ok"])
    }

    func test_list_toleratesHandWrittenFileWithoutFrontmatter() throws {
        let dir = MemoryStore.directory(for: .global, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "A bare hand-written fact.".write(to: dir.appending(path: "hand-note.md"), atomically: true, encoding: .utf8)
        let all = MemoryStore.list(.global, root: root)
        XCTAssertEqual(all.first?.name, "hand-note")
        XCTAssertEqual(all.first?.description, "A bare hand-written fact.")
    }

    func test_readAndDelete_handRenamedFileByRawStem() throws {
        // A hand-created file whose stem isn't slug-normal is listed under its raw
        // stem — read/delete by that exact name must still resolve it.
        let dir = MemoryStore.directory(for: .global, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "A hand-named fact.".write(to: dir.appending(path: "My Note.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(MemoryStore.list(.global, root: root).first?.name, "My Note")
        XCTAssertEqual(MemoryStore.read(name: "My Note", scope: .global, root: root)?.body, "A hand-named fact.")
        try MemoryStore.delete(name: "My Note", scope: .global, root: root)
        XCTAssertEqual(MemoryStore.list(.global, root: root), [])
    }

    func test_read_rawStemFallbackCannotTraverse() throws {
        try MemoryStore.save(name: "safe", description: "d", body: "b", scope: .global, root: root)
        // Names with separators/traversal never get the raw-stem fallback — they
        // resolve only via the slug, which strips `/` and `.`.
        XCTAssertNil(MemoryStore.read(name: "../global/safe", scope: .project(path: "/tmp/p"), root: root))
        XCTAssertNil(MemoryStore.read(name: "sub/safe", scope: .global, root: root))
    }

    func test_saveThenRead_longDescriptionSurvivesRoundTrip() throws {
        // The editor writes the loaded description back — a load-time clip would
        // silently truncate it (must hold up to the 500-char serialize cap).
        let desc = String(repeating: "d", count: 300)
        try MemoryStore.save(name: "long-desc", description: desc, body: "b", scope: .global, root: root)
        XCTAssertEqual(MemoryStore.read(name: "long-desc", scope: .global, root: root)?.description, desc)
    }

    func test_serializeParse_blockScalarLookingDescription() {
        // A leading `>`/`|` would parse as a YAML block scalar (empty) if unquoted.
        for desc in ["> prefer blockquotes", "| keep pipes"] {
            let text = MemoryStore.serialize(name: "n", description: desc, body: "body",
                                             updated: Date(timeIntervalSince1970: 1_700_000_000))
            let mem = MemoryStore.parse(text, fileURL: URL(fileURLWithPath: "/x/n.md"))
            XCTAssertEqual(mem.description, desc)
        }
    }

    func test_delete_removesFile_andMissingIsNoop() throws {
        try MemoryStore.save(name: "gone", description: "d", body: "b", scope: .global, root: root)
        try MemoryStore.delete(name: "gone", scope: .global, root: root)
        XCTAssertEqual(MemoryStore.list(.global, root: root), [])
        XCTAssertNoThrow(try MemoryStore.delete(name: "gone", scope: .global, root: root))
    }

    // MARK: Index injection

    func test_index_nilWhenEmpty() {
        XCTAssertNil(MemoryStore.indexInjection(scopes: [.global, .project(path: "/tmp/p")], root: root))
    }

    func test_index_formatAndScopeTags() throws {
        try MemoryStore.save(name: "user-prefers-tabs", description: "Tabs over spaces",
                             body: "b", scope: .global, root: root)
        try MemoryStore.save(name: "build-quirks", description: "How to build",
                             body: "b", scope: .project(path: "/tmp/p"), root: root)
        let index = MemoryStore.indexInjection(scopes: [.global, .project(path: "/tmp/p")], root: root)!
        XCTAssertTrue(index.hasPrefix("## Memory"))
        XCTAssertTrue(index.contains("- [global] user-prefers-tabs — Tabs over spaces"))
        XCTAssertTrue(index.contains("- [project] build-quirks — How to build"))
        XCTAssertTrue(index.contains("read_memory"))
        XCTAssertTrue(index.contains("save_memory"))
    }

    func test_index_globalOnlyScopeOmitsProjectLines() throws {
        try MemoryStore.save(name: "g", description: "d", body: "b", scope: .global, root: root)
        try MemoryStore.save(name: "p", description: "d", body: "b", scope: .project(path: "/tmp/p"), root: root)
        let index = MemoryStore.indexInjection(scopes: [.global], root: root)!
        XCTAssertTrue(index.contains("[global] g"))
        XCTAssertFalse(index.contains("[project]"))
    }

    func test_index_capsEntriesWithOverflowLine() throws {
        for i in 0..<(MemoryStore.maxIndexEntries + 5) {
            try MemoryStore.save(name: String(format: "m-%03d", i), description: "d", body: "b",
                                 scope: .global, root: root)
        }
        let index = MemoryStore.indexInjection(scopes: [.global], root: root)!
        let entryLines = index.components(separatedBy: "\n").filter { $0.hasPrefix("- [global]") }
        XCTAssertEqual(entryLines.count, MemoryStore.maxIndexEntries)
        XCTAssertTrue(index.contains("(5 more global memories"))
    }

    func test_index_contextOnlyWordingWhenToolsUnavailable() throws {
        for i in 0..<(MemoryStore.maxIndexEntries + 1) {
            try MemoryStore.save(name: "m-\(i)", description: "d", body: "b", scope: .global, root: root)
        }
        let index = MemoryStore.indexInjection(scopes: [.global], toolsAvailable: false, root: root)!
        // No tool this request — the injected text must not command tool calls.
        XCTAssertTrue(index.hasPrefix("## Memory"))
        XCTAssertFalse(index.contains("read_memory"))
        XCTAssertFalse(index.contains("save_memory"))
    }

    func test_index_clipsLongDescriptions() throws {
        try MemoryStore.save(name: "long", description: String(repeating: "d", count: 300),
                             body: "b", scope: .global, root: root)
        let line = MemoryStore.indexInjection(scopes: [.global], root: root)!
            .components(separatedBy: "\n").first { $0.hasPrefix("- [global] long") }!
        XCTAssertLessThan(line.count, 140)
    }
}
