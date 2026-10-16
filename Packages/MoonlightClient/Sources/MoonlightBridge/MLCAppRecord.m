//
//  MLCAppRecord.m
//  Adapted from moonlight-ios Limelight/Database/TemporaryApp.m at 02dc9780.
//

#import "MLCAppRecord.h"

@implementation MLCAppRecord

- (NSComparisonResult)compareName:(MLCAppRecord*)other {
    return [self.name caseInsensitiveCompare:other.name];
}

@end
