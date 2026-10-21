
#import <Foundation/Foundation.h>

typedef NS_ENUM(int, MLCInputMouseButton) {
    MLCInputMouseButtonLeft = 0x01,
    MLCInputMouseButtonMiddle = 0x02,
    MLCInputMouseButtonRight = 0x03
};

@interface MLCInputSender : NSObject

+ (int)sendMouseMoveDeltaX:(short)deltaX deltaY:(short)deltaY;
+ (int)sendMousePositionNormalizedX:(float)x y:(float)y referenceWidth:(short)referenceWidth referenceHeight:(short)referenceHeight;
+ (int)sendMouseButton:(MLCInputMouseButton)button pressed:(BOOL)pressed;
+ (int)sendScrollVerticalClicks:(signed char)clicks;

+ (int)sendKeyWithHIDUsage:(NSInteger)usage down:(BOOL)down modifierFlags:(NSInteger)modifierFlags;
+ (int)sendVirtualKey:(int)keyCode down:(BOOL)down modifiers:(char)modifiers;

+ (int)sendControllerStateWithButtonFlags:(int)buttonFlags
                             leftTrigger:(unsigned char)leftTrigger
                            rightTrigger:(unsigned char)rightTrigger
                              leftStickX:(short)leftStickX
                              leftStickY:(short)leftStickY
                             rightStickX:(short)rightStickX
                             rightStickY:(short)rightStickY;
+ (int)sendControllerPresenceArrived:(BOOL)arrived;

+ (void)releaseAllPressedKeysAndButtons;
+ (void)requestIdrFrame;
+ (BOOL)estimatedRttMs:(uint32_t*)rtt variance:(uint32_t*)variance;

@end
