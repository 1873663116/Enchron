
#import <Foundation/Foundation.h>

#ifndef MLC_LOGGER_H
#define MLC_LOGGER_H

typedef enum {
    LOG_D,
    LOG_I,
    LOG_W,
    LOG_E
} LogLevel;

void Log(LogLevel level, NSString* fmt, ...) NS_FORMAT_FUNCTION(2, 3);

#endif
