#ifndef PB_SUBTITLE_SYSTEM_FONT_H
#define PB_SUBTITLE_SYSTEM_FONT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct PBSubtitleSystemFontData {
    char *attachmentName;
    char *familyName;
    uint8_t *bytes;
    size_t byteCount;
} PBSubtitleSystemFontData;

bool PBSubtitleSystemFontCopyChineseFallback(PBSubtitleSystemFontData *fontOut);
void PBSubtitleSystemFontDataDestroy(PBSubtitleSystemFontData *font);

#endif
