#import <Foundation/Foundation.h>
#import "MLCHttpResponse.h"

@interface MLCAppAssetResponse : NSObject <MLCResponse>

- (void)populateWithData:(NSData*)data;

@property (nonatomic) NSInteger statusCode;
@property (nonatomic) NSString* statusMessage;
@property (nonatomic) NSData* data;

@end
