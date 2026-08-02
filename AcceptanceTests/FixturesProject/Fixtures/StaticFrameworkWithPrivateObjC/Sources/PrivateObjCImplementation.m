#import "StaticFrameworkWithPrivateObjC.h"

@implementation PrivateObjCImplementation
+ (NSInteger)fixtureValue {
    return 42;
}
@end

int validate(void) { return (int)PrivateObjCImplementation.fixtureValue; }
