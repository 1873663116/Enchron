
#import "MLCInputSender.h"
#import "MLCKeyboardMap.h"
#import "MLCLogger.h"

#include <Limelight.h>

#define MLC_INPUT_EXTENDED_KEY_BIT 0x8000

static NSLock* pressedStateLock;
static NSMutableSet<NSNumber*>* pressedVirtualKeys;
static NSMutableSet<NSNumber*>* pressedMouseButtons;
static BOOL controllerInputActive;

@implementation MLCInputSender

+ (void)initialize {
    if (self == [MLCInputSender class]) {
        pressedStateLock = [[NSLock alloc] init];
        pressedVirtualKeys = [[NSMutableSet alloc] init];
        pressedMouseButtons = [[NSMutableSet alloc] init];
    }
}

+ (int)sendVirtualKey:(int)keyCode down:(BOOL)down modifiers:(char)modifiers {
    [pressedStateLock lock];
    if (down) {
        [pressedVirtualKeys addObject:@(keyCode)];
    }
    else {
        [pressedVirtualKeys removeObject:@(keyCode)];
    }
    [pressedStateLock unlock];

    return LiSendKeyboardEvent((short)(MLC_INPUT_EXTENDED_KEY_BIT | keyCode),
                               down ? KEY_ACTION_DOWN : KEY_ACTION_UP,
                               modifiers);
}

+ (int)sendKeyWithHIDUsage:(NSInteger)usage down:(BOOL)down modifierFlags:(NSInteger)modifierFlags {
    int keyCode = [MLCKeyboardMap windowsKeyCodeForHIDUsage:usage];
    if (keyCode == 0) {
        Log(LOG_W, @"Unhandled HID usage: %ld", (long)usage);
        return -1;
    }

    char modifiers = [MLCKeyboardMap modifiersForHIDUsage:usage];
    modifiers |= [MLCKeyboardMap modifiersForKeyModifierFlags:modifierFlags];

    return [self sendVirtualKey:keyCode down:down modifiers:modifiers];
}

+ (void)releaseAllPressedKeysAndButtons {
    [pressedStateLock lock];
    NSArray<NSNumber*>* keys = [pressedVirtualKeys allObjects];
    NSArray<NSNumber*>* buttons = [pressedMouseButtons allObjects];
    [pressedVirtualKeys removeAllObjects];
    [pressedMouseButtons removeAllObjects];
    [pressedStateLock unlock];

    for (NSNumber* keyCode in keys) {
        LiSendKeyboardEvent((short)(MLC_INPUT_EXTENDED_KEY_BIT | keyCode.intValue), KEY_ACTION_UP, 0);
    }

    for (NSNumber* button in buttons) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, button.intValue);
    }

    if (controllerInputActive) {
        controllerInputActive = NO;
        LiSendControllerEvent(0, 0, 0, 0, 0, 0, 0);
    }
}

+ (int)sendMouseMoveDeltaX:(short)deltaX deltaY:(short)deltaY {
    return LiSendMouseMoveEvent(deltaX, deltaY);
}

+ (int)sendMousePositionNormalizedX:(float)x y:(float)y referenceWidth:(short)referenceWidth referenceHeight:(short)referenceHeight {
    return LiSendMousePositionEvent((short)(x * referenceWidth),
                                    (short)(y * referenceHeight),
                                    referenceWidth,
                                    referenceHeight);
}

+ (int)sendMouseButton:(MLCInputMouseButton)button pressed:(BOOL)pressed {
    [pressedStateLock lock];
    if (pressed) {
        [pressedMouseButtons addObject:@(button)];
    }
    else {
        [pressedMouseButtons removeObject:@(button)];
    }
    [pressedStateLock unlock];

    return LiSendMouseButtonEvent(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE, button);
}

+ (int)sendScrollVerticalClicks:(signed char)clicks {
    return LiSendScrollEvent(clicks);
}

+ (int)sendControllerStateWithButtonFlags:(int)buttonFlags
                             leftTrigger:(unsigned char)leftTrigger
                            rightTrigger:(unsigned char)rightTrigger
                              leftStickX:(short)leftStickX
                              leftStickY:(short)leftStickY
                             rightStickX:(short)rightStickX
                             rightStickY:(short)rightStickY {
    controllerInputActive = YES;
    return LiSendControllerEvent(buttonFlags, leftTrigger, rightTrigger,
                                 leftStickX, leftStickY, rightStickX, rightStickY);
}

+ (int)sendControllerArrivalNumber:(uint8_t)controllerNumber
                     gamepadMask:(uint16_t)gamepadMask
                            type:(uint8_t)type
                         buttons:(uint32_t)supportedButtons
                    capabilities:(uint16_t)capabilities {
    controllerInputActive = YES;
    int result = LiSendControllerArrivalEvent(controllerNumber, gamepadMask, type,
                                              supportedButtons, capabilities);
    if (result != LI_ERR_UNSUPPORTED) {
        return result;
    }
    return LiSendMultiControllerEvent((short)controllerNumber, (short)gamepadMask,
                                      0, 0, 0, 0, 0, 0, 0);
}

+ (int)sendHighResScrollVertical:(short)amount {
    return LiSendHighResScrollEvent(amount);
}

+ (int)sendHighResScrollHorizontal:(short)amount {
    return LiSendHighResHScrollEvent(amount);
}

+ (int)sendControllerTouchNumber:(uint8_t)controllerNumber
                       eventType:(uint8_t)eventType
                       pointerId:(uint32_t)pointerId
                               x:(float)x
                               y:(float)y
                        pressure:(float)pressure {
    return LiSendControllerTouchEvent(controllerNumber, eventType, pointerId, x, y, pressure);
}

+ (int)sendControllerRemovalNumber:(uint8_t)controllerNumber {
    controllerInputActive = NO;
    return LiSendMultiControllerEvent((short)controllerNumber, 0, 0, 0, 0, 0, 0, 0, 0);
}

+ (int)sendControllerMotionNumber:(uint8_t)controllerNumber
                             type:(uint8_t)motionType
                                x:(float)x
                                y:(float)y
                                z:(float)z {
    return LiSendControllerMotionEvent(controllerNumber, motionType, x, y, z);
}

+ (int)sendControllerBatteryNumber:(uint8_t)controllerNumber
                            state:(uint8_t)state
                       percentage:(uint8_t)percentage {
    return LiSendControllerBatteryEvent(controllerNumber, state, percentage);
}

+ (void)requestIdrFrame {
    LiRequestIdrFrame();
}

+ (BOOL)estimatedRttMs:(uint32_t*)rtt variance:(uint32_t*)variance {
    return LiGetEstimatedRttInfo(rtt, variance);
}

@end
