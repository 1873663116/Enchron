//
//  MLCServerInfoResponse.m
//  Adapted from moonlight-ios Limelight/Network/ServerInfoResponse.m at 02dc9780.
//

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
        // Use the default if it's not specified
        host.httpsPort = 47984;
    }

    // We might get an IPv4 loopback address if we're using GS IPv6 Forwarder
    NSString* lanAddr = [[self getStringTag:MLCTAG_LOCAL_IP] mlcTrim];
    if (![lanAddr hasPrefix:@"127."]) {
        unsigned short localPort;

        // If we reached this host through this port, store our port there
        if (host.addressPortString && [lanAddr isEqualToString:[MLCUtils addressPortStringToAddress:host.addressPortString]]) {
            localPort = [MLCUtils addressPortStringToPort:host.addressPortString];
        }
        else if (host.localAddress) {
            // If there's an existing local address, use the port from that
            localPort = [MLCUtils addressPortStringToPort:host.localAddress];
        }
        else {
            // If all else fails, use 47989
            localPort = 47989;
        }

        host.localAddress = [MLCUtils addressAndPortToAddressPortString:lanAddr port:localPort];
    }

    // This is a Sunshine extension for WAN port remapping
    NSInteger externalHttpPort;
    if (![self getIntTag:MLCTAG_EXTERNAL_PORT value:&externalHttpPort]) {
        // Use our active port if it's not specified
        if (host.addressPortString) {
            externalHttpPort = [MLCUtils addressPortStringToPort:host.addressPortString];
        }
        else {
            // Otherwise use the default
            externalHttpPort = 47989;
        }
    }

    // Modern GFE versions don't actually give us a WAN address anymore
    // so we leave the one that we populated from mDNS discovery via STUN.
    NSString* wanAddr = [[self getStringTag:MLCTAG_EXTERNAL_IP] mlcTrim];
    if (wanAddr) {
        host.externalAddress = [MLCUtils addressAndPortToAddressPortString:wanAddr port:externalHttpPort];
    }
    else if (host.externalAddress) {
        // If we have an external address (via STUN) already, we still need to populate the port
        host.externalAddress = [MLCUtils addressAndPortToAddressPortString:[MLCUtils addressPortStringToAddress:host.externalAddress] port:externalHttpPort];
    }

    NSString* state = [[self getStringTag:MLCTAG_STATE] mlcTrim];
    if (![state hasSuffix:@"_SERVER_BUSY"]) {
        // GFE 2.8 started keeping currentgame set to the last game played. As a result, it no longer
        // has the semantics that its name would indicate. To contain the effects of this change as much
        // as possible, we'll force the current game to zero if the server isn't in a streaming session.
        host.currentGame = @"0";
    }

    // GFE uses the Mjolnir codename in their state enum values
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
