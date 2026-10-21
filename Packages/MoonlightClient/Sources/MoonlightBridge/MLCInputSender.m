
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

+ (int)sendControllerPresenceArrived:(BOOL)arrived {
    if (arrived) {
        uint32_t supported = A_FLAG | B_FLAG | X_FLAG | Y_FLAG
            | UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG
            | LB_FLAG | RB_FLAG | PLAY_FLAG | BACK_FLAG
            | LS_CLK_FLAG | RS_CLK_FLAG;
        int result = LiSendControllerArrivalEvent(0, 0x1, LI_CTYPE_XBOX, supported,
                                                  LI_CCAP_ANALOG_TRIGGERS);
        if (result != LI_ERR_UNSUPPORTED) {
            return result;
        }
        return LiSendMultiControllerEvent(0, 0x1, 0, 0, 0, 0, 0, 0, 0);
    }
    controllerInputActive = NO;
    return LiSendMultiControllerEvent(0, 0, 0, 0, 0, 0, 0, 0, 0);
}

+ (void)requestIdrFrame {
    LiRequestIdrFrame();
}

+ (BOOL)estimatedRttMs:(uint32_t*)rtt variance:(uint32_t*)variance {
    return LiGetEstimatedRttInfo(rtt, variance);
}

@end
