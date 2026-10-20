//
//  MLCHttpResponse.h
//  Adapted from moonlight-ios Limelight/Network/HttpResponse.h at 02dc9780.
//

#import <Foundation/Foundation.h>
#import "MLCLogger.h"

#ifndef MLC_HTTP_RESPONSE_H
#define MLC_HTTP_RESPONSE_H

static NSString* const MLCTAG_STATUS_CODE = @"status_code";
static NSString* const MLCTAG_STATUS_MESSAGE = @"status_message";

@protocol MLCResponse <NSObject>

- (void)populateWithData:(NSData*)data;

@property (nonatomic) NSInteger statusCode;
@property (nonatomic) NSString* statusMessage;
@property (nonatomic) NSData* data;

@end

@interface MLCHttpResponse : NSObject <MLCResponse>

- (void)populateWithData:(NSData*)data;
- (void)parseData;
- (NSString*)getStringTag:(NSString*)tag;
- (BOOL)getIntTag:(NSString*)tag value:(NSInteger*)value;
- (BOOL)isStatusOk;

@end

#endif
