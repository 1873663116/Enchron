
#import <Foundation/Foundation.h>
#import "MLCLogger.h"

typedef NS_ENUM(int, PairState) {
    PairStateUnknown,
    PairStateUnpaired,
    PairStatePaired
};

typedef NS_ENUM(int, HostState) {
    HostStateUnknown,
    HostStateOffline,
    HostStateOnline
};

@interface MLCUtils : NSObject

+ (NSData*)randomBytes:(NSInteger)length;
+ (NSString*)bytesToHex:(NSData*)data;
+ (NSData*)hexToBytes:(NSString*)hex;
+ (BOOL)parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port;
+ (NSString*)addressPortStringToAddress:(NSString*)addressPort;
+ (unsigned short)addressPortStringToPort:(NSString*)addressPort;
+ (NSString*)addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port;

@end

NSString* MLCDeviceName(void);
void MLCSetDeviceName(NSString* name);
