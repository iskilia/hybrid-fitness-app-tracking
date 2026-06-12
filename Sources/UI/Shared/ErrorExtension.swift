import Foundation

extension Error {
    /// Returns a user-friendly message, unwrapping `DatabaseError.conflict`'s
    /// embedded string so callers get clean copy instead of a raw Swift description.
    var userMessage: String {
        if let dbErr = self as? DatabaseError,
           case .conflict(let msg) = dbErr {
            return msg
        }
        return localizedDescription
    }
}
