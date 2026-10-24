
#import "MLCLogger.h"

void Log(LogLevel level, NSString* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString* message = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSLog(@"[Moonlight] %@", message);
}
