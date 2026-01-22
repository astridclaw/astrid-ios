import CoreData
import Foundation

/**
 * CDReminderMapping
 *
 * CoreData entity for tracking the mapping between Astrid tasks and Apple Reminders.
 * Each mapping represents a link between one Astrid task and one EKReminder.
 */
@objc(CDReminderMapping)
public class CDReminderMapping: NSManagedObject {
    /// The Astrid task ID (optional for migration compatibility)
    @NSManaged public var astridTaskId: String?

    /// The Astrid list ID this task belongs to
    @NSManaged public var astridListId: String?

    /// The Apple Reminders calendarItemIdentifier (optional for migration compatibility)
    @NSManaged public var reminderIdentifier: String?

    /// The Apple Reminders calendar (list) identifier
    @NSManaged public var reminderCalendarIdentifier: String?

    /// When this mapping was last synced
    @NSManaged public var lastSyncedAt: Date?

    /// The updatedAt timestamp from Astrid at last sync
    @NSManaged public var astridUpdatedAt: Date?

    /// The lastModifiedDate from Reminders at last sync
    @NSManaged public var reminderUpdatedAt: Date?
}

extension CDReminderMapping {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDReminderMapping> {
        return NSFetchRequest<CDReminderMapping>(entityName: "CDReminderMapping")
    }

    /// Fetch all mappings
    static func fetchAll(context: NSManagedObjectContext) throws -> [CDReminderMapping] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "lastSyncedAt", ascending: false)]
        return try context.fetch(request)
    }

    /// Fetch mapping by Astrid task ID
    static func fetchByTaskId(_ taskId: String, context: NSManagedObjectContext) throws -> CDReminderMapping? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "astridTaskId == %@", taskId)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Fetch mapping by Reminder identifier
    static func fetchByReminderIdentifier(_ identifier: String, context: NSManagedObjectContext) throws -> CDReminderMapping? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "reminderIdentifier == %@", identifier)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Fetch all mappings for a specific Astrid list
    static func fetchByListId(_ listId: String, context: NSManagedObjectContext) throws -> [CDReminderMapping] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "astridListId == %@", listId)
        request.sortDescriptors = [NSSortDescriptor(key: "lastSyncedAt", ascending: false)]
        return try context.fetch(request)
    }

    /// Fetch all mappings for a specific Reminders calendar
    static func fetchByCalendarIdentifier(_ calendarId: String, context: NSManagedObjectContext) throws -> [CDReminderMapping] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "reminderCalendarIdentifier == %@", calendarId)
        request.sortDescriptors = [NSSortDescriptor(key: "lastSyncedAt", ascending: false)]
        return try context.fetch(request)
    }

    /// Delete all mappings for a specific Astrid list
    static func deleteByListId(_ listId: String, context: NSManagedObjectContext) throws {
        let mappings = try fetchByListId(listId, context: context)
        for mapping in mappings {
            context.delete(mapping)
        }
        try context.save()
    }

    /// Delete a mapping by Astrid task ID
    static func deleteByTaskId(_ taskId: String, context: NSManagedObjectContext) throws {
        if let mapping = try fetchByTaskId(taskId, context: context) {
            context.delete(mapping)
            try context.save()
        }
    }

    /// Create or update a mapping
    static func upsert(
        astridTaskId: String,
        astridListId: String?,
        reminderIdentifier: String,
        reminderCalendarIdentifier: String?,
        astridUpdatedAt: Date?,
        reminderUpdatedAt: Date?,
        context: NSManagedObjectContext
    ) throws -> CDReminderMapping {
        let mapping: CDReminderMapping

        if let existing = try fetchByTaskId(astridTaskId, context: context) {
            mapping = existing
        } else {
            mapping = CDReminderMapping(context: context)
            mapping.astridTaskId = astridTaskId
        }

        mapping.astridListId = astridListId
        mapping.reminderIdentifier = reminderIdentifier
        mapping.reminderCalendarIdentifier = reminderCalendarIdentifier
        mapping.astridUpdatedAt = astridUpdatedAt
        mapping.reminderUpdatedAt = reminderUpdatedAt
        mapping.lastSyncedAt = Date()

        try context.save()
        return mapping
    }

    /// Get the count of all mappings
    static func count(context: NSManagedObjectContext) throws -> Int {
        let request = fetchRequest()
        return try context.count(for: request)
    }

    /// Get the count of mappings for a specific list
    static func countForList(_ listId: String, context: NSManagedObjectContext) throws -> Int {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "astridListId == %@", listId)
        return try context.count(for: request)
    }
}
