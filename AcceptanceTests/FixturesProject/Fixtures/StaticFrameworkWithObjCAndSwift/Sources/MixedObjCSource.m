#import "MixedObjCAPI.h"

@implementation MixedLanguageMarker
+ (NSInteger)value {
    return 42;
}
@end

NSInteger MixedLanguageMarkerValue(void) { return [MixedLanguageMarker value]; }
