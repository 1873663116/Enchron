#ifndef ENCHRON_BLU_RAY_DISC_BRIDGE_H
#define ENCHRON_BLU_RAY_DISC_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PBBlurayCatalog PBBlurayCatalog;
typedef struct PBBlurayReader PBBlurayReader;

typedef enum {
    PBBlurayAccessImage = 1,
    PBBlurayAccessFiles = 2,
} PBBlurayAccessKind;

/** Calls are synchronous. The caller runs opens off the main actor.
   A non-NULL contextClose transfers context ownership at OpenWithIO entry;
   it is called exactly once on close or on open failure. */
typedef struct {
    void *context;
    int64_t (*imageReadAt)(void *context, int64_t offset, uint8_t *buffer, int64_t count);
    void *(*fileOpen)(void *context, const char *relativePath, int64_t *size);
    int64_t (*fileReadAt)(void *context, void *file, int64_t offset,
                          uint8_t *buffer, int64_t count);
    void (*fileClose)(void *context, void *file);
    void *(*directoryOpen)(void *context, const char *relativePath);
    int (*directoryNext)(void *context, void *directory, char *name, size_t capacity);
    void (*directoryClose)(void *context, void *directory);
    bool (*isCancelled)(void *context);
    void (*setInterrupted)(void *context, bool interrupted);
    void (*contextClose)(void *context);
} PBBlurayIOCallbacks;

typedef enum {
    PBBlurayStreamVideo = 1,
    PBBlurayStreamAudio = 2,
    PBBlurayStreamSubtitle = 3,
} PBBlurayStreamKind;

typedef struct {
    uint16_t pid;
    uint8_t codingType;
    uint8_t kind;
    uint8_t format;
    uint8_t rate;
    char language[4];
} PBBlurayStreamInfo;

typedef struct {
    uint32_t playlistID;
    uint64_t duration90k;
    uint32_t clipCount;
    uint32_t chapterCount;
    bool isMain;
    char optionalName[256];
} PBBlurayTitleInfo;

typedef struct {
    char clipID[6];
    uint64_t startTime90k;
    uint64_t inTime90k;
    uint64_t outTime90k;
    /** Inclusive virtual-title byte position. */
    uint64_t byteStart;
    /** Exclusive virtual-title byte position. */
    uint64_t byteEnd;
    uint32_t packetCount;
    uint32_t streamCount;
    uint8_t stillMode;
    uint16_t stillTime;
    bool hasInteractiveGraphics;
} PBBlurayClipInfo;

PBBlurayCatalog *PBBlurayCatalogOpen(const char *path, char *error, size_t errorCapacity);
PBBlurayCatalog *PBBlurayCatalogOpenWithIO(PBBlurayAccessKind kind,
    const PBBlurayIOCallbacks *io, char *error, size_t errorCapacity);
uint32_t PBBlurayCatalogCount(const PBBlurayCatalog *catalog);
/** The returned bytes remain valid until PBBlurayCatalogClose. */
const uint8_t *PBBlurayCatalogMetadataXML(const PBBlurayCatalog *catalog,
    int64_t *size);
bool PBBlurayCatalogTitleAt(const PBBlurayCatalog *catalog, uint32_t index,
    PBBlurayTitleInfo *result);
bool PBBlurayCatalogClipAt(const PBBlurayCatalog *catalog, uint32_t titleIndex,
    uint32_t clipIndex, PBBlurayClipInfo *result);
bool PBBlurayCatalogStreamAt(const PBBlurayCatalog *catalog, uint32_t titleIndex,
    uint32_t clipIndex, uint32_t streamIndex, PBBlurayStreamInfo *result);
void PBBlurayCatalogClose(PBBlurayCatalog *catalog);

PBBlurayReader *PBBlurayOpen(const char *path, uint32_t playlistID,
    char *error, size_t errorCapacity);
PBBlurayReader *PBBlurayOpenWithIO(PBBlurayAccessKind kind,
    const PBBlurayIOCallbacks *io, uint32_t playlistID,
    char *error, size_t errorCapacity);
int PBBlurayRead(PBBlurayReader *reader, uint8_t *buffer, int count);
int64_t PBBluraySeekBytes(PBBlurayReader *reader, uint64_t offset);
/** Returns byte position. */
int64_t PBBluraySeekTime(PBBlurayReader *reader, uint64_t time90k);
uint64_t PBBlurayTell(const PBBlurayReader *reader);
uint64_t PBBluraySize(const PBBlurayReader *reader);
uint64_t PBBlurayDuration(const PBBlurayReader *reader);
uint32_t PBBlurayReaderClipCount(const PBBlurayReader *reader);
bool PBBlurayReaderClipAt(const PBBlurayReader *reader, uint32_t clipIndex,
    PBBlurayClipInfo *result);
bool PBBlurayReaderStreamAt(const PBBlurayReader *reader, uint32_t clipIndex,
    uint32_t streamIndex, PBBlurayStreamInfo *result);
/** May be called from another thread while a remote read is blocked. */
void PBBlurayReaderSetInterrupted(PBBlurayReader *reader, bool interrupted);
void PBBlurayClose(PBBlurayReader *reader);

#ifdef __cplusplus
}
#endif

#endif
