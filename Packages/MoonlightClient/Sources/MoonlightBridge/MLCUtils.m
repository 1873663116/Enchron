//
//  MLCUtils.m
//  Adapted from moonlight-ios Limelight/Utility/Utils.m at 02dc9780.
//

#import "MLCUtils.h"

static NSString* deviceName = @"Enchron";

NSString* MLCDeviceName(void) {
    return deviceName;
}

void MLCSetDeviceName(NSString* name) {
    deviceName = [name copy];
}

@implementation MLCUtils

+ (NSData*)randomBytes:(NSInteger)length {
    char* bytes = malloc((size_t)length);
    arc4random_buf(bytes, (size_t)length);
    NSData* randomData = [NSData dataWithBytes:bytes length:(NSUInteger)length];
    free(bytes);
    return randomData;
}

+ (NSData*)hexToBytes:(NSString*)hex {
    unsigned long len = [hex length];
    NSMutableData* data = [NSMutableData dataWithCapacity:len / 2];
    char byteChars[3] = {'\0', '\0', '\0'};
    unsigned long wholeByte;

    const char* chars = [hex UTF8String];
    unsigned long i = 0;
    while (i + 1 < len) {
        byteChars[0] = chars[i++];
        byteChars[1] = chars[i++];
        wholeByte = strtoul(byteChars, NULL, 16);
        [data appendBytes:&wholeByte length:1];
    }

    return data;
}

+ (NSString*)bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString* hex = [[NSMutableString alloc] init];
    for (NSUInteger i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X", bytes[i]];
    }
    return hex;
}

+ (BOOL)parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port {
    if (![addressPort containsString:@":"]) {
        *address = NSMakeRange(0, [addressPort length]);
        *port = NSMakeRange(NSNotFound, 0);
        return YES;
    }

    NSInteger locationOfOpeningBracket = [addressPort rangeOfString:@"["].location;
    NSInteger locationOfClosingBracket = [addressPort rangeOfString:@"]"].location;
    if (locationOfOpeningBracket != NSNotFound || locationOfClosingBracket != NSNotFound) {
        if (locationOfOpeningBracket == NSNotFound || locationOfClosingBracket == NSNotFound ||
            locationOfClosingBracket < locationOfOpeningBracket) {
            return NO;
        }

        *address = NSMakeRange(locationOfOpeningBracket + 1, locationOfClosingBracket - locationOfOpeningBracket - 1);
    }
    else {
        *address = NSMakeRange(0, [addressPort rangeOfString:@":"].location);
    }

    NSUInteger remainingStringLocation = address->location + address->length;
    NSRange remainingStringRange = NSMakeRange(remainingStringLocation, [addressPort length] - remainingStringLocation);
    NSInteger locationOfPortSeparator = [addressPort rangeOfString:@":" options:0 range:remainingStringRange].location;
    if (locationOfPortSeparator != NSNotFound) {
        *port = NSMakeRange(locationOfPortSeparator + 1, [addressPort length] - locationOfPortSeparator - 1);
    }
    else {
        *port = NSMakeRange(NSNotFound, 0);
    }

    return YES;
}

+ (NSString*)addressPortStringToAddress:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange]) {
        return nil;
    }

    return [addressPort substringWithRange:addressRange];
}

+ (unsigned short)addressPortStringToPort:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange] || portRange.location == NSNotFound) {
        return 47989;
    }

    return (unsigned short)[[addressPort substringWithRange:portRange] integerValue];
}

+ (NSString*)addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port {
    if ([address containsString:@":"]) {
        return [NSString stringWithFormat:@"[%@]:%u", address, port];
    }
    return [NSString stringWithFormat:@"%@:%u", address, port];
}

@end
