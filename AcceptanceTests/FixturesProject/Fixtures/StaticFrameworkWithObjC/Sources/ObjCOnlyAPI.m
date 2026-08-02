#import "StaticFrameworkWithObjC.h"

@interface ObjectiveCOnlyValue : NSObject
+ (NSInteger)value;
@end

@implementation ObjectiveCOnlyValue
+ (NSInteger)value {
    return 42;
}
@end

int validate(void) { return (int)ObjectiveCOnlyValue.value; }
