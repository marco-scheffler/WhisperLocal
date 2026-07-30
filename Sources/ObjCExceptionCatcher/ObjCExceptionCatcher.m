#import "ObjCExceptionCatcher.h"

NSErrorDomain const WLObjCExceptionErrorDomain = @"WhisperLocal.ObjCException";
NSString *const WLObjCExceptionNameKey = @"WLObjCExceptionName";

BOOL WLCatchObjCException(void (NS_NOESCAPE ^block)(void),
                          NSError *__autoreleasing _Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            info[WLObjCExceptionNameKey] = exception.name;
            *error = [NSError errorWithDomain:WLObjCExceptionErrorDomain
                                         code:1
                                     userInfo:info];
        }
        return NO;
    }
}
