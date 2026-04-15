import Foundation

@MainActor
final class WorkspaceScheduledTaskStore {
    static let shared = WorkspaceScheduledTaskStore()

    private init() {}

    func listTasks() -> [[String: Any]] {
        loadTasks()
    }

    func upsertTask(_ raw: [String: Any]) -> [String: Any] {
        var tasks = loadTasks()
        let normalized = sanitizeTask(raw)
        let taskID = (normalized["id"] as? String) ?? ""
        if let index = tasks.firstIndex(where: { (($0["id"] as? String) ?? "") == taskID }) {
            tasks[index] = normalized
        } else {
            tasks.append(normalized)
        }
        saveTasks(tasks)
        return normalized
    }

    func deleteTask(taskId: String) -> Bool {
        let normalizedTaskID = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTaskID.isEmpty == false else { return false }
        var tasks = loadTasks()
        let oldCount = tasks.count
        tasks.removeAll(where: { (($0["id"] as? String) ?? "") == normalizedTaskID })
        saveTasks(tasks)
        return tasks.count != oldCount
    }

    func syncTasks(_ rawTasks: [[String: Any]]) -> Int {
        let normalized = rawTasks.map(sanitizeTask)
        saveTasks(normalized)
        return normalized.count
    }

    private var tasksURL: URL {
        IOSWorkspaceSupport.scheduleRootURL.appendingPathComponent("tasks.json")
    }

    private func loadTasks() -> [[String: Any]] {
        guard let object = IOSWorkspaceSupport.readJSONObject(at: tasksURL) as? [[String: Any]] else {
            return []
        }
        return object.map(sanitizeTask)
    }

    private func saveTasks(_ tasks: [[String: Any]]) {
        try? IOSWorkspaceSupport.writeJSONObject(tasks, to: tasksURL)
    }

    private func sanitizeTask(_ raw: [String: Any]) -> [String: Any] {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let taskID = normalizedOptionalString(raw["id"]) ?? UUID().uuidString
        let title = normalizedOptionalString(raw["title"]) ?? "未命名定时任务"
        return [
            "id": taskID,
            "title": title,
            "packageName": normalizedOptionalString(raw["packageName"]) ?? "",
            "nodeId": normalizedOptionalString(raw["nodeId"]) ?? "",
            "suggestionId": normalizedOptionalString(raw["suggestionId"]) ?? "",
            "targetKind": normalizedOptionalString(raw["targetKind"]) ?? "vlm",
            "subagentConversationId": normalizedOptionalString(raw["subagentConversationId"]) ?? NSNull(),
            "subagentPrompt": normalizedOptionalString(raw["subagentPrompt"]) ?? NSNull(),
            "notificationEnabled": boolValue(raw["notificationEnabled"], defaultValue: true),
            "type": normalizedOptionalString(raw["type"]) ?? "fixedTime",
            "fixedTime": normalizedOptionalString(raw["fixedTime"]) ?? NSNull(),
            "countdownMinutes": integerValue(raw["countdownMinutes"]) ?? NSNull(),
            "repeatDaily": boolValue(raw["repeatDaily"], defaultValue: false),
            "isEnabled": boolValue(raw["isEnabled"], defaultValue: true),
            "createdAt": integerValue(raw["createdAt"]) ?? now,
            "nextExecutionTime": integerValue(raw["nextExecutionTime"]) ?? NSNull(),
            "suggestionData": dictionaryValue(raw["suggestionData"]) ?? NSNull(),
            "appIconUrl": normalizedOptionalString(raw["appIconUrl"]) ?? NSNull(),
            "typeIconUrl": normalizedOptionalString(raw["typeIconUrl"]) ?? NSNull(),
        ]
    }

    private func normalizedOptionalString(_ raw: Any?) -> String? {
        switch raw {
        case let string as String:
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func integerValue(_ raw: Any?) -> Int? {
        switch raw {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func boolValue(_ raw: Any?, defaultValue: Bool) -> Bool {
        switch raw {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return defaultValue
            }
        default:
            return defaultValue
        }
    }

    private func dictionaryValue(_ raw: Any?) -> [String: Any]? {
        if let dictionary = raw as? [String: Any] {
            return dictionary
        }
        if let dictionary = raw as? [AnyHashable: Any] {
            return dictionary.reduce(into: [String: Any]()) { partialResult, entry in
                partialResult[String(describing: entry.key)] = entry.value
            }
        }
        return nil
    }
}
