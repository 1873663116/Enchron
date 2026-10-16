//
//  MLCInputSender.h
//  Thin wrappers over the moonlight-common-c input API.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(int, MLCInputMouseButton) {
    MLCInputMouseButtonLeft = 0x01,
    MLCInputMouseButtonMiddle = 0x02,
    MLCInputMouseButtonRight = 0x03
};

@interface MLCInputSender : NSObject

+ (int)sendMouseMoveDeltaX:(short)deltaX deltaY:(short)deltaY;
+ (int)sendMousePositionNormalizedX:(float)x y:(float)y;
+ (int)sendMouseButton:(MLCInputMouseButton)button pressed:(BOOL)pressed;
+ (int)sendScrollVerticalClicks:(signed char)clicks;

// modifierFlags are UIKeyModifierFlags raw values.
+ (int)sendKeyWithHIDUsage:(NSInteger)usage down:(BOOL)down modifierFlags:(NSInteger)modifierFlags;
+ (int)sendVirtualKey:(int)keyCode down:(BOOL)down modifiers:(char)modifiers;

+ (void)releaseAllPressedKeysAndButtons;
+ (void)requestIdrFrame;
+ (BOOL)estimatedRttMs:(uint32_t*)rtt variance:(uint32_t*)variance;

@end
