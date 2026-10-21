
#import "MLCIdManager.h"
#import "MLCLogger.h"

static NSString* const MLCUniqueIdKey = @"MLCUniqueId";

@implementation MLCIdManager

+ (NSString*)getUniqueId {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    NSString* uniqueId = [defaults stringForKey:MLCUniqueIdKey];
    if (uniqueId == nil) {
        uniqueId = [MLCIdManager generateUniqueId];
        [defaults setObject:uniqueId forKey:MLCUniqueIdKey];
        Log(LOG_I, @"No UUID found. Generated new UUID: %@", uniqueId);
    }

    return uniqueId;
}

+ (NSString*)generateUniqueId {
    UInt64 uuidLong = ((UInt64)arc4random() << 32) | arc4random();
    return [NSString stringWithFormat:@"%016llx", uuidLong];
}

@end
