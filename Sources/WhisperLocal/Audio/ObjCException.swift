import Foundation
import ObjCExceptionCatcher

/// Swift-friendly wrapper around the Objective-C exception shim.
enum ObjCException {
    /// Runs `body`, rethrowing any raised Objective-C exception as a Swift error.
    static func catching(_ body: () -> Void) throws {
        var error: NSError?
        guard WLCatchObjCException(body, &error) else {
            throw error ?? NSError(
                domain: WLObjCExceptionErrorDomain,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown Objective-C exception"]
            )
        }
    }
}
