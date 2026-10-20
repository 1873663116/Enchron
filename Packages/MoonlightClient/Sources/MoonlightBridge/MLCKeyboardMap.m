//
//  MLCKeyboardMap.m
//  Adapted from moonlight-ios Limelight/Input/KeyboardSupport.m at 02dc9780.
//

#import "MLCKeyboardMap.h"

#include <Limelight.h>

// UIKeyboardHIDUsage raw values, from UIKeyConstants.h.
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
        case 0x58: // Keypad Enter
            return MODIFIER_EXTENDED;
        default:
            return 0;
    }
}

+ (int)windowsKeyCodeForHIDUsage:(NSInteger)usage {
    // This converts UIKeyboardHIDUsage values to Win32 VK_* values
    // https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
    if (usage >= HID_A && usage <= HID_Z) {
        return (int)(usage - HID_A) + 0x41;
    }
    else if (usage == HID_0) {
        // This key is at the beginning of the VK_ range but the end
        // of the UIKeyboardHIDUsageKeyboard range.
        return 0x30;
    }
    else if (usage >= HID_1 && usage <= HID_9) {
        return (int)(usage - HID_1) + 0x31;
    }
    else if (usage == HID_KEYPAD0) {
        // This key is at the beginning of the VK_ range but the end
        // of the UIKeyboardHIDUsageKeypad range.
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
        case 0x28: return 0x0D; // Return or Enter
        case 0x29: return 0x1B; // Escape
        case 0x2A: return 0x08; // Delete or Backspace
        case 0x2B: return 0x09; // Tab
        case 0x2C: return 0x20; // Spacebar
        case 0x2D: return 0xBD; // Hyphen
        case 0x2E: return 0xBB; // Equal Sign
        case 0x2F: return 0xDB; // Open Bracket
        case 0x30: return 0xDD; // Close Bracket
        case 0x31: return 0xDC; // Backslash
        case 0x33: return 0xBA; // Semicolon
        case 0x34: return 0xDE; // Quote
        case 0x35: return 0xC0; // Grave Accent and Tilde
        case 0x36: return 0xBC; // Comma
        case 0x37: return 0xBE; // Period
        case 0x38: return 0xBF; // Slash
        case 0x39: return 0x14; // Caps Lock
        case 0x46: return 0x2A; // Print Screen
        case 0x47: return 0x91; // Scroll Lock
        case 0x48: return 0x13; // Pause
        case 0x49: return 0x2D; // Insert
        case 0x4A: return 0x24; // Home
        case 0x4B: return 0x21; // Page Up
        case 0x4C: return 0x2E; // Delete Forward
        case 0x4D: return 0x23; // End
        case 0x4E: return 0x22; // Page Down
        case 0x4F: return 0x27; // Right Arrow
        case 0x50: return 0x25; // Left Arrow
        case 0x51: return 0x28; // Down Arrow
        case 0x52: return 0x26; // Up Arrow
        case 0x53: return 0x90; // Keypad Num Lock
        case 0x54: return 0x6F; // Keypad Slash
        case 0x55: return 0x6A; // Keypad Asterisk
        case 0x56: return 0x6D; // Keypad Hyphen
        case 0x57: return 0x6B; // Keypad Plus
        case 0x58: return 0x0D; // Keypad Enter
        case 0x63: return 0x6E; // Keypad Period
        case 0x64: return 0xE2; // Non-US Backslash
        case 0x85: return 0x6C; // Keypad Comma
        case 0x9B: return 0x03; // Cancel
        case 0x9C: return 0x0C; // Clear
        case 0xA3: return 0xF7; // CrSel or Props
        case 0xA4: return 0xF8; // ExSel
        case 0xE3: return 0x5B; // Left GUI
        case 0xE0: return 0xA2; // Left Control
        case 0xE1: return 0xA0; // Left Shift
        case 0xE2: return 0xA4; // Left Alt
        case 0xE7: return 0x5C; // Right GUI
        case 0xE4: return 0xA3; // Right Control
        case 0xE5: return 0xA1; // Right Shift
        case 0xE6: return 0xA5; // Right Alt
        case 669: // The "Globe" or "Language" key on most Apple branded iPad keyboards.
            return 0x1B; // Escape, which is missing from most Apple branded iPad keyboards.
        default: // Unhandled HID usage
            return 0;
    }
}

@end
