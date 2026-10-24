
#import "MLCHostRecord.h"

@implementation MLCHostRecord

- (id)init {
    self = [super init];
    _name = @"";
    _uuid = @"";
    _appList = @[];
    return self;
}

- (NSComparisonResult)compareName:(MLCHostRecord*)other {
    return [self.name caseInsensitiveCompare:other.name];
}

@end
