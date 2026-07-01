import XCTest
@testable import Modelo

final class MemoryToolsTests: XCTestCase {
    private var root: URL!
    private let projectPath = "/tmp/some-project"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "memory-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var projectScopes: [MemoryScope] { [.global, .project(path: projectPath)] }

    // MARK: save_memory

    func test_save_defaultsToProjectScopeInProjectChat() async throws {
        let tool = SaveMemoryTool(scopes: projectScopes, root: root)
        let out = try await tool.execute(
            argumentsJSON: #"{"name":"Build Quirks","description":"How to build","content":"Run xcodegen."}"#)
        XCTAssertTrue(out.contains("build-quirks"))
        XCTAssertTrue(out.contains("project"))
        XCTAssertEqual(MemoryStore.list(.project(path: projectPath), root: root).count, 1)
        XCTAssertEqual(MemoryStore.list(.global, root: root).count, 0)
    }

    func test_save_defaultsToGlobalWithoutProject() async throws {
        let tool = SaveMemoryTool(scopes: [.global], root: root)
        _ = try await tool.execute(argumentsJSON: #"{"name":"n","description":"d","content":"c"}"#)
        XCTAssertEqual(MemoryStore.list(.global, root: root).count, 1)
    }

    func test_save_explicitGlobalScopeInProjectChat() async throws {
        let tool = SaveMemoryTool(scopes: projectScopes, root: root)
        _ = try await tool.execute(argumentsJSON: #"{"name":"n","description":"d","content":"c","scope":"global"}"#)
        XCTAssertEqual(MemoryStore.list(.global, root: root).count, 1)
        XCTAssertEqual(MemoryStore.list(.project(path: projectPath), root: root).count, 0)
    }

    func test_save_projectScopeWithoutProjectFallsBackWithNote() async throws {
        let tool = SaveMemoryTool(scopes: [.global], root: root)
        let out = try await tool.execute(
            argumentsJSON: #"{"name":"n","description":"d","content":"c","scope":"project"}"#)
        XCTAssertTrue(out.contains("saved globally"))
        XCTAssertEqual(MemoryStore.list(.global, root: root).count, 1)
    }

    func test_save_unknownScopeFallsBackWithNote() async throws {
        let tool = SaveMemoryTool(scopes: projectScopes, root: root)
        let out = try await tool.execute(
            argumentsJSON: #"{"name":"n","description":"d","content":"c","scope":"cosmic"}"#)
        XCTAssertTrue(out.contains("unknown scope"))
        XCTAssertEqual(MemoryStore.list(.project(path: projectPath), root: root).count, 1)
    }

    func test_save_overwriteByName() async throws {
        let tool = SaveMemoryTool(scopes: [.global], root: root)
        _ = try await tool.execute(argumentsJSON: #"{"name":"fact","description":"v1","content":"one"}"#)
        _ = try await tool.execute(argumentsJSON: #"{"name":"fact","description":"v2","content":"two"}"#)
        let all = MemoryStore.list(.global, root: root)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.body, "two")
    }

    func test_save_badArgumentsThrowActionably() async {
        let tool = SaveMemoryTool(scopes: [.global], root: root)
        do {
            _ = try await tool.execute(argumentsJSON: "not json")
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("name"))
        }
    }

    func test_save_isAutoApproved() {
        let tool = SaveMemoryTool(scopes: [.global], root: root)
        XCTAssertFalse(tool.isMutating)
        XCTAssertNil(tool.approvalPreview(argumentsJSON: "{}"))
        XCTAssertTrue(tool.alwaysVisible)
    }

    // MARK: read_memory

    func test_read_returnsBody() async throws {
        try MemoryStore.save(name: "fact", description: "d", body: "the full body", scope: .global, root: root)
        let tool = ReadMemoryTool(scopes: [.global], root: root)
        let out = try await tool.execute(argumentsJSON: #"{"name":"fact"}"#)
        XCTAssertEqual(out, "the full body")
    }

    func test_read_projectShadowsGlobalOnNameCollision() async throws {
        try MemoryStore.save(name: "fact", description: "d", body: "global version", scope: .global, root: root)
        try MemoryStore.save(name: "fact", description: "d", body: "project version",
                             scope: .project(path: projectPath), root: root)
        let tool = ReadMemoryTool(scopes: projectScopes, root: root)
        let out = try await tool.execute(argumentsJSON: #"{"name":"fact"}"#)
        XCTAssertEqual(out, "project version")
        let explicit = try await tool.execute(argumentsJSON: #"{"name":"fact","scope":"global"}"#)
        XCTAssertEqual(explicit, "global version")
    }

    func test_read_missListsAvailable() async throws {
        try MemoryStore.save(name: "alpha", description: "d", body: "b", scope: .global, root: root)
        let tool = ReadMemoryTool(scopes: [.global], root: root)
        let out = try await tool.execute(argumentsJSON: #"{"name":"nope"}"#)
        XCTAssertTrue(out.contains("No memory named \"nope\""))
        XCTAssertTrue(out.contains("alpha"))
    }

    func test_read_missWithNoMemories() async throws {
        let tool = ReadMemoryTool(scopes: [.global], root: root)
        let out = try await tool.execute(argumentsJSON: #"{"name":"nope"}"#)
        XCTAssertTrue(out.contains("no memories are saved yet"))
    }

    func test_read_badArgumentsErrorIsReadFlavored() async {
        // A read mistake must not be reported as a failed save — a weak model
        // could retry with save_memory (mutating) instead of fixing its call.
        let tool = ReadMemoryTool(scopes: [.global], root: root)
        do {
            _ = try await tool.execute(argumentsJSON: "not json")
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("read_memory"))
            XCTAssertFalse(error.localizedDescription.contains("save the memory"))
        }
    }

    func test_read_alwaysVisibleAndAutoApproved() {
        let tool = ReadMemoryTool(scopes: [.global], root: root)
        XCTAssertTrue(tool.alwaysVisible)
        XCTAssertFalse(tool.isMutating)
    }

    // MARK: registry integration

    func test_registry_alwaysVisibleNames() {
        let registry = ToolRegistry([SaveMemoryTool(scopes: [.global], root: root),
                                     ReadMemoryTool(scopes: [.global], root: root)])
        XCTAssertEqual(registry.alwaysVisibleNames(), ["save_memory", "read_memory"])
    }
}
