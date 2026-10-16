//
//  MLCKeyboardMap.h
//  Adapted from moonlight-ios Limelight/Input/KeyboardSupport.m at 02dc9780.
//
//  Usages are UIKeyboardHIDUsage raw values, passed as integers so that the
//  mapping stays free of UIKit.
//

#import <Foundation/Foundation.h>

// Mirrors UIKeyModifierFlags (UICommand.h).
typedef NS_OPTIONS(NSInteger, MLCKeyModifier) {
    MLCKeyModifierAlphaShift = 1 << 16,
    MLCKeyModifierShift = 1 << 17,
    MLCKeyModifierControl = 1 << 18,
    MLCKeyModifierAlternate = 1 << 19,
    MLCKeyModifierCommand = 1 << 20,
    MLCKeyModifierNumericPad = 1 << 21
};

@interface MLCKeyboardMap : NSObject

// Converts UIKeyModifierFlags raw values into the MODIFIER_* flags that
// LiSendKeyboardEvent expects.
+ (char)modifiersForKeyModifierFlags:(NSInteger)flags;

// Returns the MODIFIER_* flags intrinsic to the usage, the extended-key bit
// included, or 0 when the usage carries none.
+ (char)modifiersForHIDUsage:(NSInteger)usage;

// Returns a Win32 VK_* code, or 0 when the usage has no mapping.
+ (int)windowsKeyCodeForHIDUsage:(NSInteger)usage;

@end
