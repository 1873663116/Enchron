
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
- (void)controllerRumble:(unsigned short)controllerNumber
                 lowFreq:(unsigned short)lowFrequency
                highFreq:(unsigned short)highFrequency;
- (void)controllerRumbleTriggers:(uint16_t)controllerNumber
                            left:(uint16_t)leftTrigger
                           right:(uint16_t)rightTrigger;
- (void)controllerMotionRequest:(uint16_t)controllerNumber
                      motionType:(uint8_t)motionType
                     reportRateHz:(uint16_t)reportRateHz;
- (void)controllerLed:(uint16_t)controllerNumber
                    r:(uint8_t)r
                    g:(uint8_t)g
                    b:(uint8_t)b;

@end
