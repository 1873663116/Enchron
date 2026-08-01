#pragma once

#include <CoreMedia/CoreMedia.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum PBFFmpegMode {
    PBFFmpegModeCompressed = 0,
} PBFFmpegMode;

typedef enum PBFFmpegReadResult {
    PBFFmpegReadResultSample = 0,
    PBFFmpegReadResultEnd = 1,
    PBFFmpegReadResultCancelled = 2,
    PBFFmpegReadResultError = -1,
} PBFFmpegReadResult;

typedef struct PBFFmpegReader PBFFmpegReader;
typedef struct PBFFmpegAudioReader PBFFmpegAudioReader;
typedef enum PBFFmpegAudioCookieSource {
    PBFFmpegAudioCookieSourceUnavailable = 0,
    PBFFmpegAudioCookieSourceExtradata = 1,
    PBFFmpegAudioCookieSourceSynthesized = 2,
    PBFFmpegAudioCookieSourceFilterOutput = 3,
} PBFFmpegAudioCookieSource;
typedef struct PBFFmpegAudioSampleMetadata {
    int64_t packetPTS;
    int64_t packetDTS;
    int64_t packetDuration;
    int timeBaseNumerator;
    int timeBaseDenominator;
    size_t payloadByteCount;
    PBFFmpegAudioCookieSource cookieSource;
} PBFFmpegAudioSampleMetadata;
typedef struct PBFFmpegSubtitleReader PBFFmpegSubtitleReader;
typedef struct PBSubtitleFrameRenderer PBSubtitleFrameRenderer;

typedef enum PBSubtitleFrameResult {
    PBSubtitleFrameResultFrame = 0,
    PBSubtitleFrameResultEmpty = 1,
    PBSubtitleFrameResultError = -1,
} PBSubtitleFrameResult;

typedef enum PBSubtitleFrameKind {
    PBSubtitleFrameKindLibass = 0,
    PBSubtitleFrameKindBitmap = 1,
} PBSubtitleFrameKind;

typedef struct PBSubtitleFrameInfo {
    PBSubtitleFrameKind kind;
    int canvasWidth;
    int canvasHeight;
    int contentX;
    int contentY;
    int contentWidth;
    int contentHeight;
    int bytesPerRow;
    uint64_t changeIdentifier;
} PBSubtitleFrameInfo;

PBFFmpegReader *PBFFmpegReaderCreate(
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
);
PBFFmpegReader *PBFFmpegReaderAllocate(void);
bool PBFFmpegReaderOpen(
    PBFFmpegReader *reader,
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
);
void PBFFmpegReaderCancel(PBFFmpegReader *reader);

void PBFFmpegReaderDestroy(PBFFmpegReader *reader);

PBFFmpegReadResult PBFFmpegReaderCopyNextSample(
    PBFFmpegReader *reader,
    CMSampleBufferRef *sampleOut,
    char *errorBuffer,
    size_t errorBufferSize
);

double PBFFmpegReaderGetDurationSeconds(const PBFFmpegReader *reader);
double PBFFmpegReaderGetNominalFrameRate(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetCodecName(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetCodecTag(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetContainerFormat(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetColorPrimaries(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetTransferFunction(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetYCbCrMatrix(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetColorRange(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetProjectionKind(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetViewPackingKind(const PBFFmpegReader *reader);
int PBFFmpegReaderGetWidth(const PBFFmpegReader *reader);
int PBFFmpegReaderGetHeight(const PBFFmpegReader *reader);
int PBFFmpegReaderGetVideoStreamIndex(const PBFFmpegReader *reader);
int PBFFmpegReaderGetTimeBaseNumerator(const PBFFmpegReader *reader);
int PBFFmpegReaderGetTimeBaseDenominator(const PBFFmpegReader *reader);
bool PBFFmpegReaderFormatHasHvcC(const PBFFmpegReader *reader);
bool PBFFmpegReaderFormatHasDvcC(const PBFFmpegReader *reader);
bool PBFFmpegReaderFormatHasDvvC(const PBFFmpegReader *reader);

PBFFmpegAudioReader *PBFFmpegAudioReaderCreate(
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
);
PBFFmpegAudioReader *PBFFmpegAudioReaderAllocate(void);
bool PBFFmpegAudioReaderOpen(
    PBFFmpegAudioReader *reader,
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
);
void PBFFmpegAudioReaderCancel(PBFFmpegAudioReader *reader);
void PBFFmpegAudioReaderDestroy(PBFFmpegAudioReader *reader);
PBFFmpegReadResult PBFFmpegAudioReaderCopyNextSample(
    PBFFmpegAudioReader *reader,
    CMSampleBufferRef *sampleOut,
    PBFFmpegAudioSampleMetadata *metadataOut,
    char *errorBuffer,
    size_t errorBufferSize
);
int PBFFmpegAudioReaderGetStreamIndex(const PBFFmpegAudioReader *reader);
int PBFFmpegAudioReaderGetSampleRate(const PBFFmpegAudioReader *reader);
int PBFFmpegAudioReaderGetChannelCount(const PBFFmpegAudioReader *reader);
const char *PBFFmpegAudioReaderGetCodecName(const PBFFmpegAudioReader *reader);

int PBFFmpegAudioTrackCount(const char *path);
bool PBFFmpegAudioTrackCopyInfo(
    const char *path,
    int ordinal,
    int *streamIndexOut,
    int *sampleRateOut,
    int *channelCountOut,
    char *codecBuffer,
    size_t codecBufferSize,
    char *languageBuffer,
    size_t languageBufferSize,
    char *titleBuffer,
    size_t titleBufferSize
);

int PBFFmpegSubtitleTrackCount(const char *path);
bool PBFFmpegSubtitleTrackCopyInfo(
    const char *path,
    int ordinal,
    int *streamIndexOut,
    char *codecBuffer,
    size_t codecBufferSize,
    char *languageBuffer,
    size_t languageBufferSize,
    char *titleBuffer,
    size_t titleBufferSize
);
PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreate(
    const char *path,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
);
void PBFFmpegSubtitleReaderDestroy(PBFFmpegSubtitleReader *reader);
PBFFmpegReadResult PBFFmpegSubtitleReaderCopyNextCue(
    PBFFmpegSubtitleReader *reader,
    double *startSecondsOut,
    double *durationSecondsOut,
    CFStringRef *textOut,
    char *errorBuffer,
    size_t errorBufferSize
);

PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreate(
    const char *path,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
);
void PBSubtitleFrameRendererDestroy(PBSubtitleFrameRenderer *renderer);
PBSubtitleFrameResult PBSubtitleFrameRendererCopyFrame(
    PBSubtitleFrameRenderer *renderer,
    double timeSeconds,
    int viewportWidth,
    int viewportHeight,
    CFDataRef *bgraDataOut,
    PBSubtitleFrameInfo *infoOut,
    char *errorBuffer,
    size_t errorBufferSize
);
