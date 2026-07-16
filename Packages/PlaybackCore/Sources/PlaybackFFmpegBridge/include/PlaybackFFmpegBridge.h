#pragma once

#include <CoreMedia/CoreMedia.h>
#include <stdbool.h>
#include <stddef.h>

typedef enum PBFFmpegMode {
    PBFFmpegModeCompressed = 0,
} PBFFmpegMode;

typedef enum PBFFmpegReadResult {
    PBFFmpegReadResultSample = 0,
    PBFFmpegReadResultEnd = 1,
    PBFFmpegReadResultError = -1,
} PBFFmpegReadResult;

typedef struct PBFFmpegReader PBFFmpegReader;
typedef struct PBFFmpegAudioReader PBFFmpegAudioReader;
typedef struct PBFFmpegSubtitleReader PBFFmpegSubtitleReader;

PBFFmpegReader *PBFFmpegReaderCreate(
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
);

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
void PBFFmpegAudioReaderDestroy(PBFFmpegAudioReader *reader);
PBFFmpegReadResult PBFFmpegAudioReaderCopyNextSample(
    PBFFmpegAudioReader *reader,
    CMSampleBufferRef *sampleOut,
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
