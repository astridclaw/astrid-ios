import Foundation

struct ListFilters: Codable {
    var filterCompletion: String?     // "default", "all", "completed", "incomplete"
    var filterDueDate: String?        // "all", "overdue", "today", "this_week", etc.
    var filterAssignee: String?       // "all", "current_user", "not_current_user", "unassigned", userId
    var filterAssignedBy: String?     // "all", "current_user", userId
    var filterRepeating: String?      // "all", "not_repeating", "daily", "weekly", "monthly", "yearly"
    var filterPriority: String?       // "all", "0", "1", "2", "3"
    var filterInLists: String?        // "dont_filter", "in_list", "not_in_list"

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        if let completion = filterCompletion {
            dict["filterCompletion"] = completion
        }
        if let dueDate = filterDueDate {
            dict["filterDueDate"] = dueDate
        }
        if let assignee = filterAssignee {
            dict["filterAssignee"] = assignee
        }
        if let assignedBy = filterAssignedBy {
            dict["filterAssignedBy"] = assignedBy
        }
        if let repeating = filterRepeating {
            dict["filterRepeating"] = repeating
        }
        if let priority = filterPriority {
            dict["filterPriority"] = priority
        }
        if let inLists = filterInLists {
            dict["filterInLists"] = inLists
        }

        return dict
    }

    var hasActiveFilters: Bool {
        return filterCompletion != nil && filterCompletion != "default"
            || filterDueDate != nil && filterDueDate != "all"
            || filterAssignee != nil && filterAssignee != "all"
            || filterAssignedBy != nil && filterAssignedBy != "all"
            || filterRepeating != nil && filterRepeating != "all"
            || filterPriority != nil && filterPriority != "all"
            || filterInLists != nil && filterInLists != "dont_filter"
    }
}
