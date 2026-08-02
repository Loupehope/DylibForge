#import "MixedObjCAPI.h"

@implementation MixedLanguageMarker
- (NSInteger)validate {
    return 42;
}
@end

NSInteger MixedLanguageMarkerValue(void) {
    return [[MixedLanguageMarker new] validate];
}
