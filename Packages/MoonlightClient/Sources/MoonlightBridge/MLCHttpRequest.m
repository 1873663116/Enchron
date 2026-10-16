//
//  MLCHttpRequest.m
//  Adapted from moonlight-ios Limelight/Network/HttpRequest.m at 02dc9780.
//

#import "MLCHttpRequest.h"

@implementation MLCHttpRequest

+ (MLCHttpRequest*)requestForResponse:(id<MLCResponse>)response withUrlRequest:(NSURLRequest*)req {
    MLCHttpRequest* request = [[MLCHttpRequest alloc] init];
    request.request = req;
    request.response = response;
    return request;
}

+ (MLCHttpRequest*)requestWithUrlRequest:(NSURLRequest*)req {
    MLCHttpRequest* request = [[MLCHttpRequest alloc] init];
    request.request = req;
    return request;
}

+ (MLCHttpRequest*)requestForResponse:(id<MLCResponse>)response withUrlRequest:(NSURLRequest*)req fallbackError:(int)error fallbackRequest:(NSURLRequest*)fallbackReq {
    MLCHttpRequest* request = [[MLCHttpRequest alloc] init];
    request.request = req;
    request.response = response;
    request.fallbackError = error;
    request.fallbackRequest = fallbackReq;
    return request;
}

@end
