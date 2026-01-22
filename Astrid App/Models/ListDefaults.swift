import Foundation

struct ListDefaults: Codable {
    var defaultAssigneeId: String?
    var defaultPriority: Int?
    var defaultRepeating: String?
    var defaultIsPrivate: Bool?
    var defaultDueDate: String?
    var defaultDueTime: String?

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        // CRITICAL: Always include defaultAssigneeId to support "Task Creator" (nil) option
        // nil = "task_creator" (assign to current user), "unassigned" = no assignee, otherwise = specific user ID
        if let assigneeId = defaultAssigneeId {
            dict["defaultAssigneeId"] = assigneeId
        } else {
            // Send null to server to indicate "Task Creator" (clears any previously set value)
            dict["defaultAssigneeId"] = NSNull()
        }
        if let priority = defaultPriority {
            dict["defaultPriority"] = priority
        }
        if let repeating = defaultRepeating {
            dict["defaultRepeating"] = repeating
        }
        if let isPrivate = defaultIsPrivate {
            dict["defaultIsPrivate"] = isPrivate
        }
        if let dueDate = defaultDueDate {
            dict["defaultDueDate"] = dueDate
        }
        if let dueTime = defaultDueTime {
            dict["defaultDueTime"] = dueTime
        }

        return dict
    }
}
