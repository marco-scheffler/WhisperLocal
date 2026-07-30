#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for exceptions converted by `WLCatchObjCException`.
extern NSErrorDomain const WLObjCExceptionErrorDomain;

/// Key under which the original `NSException` name is stored in the error's userInfo.
extern NSString *const WLObjCExceptionNameKey;

/// Runs `block`, converting a raised `NSException` into an `NSError`.
///
/// AVFAudio reports fatal misconfiguration (most notably a tap format that does
/// not match the input hardware) by raising an Objective-C exception. Swift's
/// `try` cannot catch those, and an uncaught one tears down the whole process
/// without producing a crash report. This shim turns it into a value Swift can
/// handle.
///
/// Returns `YES` if the block ran to completion, `NO` if it raised.
BOOL WLCatchObjCException(void (NS_NOESCAPE ^block)(void),
                          NSError *__autoreleasing _Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
