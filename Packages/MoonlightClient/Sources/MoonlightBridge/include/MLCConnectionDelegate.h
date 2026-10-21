
#import <Foundation/Foundation.h>

@protocol MLCConnectionDelegate <NSObject>

- (void)connectionStarted;
- (void)connectionTerminated:(int)errorCode;
- (void)stageStarting:(const char*)stageName;
- (void)stageComplete:(const char*)stageName;
- (void)stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags;
- (void)connectionStatusUpdate:(int)status;
- (void)setHdrMode:(bool)enabled;
- (void)videoContentShown;

@end
