
#import "MLCServerInfoResponse.h"
#import "MLCUtils.h"

@interface NSString (MLCTrim)
- (NSString*)mlcTrim;
@end

@implementation NSString (MLCTrim)
- (NSString*)mlcTrim {
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
@end

@implementation MLCServerInfoResponse
@synthesize data, statusCode, statusMessage;

- (void)populateWithData:(NSData*)xml {
    self.data = xml;
    [super parseData];
}

- (void)populateHost:(MLCHostRecord*)host {
    host.name = [[self getStringTag:MLCTAG_HOSTNAME] mlcTrim];
    host.uuid = [[self getStringTag:MLCTAG_UNIQUE_ID] mlcTrim];
    host.mac = [[self getStringTag:MLCTAG_MAC_ADDRESS] mlcTrim];
    host.currentGame = [[self getStringTag:MLCTAG_CURRENT_GAME] mlcTrim];

    NSInteger httpsPort;
    if ([self getIntTag:MLCTAG_HTTPS_PORT value:&httpsPort]) {
        host.httpsPort = (unsigned short)httpsPort;
    }
    else {
        host.httpsPort = 47984;
    }

    NSString* lanAddr = [[self getStringTag:MLCTAG_LOCAL_IP] mlcTrim];
    if (![lanAddr hasPrefix:@"127."]) {
        unsigned short localPort;

        if (host.addressPortString && [lanAddr isEqualToString:[MLCUtils addressPortStringToAddress:host.addressPortString]]) {
            localPort = [MLCUtils addressPortStringToPort:host.addressPortString];
        }
        else if (host.localAddress) {
            localPort = [MLCUtils addressPortStringToPort:host.localAddress];
        }
        else {
            localPort = 47989;
        }

        host.localAddress = [MLCUtils addressAndPortToAddressPortString:lanAddr port:localPort];
    }

    NSInteger externalHttpPort;
    if (![self getIntTag:MLCTAG_EXTERNAL_PORT value:&externalHttpPort]) {
        if (host.addressPortString) {
            externalHttpPort = [MLCUtils addressPortStringToPort:host.addressPortString];
        }
        else {
            externalHttpPort = 47989;
        }
    }

    NSString* wanAddr = [[self getStringTag:MLCTAG_EXTERNAL_IP] mlcTrim];
    if (wanAddr) {
        host.externalAddress = [MLCUtils addressAndPortToAddressPortString:wanAddr port:externalHttpPort];
    }
    else if (host.externalAddress) {
        host.externalAddress = [MLCUtils addressAndPortToAddressPortString:[MLCUtils addressPortStringToAddress:host.externalAddress] port:externalHttpPort];
    }

    NSString* state = [[self getStringTag:MLCTAG_STATE] mlcTrim];
    if (![state hasSuffix:@"_SERVER_BUSY"]) {
        host.currentGame = @"0";
    }

    host.isNvidiaServerSoftware = [state containsString:@"MJOLNIR"];

    NSInteger pairStatus;
    if ([self getIntTag:MLCTAG_PAIR_STATUS value:&pairStatus]) {
        host.pairState = pairStatus ? PairStatePaired : PairStateUnpaired;
    } else {
        host.pairState = PairStateUnknown;
    }

    NSString* serverCodecModeString = [self getStringTag:@"ServerCodecModeSupport"];
    if (serverCodecModeString != nil) {
        host.serverCodecModeSupport = [[serverCodecModeString mlcTrim] intValue];
    }
}

@end
