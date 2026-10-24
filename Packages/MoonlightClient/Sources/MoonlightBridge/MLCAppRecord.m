
#import "MLCAppRecord.h"

@implementation MLCAppRecord

- (NSComparisonResult)compareName:(MLCAppRecord*)other {
    return [self.name caseInsensitiveCompare:other.name];
}

@end
