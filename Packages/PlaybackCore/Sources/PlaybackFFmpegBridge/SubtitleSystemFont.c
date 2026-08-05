#include "SubtitleSystemFont.h"

#include <CoreText/CoreText.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define PB_FONT_TAG(a, b, c, d) \
    (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

typedef struct PBSystemFontTable {
    CTFontTableTag tag;
    CFDataRef data;
    uint32_t offset;
} PBSystemFontTable;

static void write_big_endian_uint16(uint8_t *destination, uint16_t value) {
    destination[0] = (uint8_t)(value >> 8);
    destination[1] = (uint8_t)value;
}

static void write_big_endian_uint32(uint8_t *destination, uint32_t value) {
    destination[0] = (uint8_t)(value >> 24);
    destination[1] = (uint8_t)(value >> 16);
    destination[2] = (uint8_t)(value >> 8);
    destination[3] = (uint8_t)value;
}

static uint32_t open_type_checksum(const uint8_t *bytes, size_t byteCount) {
    uint32_t checksum = 0;
    for (size_t offset = 0; offset < byteCount; offset += 4) {
        uint32_t word = 0;
        for (size_t byte = 0; byte < 4 && offset + byte < byteCount; byte++) {
            word |= (uint32_t)bytes[offset + byte] << (24 - byte * 8);
        }
        checksum += word;
    }
    return checksum;
}

static char *copy_utf8_string(CFStringRef string) {
    if (!string) return NULL;
    CFIndex length = CFStringGetLength(string);
    CFIndex capacity = CFStringGetMaximumSizeForEncoding(
        length,
        kCFStringEncodingUTF8
    ) + 1;
    if (capacity <= 1) return NULL;
    char *buffer = calloc((size_t)capacity, 1);
    if (!buffer) return NULL;
    if (!CFStringGetCString(string, buffer, capacity, kCFStringEncodingUTF8)) {
        free(buffer);
        return NULL;
    }
    return buffer;
}

static int compare_font_tables(const void *left, const void *right) {
    const PBSystemFontTable *leftTable = left;
    const PBSystemFontTable *rightTable = right;
    if (leftTable->tag < rightTable->tag) return -1;
    if (leftTable->tag > rightTable->tag) return 1;
    return 0;
}

static void release_font_tables(PBSystemFontTable *tables, size_t tableCount) {
    if (!tables) return;
    for (size_t index = 0; index < tableCount; index++) {
        if (tables[index].data) CFRelease(tables[index].data);
    }
    free(tables);
}

static uint8_t *copy_open_type_font(
    CTFontRef font,
    size_t *byteCountOut
) {
    CFArrayRef availableTables = CTFontCopyAvailableTables(
        font,
        kCTFontTableOptionNoOptions
    );
    if (!availableTables) return NULL;
    CFIndex availableCount = CFArrayGetCount(availableTables);
    if (availableCount <= 0 || availableCount > UINT16_MAX) {
        CFRelease(availableTables);
        return NULL;
    }

    PBSystemFontTable *tables = calloc(
        (size_t)availableCount,
        sizeof(PBSystemFontTable)
    );
    if (!tables) {
        CFRelease(availableTables);
        return NULL;
    }

    size_t tableCount = 0;
    for (CFIndex index = 0; index < availableCount; index++) {
        CTFontTableTag tag = (CTFontTableTag)(uintptr_t)CFArrayGetValueAtIndex(
            availableTables,
            index
        );
        CFDataRef data = CTFontCopyTable(
            font,
            tag,
            kCTFontTableOptionNoOptions
        );
        if (!data || CFDataGetLength(data) <= 0) {
            if (data) CFRelease(data);
            continue;
        }
        tables[tableCount++] = (PBSystemFontTable) {
            .tag = tag,
            .data = data,
        };
    }
    CFRelease(availableTables);
    if (tableCount == 0) {
        release_font_tables(tables, tableCount);
        return NULL;
    }
    qsort(tables, tableCount, sizeof(PBSystemFontTable), compare_font_tables);

    size_t headerSize = 12 + tableCount * 16;
    size_t fontSize = headerSize;
    bool hasCompactFontFormat = false;
    size_t headTableIndex = SIZE_MAX;
    for (size_t index = 0; index < tableCount; index++) {
        CFIndex tableLength = CFDataGetLength(tables[index].data);
        if (tableLength <= 0 || (uint64_t)tableLength > UINT32_MAX) {
            release_font_tables(tables, tableCount);
            return NULL;
        }
        size_t paddedLength = ((size_t)tableLength + 3) & ~(size_t)3;
        if (paddedLength < (size_t)tableLength || fontSize > SIZE_MAX - paddedLength) {
            release_font_tables(tables, tableCount);
            return NULL;
        }
        tables[index].offset = (uint32_t)fontSize;
        fontSize += paddedLength;
        if (tables[index].tag == PB_FONT_TAG('h', 'e', 'a', 'd')) {
            headTableIndex = index;
        } else if (tables[index].tag == PB_FONT_TAG('C', 'F', 'F', ' ') ||
                   tables[index].tag == PB_FONT_TAG('C', 'F', 'F', '2')) {
            hasCompactFontFormat = true;
        }
    }
    if (fontSize > UINT32_MAX || fontSize > INT_MAX || headTableIndex == SIZE_MAX) {
        release_font_tables(tables, tableCount);
        return NULL;
    }

    uint8_t *fontBytes = calloc(fontSize, 1);
    if (!fontBytes) {
        release_font_tables(tables, tableCount);
        return NULL;
    }
    write_big_endian_uint32(
        fontBytes,
        hasCompactFontFormat ? PB_FONT_TAG('O', 'T', 'T', 'O') : 0x00010000
    );
    write_big_endian_uint16(fontBytes + 4, (uint16_t)tableCount);
    uint16_t largestPowerOfTwo = 1;
    uint16_t entrySelector = 0;
    while ((uint32_t)largestPowerOfTwo * 2 <= tableCount) {
        largestPowerOfTwo *= 2;
        entrySelector++;
    }
    uint16_t searchRange = largestPowerOfTwo * 16;
    write_big_endian_uint16(fontBytes + 6, searchRange);
    write_big_endian_uint16(fontBytes + 8, entrySelector);
    write_big_endian_uint16(
        fontBytes + 10,
        (uint16_t)(tableCount * 16 - searchRange)
    );

    for (size_t index = 0; index < tableCount; index++) {
        CFIndex tableLength = CFDataGetLength(tables[index].data);
        memcpy(
            fontBytes + tables[index].offset,
            CFDataGetBytePtr(tables[index].data),
            (size_t)tableLength
        );
    }
    CFIndex headLength = CFDataGetLength(tables[headTableIndex].data);
    if (headLength < 12) {
        free(fontBytes);
        release_font_tables(tables, tableCount);
        return NULL;
    }
    uint32_t headOffset = tables[headTableIndex].offset;
    memset(fontBytes + headOffset + 8, 0, 4);

    for (size_t index = 0; index < tableCount; index++) {
        CFIndex tableLength = CFDataGetLength(tables[index].data);
        uint8_t *directoryEntry = fontBytes + 12 + index * 16;
        write_big_endian_uint32(directoryEntry, tables[index].tag);
        write_big_endian_uint32(
            directoryEntry + 4,
            open_type_checksum(fontBytes + tables[index].offset, (size_t)tableLength)
        );
        write_big_endian_uint32(directoryEntry + 8, tables[index].offset);
        write_big_endian_uint32(directoryEntry + 12, (uint32_t)tableLength);
    }
    uint32_t checksumAdjustment = 0xB1B0AFBA - open_type_checksum(
        fontBytes,
        fontSize
    );
    write_big_endian_uint32(fontBytes + headOffset + 8, checksumAdjustment);

    release_font_tables(tables, tableCount);
    *byteCountOut = fontSize;
    return fontBytes;
}

bool PBSubtitleSystemFontCopyChineseFallback(PBSubtitleSystemFontData *fontOut) {
    if (!fontOut) return false;
    memset(fontOut, 0, sizeof(*fontOut));
    const UniChar sampleCharacters[] = {0x5B57, 0x5E55, 0x9A8C, 0x8BC1};
    CFStringRef sample = CFStringCreateWithCharacters(
        kCFAllocatorDefault,
        sampleCharacters,
        4
    );
    CTFontRef baseFont = CTFontCreateWithName(CFSTR("Helvetica Neue"), 64, NULL);
    CTFontRef fallbackFont = baseFont && sample
        ? CTFontCreateForStringWithLanguage(
            baseFont,
            sample,
            CFRangeMake(0, 4),
            CFSTR("zh-Hans")
        )
        : NULL;
    if (baseFont) CFRelease(baseFont);
    if (sample) CFRelease(sample);
    if (!fallbackFont) return false;

    CGGlyph glyphs[4] = {0};
    bool coversSample = CTFontGetGlyphsForCharacters(
        fallbackFont,
        sampleCharacters,
        glyphs,
        4
    );
    if (!coversSample) {
        CFRelease(fallbackFont);
        return false;
    }

    CFStringRef postScriptName = CTFontCopyPostScriptName(fallbackFont);
    CFStringRef familyName = CTFontCopyFamilyName(fallbackFont);
    fontOut->attachmentName = copy_utf8_string(postScriptName);
    fontOut->familyName = copy_utf8_string(familyName);
    if (postScriptName) CFRelease(postScriptName);
    if (familyName) CFRelease(familyName);
    fontOut->bytes = copy_open_type_font(fallbackFont, &fontOut->byteCount);
    CFRelease(fallbackFont);

    if (!fontOut->attachmentName || !fontOut->familyName || !fontOut->bytes ||
        fontOut->byteCount == 0 || fontOut->byteCount > INT_MAX) {
        PBSubtitleSystemFontDataDestroy(fontOut);
        return false;
    }
    return true;
}

void PBSubtitleSystemFontDataDestroy(PBSubtitleSystemFontData *font) {
    if (!font) return;
    free(font->attachmentName);
    free(font->familyName);
    free(font->bytes);
    memset(font, 0, sizeof(*font));
}
