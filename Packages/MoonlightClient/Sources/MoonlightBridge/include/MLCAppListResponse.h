
#import <Foundation/Foundation.h>
#import "MLCHttpResponse.h"

#ifndef MLC_APP_LIST_RESPONSE_H
#define MLC_APP_LIST_RESPONSE_H

@interface MLCAppListResponse : NSObject <MLCResponse>

- (void)populateWithData:(NSData*)data;
- (NSSet*)getAppList;
- (BOOL)isStatusOk;

@end

#endif
