
#import "MLCKeyboardMap.h"

#include <Limelight.h>

#define HID_A 0x04
#define HID_Z 0x1D
#define HID_1 0x1E
#define HID_9 0x26
#define HID_0 0x27
#define HID_KEYPAD1 0x59
#define HID_KEYPAD9 0x61
#define HID_KEYPAD0 0x62
#define HID_F1 0x3A
#define HID_F12 0x45
#define HID_F13 0x68
#define HID_F24 0x73

@implementation MLCKeyboardMap

+ (char)modifiersForKeyModifierFlags:(NSInteger)flags {
    char modifiers = 0;

    if (flags & MLCKeyModifierShift) {
        modifiers |= MODIFIER_SHIFT;
    }
    if (flags & MLCKeyModifierAlternate) {
        modifiers |= MODIFIER_ALT;
    }
    if (flags & MLCKeyModifierControl) {
        modifiers |= MODIFIER_CTRL;
    }
    if (flags & MLCKeyModifierCommand) {
        modifiers |= MODIFIER_META;
    }

    return modifiers;
}

+ (char)modifiersForHIDUsage:(NSInteger)usage {
    switch (usage) {
        case 0x58:
            return MODIFIER_EXTENDED;
        default:
            return 0;
    }
}

+ (int)windowsKeyCodeForHIDUsage:(NSInteger)usage {
    if (usage >= HID_A && usage <= HID_Z) {
        return (int)(usage - HID_A) + 0x41;
    }
    else if (usage == HID_0) {
        return 0x30;
    }
    else if (usage >= HID_1 && usage <= HID_9) {
        return (int)(usage - HID_1) + 0x31;
    }
    else if (usage == HID_KEYPAD0) {
        return 0x60;
    }
    else if (usage >= HID_KEYPAD1 && usage <= HID_KEYPAD9) {
        return (int)(usage - HID_KEYPAD1) + 0x61;
    }
    else if (usage >= HID_F1 && usage <= HID_F12) {
        return (int)(usage - HID_F1) + 0x70;
    }
    else if (usage >= HID_F13 && usage <= HID_F24) {
        return (int)(usage - HID_F13) + 0x7C;
    }

    switch (usage) {
        case 0x28: return 0x0D;
        case 0x29: return 0x1B;
        case 0x2A: return 0x08;
        case 0x2B: return 0x09;
        case 0x2C: return 0x20;
        case 0x2D: return 0xBD;
        case 0x2E: return 0xBB;
        case 0x2F: return 0xDB;
        case 0x30: return 0xDD;
        case 0x31: return 0xDC;
        case 0x33: return 0xBA;
        case 0x34: return 0xDE;
        case 0x35: return 0xC0;
        case 0x36: return 0xBC;
        case 0x37: return 0xBE;
        case 0x38: return 0xBF;
        case 0x39: return 0x14;
        case 0x46: return 0x2A;
        case 0x47: return 0x91;
        case 0x48: return 0x13;
        case 0x49: return 0x2D;
        case 0x4A: return 0x24;
        case 0x4B: return 0x21;
        case 0x4C: return 0x2E;
        case 0x4D: return 0x23;
        case 0x4E: return 0x22;
        case 0x4F: return 0x27;
        case 0x50: return 0x25;
        case 0x51: return 0x28;
        case 0x52: return 0x26;
        case 0x53: return 0x90;
        case 0x54: return 0x6F;
        case 0x55: return 0x6A;
        case 0x56: return 0x6D;
        case 0x57: return 0x6B;
        case 0x58: return 0x0D;
        case 0x63: return 0x6E;
        case 0x64: return 0xE2;
        case 0x85: return 0x6C;
        case 0x9B: return 0x03;
        case 0x9C: return 0x0C;
        case 0xA3: return 0xF7;
        case 0xA4: return 0xF8;
        case 0xE3: return 0x5B;
        case 0xE0: return 0xA2;
        case 0xE1: return 0xA0;
        case 0xE2: return 0xA4;
        case 0xE7: return 0x5C;
        case 0xE4: return 0xA3;
        case 0xE5: return 0xA1;
        case 0xE6: return 0xA5;
        case 669:
            return 0x1B;
        default:
            return 0;
    }
}

@end
