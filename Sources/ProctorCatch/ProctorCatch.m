#import "include/ProctorCatch.h"

NSString *_Nullable ProctorCatchNSException(void(NS_NOESCAPE ^ _Nonnull body)(void)) {
    @try {
        body();
        return nil;
    } @catch (NSException *exception) {
        // The reason is the half that identifies the defect; the name and the
        // stack are what make a second occurrence diagnosable without a crash
        // report. The first occurrence of this in the run HUD left only a stack,
        // which is why the intermittent nil behind it is still unidentified.
        NSString *stack = [[exception callStackSymbols] componentsJoinedByString:@"\n"] ?: @"";
        return [NSString stringWithFormat:@"%@: %@\n%@",
                exception.name ?: @"NSException",
                exception.reason ?: @"no reason given",
                stack];
    }
}
