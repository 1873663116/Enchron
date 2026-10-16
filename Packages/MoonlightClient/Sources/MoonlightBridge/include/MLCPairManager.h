//
//  MLCPairManager.h
//  Adapted from moonlight-ios Limelight/Network/PairManager.h at 02dc9780.
//

#import <Foundation/Foundation.h>
#import "MLCHttpManager.h"

#ifndef MLC_PAIR_MANAGER_H
#define MLC_PAIR_MANAGER_H

@protocol MLCPairCallback <NSObject>

- (void)startPairing:(NSString*)PIN;
- (void)pairSuccessful:(NSData*)serverCert;
- (void)pairFailed:(NSString*)message;
- (void)alreadyPaired;

@end

@interface MLCPairManager : NSOperation

- (id)initWithManager:(MLCHttpManager*)httpManager clientCert:(NSData*)clientCert callback:(id<MLCPairCallback>)callback;
- (id)initWithManager:(MLCHttpManager*)httpManager clientCert:(NSData*)clientCert callback:(id<MLCPairCallback>)callback pin:(NSString*)pin;

@end

#endif
