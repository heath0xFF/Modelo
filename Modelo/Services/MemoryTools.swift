import Foundation

/// Lets the model persist a durable fact across conversations. Not gated behind an
/// approval card: writes are confined to `~/.modelo/memory` because `MemoryStore`
/// slugs the name (no `/` or `..` can survive), and the result line in the
/// transcript keeps the save visible.
struct SaveMemoryTool: Tool {
    /// Scopes available to this chat: `[.global]` or `[.global, .project(path:)]`.
    let scopes: [MemoryScope]
    var root: URL = MemoryStore.defaultRoot
    let name = "save_memory"
    let alwaysVisible = true

    var description: String {
        "Save a durable memory that persists across conversations — a user preference, "
        + "fact, or correction worth remembering. Saving with an existing name overwrites "
        + "that memory."
    }

    var parameters: JSONSchema {
        JSONSchema(properties: [
            "name": .init("string", "Short kebab-case identifier, e.g. preferred-code-style."),
            "description": .init("string", "One sentence summarizing the memory, shown in the memory index."),
            "content": .init("string", "The full memory content (markdown). Keep it a short fact, not a document."),
            "scope": .init("string", scopeHint)
        ], required: ["name", "description", "content"])
    }

    private var projectScope: MemoryScope? {
        scopes.first { if case .project = $0 { true } else { false } }
    }

    private var scopeHint: String {
        projectScope != nil
            ? "\"global\" for facts about the user; \"project\" for facts about this project. Default: project."
            : "Only \"global\" is available in this chat."
    }

    func execute(argumentsJSON: String) async throws -> String {
        struct Args: Decodable { let name: String; let description: String; let content: String; let scope: String? }
        let args: Args
        do { args = try JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) }
        catch { throw MemoryError.writeFailed("expected JSON arguments {name, description, content, scope?}") }

        var note = ""
        let scope: MemoryScope
        switch args.scope?.lowercased() {
        case "global":
            scope = .global
        case "project", nil, "":
            if let project = projectScope { scope = project }
            else {
                scope = .global
                if args.scope != nil { note = " (no project is bound to this chat, so it was saved globally)" }
            }
        case .some(let other):
            scope = projectScope ?? .global
            note = " (unknown scope \"\(other)\"; saved to the default scope)"
        }
        let memory = try MemoryStore.save(name: args.name, description: args.description,
                                          body: args.content, scope: scope, root: root)
        let label = switch scope { case .global: "global"; case .project: "project" }
        return "Saved memory \"\(memory.name)\" (\(label))\(note)."
    }
}

/// Fetches a saved memory's full content. The system prompt carries only a compact
/// index (name — description); the model calls this when an entry looks relevant.
struct ReadMemoryTool: Tool {
    /// Searched in order — project first, then global — when no scope is given.
    let scopes: [MemoryScope]
    var root: URL = MemoryStore.defaultRoot
    let name = "read_memory"
    let alwaysVisible = true

    let description = "Read the full content of a saved memory from the memory index in the system prompt."

    var parameters: JSONSchema {
        JSONSchema(properties: [
            "name": .init("string", "The exact memory name from the index."),
            "scope": .init("string", "Optional: \"global\" or \"project\" when the same name exists in both.")
        ], required: ["name"])
    }

    func execute(argumentsJSON: String) async throws -> String {
        struct Args: Decodable { let name: String; let scope: String? }
        guard let args = try? JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) else {
            throw MemoryError.writeFailed("expected JSON arguments {name, scope?}")
        }
        // Project scope shadows global on a name hit, so search project first.
        let projectScopes = scopes.filter { if case .project = $0 { true } else { false } }
        let searched: [MemoryScope]
        switch args.scope?.lowercased() {
        case "global":  searched = [.global]
        case "project": searched = projectScopes
        default:        searched = projectScopes + scopes.filter { if case .global = $0 { true } else { false } }
        }
        for scope in searched {
            if let memory = MemoryStore.read(name: args.name, scope: scope, root: root) {
                return memory.body
            }
        }
        let available = scopes.flatMap { MemoryStore.list($0, root: root) }.map(\.name)
        return available.isEmpty
            ? "No memory named \"\(args.name)\" — no memories are saved yet."
            : "No memory named \"\(args.name)\". Available: \(available.joined(separator: ", "))."
    }
}
