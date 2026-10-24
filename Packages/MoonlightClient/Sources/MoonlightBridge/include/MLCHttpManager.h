
#import <Foundation/Foundation.h>
#import "MLCHttpRequest.h"
#import "MLCHttpResponse.h"
#import "MLCHostRecord.h"
#import "MLCStreamConfiguration.h"

#ifndef MLC_HTTP_MANAGER_H
#define MLC_HTTP_MANAGER_H

@interface MLCHttpManager : NSObject <NSURLSessionDelegate>

- (id)initWithHost:(MLCHostRecord*)host;
- (id)initWithAddress:(NSString*)hostAddressPortString httpsPort:(unsigned short)httpsPort serverCert:(NSData*)serverCert;
- (void)setServerCert:(NSData*)serverCert;
- (NSURLRequest*)newPairRequest:(NSData*)salt clientCert:(NSData*)clientCert;
- (NSURLRequest*)newUnpairRequest;
- (NSURLRequest*)newChallengeRequest:(NSData*)challenge;
- (NSURLRequest*)newChallengeRespRequest:(NSData*)challengeResp;
- (NSURLRequest*)newClientSecretRespRequest:(NSString*)clientPairSecret;
- (NSURLRequest*)newPairChallenge;
- (NSURLRequest*)newAppListRequest;
- (NSURLRequest*)newServerInfoRequest:(bool)fastFail;
- (NSURLRequest*)newHttpServerInfoRequest:(bool)fastFail;
- (NSURLRequest*)newHttpServerInfoRequest;
- (NSURLRequest*)newLaunchOrResumeRequest:(NSString*)verb config:(MLCStreamConfiguration*)config;
- (NSURLRequest*)newQuitAppRequest;
- (NSURLRequest*)newAppAssetRequestWithAppId:(NSString*)appId;
- (void)executeRequestSynchronously:(MLCHttpRequest*)request;

@end

#endif
