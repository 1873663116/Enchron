
#import <Foundation/Foundation.h>

typedef NS_ENUM(int, MLCInputMouseButton) {
    MLCInputMouseButtonLeft = 0x01,
    MLCInputMouseButtonMiddle = 0x02,
    MLCInputMouseButtonRight = 0x03,
    MLCInputMouseButtonX1 = 0x04,
    MLCInputMouseButtonX2 = 0x05
};

@interface MLCInputSender : NSObject

+ (int)sendMouseMoveDeltaX:(short)deltaX deltaY:(short)deltaY;
+ (int)sendMousePositionNormalizedX:(float)x y:(float)y referenceWidth:(short)referenceWidth referenceHeight:(short)referenceHeight;
+ (int)sendMouseButton:(MLCInputMouseButton)button pressed:(BOOL)pressed;
+ (int)sendScrollVerticalClicks:(signed char)clicks;
+ (int)sendHighResScrollVertical:(short)amount;
+ (int)sendHighResScrollHorizontal:(short)amount;

+ (int)sendKeyWithHIDUsage:(NSInteger)usage down:(BOOL)down modifierFlags:(NSInteger)modifierFlags;
+ (int)sendVirtualKey:(int)keyCode down:(BOOL)down modifiers:(char)modifiers;

+ (int)sendControllerStateWithButtonFlags:(int)buttonFlags
                             leftTrigger:(unsigned char)leftTrigger
                            rightTrigger:(unsigned char)rightTrigger
                              leftStickX:(short)leftStickX
                              leftStickY:(short)leftStickY
                             rightStickX:(short)rightStickX
                             rightStickY:(short)rightStickY;
+ (int)sendControllerArrivalNumber:(uint8_t)controllerNumber
                     gamepadMask:(uint16_t)gamepadMask
                            type:(uint8_t)type
                         buttons:(uint32_t)supportedButtons
                    capabilities:(uint16_t)capabilities;
+ (int)sendControllerRemovalNumber:(uint8_t)controllerNumber;
+ (int)sendControllerTouchNumber:(uint8_t)controllerNumber
                       eventType:(uint8_t)eventType
                       pointerId:(uint32_t)pointerId
                               x:(float)x
                               y:(float)y
                        pressure:(float)pressure;
+ (int)sendControllerMotionNumber:(uint8_t)controllerNumber
                             type:(uint8_t)motionType
                                x:(float)x
                                y:(float)y
                                z:(float)z;
+ (int)sendControllerBatteryNumber:(uint8_t)controllerNumber
                            state:(uint8_t)state
                       percentage:(uint8_t)percentage;

+ (void)releaseAllPressedKeysAndButtons;
+ (void)requestIdrFrame;
+ (BOOL)estimatedRttMs:(uint32_t*)rtt variance:(uint32_t*)variance;

@end
