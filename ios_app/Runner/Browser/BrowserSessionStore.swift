import Foundation

@MainActor
final class BrowserSessionStore {
    static let shared = BrowserSessionStore()

    private var snapshotsByWorkspaceId: [String: BrowserSessionSnapshotMessage] = [:]
    private var snapshot = BrowserSessionSnapshotMessage(
        available: false,
        workspaceId: "",
        activeTabId: nil,
        currentUrl: "",
        title: "",
        userAgentProfile: nil
    )

    private init() {}

    func currentSnapshot() -> BrowserSessionSnapshotMessage {
        snapshot
    }

    func snapshot(for workspaceId: String) -> BrowserSessionSnapshotMessage? {
        let normalizedWorkspaceId = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedWorkspaceId.isEmpty == false else { return nil }
        return snapshotsByWorkspaceId[normalizedWorkspaceId]
    }

    func update(
        available: Bool,
        workspaceId: String,
        activeTabId: Int64?,
        currentUrl: String,
        title: String,
        userAgentProfile: String?
    ) {
        snapshot = BrowserSessionSnapshotMessage(
            available: available,
            workspaceId: workspaceId,
            activeTabId: activeTabId,
            currentUrl: currentUrl,
            title: title,
            userAgentProfile: userAgentProfile
        )
        if workspaceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            snapshotsByWorkspaceId[workspaceId] = snapshot
        }
    }

    func markDetached(workspaceId: String, activeTabId: Int64?) {
        let normalizedWorkspaceId = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedWorkspaceId.isEmpty == false else { return }
        guard let existing = snapshotsByWorkspaceId[normalizedWorkspaceId] else { return }
        let updated = BrowserSessionSnapshotMessage(
            available: true,
            workspaceId: normalizedWorkspaceId,
            activeTabId: activeTabId ?? existing.activeTabId,
            currentUrl: existing.currentUrl,
            title: existing.title,
            userAgentProfile: existing.userAgentProfile
        )
        snapshotsByWorkspaceId[normalizedWorkspaceId] = updated
        if snapshot.workspaceId == normalizedWorkspaceId {
            snapshot = updated
        }
    }
}
