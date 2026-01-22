# Core Data Model Setup

Since Core Data model files (.xcdatamodeld) require Xcode GUI, follow these steps:

## Create Core Data Model in Xcode:

1. **File > New > File > Core Data > Data Model**
2. Name: `AstridApp`
3. Save in `Resources/` folder

## Add CDTask Entity:
Attributes:
- id: String
- title: String
- taskDescription: String
- priority: Integer 16
- completed: Boolean
- isPrivate: Boolean
- repeating: String
- dueDateTime: Date (optional)
- reminderTime: Date (optional)
- reminderSent: Boolean
- reminderType: String (optional)
- createdAt: Date (optional)
- updatedAt: Date (optional)
- syncStatus: String
- lastSyncedAt: Date (optional)
- assigneeId: String (optional)
- creatorId: String
- listIds: Transformable (optional)
- repeatingDataJSON: String (optional)

Class: CDTask, Module: Current Product Module, Codegen: Manual/None

## Add CDTaskList Entity:
Attributes:
- id: String
- name: String
- listDescription: String (optional)
- color: String (optional)
- imageUrl: String (optional)
- privacy: String
- ownerId: String
- isFavorite: Boolean
- favoriteOrder: Integer 32
- createdAt: Date (optional)
- updatedAt: Date (optional)
- syncStatus: String
- lastSyncedAt: Date (optional)
- defaultAssigneeId: String (optional)
- defaultPriority: Integer 16
- defaultRepeating: String (optional)
- defaultIsPrivate: Boolean
- defaultDueDate: String (optional)

Class: CDTaskList, Module: Current Product Module, Codegen: Manual/None
