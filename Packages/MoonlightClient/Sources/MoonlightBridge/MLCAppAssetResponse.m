#import "MLCAppAssetResponse.h"

@implementation MLCAppAssetResponse
@synthesize data, statusCode, statusMessage;

- (void)populateWithData:(NSData*)imageData {
    self.data = imageData;
    self.statusMessage = @"App asset has no status message";
    self.statusCode = -1;
}

@end
