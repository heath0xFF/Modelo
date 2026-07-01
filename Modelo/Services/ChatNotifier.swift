import Foundation
import SwiftData
import UserNotifications
import AppKit

/// Posts a macOS user notification when a chat's reply finishes while the user
/// isn't watching it — the app is in the background, or a different chat (or
/// non-chat view) is on screen. Held by `ContentView` and injected; ContentView
/// keeps `foreground` in sync with the open conversation.
///
/// Also the notification-center delegate. That's what lets a banner appear when
/// the app is frontmost but a *different* chat is on screen (macOS suppresses
/// foreground notifications unless the delegate opts in), and lets a tap
/// deep-link back to the chat that produced the reply (see the delegate methods).
@Observable @MainActor
final class ChatNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// The conversation currently on screen, or nil for non-chat views. A reply
    /// that finishes here while the app is focused isn't worth interrupting.
    var foreground: PersistentIdentifier?

    /// Set when the user taps a reply notification. `ContentView` observes this,
    /// navigates to the chat, then clears it back to nil.
    var tappedConversation: PersistentIdentifier?

    /// `userInfo` key carrying the chat's JSON-encoded `PersistentIdentifier`, so a
    /// tapped notification can route back to the conversation that produced it.
    /// `nonisolated` so the delegate callbacks (off the main actor) can read it.
    nonisolated private static let conversationKey = "conversationID"

    /// Register as the notification-center delegate. Called from `ModeloApp.init()`
    /// — early, before launch finishes — so the delegate (a) outlives any window
    /// (the app keeps running menu-bar-only after the main window closes) and
    /// (b) still receives a tap that cold-launched the app. Required for foreground
    /// banners and tap routing to work at all.
    func registerDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Ask the OS for permission once, up front, so the first real notification
    /// isn't lost behind the prompt. Called from the UI (ContentView.onAppear) so
    /// the prompt appears with the window, not mid-launch. No-op if already decided.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A reply just finished in `conversation`. Surface it unless the user is
    /// already looking at that chat with the app focused.
    func replyFinished(conversation id: PersistentIdentifier, title: String, snippet: String) {
        if NSApplication.shared.isActive, foreground == id { return }

        let body = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }   // an error or empty turn isn't a "reply"

        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Reply ready" : title
        content.body = String(body.prefix(180))
        content.sound = .default
        // Stash the chat id so a tap can deep-link back to it. `userInfo` only takes
        // plist types, so encode the Codable PersistentIdentifier to Data.
        if let data = try? JSONEncoder().encode(id) {
            content.userInfo = [Self.conversationKey: data]
        }
        // Immediate, one-shot (nil trigger); a fresh id so replies don't coalesce.
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Present the banner even while the app is frontmost — but honor the same rule
    /// as `replyFinished`: stay silent if the user is now actively viewing the chat
    /// this reply belongs to. `add(_:)` is async, so a reply posted while its chat
    /// was backgrounded can reach here just after the user navigated back to it;
    /// re-checking `foreground` at present time closes that race.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = Self.conversationID(from: notification.request.content.userInfo)
        Task { @MainActor in
            if NSApplication.shared.isActive, let id, foreground == id {
                completionHandler([])   // user is looking at this chat — don't interrupt
            } else {
                completionHandler([.banner, .sound, .list])
            }
        }
    }

    /// The user tapped a reply notification — decode the chat id and hand it to
    /// `ContentView` (via `tappedConversation`) so it navigates there.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = Self.conversationID(from: response.notification.request.content.userInfo)
        Task { @MainActor in
            if let id { tappedConversation = id }
            NSApp.activate()   // bring the main window forward to show the chat
            completionHandler()
        }
    }

    /// Decode the chat `PersistentIdentifier` stamped into a notification's `userInfo`.
    nonisolated private static func conversationID(from userInfo: [AnyHashable: Any]) -> PersistentIdentifier? {
        (userInfo[conversationKey] as? Data)
            .flatMap { try? JSONDecoder().decode(PersistentIdentifier.self, from: $0) }
    }
}
