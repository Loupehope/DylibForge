#import <Foundation/Foundation.h>

__attribute__((visibility("hidden")))
@interface PrivateObjCImplementation : NSObject
+ (NSInteger)fixtureValue;
@end

int validate(void);
