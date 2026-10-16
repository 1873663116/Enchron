//
//  MLCServerInfoResponse.h
//  Adapted from moonlight-ios Limelight/Network/ServerInfoResponse.h at 02dc9780.
//

#import <Foundation/Foundation.h>
#import "MLCHttpResponse.h"
#import "MLCHostRecord.h"

#ifndef MLC_SERVER_INFO_RESPONSE_H
#define MLC_SERVER_INFO_RESPONSE_H

#define MLCTAG_HOSTNAME @"hostname"
#define MLCTAG_EXTERNAL_IP @"ExternalIP"
#define MLCTAG_HTTPS_PORT @"HttpsPort"
#define MLCTAG_LOCAL_IP @"LocalIP"
#define MLCTAG_UNIQUE_ID @"uniqueid"
#define MLCTAG_MAC_ADDRESS @"mac"
#define MLCTAG_PAIR_STATUS @"PairStatus"
#define MLCTAG_STATE @"state"
#define MLCTAG_CURRENT_GAME @"currentgame"

// Sunshine extension
#define MLCTAG_EXTERNAL_PORT @"ExternalPort"

@interface MLCServerInfoResponse : MLCHttpResponse <MLCResponse>

- (void)populateWithData:(NSData*)data;
- (void)populateHost:(MLCHostRecord*)host;

@end

#endif
