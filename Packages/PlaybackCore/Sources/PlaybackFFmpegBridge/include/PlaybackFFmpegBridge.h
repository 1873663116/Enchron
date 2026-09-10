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

typedef enum PBFFmpegActiveFailureCause {
    PBFFmpegActiveFailureCauseNone = 0,
    PBFFmpegActiveFailureCauseConnectionInterrupted = 1,
    PBFFmpegActiveFailureCauseSourceFileMissing = 2,
    PBFFmpegActiveFailureCauseSourceAccessDenied = 3,
    PBFFmpegActiveFailureCauseMediaDataCorrupt = 4,
} PBFFmpegActiveFailureCause;

typedef struct PBFFmpegReader PBFFmpegReader;
typedef struct PBFFmpegAudioReader PBFFmpegAudioReader;
typedef struct PBFFmpegDemuxSource PBFFmpegDemuxSource;
typedef struct PBFFmpegSourceReadMonitor PBFFmpegSourceReadMonitor;
typedef struct PBFFmpegReadCancellation PBFFmpegReadCancellation;
typedef struct PBFFmpegMediaSourceInformation PBFFmpegMediaSourceInformation;
typedef enum PBFFmpegMediaStreamCategory {
    PBFFmpegMediaStreamCategoryOther = 0,
    PBFFmpegMediaStreamCategoryVideo = 1,
    PBFFmpegMediaStreamCategoryAudio = 2,
    PBFFmpegMediaStreamCategorySubtitle = 3,
} PBFFmpegMediaStreamCategory;
typedef struct PBFFmpegMediaStreamInfo {
    int streamIndex;
    PBFFmpegMediaStreamCategory category;
    int codecID;
    uint32_t codecTag;
    int disposition;
    int width;
    int height;
    double nominalFrameRate;
    /// Frames the encoder may hold before output order catches up, from the
    /// stream's own reorder delay. A decode queue shallower than this starves.
    int reorderDepth;
    /// Bytes one decoded pixel occupies on the platform's output surface.
    /// Chroma subsampling is counted in samples per pixel; components deeper
    /// than eight bits land in sixteen-bit words, so ten-bit 4:2:0 costs three
    /// bytes where eight-bit costs one and a half.
    double decodedBytesPerPixel;
    int sampleRate;
    int channelCount;
} PBFFmpegMediaStreamInfo;
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
    uint64_t trueHDDecoderInputPacketCount;
    uint64_t trueHDDecoderBatchCount;
    uint64_t trueHDAggregatedDecoderBatchCount;
    uint64_t trueHDOutputSampleBufferCount;
    uint32_t trueHDLastDecoderBatchInputPacketCount;
} PBFFmpegAudioSampleMetadata;
typedef struct PBFFmpegSubtitleReader PBFFmpegSubtitleReader;
typedef struct PBSubtitleFrameRenderer PBSubtitleFrameRenderer;

typedef enum PBFFmpegDemuxBufferMode {
    PBFFmpegDemuxBufferModeNone = 0,
    PBFFmpegDemuxBufferModeAutomatic = 1,
    PBFFmpegDemuxBufferModeBytes = 2,
} PBFFmpegDemuxBufferMode;

typedef struct PBFFmpegDemuxBufferConfiguration {
    PBFFmpegDemuxBufferMode mode;
    int64_t forwardByteLimit;
    int64_t backwardByteLimit;
    double targetDurationSeconds;
} PBFFmpegDemuxBufferConfiguration;

// The configure line the vendored FFmpeg was built with. The build decides
// which container features exist at all - a Matroska track whose frames are
// zlib compressed is readable only in a build that has zlib - so the line is
// part of what this package promises, not a detail of how it was made.
const char *PBFFmpegBuildConfiguration(void);

// Whether the vendored build actually contains a component this engine reads
// media through. The configure line says what was asked for; these answer
// what is in the binary, which is what a source at runtime meets.
bool PBFFmpegHasDemuxer(const char *name);
bool PBFFmpegHasDecoder(const char *name);
bool PBFFmpegHasInputProtocol(const char *name);

PBFFmpegDemuxBufferConfiguration PBFFmpegDemuxBufferConfigurationMake(
    PBFFmpegDemuxBufferMode mode,
    int64_t explicitForwardByteLimit
);

PBFFmpegSourceReadMonitor *PBFFmpegSourceReadMonitorCreate(void);
void PBFFmpegSourceReadMonitorDestroy(PBFFmpegSourceReadMonitor *monitor);
uint64_t PBFFmpegSourceReadMonitorGetTotalBytesRead(
    const PBFFmpegSourceReadMonitor *monitor
);
// Aborts the current and every later read of every format context opened
// with this monitor, within one interrupt poll of the transport. Permanent:
// a session interrupts its monitor once, at close.
void PBFFmpegSourceReadMonitorInterrupt(PBFFmpegSourceReadMonitor *monitor);

// One read's cancellation, independent of the session's monitor: it aborts
// only the contexts opened with this handle, so a caller can drop a single
// subtitle read while the session keeps playing. The flag is sticky, Cancel is
// idempotent, and a context opened after Cancel fails at open. The handle has
// to outlive every context opened with it: FFmpeg copies the interrupt
// callback's opaque into each URLContext it opens.
PBFFmpegReadCancellation *PBFFmpegReadCancellationCreate(void);
void PBFFmpegReadCancellationCancel(PBFFmpegReadCancellation *cancellation);
void PBFFmpegReadCancellationDestroy(PBFFmpegReadCancellation *cancellation);

PBFFmpegDemuxSource *PBFFmpegDemuxSourceCreate(
    const char *path,
    bool isRemote,
    PBFFmpegDemuxBufferConfiguration bufferConfiguration,
    PBFFmpegSourceReadMonitor *monitor,
    char *errorBuffer,
    size_t errorBufferSize
);
void PBFFmpegDemuxSourceInterrupt(PBFFmpegDemuxSource *source);
// True when the live format context's interrupt callback points at the read
// context the source owns. A reconnect that opened its replacement with a
// read context on the stack leaves this false, and every later interrupt
// poll on that context reads a dead frame.
bool PBFFmpegDemuxSourceInterruptTargetsOwnReadContext(
    const PBFFmpegDemuxSource *source
);
void PBFFmpegDemuxSourceDestroy(PBFFmpegDemuxSource *source);
PBFFmpegMediaSourceInformation *PBFFmpegDemuxSourceCopyInformation(
    PBFFmpegDemuxSource *source,
    char *errorBuffer,
    size_t errorBufferSize
);
bool PBFFmpegDemuxSourceSeek(
    PBFFmpegDemuxSource *source,
    double seconds,
    char *errorBuffer,
    size_t errorBufferSize
);
double PBFFmpegDemuxSourceGetBufferedDurationSeconds(
    PBFFmpegDemuxSource *source
);
double PBFFmpegDemuxSourceGetBufferTargetDurationSeconds(
    PBFFmpegDemuxSource *source
);
int64_t PBFFmpegDemuxSourceGetForwardBufferedByteCount(
    PBFFmpegDemuxSource *source
);
int64_t PBFFmpegDemuxSourceGetForwardBufferByteLimit(
    PBFFmpegDemuxSource *source
);
// Read-ahead held by subscribed streams playing the video does not need -
// subtitles and anything else that rides along. It is counted apart from the
// forward budget because it is never allowed to park the read thread: over
// its own limit the oldest packets are evicted instead.
int64_t PBFFmpegDemuxSourceGetAuxiliaryBufferedByteCount(
    PBFFmpegDemuxSource *source
);
// Packets of one stream given up because its reader left them behind. Any
// value above zero means that stream's consumer has seen a gap.
uint64_t PBFFmpegDemuxSourceGetDroppedPacketCount(
    PBFFmpegDemuxSource *source,
    int streamIndex
);
int64_t PBFFmpegDemuxSourceGetBackwardBufferedByteCount(
    PBFFmpegDemuxSource *source
);
int64_t PBFFmpegDemuxSourceGetBackwardBufferByteLimit(
    PBFFmpegDemuxSource *source
);
PBFFmpegDemuxBufferMode PBFFmpegDemuxSourceGetBufferMode(
    PBFFmpegDemuxSource *source
);
uint64_t PBFFmpegDemuxSourceGetReadFrameCount(
    PBFFmpegDemuxSource *source
);
unsigned int PBFFmpegDemuxSourceGetReconnectAttemptCount(
    PBFFmpegDemuxSource *source
);

PBFFmpegMediaSourceInformation *PBFFmpegMediaSourceInformationCreate(
    const char *path,
    char *errorBuffer,
    size_t errorBufferSize
);
PBFFmpegMediaSourceInformation *PBFFmpegMediaSourceInformationCreateWithSourceReadMonitor(
    const char *path,
    PBFFmpegSourceReadMonitor *monitor,
    char *errorBuffer,
    size_t errorBufferSize
);
void PBFFmpegMediaSourceInformationDestroy(
    PBFFmpegMediaSourceInformation *information
);
const char *PBFFmpegMediaSourceInformationGetContainerFormat(
    const PBFFmpegMediaSourceInformation *information
);
double PBFFmpegMediaSourceInformationGetDurationSeconds(
    const PBFFmpegMediaSourceInformation *information
);
bool PBFFmpegMediaSourceInformationContainerSupportsSourceFormatDescription(
    const PBFFmpegMediaSourceInformation *information
);
int PBFFmpegMediaSourceInformationGetDolbyVisionProfile(
    const PBFFmpegMediaSourceInformation *information
);
int PBFFmpegMediaSourceInformationGetDolbyVisionCrossCompatibilityID(
    const PBFFmpegMediaSourceInformation *information
);
bool PBFFmpegMediaSourceInformationDolbyVisionHasEnhancementLayer(
    const PBFFmpegMediaSourceInformation *information
);
bool PBFFmpegMediaSourceInformationHasStereoVideoEnhancementLayer(
    const PBFFmpegMediaSourceInformation *information
);
int PBFFmpegMediaSourceInformationGetStreamCount(
    const PBFFmpegMediaSourceInformation *information
);
bool PBFFmpegMediaSourceInformationCopyStream(
    const PBFFmpegMediaSourceInformation *information,
    int ordinal,
    PBFFmpegMediaStreamInfo *infoOut,
    char *codecNameBuffer,
    size_t codecNameBufferSize,
    char *languageBuffer,
    size_t languageBufferSize,
    char *titleBuffer,
    size_t titleBufferSize,
    char *colorPrimariesBuffer,
    size_t colorPrimariesBufferSize,
    char *transferFunctionBuffer,
    size_t transferFunctionBufferSize,
    char *yCbCrMatrixBuffer,
    size_t yCbCrMatrixBufferSize,
    char *colorRangeBuffer,
    size_t colorRangeBufferSize,
    char *projectionKindBuffer,
    size_t projectionKindBufferSize
);

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
void PBFFmpegReaderSetSourceReadMonitor(
    PBFFmpegReader *reader,
    PBFFmpegSourceReadMonitor *monitor
);
bool PBFFmpegReaderOpen(
    PBFFmpegReader *reader,
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
);
bool PBFFmpegReaderOpenWithDemuxSource(
    PBFFmpegReader *reader,
    PBFFmpegDemuxSource *source,
    PBFFmpegMode mode,
    char *errorBuffer,
    size_t errorBufferSize
);
void PBFFmpegReaderCancel(PBFFmpegReader *reader);

/// Test seam for exercising streams whose container metadata omits codec configuration.
/// Call after allocation and before `PBFFmpegReaderOpen`.
void PBFFmpegReaderForceBitstreamExtradataBootstrap(PBFFmpegReader *reader);
bool PBFFmpegReaderUsedBitstreamExtradataBootstrap(const PBFFmpegReader *reader);

void PBFFmpegReaderDestroy(PBFFmpegReader *reader);

PBFFmpegMediaSourceInformation *PBFFmpegReaderCopyMediaSourceInformation(
    const PBFFmpegReader *reader
);

/// Creates or copies every compressed video format description owned by the bridge.
/// Pass only `reader` to create or copy its compressed format. Otherwise, pass
/// `sourceFormat` with either `bridgeFormat` or `replacementExtensions`. A bridge
/// format fills missing decoder-configuration atoms without replacing source atoms;
/// replacement extensions form the complete extension dictionary.
/// The caller owns the returned format description and must release it.
OSStatus PBFFmpegVideoFormatDescriptionCreate(
    PBFFmpegReader *reader,
    CMVideoFormatDescriptionRef sourceFormat,
    CMVideoFormatDescriptionRef bridgeFormat,
    CFDictionaryRef replacementExtensions,
    CMVideoFormatDescriptionRef *formatOut
);

PBFFmpegReadResult PBFFmpegReaderCopyNextSample(
    PBFFmpegReader *reader,
    CMSampleBufferRef *sampleOut,
    char *errorBuffer,
    size_t errorBufferSize
);
PBFFmpegActiveFailureCause PBFFmpegReaderGetLastActiveFailureCause(
    const PBFFmpegReader *reader
);

double PBFFmpegReaderGetDurationSeconds(const PBFFmpegReader *reader);
double PBFFmpegReaderGetNominalFrameRate(const PBFFmpegReader *reader);
const char *PBFFmpegReaderGetCodecName(const PBFFmpegReader *reader);
bool PBFFmpegReaderOpenFailedWithUnsupportedVideoCodec(
    const PBFFmpegReader *reader
);
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
bool PBFFmpegReaderIsMVHEVC(const PBFFmpegReader *reader);

PBFFmpegAudioReader *PBFFmpegAudioReaderCreate(
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
);
PBFFmpegAudioReader *PBFFmpegAudioReaderAllocate(void);
void PBFFmpegAudioReaderSetSourceReadMonitor(
    PBFFmpegAudioReader *reader,
    PBFFmpegSourceReadMonitor *monitor
);
bool PBFFmpegAudioReaderOpen(
    PBFFmpegAudioReader *reader,
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
);
bool PBFFmpegAudioReaderOpenWithDemuxSource(
    PBFFmpegAudioReader *reader,
    PBFFmpegDemuxSource *source,
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
PBFFmpegActiveFailureCause PBFFmpegAudioReaderGetLastActiveFailureCause(
    const PBFFmpegAudioReader *reader
);
int PBFFmpegAudioReaderGetStreamIndex(const PBFFmpegAudioReader *reader);
int PBFFmpegAudioReaderGetSampleRate(const PBFFmpegAudioReader *reader);
int PBFFmpegAudioReaderGetChannelCount(const PBFFmpegAudioReader *reader);
const char *PBFFmpegAudioReaderGetCodecName(const PBFFmpegAudioReader *reader);
bool PBFFmpegAudioReaderOutputsPCM(const PBFFmpegAudioReader *reader);

PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
    const char *path,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize,
    PBFFmpegSourceReadMonitor *monitor,
    PBFFmpegReadCancellation *cancellation
);
PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreateWithDemuxSource(
    PBFFmpegDemuxSource *source,
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

// Reads a subtitle document (a sidecar whose bytes are subtitle content) to
// its end through the bridge's monitored door, so an interrupted monitor or a
// cancelled read aborts it and the constructor fails instead of returning a
// half-populated renderer.
PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreate(
    const char *path,
    int streamIndex,
    PBFFmpegSourceReadMonitor *monitor,
    PBFFmpegReadCancellation *cancellation,
    char *errorBuffer,
    size_t errorBufferSize
);
PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreateWithDemuxSource(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
);
// Folds in every packet the shared demux source has queued for the
// renderer's stream since creation or the previous call, without waiting.
// Returns the number of packets ingested, or -1 with an error message.
// A renderer created from a path scanned its file at creation and returns 0.
int PBSubtitleFrameRendererIngestAvailablePackets(
    PBSubtitleFrameRenderer *renderer,
    char *errorBuffer,
    size_t errorBufferSize
);

int PBSubtitleFrameRendererGetTextCueCount(
    const PBSubtitleFrameRenderer *renderer
);

// Packets this renderer has put through the subtitle decoder. A bitmap track
// keeps the display sets it decoded, so the count follows the track's packets
// rather than the number of frame requests.
uint64_t PBSubtitleFrameRendererGetDecodedPacketCount(
    const PBSubtitleFrameRenderer *renderer
);

// What a bitmap renderer holds, for telling apart the ways it can come up
// empty: no packet ever reached it, packets reached it but decoded to nothing,
// or display sets exist and none covers the time being asked for.
typedef struct PBSubtitleFrameRendererState {
    uint64_t ingestedPacketCount;
    uint64_t heldPacketCount;
    uint64_t decodedPacketCount;
    uint64_t displaySetCount;
    uint64_t decodeCursor;
    double firstPacketSeconds;
    double lastPacketSeconds;
    double coveredStartSeconds;
    double coveredEndSeconds;
    // The last packet handed to the subtitle decoder and what came back, for
    // the case where packets arrive and no display set ever comes out.
    int lastPacketSize;
    int lastPacketHasPresentationTime;
    int lastPacketSegmentType;
    int lastPacketSegmentLength;
    int lastDecodeResult;
    int lastDecodeProduced;
    unsigned int lastSubtitleRectCount;
    unsigned int lastSubtitleFormat;
    unsigned int lastSubtitleStartDisplayTime;
    unsigned int lastSubtitleEndDisplayTime;
} PBSubtitleFrameRendererState;

PBSubtitleFrameRendererState PBSubtitleFrameRendererCopyState(
    const PBSubtitleFrameRenderer *renderer
);
bool PBSubtitleFrameRendererCopyTextCue(
    const PBSubtitleFrameRenderer *renderer,
    int index,
    double *startSecondsOut,
    double *durationSecondsOut,
    CFStringRef *textOut
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
