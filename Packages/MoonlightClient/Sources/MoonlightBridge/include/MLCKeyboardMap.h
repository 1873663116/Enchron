
#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSInteger, MLCKeyModifier) {
    MLCKeyModifierAlphaShift = 1 << 16,
    MLCKeyModifierShift = 1 << 17,
    MLCKeyModifierControl = 1 << 18,
    MLCKeyModifierAlternate = 1 << 19,
    MLCKeyModifierCommand = 1 << 20,
    MLCKeyModifierNumericPad = 1 << 21
};

@interface MLCKeyboardMap : NSObject

+ (char)modifiersForKeyModifierFlags:(NSInteger)flags;

+ (char)modifiersForHIDUsage:(NSInteger)usage;

+ (int)windowsKeyCodeForHIDUsage:(NSInteger)usage;

@end
