import Foundation

/// Secure value transformer for [String] arrays used in Core Data
/// Fixes warning: "CDTask.listIds is using a nil or insecure value transformer"
@objc(StringArrayTransformer)
final class StringArrayTransformer: NSSecureUnarchiveFromDataTransformer {

    /// The name of the transformer for use in Core Data model
    static let name = NSValueTransformerName(rawValue: "StringArrayTransformer")

    /// Supported class types for secure unarchiving
    override class var allowedTopLevelClasses: [AnyClass] {
        return [NSArray.self, NSString.self]
    }

    /// Register the transformer on app launch
    public static func register() {
        let transformer = StringArrayTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}
