//
//  MLCHttpRequest.h
//  Adapted from moonlight-ios Limelight/Network/HttpRequest.h at 02dc9780.
//

#import <Foundation/Foundation.h>
#import "MLCHttpResponse.h"

#ifndef MLC_HTTP_REQUEST_H
#define MLC_HTTP_REQUEST_H

@interface MLCHttpRequest : NSObject

@property (nonatomic) id<MLCResponse> response;
@property (nonatomic) NSURLRequest* request;
@property (nonatomic) int fallbackError;
@property (nonatomic) NSURLRequest* fallbackRequest;

+ (instancetype)requestForResponse:(id<MLCResponse>)response withUrlRequest:(NSURLRequest*)req fallbackError:(int)error fallbackRequest:(NSURLRequest*)fallbackReq;
+ (instancetype)requestForResponse:(id<MLCResponse>)response withUrlRequest:(NSURLRequest*)req;
+ (instancetype)requestWithUrlRequest:(NSURLRequest*)req;

@end

#endif
