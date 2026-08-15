#include "PlaybackFFmpegBridge.h"

#include <AudioToolbox/AudioToolbox.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/mastering_display_metadata.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/spherical.h>
#include <libavutil/stereo3d.h>
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct {
    int64_t offset;
    size_t length;
    uint8_t *bytes;
} PBFFmpegSourceByteRange;

typedef enum {
    PBFFmpegFirstOpenSourceBytesEmpty,
    PBFFmpegFirstOpenSourceBytesRecording,
    PBFFmpegFirstOpenSourceBytesFrozen,
} PBFFmpegFirstOpenSourceBytesState;

typedef struct {
    pthread_mutex_t lock;
    PBFFmpegFirstOpenSourceBytesState state;
    char *sourcePath;
    PBFFmpegSourceByteRange *ranges;
    size_t rangeCount;
    size_t rangeCapacity;
} PBFFmpegFirstOpenSourceBytes;

struct PBFFmpegSourceReadMonitor {
    atomic_uint_fast64_t totalBytesRead;
    PBFFmpegFirstOpenSourceBytes firstOpenSourceBytes;
};

typedef enum {
    PBFFmpegSourceIOBypassFirstOpenBytes,
    PBFFmpegSourceIORecordFirstOpenBytes,
    PBFFmpegSourceIOReplayFirstOpenBytes,
} PBFFmpegSourceIOFirstOpenBytesMode;

typedef struct {
    PBFFmpegSourceReadMonitor *monitor;
    AVIOContext *outer;
    AVIOContext *inner;
    int64_t position;
    PBFFmpegSourceIOFirstOpenBytesMode firstOpenBytesMode;
    bool firstOpenBytesEnabled;
} PBFFmpegSourceIO;

typedef struct {
    PBFFmpegSourceReadMonitor *monitor;
    atomic_bool *cancelled;
    AVFormatContext *formatContext;
    PBFFmpegSourceIO *sourceIO;
    int64_t accountedBytesRead;
} PBFFmpegSourceReadContext;

typedef struct {
    bool movFamily;
    bool skippedProbe;
} PBStreamInformationRead;

static int read_stream_information(
    AVFormatContext *context,
    PBFFmpegSourceReadContext *sourceReadContext,
    PBStreamInformationRead *readOut
);

typedef struct {
    PBFFmpegMediaStreamInfo info;
    char codecName[64];
    char language[64];
    char title[256];
    char colorPrimaries[64];
    char transferFunction[64];
    char yCbCrMatrix[64];
    char colorRange[64];
    char projectionKind[64];
} PBFFmpegMediaStreamStorage;

struct PBFFmpegMediaSourceInformation {
    char containerFormat[64];
    double durationSeconds;
    int streamCount;
    PBFFmpegMediaStreamStorage *streams;
};

struct PBFFmpegReader {
    atomic_bool cancelled;
    PBFFmpegSourceReadContext sourceReadContext;
    AVFormatContext *formatContext;
    AVPacket *packet;
    int videoStreamIndex;
    AVRational timeBase;
    int64_t startTimestamp;
    PBFFmpegMode mode;
    CMVideoFormatDescriptionRef compressedFormat;
    bool convertsAnnexB;
    bool forceBitstreamExtradataBootstrap;
    bool usedBitstreamExtradataBootstrap;
    bool bootstrapPacketsAreAnnexB;
    AVPacket **bootstrapPackets;
    size_t bootstrapPacketCount;
    size_t bootstrapPacketIndex;
    size_t bootstrapPacketBytes;
    double durationSeconds;
    double nominalFrameRate;
    char codecName[64];
    char codecTag[5];
    char containerFormat[64];
    char colorPrimaries[64];
    char transferFunction[64];
    char yCbCrMatrix[64];
    char colorRange[64];
    char projectionKind[64];
    char viewPackingKind[64];
    int width;
    int height;
    int dolbyVisionProfile;
    int dolbyVisionCrossCompatibilityID;
    bool dolbyVisionHasEnhancementLayer;
};

struct PBFFmpegAudioReader {
    atomic_bool cancelled;
    PBFFmpegSourceReadContext sourceReadContext;
    AVFormatContext *formatContext;
    AVPacket *packet;
    AVPacket *filteredPacket;
    AVBSFContext *bitstreamFilter;
    int audioStreamIndex;
    AVRational timeBase;
    int64_t startTimestamp;
    int sampleRate;
    int channelCount;
    bool inputEnded;
    bool filterDrained;
    bool outputsPCM;
    CFDataRef codecMagicCookie;
    int64_t pendingOriginalPTS;
    int64_t pendingOriginalDTS;
    int64_t pendingOriginalDuration;
    CMAudioFormatDescriptionRef formatDescription;
    char codecName[64];
};

static int configure_source_io_first_open_bytes(
    PBFFmpegSourceIO *sourceIO,
    const char *path
) {
    if (!sourceIO || !sourceIO->monitor) return 0;
    PBFFmpegFirstOpenSourceBytes *bytes =
        &sourceIO->monitor->firstOpenSourceBytes;
    pthread_mutex_lock(&bytes->lock);
    int result = 0;
    if (bytes->state == PBFFmpegFirstOpenSourceBytesEmpty) {
        bytes->sourcePath = av_strdup(path);
        if (!bytes->sourcePath) {
            result = AVERROR(ENOMEM);
        } else {
            bytes->state = PBFFmpegFirstOpenSourceBytesRecording;
            sourceIO->firstOpenBytesMode =
                PBFFmpegSourceIORecordFirstOpenBytes;
            sourceIO->firstOpenBytesEnabled = true;
        }
    } else if (
        bytes->state == PBFFmpegFirstOpenSourceBytesFrozen &&
        bytes->sourcePath && strcmp(bytes->sourcePath, path) == 0
    ) {
        sourceIO->firstOpenBytesMode =
            PBFFmpegSourceIOReplayFirstOpenBytes;
        sourceIO->firstOpenBytesEnabled = true;
    }
    pthread_mutex_unlock(&bytes->lock);
    return result;
}

static int copy_first_open_source_bytes(
    PBFFmpegSourceIO *sourceIO,
    uint8_t *buffer,
    int bufferSize,
    int64_t *nextRangeOffset
) {
    if (nextRangeOffset) *nextRangeOffset = -1;
    if (!sourceIO || !sourceIO->monitor ||
        !sourceIO->firstOpenBytesEnabled || bufferSize <= 0) return 0;
    PBFFmpegFirstOpenSourceBytes *bytes =
        &sourceIO->monitor->firstOpenSourceBytes;
    pthread_mutex_lock(&bytes->lock);
    int copied = 0;
    for (size_t index = 0; index < bytes->rangeCount; index++) {
        PBFFmpegSourceByteRange *range = &bytes->ranges[index];
        if (range->offset > sourceIO->position) {
            if (nextRangeOffset) *nextRangeOffset = range->offset;
            break;
        }
        int64_t relativeOffset = sourceIO->position - range->offset;
        if (relativeOffset < 0 || (uint64_t)relativeOffset >= range->length) continue;
        size_t available = range->length - (size_t)relativeOffset;
        copied = bufferSize < (int)available ? bufferSize : (int)available;
        memcpy(buffer, range->bytes + relativeOffset, (size_t)copied);
        break;
    }
    pthread_mutex_unlock(&bytes->lock);
    return copied;
}

static int remember_first_open_source_bytes(
    PBFFmpegSourceIO *sourceIO,
    int64_t offset,
    const uint8_t *buffer,
    int bufferSize
) {
    if (!sourceIO || sourceIO->firstOpenBytesMode !=
            PBFFmpegSourceIORecordFirstOpenBytes || bufferSize <= 0) return 0;
    uint8_t *copy = av_memdup(buffer, (size_t)bufferSize);
    if (!copy) return AVERROR(ENOMEM);
    PBFFmpegFirstOpenSourceBytes *bytes =
        &sourceIO->monitor->firstOpenSourceBytes;
    pthread_mutex_lock(&bytes->lock);
    int result = 0;
    if (bytes->state != PBFFmpegFirstOpenSourceBytesRecording) {
        result = AVERROR(EINVAL);
        goto finish;
    }
    if (bytes->rangeCount == bytes->rangeCapacity) {
        if (bytes->rangeCapacity > SIZE_MAX / 2) {
            result = AVERROR(ENOMEM);
            goto finish;
        }
        size_t capacity = bytes->rangeCapacity ? bytes->rangeCapacity * 2 : 1;
        PBFFmpegSourceByteRange *ranges = av_realloc_array(
            bytes->ranges,
            capacity,
            sizeof(*ranges)
        );
        if (!ranges) {
            result = AVERROR(ENOMEM);
            goto finish;
        }
        bytes->ranges = ranges;
        bytes->rangeCapacity = capacity;
    }
    size_t insertionIndex = 0;
    while (insertionIndex < bytes->rangeCount &&
           bytes->ranges[insertionIndex].offset < offset) {
        insertionIndex++;
    }
    memmove(
        &bytes->ranges[insertionIndex + 1],
        &bytes->ranges[insertionIndex],
        (bytes->rangeCount - insertionIndex) * sizeof(*bytes->ranges)
    );
    bytes->ranges[insertionIndex] = (PBFFmpegSourceByteRange) {
        .offset = offset,
        .length = (size_t)bufferSize,
        .bytes = copy,
    };
    bytes->rangeCount++;
    copy = NULL;
finish:
    pthread_mutex_unlock(&bytes->lock);
    av_free(copy);
    return result;
}

static void freeze_first_open_source_bytes(PBFFmpegSourceIO *sourceIO) {
    if (!sourceIO || !sourceIO->monitor ||
        sourceIO->firstOpenBytesMode !=
            PBFFmpegSourceIORecordFirstOpenBytes) return;
    PBFFmpegFirstOpenSourceBytes *bytes =
        &sourceIO->monitor->firstOpenSourceBytes;
    pthread_mutex_lock(&bytes->lock);
    if (bytes->state == PBFFmpegFirstOpenSourceBytesRecording) {
        bytes->state = PBFFmpegFirstOpenSourceBytesFrozen;
    }
    pthread_mutex_unlock(&bytes->lock);
}

static int source_io_read(void *opaque, uint8_t *buffer, int bufferSize) {
    PBFFmpegSourceIO *sourceIO = opaque;
    if (!sourceIO || !sourceIO->inner || bufferSize <= 0) return AVERROR(EINVAL);
    int64_t nextRangeOffset = -1;
    int copied = copy_first_open_source_bytes(
        sourceIO,
        buffer,
        bufferSize,
        &nextRangeOffset
    );
    if (copied > 0) {
        sourceIO->position += copied;
        return copied;
    }
    int forwardedSize = bufferSize;
    if (nextRangeOffset > sourceIO->position &&
        nextRangeOffset - sourceIO->position < forwardedSize) {
        forwardedSize = (int)(nextRangeOffset - sourceIO->position);
    }
    int64_t innerPosition = avio_tell(sourceIO->inner);
    if (innerPosition != sourceIO->position) {
        int64_t seekResult = avio_seek(
            sourceIO->inner,
            sourceIO->position,
            SEEK_SET
        );
        if (seekResult < 0) return (int)seekResult;
    }
    int bytesRead = avio_read(sourceIO->inner, buffer, forwardedSize);
    if (bytesRead <= 0) return bytesRead == 0 ? AVERROR_EOF : bytesRead;
    int result = remember_first_open_source_bytes(
        sourceIO,
        sourceIO->position,
        buffer,
        bytesRead
    );
    if (result < 0) return result;
    sourceIO->position += bytesRead;
    return bytesRead;
}

static bool add_source_offset(int64_t base, int64_t offset, int64_t *result) {
    if ((offset > 0 && base > INT64_MAX - offset) ||
        (offset < 0 && base < INT64_MIN - offset)) return false;
    *result = base + offset;
    return *result >= 0;
}

static int64_t source_io_seek(void *opaque, int64_t offset, int whence) {
    PBFFmpegSourceIO *sourceIO = opaque;
    if (!sourceIO || !sourceIO->inner) return AVERROR(EINVAL);
    if ((whence & AVSEEK_SIZE) == AVSEEK_SIZE) {
        return avio_size(sourceIO->inner);
    }
    int origin = whence & ~AVSEEK_FORCE;
    int64_t base = 0;
    switch (origin) {
        case SEEK_SET:
            break;
        case SEEK_CUR:
            base = sourceIO->position;
            break;
        case SEEK_END:
            base = avio_size(sourceIO->inner);
            if (base < 0) return base;
            break;
        default:
            return AVERROR(EINVAL);
    }
    int64_t position = 0;
    if (!add_source_offset(base, offset, &position)) return AVERROR(EINVAL);
    sourceIO->position = position;
    return position;
}

static void destroy_source_io(PBFFmpegSourceIO **sourceIOPointer) {
    if (!sourceIOPointer || !*sourceIOPointer) return;
    PBFFmpegSourceIO *sourceIO = *sourceIOPointer;
    if (sourceIO->outer) {
        av_freep(&sourceIO->outer->buffer);
        avio_context_free(&sourceIO->outer);
    }
    if (sourceIO->inner) avio_closep(&sourceIO->inner);
    av_free(sourceIO);
    *sourceIOPointer = NULL;
}

static int wrap_source_io(
    AVIOContext *inner,
    const char *path,
    PBFFmpegSourceReadMonitor *monitor,
    PBFFmpegSourceIO **sourceIOOut
) {
    *sourceIOOut = NULL;
    if (!inner || inner->buffer_size <= 0) return AVERROR(EINVAL);
    PBFFmpegSourceIO *sourceIO = av_mallocz(sizeof(*sourceIO));
    if (!sourceIO) return AVERROR(ENOMEM);
    sourceIO->monitor = monitor;
    sourceIO->inner = inner;
    uint8_t *buffer = av_malloc((size_t)inner->buffer_size);
    if (!buffer) {
        av_free(sourceIO);
        return AVERROR(ENOMEM);
    }
    sourceIO->outer = avio_alloc_context(
        buffer,
        inner->buffer_size,
        0,
        sourceIO,
        source_io_read,
        NULL,
        source_io_seek
    );
    if (!sourceIO->outer) {
        av_free(buffer);
        av_free(sourceIO);
        return AVERROR(ENOMEM);
    }
    sourceIO->outer->seekable = inner->seekable;
    sourceIO->outer->direct = inner->direct;
    sourceIO->outer->max_packet_size = inner->max_packet_size;
    int result = configure_source_io_first_open_bytes(
        sourceIO,
        path
    );
    if (result < 0) {
        sourceIO->inner = NULL;
        destroy_source_io(&sourceIO);
        return result;
    }
    *sourceIOOut = sourceIO;
    return 0;
}

static int finish_source_io_open(PBFFmpegSourceIO *sourceIO) {
    if (!sourceIO || !sourceIO->outer) return 0;
    freeze_first_open_source_bytes(sourceIO);
    int64_t position = avio_tell(sourceIO->outer);
    if (position < 0) return (int)position;
    sourceIO->firstOpenBytesEnabled = false;
    avio_flush(sourceIO->outer);
    int64_t resetPosition = avio_seek(sourceIO->outer, position, SEEK_SET);
    return resetPosition < 0 ? (int)resetPosition : 0;
}

static void publish_source_bytes(PBFFmpegSourceReadContext *context) {
    if (!context || !context->monitor) return;
    AVIOContext *meteredIO = context->sourceIO
        ? context->sourceIO->inner
        : context->formatContext
            ? context->formatContext->pb
            : NULL;
    if (!meteredIO) return;
    int64_t bytesRead = meteredIO->bytes_read;
    if (bytesRead < 0) return;
    uint64_t delta = bytesRead >= context->accountedBytesRead
        ? (uint64_t)(bytesRead - context->accountedBytesRead)
        : (uint64_t)bytesRead;
    context->accountedBytesRead = bytesRead;
    if (delta > 0) {
        atomic_fetch_add_explicit(
            &context->monitor->totalBytesRead,
            delta,
            memory_order_relaxed
        );
    }
}

static int publish_source_bytes_and_check_cancellation(void *opaque) {
    PBFFmpegSourceReadContext *context = opaque;
    publish_source_bytes(context);
    atomic_bool *cancelled = context ? context->cancelled : NULL;
    return cancelled && atomic_load_explicit(cancelled, memory_order_relaxed);
}

static bool cancellation_requested(const atomic_bool *cancelled) {
    return cancelled && atomic_load_explicit(cancelled, memory_order_relaxed);
}

static AVFormatContext *allocate_format_context(
    atomic_bool *cancelled,
    PBFFmpegSourceReadContext *sourceReadContext
) {
    AVFormatContext *context = avformat_alloc_context();
    if (context && sourceReadContext) {
        sourceReadContext->cancelled = cancelled;
        sourceReadContext->formatContext = context;
        sourceReadContext->sourceIO = NULL;
        sourceReadContext->accountedBytesRead = 0;
        context->interrupt_callback.callback =
            publish_source_bytes_and_check_cancellation;
        context->interrupt_callback.opaque = sourceReadContext;
    }
    return context;
}

static void finish_source_read_context(PBFFmpegSourceReadContext *context) {
    publish_source_bytes(context);
    if (!context) return;
    context->formatContext = NULL;
    context->accountedBytesRead = 0;
}

static void close_media_source(
    AVFormatContext **formatContext,
    PBFFmpegSourceReadContext *sourceReadContext
) {
    finish_source_read_context(sourceReadContext);
    avformat_close_input(formatContext);
    if (sourceReadContext) destroy_source_io(&sourceReadContext->sourceIO);
}

PBFFmpegSourceReadMonitor *PBFFmpegSourceReadMonitorCreate(void) {
    PBFFmpegSourceReadMonitor *monitor = calloc(1, sizeof(PBFFmpegSourceReadMonitor));
    if (!monitor) return NULL;
    atomic_init(&monitor->totalBytesRead, 0);
    if (pthread_mutex_init(&monitor->firstOpenSourceBytes.lock, NULL) != 0) {
        free(monitor);
        return NULL;
    }
    return monitor;
}

void PBFFmpegSourceReadMonitorDestroy(PBFFmpegSourceReadMonitor *monitor) {
    if (!monitor) return;
    PBFFmpegFirstOpenSourceBytes *bytes = &monitor->firstOpenSourceBytes;
    for (size_t index = 0; index < bytes->rangeCount; index++) {
        av_free(bytes->ranges[index].bytes);
    }
    av_free(bytes->ranges);
    av_free(bytes->sourcePath);
    pthread_mutex_destroy(&bytes->lock);
    free(monitor);
}

uint64_t PBFFmpegSourceReadMonitorGetTotalBytesRead(
    const PBFFmpegSourceReadMonitor *monitor
) {
    return monitor
        ? atomic_load_explicit(&monitor->totalBytesRead, memory_order_relaxed)
        : 0;
}

struct PBFFmpegSubtitleReader {
    PBFFmpegSourceReadContext sourceReadContext;
    AVFormatContext *formatContext;
    AVPacket *packet;
    AVCodecContext *decoder;
    int subtitleStreamIndex;
    enum AVCodecID codecID;
    AVRational timeBase;
    int64_t startTimestamp;
};

static bool subtitle_stream_is_supported(const AVStream *stream) {
    if (!stream || stream->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) return false;
    switch (stream->codecpar->codec_id) {
        case AV_CODEC_ID_ASS:
        case AV_CODEC_ID_SSA:
        case AV_CODEC_ID_SUBRIP:
        case AV_CODEC_ID_WEBVTT:
        case AV_CODEC_ID_MOV_TEXT:
        case AV_CODEC_ID_HDMV_PGS_SUBTITLE:
        case AV_CODEC_ID_DVD_SUBTITLE:
        case AV_CODEC_ID_DVB_SUBTITLE:
            return true;
        default:
            return false;
    }
}

static int aac_audio_object_type(const AVCodecParameters *parameters) {
    if (!parameters || parameters->codec_id != AV_CODEC_ID_AAC) return 0;
    if (parameters->profile == AV_PROFILE_AAC_USAC) return 42;
    if (!parameters->extradata || parameters->extradata_size < 2) return 0;
    int objectType = parameters->extradata[0] >> 3;
    if (objectType == 31) {
        objectType = 32 +
            ((parameters->extradata[0] & 0x07) << 3) +
            (parameters->extradata[1] >> 5);
    }
    return objectType;
}

static bool aac_is_usac(const AVCodecParameters *parameters) {
    return aac_audio_object_type(parameters) == 42;
}

static AudioFormatID compressed_audio_format_id(const AVCodecParameters *parameters) {
    switch (parameters->codec_id) {
        case AV_CODEC_ID_AAC:
            if (aac_is_usac(parameters)) {
                return kAudioFormatMPEGD_USAC;
            }
            if (parameters->profile == AV_PROFILE_AAC_HE) {
                return kAudioFormatMPEG4AAC_HE;
            }
            if (parameters->profile == AV_PROFILE_AAC_HE_V2) {
                return kAudioFormatMPEG4AAC_HE_V2;
            }
            return kAudioFormatMPEG4AAC;
        case AV_CODEC_ID_AC3: return kAudioFormatAC3;
        case AV_CODEC_ID_EAC3: return kAudioFormatEnhancedAC3;
        case AV_CODEC_ID_MP2: return kAudioFormatMPEGLayer2;
        case AV_CODEC_ID_MP3: return kAudioFormatMPEGLayer3;
        case AV_CODEC_ID_ALAC: return kAudioFormatAppleLossless;
        case AV_CODEC_ID_OPUS: return kAudioFormatOpus;
        case AV_CODEC_ID_FLAC: return kAudioFormatFLAC;
        case AV_CODEC_ID_APAC: return kAudioFormatAPAC;
        default: return 0;
    }
}

typedef struct SourcePCMFormat {
    UInt32 bytesPerSample;
    UInt32 bitsPerChannel;
    AudioFormatFlags flags;
} SourcePCMFormat;

static bool source_pcm_format(enum AVCodecID codecID, SourcePCMFormat *formatOut) {
    SourcePCMFormat format = {0};
    switch (codecID) {
        case AV_CODEC_ID_PCM_S8:
            format = (SourcePCMFormat){1, 8, kAudioFormatFlagIsSignedInteger};
            break;
        case AV_CODEC_ID_PCM_U8:
            format = (SourcePCMFormat){1, 8, 0};
            break;
        case AV_CODEC_ID_PCM_S16LE:
            format = (SourcePCMFormat){2, 16, kAudioFormatFlagIsSignedInteger};
            break;
        case AV_CODEC_ID_PCM_S16BE:
            format = (SourcePCMFormat){
                2, 16, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian
            };
            break;
        case AV_CODEC_ID_PCM_U16LE:
            format = (SourcePCMFormat){2, 16, 0};
            break;
        case AV_CODEC_ID_PCM_U16BE:
            format = (SourcePCMFormat){2, 16, kAudioFormatFlagIsBigEndian};
            break;
        case AV_CODEC_ID_PCM_S24LE:
            format = (SourcePCMFormat){3, 24, kAudioFormatFlagIsSignedInteger};
            break;
        case AV_CODEC_ID_PCM_S24BE:
            format = (SourcePCMFormat){
                3, 24, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian
            };
            break;
        case AV_CODEC_ID_PCM_U24LE:
            format = (SourcePCMFormat){3, 24, 0};
            break;
        case AV_CODEC_ID_PCM_U24BE:
            format = (SourcePCMFormat){3, 24, kAudioFormatFlagIsBigEndian};
            break;
        case AV_CODEC_ID_PCM_S32LE:
            format = (SourcePCMFormat){4, 32, kAudioFormatFlagIsSignedInteger};
            break;
        case AV_CODEC_ID_PCM_S32BE:
            format = (SourcePCMFormat){
                4, 32, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian
            };
            break;
        case AV_CODEC_ID_PCM_U32LE:
            format = (SourcePCMFormat){4, 32, 0};
            break;
        case AV_CODEC_ID_PCM_U32BE:
            format = (SourcePCMFormat){4, 32, kAudioFormatFlagIsBigEndian};
            break;
        case AV_CODEC_ID_PCM_F32LE:
            format = (SourcePCMFormat){4, 32, kAudioFormatFlagIsFloat};
            break;
        case AV_CODEC_ID_PCM_F32BE:
            format = (SourcePCMFormat){
                4, 32, kAudioFormatFlagIsFloat | kAudioFormatFlagIsBigEndian
            };
            break;
        case AV_CODEC_ID_PCM_F64LE:
            format = (SourcePCMFormat){8, 64, kAudioFormatFlagIsFloat};
            break;
        case AV_CODEC_ID_PCM_F64BE:
            format = (SourcePCMFormat){
                8, 64, kAudioFormatFlagIsFloat | kAudioFormatFlagIsBigEndian
            };
            break;
        default:
            return false;
    }
    format.flags |= kAudioFormatFlagIsPacked;
    if (formatOut) *formatOut = format;
    return true;
}

static bool audio_codec_is_source_pcm(enum AVCodecID codecID) {
    return source_pcm_format(codecID, NULL);
}

static bool audio_codec_is_supported(enum AVCodecID codecID) {
    switch (codecID) {
        case AV_CODEC_ID_AAC:
        case AV_CODEC_ID_AC3:
        case AV_CODEC_ID_EAC3:
        case AV_CODEC_ID_MP2:
        case AV_CODEC_ID_MP3:
        case AV_CODEC_ID_ALAC:
        case AV_CODEC_ID_OPUS:
        case AV_CODEC_ID_FLAC:
        case AV_CODEC_ID_APAC:
            return true;
        default:
            return audio_codec_is_source_pcm(codecID);
    }
}

static bool audio_stream_is_supported(const AVStream *stream) {
    if (!stream || stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) return false;
    return audio_codec_is_supported(stream->codecpar->codec_id) &&
        stream->codecpar->sample_rate > 0 &&
        stream->codecpar->ch_layout.nb_channels > 0;
}

static void set_error(char *buffer, size_t size, const char *message);

static bool audio_stream_needs_more_probe(const AVStream *stream) {
    if (!stream || stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) return false;
    return audio_codec_is_supported(stream->codecpar->codec_id) &&
        (stream->codecpar->sample_rate <= 0 ||
         stream->codecpar->ch_layout.nb_channels <= 0);
}

static bool is_audio_stream(const AVStream *stream) {
    return stream && stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO;
}

static bool audio_stream_has_supported_codec(const AVStream *stream) {
    return is_audio_stream(stream) &&
        audio_codec_is_supported(stream->codecpar->codec_id);
}

static const int aac_sample_rates[] = {
    96000, 88200, 64000, 48000, 44100, 32000, 24000,
    22050, 16000, 12000, 11025, 8000, 7350,
};

static bool fill_aac_parameters_from_adts(AVStream *stream, const AVPacket *packet) {
    if (!stream || !packet || stream->codecpar->codec_id != AV_CODEC_ID_AAC) return false;
    int searchLimit = packet->size < 64 ? packet->size : 64;
    for (int offset = 0; offset + 7 <= searchLimit; offset++) {
        const uint8_t *header = packet->data + offset;
        if (header[0] != 0xff || (header[1] & 0xf6) != 0xf0) continue;
        int sampleRateIndex = (header[2] >> 2) & 0x0f;
        int channelCount = ((header[2] & 0x01) << 2) | ((header[3] >> 6) & 0x03);
        if (sampleRateIndex >= 13 || channelCount <= 0) continue;

        stream->codecpar->sample_rate = aac_sample_rates[sampleRateIndex];
        av_channel_layout_uninit(&stream->codecpar->ch_layout);
        av_channel_layout_default(&stream->codecpar->ch_layout, channelCount);
        stream->codecpar->profile = (header[2] >> 6) & 0x03;
        stream->codecpar->frame_size = 1024;
        return true;
    }
    return false;
}

static void probe_delayed_audio_parameters(AVFormatContext *context) {
    int unresolved = 0;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        if (audio_stream_needs_more_probe(context->streams[index])) unresolved++;
    }
    if (unresolved == 0) return;

    AVPacket *packet = av_packet_alloc();
    if (!packet) return;
    int packetCount = 0;
    int64_t byteCount = 0;
    while (unresolved > 0 && packetCount < 100000 && byteCount < 100LL * 1024 * 1024) {
        int result = av_read_frame(context, packet);
        if (result < 0) break;
        packetCount++;
        byteCount += packet->size;
        if (packet->stream_index >= 0 &&
            packet->stream_index < (int)context->nb_streams) {
            AVStream *stream = context->streams[packet->stream_index];
            if (audio_stream_needs_more_probe(stream) &&
                fill_aac_parameters_from_adts(stream, packet)) {
                unresolved--;
            }
        }
        av_packet_unref(packet);
    }
    av_packet_free(&packet);

    if (context->pb && (context->pb->seekable & AVIO_SEEKABLE_NORMAL)) {
        if (avformat_seek_file(
                context, -1, INT64_MIN, 0, INT64_MAX, AVSEEK_FLAG_BACKWARD
            ) >= 0) {
            avformat_flush(context);
        }
    }
}

static void set_audio_stream_selection_error(
    AVFormatContext *context,
    char *errorBuffer,
    size_t errorBufferSize
) {
    bool hasAudioStream = false;
    bool hasSupportedCodec = false;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVStream *stream = context->streams[index];
        hasAudioStream = hasAudioStream || is_audio_stream(stream);
        hasSupportedCodec = hasSupportedCodec || audio_stream_has_supported_codec(stream);
    }
    if (!hasAudioStream) {
        set_error(errorBuffer, errorBufferSize, "The selected source has no audio stream");
    } else if (!hasSupportedCodec) {
        set_error(errorBuffer, errorBufferSize, "The selected audio codec is not supported by PlaybackCore");
    } else {
        set_error(
            errorBuffer,
            errorBufferSize,
            "Audio stream parameters are unavailable after extended probe"
        );
    }
}

static void set_error(char *buffer, size_t size, const char *message) {
    if (buffer == NULL || size == 0) return;
    snprintf(buffer, size, "%s", message);
}

static void set_av_error(char *buffer, size_t size, const char *operation, int code) {
    char detail[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, detail, sizeof(detail));
    if (buffer == NULL || size == 0) return;
    snprintf(buffer, size, "%s: %s (%d)", operation, detail, code);
}

static void normalize_mov_apac_codec_id(AVFormatContext *context) {
    if (!context) return;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVCodecParameters *parameters = context->streams[index]->codecpar;
        if (parameters->codec_type == AVMEDIA_TYPE_AUDIO &&
            (parameters->codec_id == AV_CODEC_ID_NONE ||
             parameters->codec_id == AV_CODEC_ID_APPLE_APAC) &&
            parameters->codec_tag == MKTAG('a', 'p', 'a', 'c')) {
            parameters->codec_id = AV_CODEC_ID_APAC;
        }
    }
}

/// A disc image carries no header a probe can read, because its first bytes are
/// filesystem descriptors rather than media. FFmpeg scores those descriptors as an
/// MPEG program stream and opens the image with one unreadable video stream, so the
/// demuxer is named instead of guessed. Measured on FEL_test_for_AVS.iso: probed it
/// reports format mpeg with 1 stream and the decoder rejects the picture, named it
/// reports mpegts with the 2 streams the disc holds and the same 119.99 seconds.
///
/// Only a UDF image is claimed, which is what Blu-ray uses and where the video is
/// always MPEG-TS. A DVD image holds a program stream and is not covered, and an
/// encrypted disc has a payload no demuxer can read whatever it is named.
static const AVInputFormat *disc_image_input_format(const char *path) {
    if (!path) return NULL;
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    // The volume recognition sequence sits 32 KB in, as consecutive 2048-byte
    // descriptors each carrying a five-character identifier one byte from its start.
    uint8_t descriptors[2][2048];
    bool isUDF = false;
    if (fseek(file, 32768, SEEK_SET) == 0
        && fread(descriptors, sizeof(descriptors[0]), 2, file) == 2
        && memcmp(descriptors[0] + 1, "BEA01", 5) == 0) {
        isUDF = memcmp(descriptors[1] + 1, "NSR02", 5) == 0
            || memcmp(descriptors[1] + 1, "NSR03", 5) == 0;
    }
    fclose(file);
    return isUDF ? av_find_input_format("mpegts") : NULL;
}

static bool path_is_http(const char *path) {
    return path &&
        (strncmp(path, "http://", 7) == 0 || strncmp(path, "https://", 8) == 0);
}

/// Opens `path`, naming the demuxer and setting its options where the source needs
/// it. A disc image and an HTTP source each need one, and both follow from a fact
/// about the source, so one function owns what opening a path means here.
static int open_media_source(
    AVFormatContext **context,
    const char *path,
    PBFFmpegSourceReadContext *sourceReadContext
) {
    AVDictionary *options = NULL;
    AVIOContext *openedIO = NULL;
    PBFFmpegSourceIO *sourceIO = NULL;
    int result = 0;
    if (path_is_http(path)) {
        result = avio_open2(
            &openedIO,
            path,
            AVIO_FLAG_READ,
            *context ? &(*context)->interrupt_callback : NULL,
            NULL
        );
        if (result < 0) goto finish;
        int64_t length = avio_size(openedIO);
        if (length > 0) {
            // HTTP uses end_offset as its effective EOF, so only this response's
            // length can bound later ranges without silently truncating the tail.
            result = av_opt_set_int(
                openedIO,
                "end_offset",
                length,
                AV_OPT_SEARCH_CHILDREN
            );
            if (result < 0) goto finish;
        }
        if (sourceReadContext && sourceReadContext->monitor) {
            result = wrap_source_io(
                openedIO,
                path,
                sourceReadContext->monitor,
                &sourceIO
            );
            if (result < 0) goto finish;
            sourceReadContext->sourceIO = sourceIO;
            (*context)->pb = sourceIO->outer;
            openedIO = NULL;
        } else {
            (*context)->pb = openedIO;
        }
    }
    const AVInputFormat *format = disc_image_input_format(path);
    if (format) {
        // The stream sits behind the disc's filesystem metadata, and the demuxer
        // stops looking for its first sync byte after 64 KB. Measured on
        // FEL_test_for_AVS.iso, whose payload starts 917504 bytes in: at the default
        // limit the streams are still identified, because probing reads ahead of
        // where playback starts, and then the first av_read_frame returns nothing at
        // all. That is the shape of the failure, an open that succeeds onto a stream
        // no packet ever arrives from.
        av_dict_set_int(&options, "resync_size", 16LL * 1024 * 1024, 0);
    }
    result = avformat_open_input(context, path, format, &options);
    if (result >= 0 && sourceIO) {
        result = finish_source_io_open(sourceIO);
    } else if (result >= 0 && openedIO) {
        // avformat_open_input marks caller-supplied IO as custom; ownership moves
        // here so the existing avformat_close_input paths still close the socket.
        (*context)->flags &= ~AVFMT_FLAG_CUSTOM_IO;
        openedIO = NULL;
    }
finish:
    if (sourceIO && sourceIO->firstOpenBytesMode ==
            PBFFmpegSourceIORecordFirstOpenBytes) {
        freeze_first_open_source_bytes(sourceIO);
    }
    if (result < 0 && *context && (*context)->pb == openedIO) {
        (*context)->pb = NULL;
    }
    if (openedIO) avio_closep(&openedIO);
    av_dict_free(&options);
    if (sourceReadContext) {
        sourceReadContext->formatContext = result >= 0 ? *context : NULL;
        publish_source_bytes(sourceReadContext);
    }
    return result;
}

static int open_media_source_for_audio(
    const char *path,
    AVFormatContext **contextOut,
    atomic_bool *cancelled,
    PBFFmpegSourceReadContext *sourceReadContext,
    char *errorBuffer,
    size_t errorBufferSize
) {
    AVFormatContext *context = allocate_format_context(cancelled, sourceReadContext);
    if (context == NULL) return AVERROR(ENOMEM);
    int result = open_media_source(&context, path, sourceReadContext);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open audio media source", result);
        close_media_source(&context, sourceReadContext);
        return result;
    }
    normalize_mov_apac_codec_id(context);
    PBStreamInformationRead informationRead = {0};
    result = read_stream_information(
        context,
        sourceReadContext,
        &informationRead
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read audio stream information", result);
        close_media_source(&context, sourceReadContext);
        return result;
    }
    normalize_mov_apac_codec_id(context);

    bool needsMoreProbe = false;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        if (audio_stream_needs_more_probe(context->streams[index])) {
            needsMoreProbe = true;
            break;
        }
    }
    if (!needsMoreProbe) {
        *contextOut = context;
        return 0;
    }

    if (informationRead.movFamily) {
        if (informationRead.skippedProbe) {
            result = avformat_find_stream_info(context, NULL);
            publish_source_bytes(sourceReadContext);
            if (result < 0) {
                set_av_error(
                    errorBuffer,
                    errorBufferSize,
                    "Read audio stream information",
                    result
                );
                close_media_source(&context, sourceReadContext);
                return result;
            }
            normalize_mov_apac_codec_id(context);
        }
        probe_delayed_audio_parameters(context);
        publish_source_bytes(sourceReadContext);
        if (cancellation_requested(cancelled)) {
            close_media_source(&context, sourceReadContext);
            return AVERROR_EXIT;
        }
        *contextOut = context;
        return 0;
    }

    close_media_source(&context, sourceReadContext);
    context = allocate_format_context(cancelled, sourceReadContext);
    if (context == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate extended audio probe context");
        return AVERROR(ENOMEM);
    }
    context->probesize = 100LL * 1024 * 1024;
    context->max_analyze_duration = 30LL * AV_TIME_BASE;
    context->max_probe_packets = 100000;
    result = open_media_source(&context, path, sourceReadContext);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Reopen audio media source", result);
        close_media_source(&context, sourceReadContext);
        return result;
    }
    normalize_mov_apac_codec_id(context);
    result = read_stream_information(context, sourceReadContext, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read extended audio stream information", result);
        close_media_source(&context, sourceReadContext);
        return result;
    }
    normalize_mov_apac_codec_id(context);
    probe_delayed_audio_parameters(context);
    publish_source_bytes(sourceReadContext);
    if (cancellation_requested(cancelled)) {
        close_media_source(&context, sourceReadContext);
        return AVERROR_EXIT;
    }
    *contextOut = context;
    return 0;
}

static CFDataRef copy_audio_file_magic_cookie(const char *path) {
    if (!path) return NULL;
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault,
        (const UInt8 *)path,
        (CFIndex)strlen(path),
        false
    );
    if (!url) return NULL;
    AudioFileID file = NULL;
    OSStatus status = AudioFileOpenURL(url, kAudioFileReadPermission, 0, &file);
    CFRelease(url);
    if (status != noErr || !file) return NULL;

    UInt32 byteCount = 0;
    UInt32 writable = 0;
    status = AudioFileGetPropertyInfo(
        file,
        kAudioFilePropertyMagicCookieData,
        &byteCount,
        &writable
    );
    if (status != noErr || byteCount == 0) {
        AudioFileClose(file);
        return NULL;
    }
    uint8_t *bytes = malloc(byteCount);
    if (!bytes) {
        AudioFileClose(file);
        return NULL;
    }
    status = AudioFileGetProperty(
        file,
        kAudioFilePropertyMagicCookieData,
        &byteCount,
        bytes
    );
    AudioFileClose(file);
    CFDataRef result = status == noErr
        ? CFDataCreate(kCFAllocatorDefault, bytes, byteCount)
        : NULL;
    free(bytes);
    return result;
}

static char *copy_local_hls_initialization_segment_path(const char *playlistPath) {
    if (!playlistPath) return NULL;
    const char *extension = strrchr(playlistPath, '.');
    if (!extension || strcasecmp(extension, ".m3u8") != 0) return NULL;
    FILE *playlist = fopen(playlistPath, "r");
    if (!playlist) return NULL;

    char *line = NULL;
    size_t lineCapacity = 0;
    char *result = NULL;
    while (getline(&line, &lineCapacity, playlist) >= 0) {
        const char *marker = strstr(line, "#EXT-X-MAP:URI=\"");
        if (!marker) continue;
        const char *uriStart = marker + strlen("#EXT-X-MAP:URI=\"");
        const char *uriEnd = strchr(uriStart, '"');
        if (!uriEnd || uriEnd == uriStart) break;
        size_t uriLength = (size_t)(uriEnd - uriStart);
        if (uriStart[0] == '/') {
            result = strndup(uriStart, uriLength);
            break;
        }
        const char *separator = strrchr(playlistPath, '/');
        size_t directoryLength = separator
            ? (size_t)(separator - playlistPath + 1)
            : 0;
        if (directoryLength > SIZE_MAX - uriLength - 1) break;
        result = malloc(directoryLength + uriLength + 1);
        if (!result) break;
        memcpy(result, playlistPath, directoryLength);
        memcpy(result + directoryLength, uriStart, uriLength);
        result[directoryLength + uriLength] = '\0';
        break;
    }
    free(line);
    fclose(playlist);
    return result;
}

static CFDataRef copy_apac_magic_cookie(const char *path) {
    CFDataRef directCookie = copy_audio_file_magic_cookie(path);
    if (directCookie) return directCookie;
    char *initializationSegment = copy_local_hls_initialization_segment_path(path);
    if (!initializationSegment) return NULL;
    CFDataRef result = copy_audio_file_magic_cookie(initializationSegment);
    free(initializationSegment);
    return result;
}

static CMTime cm_time(int64_t value, AVRational timeBase) {
    if (value == AV_NOPTS_VALUE || timeBase.num <= 0 || timeBase.den <= 0) return kCMTimeInvalid;
    return CMTimeMake(value * (int64_t)timeBase.num, timeBase.den);
}

static int64_t stream_start_timestamp(AVFormatContext *context, AVStream *stream) {
    if (context->start_time != AV_NOPTS_VALUE) {
        return av_rescale_q(context->start_time, AV_TIME_BASE_Q, stream->time_base);
    }
    if (stream->start_time != AV_NOPTS_VALUE) return stream->start_time;
    return 0;
}

static OSType prores_codec_type(uint32_t codecTag) {
    switch (codecTag) {
        case MKTAG('a', 'p', 'c', 'o'): return kCMVideoCodecType_AppleProRes422Proxy;
        case MKTAG('a', 'p', 'c', 's'): return kCMVideoCodecType_AppleProRes422LT;
        case MKTAG('a', 'p', 'c', 'n'): return kCMVideoCodecType_AppleProRes422;
        case MKTAG('a', 'p', 'c', 'h'): return kCMVideoCodecType_AppleProRes422HQ;
        case MKTAG('a', 'p', '4', 'h'): return kCMVideoCodecType_AppleProRes4444;
        case MKTAG('a', 'p', '4', 'x'): return kCMVideoCodecType_AppleProRes4444XQ;
        default: return 0;
    }
}

/// A dual-layer source is not declared as Dolby Vision, because only its base layer
/// reaches this reader's one decoder input. Declaring it makes VideoToolbox reject a
/// base layer it would otherwise decode as HDR10, which is what the wearer is shown
/// and what the dynamic range line already says.
static bool has_usable_dovi_configuration(const AVCodecParameters *parameters) {
    const AVPacketSideData *sideData = av_packet_side_data_get(
        parameters->coded_side_data,
        parameters->nb_coded_side_data,
        AV_PKT_DATA_DOVI_CONF
    );
    if (!sideData || sideData->size < sizeof(AVDOVIDecoderConfigurationRecord)) {
        return false;
    }
    const AVDOVIDecoderConfigurationRecord *record =
        (const AVDOVIDecoderConfigurationRecord *)sideData->data;
    return record->el_present_flag == 0;
}

static OSType codec_type(const AVCodecParameters *parameters) {
    switch (parameters->codec_id) {
        case AV_CODEC_ID_H264: return kCMVideoCodecType_H264;
        case AV_CODEC_ID_HEVC:
            if ((parameters->codec_tag == MKTAG('d', 'v', 'h', '1') ||
                 parameters->codec_tag == MKTAG('d', 'v', 'h', 'e')) &&
                has_usable_dovi_configuration(parameters)) {
                return kCMVideoCodecType_DolbyVisionHEVC;
            }
            return kCMVideoCodecType_HEVC;
        case AV_CODEC_ID_AV1: return kCMVideoCodecType_AV1;
        case AV_CODEC_ID_PRORES: return prores_codec_type(parameters->codec_tag);
        default: return 0;
    }
}

static bool compressed_codec_is_renderable(OSType type) {
    return type != 0;
}

static bool add_dovi_configuration_atom(
    const AVCodecParameters *parameters,
    CFMutableDictionaryRef atoms
) {
    const AVPacketSideData *sideData = av_packet_side_data_get(
        parameters->coded_side_data,
        parameters->nb_coded_side_data,
        AV_PKT_DATA_DOVI_CONF
    );
    if (!has_usable_dovi_configuration(parameters)) return false;
    const AVDOVIDecoderConfigurationRecord *configuration =
        (const AVDOVIDecoderConfigurationRecord *)sideData->data;
    uint8_t bytes[24] = {0};
    bytes[0] = configuration->dv_version_major;
    bytes[1] = configuration->dv_version_minor;
    bytes[2] = (uint8_t)((configuration->dv_profile << 1) | (configuration->dv_level >> 5));
    bytes[3] = (uint8_t)(
        (configuration->dv_level << 3) |
        (configuration->rpu_present_flag << 2) |
        (configuration->el_present_flag << 1) |
        configuration->bl_present_flag
    );
    bytes[4] = (uint8_t)(
        (configuration->dv_bl_signal_compatibility_id << 4) |
        (configuration->dv_md_compression & 0x0f)
    );
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, sizeof(bytes));
    if (!data) return false;
    bool dolbyVisionSampleEntry =
        parameters->codec_tag == MKTAG('d', 'v', 'h', '1') ||
        parameters->codec_tag == MKTAG('d', 'v', 'h', 'e');
    CFDictionarySetValue(atoms, dolbyVisionSampleEntry ? CFSTR("dvcC") : CFSTR("dvvC"), data);
    CFRelease(data);
    return true;
}

static CFStringRef atom_name(const AVCodecParameters *parameters) {
    switch (parameters->codec_id) {
        case AV_CODEC_ID_H264: return CFSTR("avcC");
        case AV_CODEC_ID_HEVC: return CFSTR("hvcC");
        case AV_CODEC_ID_AV1: return CFSTR("av1C");
        default: return NULL;
    }
}

static CFDataRef create_av1_configuration(const AVCodecParameters *parameters) {
    if (parameters->extradata == NULL || parameters->extradata_size <= 0) return NULL;
    if ((parameters->extradata[0] & 0x80) != 0 &&
        (parameters->extradata[0] & 0x7f) == 1) {
        return CFDataCreate(
            kCFAllocatorDefault,
            parameters->extradata,
            parameters->extradata_size
        );
    }

    uint8_t profile = parameters->profile >= 0 && parameters->profile <= 7
        ? (uint8_t)parameters->profile
        : 0;
    uint8_t level = parameters->level >= 0 && parameters->level <= 31
        ? (uint8_t)parameters->level
        : 0;
    uint8_t highBitDepth = 0;
    uint8_t twelveBit = 0;
    uint8_t monochrome = 0;
    uint8_t subsamplingX = 0;
    uint8_t subsamplingY = 0;
    uint8_t chromaSamplePosition = 0;
    const AVPixFmtDescriptor *pixelFormat = av_pix_fmt_desc_get(parameters->format);
    if (pixelFormat) {
        int depth = pixelFormat->comp[0].depth;
        highBitDepth = depth > 8;
        twelveBit = depth > 10;
        monochrome = pixelFormat->nb_components == 1;
        subsamplingX = pixelFormat->log2_chroma_w > 0;
        subsamplingY = pixelFormat->log2_chroma_h > 0;
        if (subsamplingX && subsamplingY) {
            if (parameters->chroma_location == AVCHROMA_LOC_LEFT) {
                chromaSamplePosition = 1;
            } else if (parameters->chroma_location == AVCHROMA_LOC_TOPLEFT) {
                chromaSamplePosition = 2;
            }
        }
    }

    size_t size = (size_t)parameters->extradata_size + 4;
    uint8_t *bytes = malloc(size);
    if (!bytes) return NULL;
    bytes[0] = 0x81;
    bytes[1] = (uint8_t)((profile << 5) | level);
    bytes[2] = (uint8_t)(
        (highBitDepth << 6) |
        (twelveBit << 5) |
        (monochrome << 4) |
        (subsamplingX << 3) |
        (subsamplingY << 2) |
        chromaSamplePosition
    );
    bytes[3] = 0;
    memcpy(bytes + 4, parameters->extradata, parameters->extradata_size);
    CFDataRef configuration = CFDataCreate(kCFAllocatorDefault, bytes, size);
    free(bytes);
    return configuration;
}

static void write_be16(uint8_t *destination, uint16_t value);
static void write_be32(uint8_t *destination, uint32_t value);

static void write_be16(uint8_t *destination, uint16_t value) {
    destination[0] = (uint8_t)(value >> 8);
    destination[1] = (uint8_t)value;
}

static void write_be32(uint8_t *destination, uint32_t value) {
    destination[0] = (uint8_t)(value >> 24);
    destination[1] = (uint8_t)(value >> 16);
    destination[2] = (uint8_t)(value >> 8);
    destination[3] = (uint8_t)value;
}

static CFStringRef color_primaries(enum AVColorPrimaries value) {
    switch (value) {
        case AVCOL_PRI_BT709: return kCMFormatDescriptionColorPrimaries_ITU_R_709_2;
        case AVCOL_PRI_BT2020: return kCMFormatDescriptionColorPrimaries_ITU_R_2020;
        case AVCOL_PRI_SMPTE432: return kCMFormatDescriptionColorPrimaries_P3_D65;
        default: return NULL;
    }
}

/// Dolby Vision Profile 7 stores its picture across two video streams, and the
/// configuration record sits on the enhancement stream rather than on the base layer
/// that gets decoded. Scanning every video stream is therefore the only way to learn
/// that a source claims Dolby Vision at all, because reading the decoded stream alone
/// reports a plain HDR10 track and the claim disappears. What separates a Dolby Vision
/// picture from a base layer standing in for one is the enhancement layer flag, which
/// reads the same wherever the record was found.
static void detect_dolby_vision(PBFFmpegReader *reader) {
    for (unsigned index = 0; index < reader->formatContext->nb_streams; index++) {
        AVStream *candidate = reader->formatContext->streams[index];
        if (candidate->codecpar->codec_type != AVMEDIA_TYPE_VIDEO) continue;
        const AVPacketSideData *entry = av_packet_side_data_get(
            candidate->codecpar->coded_side_data,
            candidate->codecpar->nb_coded_side_data,
            AV_PKT_DATA_DOVI_CONF
        );
        if (!entry || entry->size < sizeof(AVDOVIDecoderConfigurationRecord)) continue;
        const AVDOVIDecoderConfigurationRecord *record =
            (const AVDOVIDecoderConfigurationRecord *)entry->data;
        bool onDecodedStream = (int)index == reader->videoStreamIndex;
        if (!onDecodedStream) {
            // Believed only when it describes a pure enhancement layer, because such a
            // layer cannot stand alone and so belongs to the stream being decoded. A
            // second stream carrying its own base layer is an unrelated title, and its
            // profile is not a fact about this one.
            if (record->bl_present_flag != 0) continue;
            // The decoded stream's own record outranks this one, so a record already
            // taken from anywhere is left in place until that stream is reached.
            if (reader->dolbyVisionProfile != 0) continue;
        }
        reader->dolbyVisionProfile = record->dv_profile;
        reader->dolbyVisionCrossCompatibilityID = record->dv_bl_signal_compatibility_id;
        reader->dolbyVisionHasEnhancementLayer = record->el_present_flag != 0;
        if (onDecodedStream) return;
    }
}

static CFStringRef transfer_function(enum AVColorTransferCharacteristic value) {
    switch (value) {
        case AVCOL_TRC_BT709: return kCMFormatDescriptionTransferFunction_ITU_R_709_2;
        case AVCOL_TRC_SMPTE2084: return kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ;
        case AVCOL_TRC_ARIB_STD_B67: return kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG;
        default: return NULL;
    }
}

static CFStringRef ycbcr_matrix(enum AVColorSpace value) {
    switch (value) {
        case AVCOL_SPC_BT709: return kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2;
        case AVCOL_SPC_BT2020_NCL:
        case AVCOL_SPC_BT2020_CL:
            return kCMFormatDescriptionYCbCrMatrix_ITU_R_2020;
        default: return NULL;
    }
}

static const AVPacketSideData *codec_side_data(
    const AVCodecParameters *parameters,
    enum AVPacketSideDataType type
) {
    return av_packet_side_data_get(
        parameters->coded_side_data,
        parameters->nb_coded_side_data,
        type
    );
}

static bool scaled_rational_u32(
    AVRational value,
    double scale,
    uint32_t maximum,
    uint32_t *resultOut
) {
    if (!resultOut || value.den == 0) return false;
    double scaled = av_q2d(value) * scale;
    if (!isfinite(scaled) || scaled < 0 || scaled > maximum) return false;
    *resultOut = (uint32_t)llround(scaled);
    return true;
}

static void add_static_hdr_extensions(
    const AVCodecParameters *parameters,
    CFMutableDictionaryRef extensions
) {
    const AVPacketSideData *masteringSideData = codec_side_data(
        parameters,
        AV_PKT_DATA_MASTERING_DISPLAY_METADATA
    );
    if (masteringSideData &&
        masteringSideData->size >= sizeof(AVMasteringDisplayMetadata)) {
        const AVMasteringDisplayMetadata *metadata =
            (const AVMasteringDisplayMetadata *)masteringSideData->data;
        uint32_t chromaticity[8] = {0};
        uint32_t luminance[2] = {0};
        // ISO/IEC 23008-2 serializes green, blue, red, then white point.
        const int primaryOrder[3] = {1, 2, 0};
        bool usable = metadata->has_primaries && metadata->has_luminance;
        for (int outputPrimary = 0; usable && outputPrimary < 3; outputPrimary++) {
            int sourcePrimary = primaryOrder[outputPrimary];
            usable = scaled_rational_u32(
                    metadata->display_primaries[sourcePrimary][0],
                    50000.0,
                    UINT16_MAX,
                    &chromaticity[outputPrimary * 2]
                ) && scaled_rational_u32(
                    metadata->display_primaries[sourcePrimary][1],
                    50000.0,
                    UINT16_MAX,
                    &chromaticity[outputPrimary * 2 + 1]
                );
        }
        usable = usable && scaled_rational_u32(
            metadata->white_point[0], 50000.0, UINT16_MAX, &chromaticity[6]
        );
        usable = usable && scaled_rational_u32(
            metadata->white_point[1], 50000.0, UINT16_MAX, &chromaticity[7]
        );
        usable = usable && scaled_rational_u32(
            metadata->max_luminance, 10000.0, UINT32_MAX, &luminance[0]
        );
        usable = usable && scaled_rational_u32(
            metadata->min_luminance, 10000.0, UINT32_MAX, &luminance[1]
        );
        if (usable) {
            uint8_t payload[24];
            for (int index = 0; index < 8; index++) {
                write_be16(payload + index * 2, (uint16_t)chromaticity[index]);
            }
            write_be32(payload + 16, luminance[0]);
            write_be32(payload + 20, luminance[1]);
            CFDataRef data = CFDataCreate(kCFAllocatorDefault, payload, sizeof(payload));
            if (data) {
                CFDictionarySetValue(
                    extensions,
                    kCMFormatDescriptionExtension_MasteringDisplayColorVolume,
                    data
                );
                CFRelease(data);
            }
        }
    }

    const AVPacketSideData *contentLightSideData = codec_side_data(
        parameters,
        AV_PKT_DATA_CONTENT_LIGHT_LEVEL
    );
    if (contentLightSideData &&
        contentLightSideData->size >= sizeof(AVContentLightMetadata)) {
        const AVContentLightMetadata *metadata =
            (const AVContentLightMetadata *)contentLightSideData->data;
        if (metadata->MaxCLL <= UINT16_MAX && metadata->MaxFALL <= UINT16_MAX) {
            uint8_t payload[4];
            write_be16(payload, (uint16_t)metadata->MaxCLL);
            write_be16(payload + 2, (uint16_t)metadata->MaxFALL);
            CFDataRef data = CFDataCreate(kCFAllocatorDefault, payload, sizeof(payload));
            if (data) {
                CFDictionarySetValue(
                    extensions,
                    kCMFormatDescriptionExtension_ContentLightLevelInfo,
                    data
                );
                CFRelease(data);
            }
        }
    }
}

static void add_projected_media_extensions(
    const AVCodecParameters *parameters,
    CFMutableDictionaryRef extensions
) {
    const AVPacketSideData *sphericalData = codec_side_data(
        parameters,
        AV_PKT_DATA_SPHERICAL
    );
    if (sphericalData && sphericalData->size >= sizeof(AVSphericalMapping)) {
        const AVSphericalMapping *mapping = (const AVSphericalMapping *)sphericalData->data;
        CFStringRef projection = NULL;
        uint32_t knownHorizontalFieldOfView = 0;
        switch (mapping->projection) {
            case AV_SPHERICAL_RECTILINEAR:
                projection = kCMFormatDescriptionProjectionKind_Rectilinear;
                break;
            case AV_SPHERICAL_EQUIRECTANGULAR:
                projection = kCMFormatDescriptionProjectionKind_Equirectangular;
                knownHorizontalFieldOfView = 360000;
                break;
            case AV_SPHERICAL_HALF_EQUIRECTANGULAR:
                projection = kCMFormatDescriptionProjectionKind_HalfEquirectangular;
                knownHorizontalFieldOfView = 180000;
                break;
            case AV_SPHERICAL_PARAMETRIC_IMMERSIVE:
                projection = kCMFormatDescriptionProjectionKind_ParametricImmersive;
                break;
            default:
                break;
        }
        if (projection) {
            CFDictionarySetValue(
                extensions,
                kCMFormatDescriptionExtension_ProjectionKind,
                projection
            );
        }
        if (knownHorizontalFieldOfView > 0) {
            CFNumberRef value = CFNumberCreate(
                kCFAllocatorDefault,
                kCFNumberSInt32Type,
                &knownHorizontalFieldOfView
            );
            if (value) {
                CFDictionarySetValue(
                    extensions,
                    kCMFormatDescriptionExtension_HorizontalFieldOfView,
                    value
                );
                CFRelease(value);
            }
        }
    }

    const AVPacketSideData *stereoData = codec_side_data(
        parameters,
        AV_PKT_DATA_STEREO3D
    );
    if (!stereoData || stereoData->size < sizeof(AVStereo3D)) return;
    const AVStereo3D *stereo = (const AVStereo3D *)stereoData->data;
    CFStringRef packing = NULL;
    if (stereo->type == AV_STEREO3D_SIDEBYSIDE) {
        packing = kCMFormatDescriptionViewPackingKind_SideBySide;
    } else if (stereo->type == AV_STEREO3D_TOPBOTTOM) {
        packing = kCMFormatDescriptionViewPackingKind_OverUnder;
    }
    if (packing) {
        CFDictionarySetValue(
            extensions,
            kCMFormatDescriptionExtension_ViewPackingKind,
            packing
        );
    }
    if (stereo->baseline > 0) {
        uint32_t baseline = stereo->baseline;
        CFNumberRef value = CFNumberCreate(
            kCFAllocatorDefault,
            kCFNumberSInt32Type,
            &baseline
        );
        if (value) {
            CFDictionarySetValue(
                extensions,
                kCMFormatDescriptionExtension_StereoCameraBaseline,
                value
            );
            CFRelease(value);
        }
    }
    double fieldOfView = av_q2d(stereo->horizontal_field_of_view);
    if (isfinite(fieldOfView) && fieldOfView > 0 && fieldOfView <= UINT32_MAX / 1000.0) {
        uint32_t millidegrees = (uint32_t)llround(fieldOfView * 1000.0);
        CFNumberRef value = CFNumberCreate(
            kCFAllocatorDefault,
            kCFNumberSInt32Type,
            &millidegrees
        );
        if (value) {
            CFDictionarySetValue(
                extensions,
                kCMFormatDescriptionExtension_HorizontalFieldOfView,
                value
            );
            CFRelease(value);
        }
    }
}

static void add_pixel_aspect_ratio_extension(
    AVRational sampleAspectRatio,
    CFMutableDictionaryRef extensions
) {
    if (sampleAspectRatio.num <= 0 || sampleAspectRatio.den <= 0 ||
        sampleAspectRatio.num == sampleAspectRatio.den) {
        return;
    }
    int32_t horizontalSpacing = sampleAspectRatio.num;
    int32_t verticalSpacing = sampleAspectRatio.den;
    CFNumberRef horizontal = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt32Type,
        &horizontalSpacing
    );
    CFNumberRef vertical = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt32Type,
        &verticalSpacing
    );
    CFMutableDictionaryRef pixelAspectRatio = CFDictionaryCreateMutable(
        kCFAllocatorDefault,
        0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    if (horizontal && vertical && pixelAspectRatio) {
        CFDictionarySetValue(
            pixelAspectRatio,
            kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing,
            horizontal
        );
        CFDictionarySetValue(
            pixelAspectRatio,
            kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing,
            vertical
        );
        CFDictionarySetValue(
            extensions,
            kCMFormatDescriptionExtension_PixelAspectRatio,
            pixelAspectRatio
        );
    }
    if (pixelAspectRatio) CFRelease(pixelAspectRatio);
    if (vertical) CFRelease(vertical);
    if (horizontal) CFRelease(horizontal);
}

static OSStatus create_format_by_adding_pixel_aspect_ratio(
    CMVideoFormatDescriptionRef source,
    CFDictionaryRef additions,
    CMVideoFormatDescriptionRef *formatOut
) {
    CFTypeRef pixelAspectRatio = additions
        ? CFDictionaryGetValue(
            additions,
            kCMFormatDescriptionExtension_PixelAspectRatio
        )
        : NULL;
    if (!pixelAspectRatio) {
        CFRetain(source);
        *formatOut = source;
        return noErr;
    }
    CFDictionaryRef sourceExtensions = CMFormatDescriptionGetExtensions(source);
    CFMutableDictionaryRef merged = sourceExtensions
        ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, sourceExtensions)
        : CFDictionaryCreateMutable(
            kCFAllocatorDefault,
            0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        );
    if (!merged) return kCMFormatDescriptionError_AllocationFailed;
    CFDictionarySetValue(
        merged,
        kCMFormatDescriptionExtension_PixelAspectRatio,
        pixelAspectRatio
    );
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(source);
    OSStatus status = CMVideoFormatDescriptionCreate(
        kCFAllocatorDefault,
        CMFormatDescriptionGetMediaSubType(source),
        dimensions.width,
        dimensions.height,
        merged,
        formatOut
    );
    CFRelease(merged);
    return status;
}

static const uint8_t *find_start_code(const uint8_t *position, const uint8_t *end, size_t *length) {
    for (const uint8_t *cursor = position; cursor + 3 <= end; cursor++) {
        if (cursor[0] != 0 || cursor[1] != 0) continue;
        if (cursor[2] == 1) { *length = 3; return cursor; }
        if (cursor + 4 <= end && cursor[2] == 0 && cursor[3] == 1) {
            *length = 4;
            return cursor;
        }
    }
    return NULL;
}

static int buffer_bootstrap_packet(PBFFmpegReader *reader, const AVPacket *packet) {
    if (reader->bootstrapPacketCount >= 512 ||
        reader->bootstrapPacketBytes > 64 * 1024 * 1024 ||
        (size_t)packet->size > 64 * 1024 * 1024 - reader->bootstrapPacketBytes) {
        return AVERROR(ENOBUFS);
    }
    AVPacket *copy = av_packet_clone(packet);
    if (!copy) return AVERROR(ENOMEM);
    AVPacket **packets = realloc(
        reader->bootstrapPackets,
        (reader->bootstrapPacketCount + 1) * sizeof(*packets)
    );
    if (!packets) {
        av_packet_free(&copy);
        return AVERROR(ENOMEM);
    }
    reader->bootstrapPackets = packets;
    reader->bootstrapPackets[reader->bootstrapPacketCount++] = copy;
    reader->bootstrapPacketBytes += (size_t)packet->size;
    return 0;
}

static void discard_bootstrap_packets(PBFFmpegReader *reader) {
    if (!reader) return;
    for (size_t index = 0; index < reader->bootstrapPacketCount; index++) {
        av_packet_free(&reader->bootstrapPackets[index]);
    }
    free(reader->bootstrapPackets);
    reader->bootstrapPackets = NULL;
    reader->bootstrapPacketCount = 0;
    reader->bootstrapPacketIndex = 0;
    reader->bootstrapPacketBytes = 0;
}

static bool packet_starts_with_annexb(const AVPacket *packet) {
    if (!packet || packet->size < 4) return false;
    size_t startLength = 0;
    return find_start_code(
        packet->data,
        packet->data + packet->size,
        &startLength
    ) == packet->data;
}

static int install_bootstrap_extradata(
    AVCodecParameters *parameters,
    const uint8_t *bytes,
    size_t size
) {
    if (!bytes || size == 0 || size > INT_MAX) return AVERROR_INVALIDDATA;
    uint8_t *copy = av_mallocz(size + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!copy) return AVERROR(ENOMEM);
    memcpy(copy, bytes, size);
    av_freep(&parameters->extradata);
    parameters->extradata = copy;
    parameters->extradata_size = (int)size;
    return 0;
}

static bool video_codec_configuration_is_usable(const AVCodecParameters *parameters) {
    if (!parameters || !parameters->extradata || parameters->extradata_size <= 0) {
        return false;
    }
    const uint8_t *configuration = parameters->extradata;
    size_t size = (size_t)parameters->extradata_size;
    switch (parameters->codec_id) {
        case AV_CODEC_ID_HEVC:
            if (configuration[0] != 1) return true;
            return size >= 23 && configuration[22] != 0;
        case AV_CODEC_ID_H264:
            if (configuration[0] != 1) return true;
            return size >= 6 && (configuration[5] & 0x1f) != 0;
        case AV_CODEC_ID_AV1:
            if ((configuration[0] & 0x80) == 0) return true;
            return size >= 4 && (configuration[0] & 0x7f) == 1;
        default:
            return true;
    }
}

static bool context_uses_mov_demuxer(const AVFormatContext *context) {
    return context && context->iformat && context->iformat->name &&
        strcmp(context->iformat->name, "mov,mp4,m4a,3gp,3g2,mj2") == 0;
}

static bool mov_av1_configuration_is_complete(const AVCodecParameters *parameters) {
    return parameters && parameters->extradata && parameters->extradata_size >= 4 &&
        (parameters->extradata[0] & 0x80) != 0 &&
        (parameters->extradata[0] & 0x7f) == 1;
}

static bool mov_stream_table_is_qualified(const AVFormatContext *context) {
    bool hasVideo = false;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        const AVCodecParameters *parameters = context->streams[index]->codecpar;
        if (parameters->codec_type != AVMEDIA_TYPE_VIDEO) continue;
        hasVideo = true;
        if (parameters->codec_id == AV_CODEC_ID_NONE ||
            parameters->width <= 0 || parameters->height <= 0) {
            return false;
        }
        switch (parameters->codec_id) {
            case AV_CODEC_ID_H264:
            case AV_CODEC_ID_HEVC:
                if (!video_codec_configuration_is_usable(parameters)) return false;
                break;
            case AV_CODEC_ID_AV1:
                if (!mov_av1_configuration_is_complete(parameters)) return false;
                break;
            default:
                break;
        }
    }
    return hasVideo;
}

static void fill_video_color_from_codec_configuration(AVFormatContext *context) {
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVCodecParameters *parameters = context->streams[index]->codecpar;
        if (parameters->codec_type != AVMEDIA_TYPE_VIDEO ||
            !parameters->extradata || parameters->extradata_size <= 0) continue;
        if (parameters->color_primaries != AVCOL_PRI_UNSPECIFIED &&
            parameters->color_trc != AVCOL_TRC_UNSPECIFIED &&
            parameters->color_space != AVCOL_SPC_UNSPECIFIED &&
            parameters->color_range != AVCOL_RANGE_UNSPECIFIED) continue;
        const AVCodec *decoder = avcodec_find_decoder(parameters->codec_id);
        AVCodecContext *codecContext = decoder
            ? avcodec_alloc_context3(decoder)
            : NULL;
        if (!codecContext) continue;
        int result = avcodec_parameters_to_context(codecContext, parameters);
        if (result >= 0) result = avcodec_open2(codecContext, decoder, NULL);
        if (result >= 0) {
            if (parameters->color_primaries == AVCOL_PRI_UNSPECIFIED) {
                parameters->color_primaries = codecContext->color_primaries;
            }
            if (parameters->color_trc == AVCOL_TRC_UNSPECIFIED) {
                parameters->color_trc = codecContext->color_trc;
            }
            if (parameters->color_space == AVCOL_SPC_UNSPECIFIED) {
                parameters->color_space = codecContext->colorspace;
            }
            if (parameters->color_range == AVCOL_RANGE_UNSPECIFIED) {
                parameters->color_range = codecContext->color_range;
            }
        }
        avcodec_free_context(&codecContext);
    }
}

static int read_stream_information(
    AVFormatContext *context,
    PBFFmpegSourceReadContext *sourceReadContext,
    PBStreamInformationRead *readOut
) {
    PBStreamInformationRead read = {
        .movFamily = context_uses_mov_demuxer(context),
        .skippedProbe = false,
    };
    if (read.movFamily && mov_stream_table_is_qualified(context)) {
        fill_video_color_from_codec_configuration(context);
        read.skippedProbe = true;
        if (readOut) *readOut = read;
        return 0;
    }
    int result = avformat_find_stream_info(context, NULL);
    publish_source_bytes(sourceReadContext);
    if (readOut) *readOut = read;
    return result;
}

typedef struct PBParameterSet {
    uint8_t *bytes;
    size_t size;
} PBParameterSet;

static int video_parameter_set_slot(enum AVCodecID codecID, const uint8_t *nal, size_t size) {
    if (!nal || size == 0) return -1;
    if (codecID == AV_CODEC_ID_HEVC) {
        int type = (nal[0] >> 1) & 0x3f;
        return type >= 32 && type <= 34 ? type - 32 : -1;
    }
    if (codecID == AV_CODEC_ID_H264) {
        int type = nal[0] & 0x1f;
        if (type == 7) return 0;
        if (type == 8) return 1;
    }
    return -1;
}

static int store_video_parameter_set(
    enum AVCodecID codecID,
    const uint8_t *nal,
    size_t size,
    PBParameterSet sets[3]
) {
    int slot = video_parameter_set_slot(codecID, nal, size);
    if (slot < 0 || sets[slot].bytes) return 0;
    sets[slot].bytes = av_memdup(nal, size);
    if (!sets[slot].bytes) return AVERROR(ENOMEM);
    sets[slot].size = size;
    return 0;
}

static int collect_annexb_parameter_sets(
    enum AVCodecID codecID,
    const AVPacket *packet,
    PBParameterSet sets[3]
) {
    const uint8_t *cursor = packet->data;
    const uint8_t *end = cursor + packet->size;
    while (cursor < end) {
        size_t startLength = 0;
        const uint8_t *start = find_start_code(cursor, end, &startLength);
        if (!start) break;
        const uint8_t *nal = start + startLength;
        size_t nextLength = 0;
        const uint8_t *next = find_start_code(nal, end, &nextLength);
        const uint8_t *nalEnd = next ?: end;
        while (nalEnd > nal && nalEnd[-1] == 0) nalEnd--;
        int result = store_video_parameter_set(
            codecID, nal, (size_t)(nalEnd - nal), sets
        );
        if (result < 0) return result;
        cursor = next ?: end;
    }
    return 0;
}

static bool collect_length_prefixed_parameter_sets(
    enum AVCodecID codecID,
    const AVPacket *packet,
    size_t lengthSize,
    PBParameterSet sets[3],
    int *errorOut
) {
    size_t offset = 0;
    bool parsedNAL = false;
    while (offset + lengthSize <= (size_t)packet->size) {
        uint32_t nalSize = 0;
        for (size_t index = 0; index < lengthSize; index++) {
            nalSize = (nalSize << 8) | packet->data[offset + index];
        }
        offset += lengthSize;
        if (nalSize == 0 || nalSize > (size_t)packet->size - offset) return false;
        offset += nalSize;
        parsedNAL = true;
    }
    if (!parsedNAL || offset != (size_t)packet->size) return false;

    offset = 0;
    while (offset + lengthSize <= (size_t)packet->size) {
        uint32_t nalSize = 0;
        for (size_t index = 0; index < lengthSize; index++) {
            nalSize = (nalSize << 8) | packet->data[offset + index];
        }
        offset += lengthSize;
        if (nalSize == 0 || nalSize > (size_t)packet->size - offset) return false;
        int result = store_video_parameter_set(
            codecID, packet->data + offset, nalSize, sets
        );
        if (result < 0) {
            *errorOut = result;
            return false;
        }
        offset += nalSize;
    }
    return true;
}

static int collect_video_parameter_sets(
    enum AVCodecID codecID,
    const AVPacket *packet,
    PBParameterSet sets[3],
    size_t *nalUnitHeaderLengthOut
) {
    if (packet_starts_with_annexb(packet)) {
        if (nalUnitHeaderLengthOut) *nalUnitHeaderLengthOut = 4;
        return collect_annexb_parameter_sets(codecID, packet, sets);
    }
    for (size_t lengthSize = 4; lengthSize >= 1; lengthSize--) {
        int result = 0;
        if (collect_length_prefixed_parameter_sets(
                codecID, packet, lengthSize, sets, &result
            )) {
            if (nalUnitHeaderLengthOut) *nalUnitHeaderLengthOut = lengthSize;
            return 0;
        }
        if (result < 0) return result;
    }
    return 0;
}

static bool video_parameter_sets_complete(
    enum AVCodecID codecID,
    const PBParameterSet sets[3]
) {
    size_t required = codecID == AV_CODEC_ID_HEVC ? 3 : 2;
    for (size_t index = 0; index < required; index++) {
        if (!sets[index].bytes || sets[index].size == 0) return false;
    }
    return true;
}

static int install_parameter_set_configuration(
    AVCodecParameters *parameters,
    PBParameterSet sets[3],
    size_t nalUnitHeaderLength
) {
    size_t required = parameters->codec_id == AV_CODEC_ID_HEVC ? 3 : 2;
    for (size_t index = 0; index < required; index++) {
        if (!sets[index].bytes || sets[index].size == 0) return AVERROR_INVALIDDATA;
    }
    if (nalUnitHeaderLength < 1 || nalUnitHeaderLength > 4) {
        return AVERROR_INVALIDDATA;
    }

    const uint8_t *parameterSetBytes[3] = {0};
    size_t parameterSetSizes[3] = {0};
    for (size_t index = 0; index < required; index++) {
        parameterSetBytes[index] = sets[index].bytes;
        parameterSetSizes[index] = sets[index].size;
    }

    CMVideoFormatDescriptionRef format = NULL;
    OSStatus status = parameters->codec_id == AV_CODEC_ID_HEVC
        ? CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            kCFAllocatorDefault,
            required,
            parameterSetBytes,
            parameterSetSizes,
            (int)nalUnitHeaderLength,
            NULL,
            &format
        )
        : CMVideoFormatDescriptionCreateFromH264ParameterSets(
            kCFAllocatorDefault,
            required,
            parameterSetBytes,
            parameterSetSizes,
            (int)nalUnitHeaderLength,
            &format
        );
    if (status != noErr || !format) {
        if (format) CFRelease(format);
        return AVERROR_INVALIDDATA;
    }

    CFDictionaryRef atoms = CMFormatDescriptionGetExtension(
        format,
        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
    );
    CFStringRef atom = atom_name(parameters);
    CFDataRef configuration = atoms && atom
        ? (CFDataRef)CFDictionaryGetValue(atoms, atom)
        : NULL;
    int result = configuration && CFGetTypeID(configuration) == CFDataGetTypeID()
        ? install_bootstrap_extradata(
            parameters,
            CFDataGetBytePtr(configuration),
            (size_t)CFDataGetLength(configuration)
        )
        : AVERROR_INVALIDDATA;
    CFRelease(format);
    return result;
}

static void free_video_parameter_sets(PBParameterSet sets[3]) {
    for (size_t index = 0; index < 3; index++) av_freep(&sets[index].bytes);
}

static int bootstrap_video_extradata(
    PBFFmpegReader *reader,
    AVStream *stream,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (stream->codecpar->codec_id == AV_CODEC_ID_PRORES) return 0;
    if (!reader->forceBitstreamExtradataBootstrap &&
        video_codec_configuration_is_usable(stream->codecpar)) {
        return 0;
    }
    enum AVCodecID codecID = stream->codecpar->codec_id;
    if (codecID != AV_CODEC_ID_H264 &&
        codecID != AV_CODEC_ID_HEVC &&
        codecID != AV_CODEC_ID_AV1) {
        char message[192];
        snprintf(
            message,
            sizeof(message),
            "Compressed video codec configuration is missing from the container (codec=%s tag=%s extradata=%d)",
            avcodec_get_name(codecID),
            reader->codecTag[0] ? reader->codecTag : "unknown",
            stream->codecpar->extradata_size
        );
        set_error(errorBuffer, errorBufferSize, message);
        return AVERROR_INVALIDDATA;
    }
    av_freep(&stream->codecpar->extradata);
    stream->codecpar->extradata_size = 0;
    const AVBitStreamFilter *filter = av_bsf_get_by_name("extract_extradata");
    if (!filter) {
        set_error(errorBuffer, errorBufferSize, "FFmpeg extract_extradata filter is unavailable");
        return AVERROR(ENOSYS);
    }
    AVBSFContext *context = NULL;
    int result = av_bsf_alloc(filter, &context);
    if (result >= 0) result = avcodec_parameters_copy(context->par_in, stream->codecpar);
    if (result >= 0) {
        context->time_base_in = stream->time_base;
        result = av_bsf_init(context);
    }
    AVPacket *input = av_packet_alloc();
    AVPacket *output = av_packet_alloc();
    PBParameterSet parameterSets[3] = {0};
    size_t parameterSetNALUnitHeaderLength = 0;
    if (result < 0 || !input || !output) {
        if (result >= 0) result = AVERROR(ENOMEM);
        set_av_error(errorBuffer, errorBufferSize, "Initialize video extradata bootstrap", result);
        av_packet_free(&input);
        av_packet_free(&output);
        av_bsf_free(&context);
        return result;
    }

    while (reader->bootstrapPacketCount < 512 &&
           reader->bootstrapPacketBytes <= 64 * 1024 * 1024) {
        if (cancellation_requested(&reader->cancelled)) {
            result = AVERROR_EXIT;
            break;
        }
        result = av_read_frame(reader->formatContext, input);
        publish_source_bytes(&reader->sourceReadContext);
        if (result < 0) break;
        if (input->stream_index != reader->videoStreamIndex) {
            av_packet_unref(input);
            continue;
        }
        if (reader->bootstrapPacketCount == 0) {
            reader->bootstrapPacketsAreAnnexB = packet_starts_with_annexb(input);
        }
        result = buffer_bootstrap_packet(reader, input);
        if (result < 0) {
            av_packet_unref(input);
            break;
        }

        if (codecID == AV_CODEC_ID_H264 || codecID == AV_CODEC_ID_HEVC) {
            result = collect_video_parameter_sets(
                codecID,
                input,
                parameterSets,
                &parameterSetNALUnitHeaderLength
            );
            if (result >= 0 && video_parameter_sets_complete(codecID, parameterSets)) {
                result = install_parameter_set_configuration(
                    stream->codecpar,
                    parameterSets,
                    parameterSetNALUnitHeaderLength
                );
            }
            if (result < 0 || stream->codecpar->extradata_size > 0) {
                av_packet_unref(input);
                break;
            }
            av_packet_unref(input);
            result = 0;
            continue;
        }

        AVPacket *filterInput = av_packet_clone(input);
        av_packet_unref(input);
        if (!filterInput) {
            result = AVERROR(ENOMEM);
            break;
        }
        result = av_bsf_send_packet(context, filterInput);
        av_packet_free(&filterInput);
        if (result < 0) break;

        while ((result = av_bsf_receive_packet(context, output)) >= 0) {
            size_t sideDataSize = 0;
            const uint8_t *sideData = av_packet_get_side_data(
                output,
                AV_PKT_DATA_NEW_EXTRADATA,
                &sideDataSize
            );
            if (sideData && sideDataSize > 0) {
                result = install_bootstrap_extradata(
                    stream->codecpar,
                    sideData,
                    sideDataSize
                );
            } else if (context->par_out->extradata && context->par_out->extradata_size > 0) {
                result = install_bootstrap_extradata(
                    stream->codecpar,
                    context->par_out->extradata,
                    (size_t)context->par_out->extradata_size
                );
            }
            av_packet_unref(output);
            if (stream->codecpar->extradata && stream->codecpar->extradata_size > 0) {
                result = 0;
                break;
            }
        }
        if (stream->codecpar->extradata && stream->codecpar->extradata_size > 0) {
            result = 0;
            break;
        }
        if (result == AVERROR(EAGAIN)) result = 0;
        if (result < 0) break;
    }

    av_packet_free(&input);
    av_packet_free(&output);
    av_bsf_free(&context);
    free_video_parameter_sets(parameterSets);
    if (!stream->codecpar->extradata || stream->codecpar->extradata_size <= 0) {
        if (result == AVERROR_EOF || result >= 0) result = AVERROR_INVALIDDATA;
        set_av_error(errorBuffer, errorBufferSize, "Bootstrap video codec configuration from bitstream", result);
        return result;
    }
    return 0;
}

static OSStatus create_annexb_format(
    const AVCodecParameters *parameters,
    CFDictionaryRef extensions,
    CMVideoFormatDescriptionRef *formatOut
) {
    const uint8_t *sets[3] = {0};
    size_t sizes[3] = {0};
    size_t required = parameters->codec_id == AV_CODEC_ID_HEVC ? 3 : 2;
    const uint8_t *cursor = parameters->extradata;
    const uint8_t *end = cursor + parameters->extradata_size;
    while (cursor < end) {
        size_t startLength = 0;
        const uint8_t *start = find_start_code(cursor, end, &startLength);
        if (!start) break;
        const uint8_t *nal = start + startLength;
        size_t nextLength = 0;
        const uint8_t *next = find_start_code(nal, end, &nextLength);
        const uint8_t *nalEnd = next ?: end;
        while (nalEnd > nal && nalEnd[-1] == 0) nalEnd--;
        if (nal < nalEnd) {
            int slot = -1;
            if (parameters->codec_id == AV_CODEC_ID_HEVC) {
                int type = (nal[0] >> 1) & 0x3f;
                if (type >= 32 && type <= 34) slot = type - 32;
            } else {
                int type = nal[0] & 0x1f;
                if (type == 7) slot = 0;
                if (type == 8) slot = 1;
            }
            if (slot >= 0 && sets[slot] == NULL) {
                sets[slot] = nal;
                sizes[slot] = (size_t)(nalEnd - nal);
            }
        }
        cursor = next ?: end;
    }
    for (size_t index = 0; index < required; index++) {
        if (!sets[index] || sizes[index] == 0) return kCMFormatDescriptionError_InvalidParameter;
    }
    if (parameters->codec_id == AV_CODEC_ID_HEVC) {
        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            kCFAllocatorDefault, required, sets, sizes, 4, extensions, formatOut
        );
    }
    CMVideoFormatDescriptionRef baseFormat = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
        kCFAllocatorDefault, required, sets, sizes, 4, &baseFormat
    );
    if (status != noErr || !baseFormat) return status;
    status = create_format_by_adding_pixel_aspect_ratio(
        baseFormat,
        extensions,
        formatOut
    );
    CFRelease(baseFormat);
    return status;
}

static OSStatus create_dolby_vision_format(
    const AVCodecParameters *parameters,
    CFDictionaryRef atoms,
    CMVideoFormatDescriptionRef *formatOut
) {
    CFDataRef hvcC = (CFDataRef)CFDictionaryGetValue(atoms, CFSTR("hvcC"));
    CFDataRef dvcC = (CFDataRef)CFDictionaryGetValue(atoms, CFSTR("dvcC"));
    if (!hvcC || CFGetTypeID(hvcC) != CFDataGetTypeID() ||
        !dvcC || CFGetTypeID(dvcC) != CFDataGetTypeID()) {
        return kCMFormatDescriptionError_InvalidParameter;
    }
    size_t hvcCSize = (size_t)CFDataGetLength(hvcC);
    size_t dvcCSize = (size_t)CFDataGetLength(dvcC);
    if (hvcCSize > UINT32_MAX - 8 || dvcCSize > UINT32_MAX - 8 ||
        hvcCSize > SIZE_MAX - 102 - dvcCSize) {
        return kCMFormatDescriptionError_InvalidParameter;
    }

    size_t descriptionSize = 86 + 8 + hvcCSize + 8 + dvcCSize;
    uint8_t *description = calloc(1, descriptionSize);
    if (!description) return kCMFormatDescriptionError_AllocationFailed;
    write_be32(description, (uint32_t)descriptionSize);
    memcpy(description + 4, "dvh1", 4);
    write_be16(description + 14, 1);
    write_be16(description + 32, (uint16_t)parameters->width);
    write_be16(description + 34, (uint16_t)parameters->height);
    write_be32(description + 36, 72 << 16);
    write_be32(description + 40, 72 << 16);
    write_be16(description + 48, 1);
    description[50] = 11;
    memcpy(description + 51, "DOVI Coding", 11);
    write_be16(description + 82, 24);
    write_be16(description + 84, UINT16_MAX);

    size_t atomOffset = 86;
    write_be32(description + atomOffset, (uint32_t)(8 + hvcCSize));
    memcpy(description + atomOffset + 4, "hvcC", 4);
    memcpy(description + atomOffset + 8, CFDataGetBytePtr(hvcC), hvcCSize);
    atomOffset += 8 + hvcCSize;
    write_be32(description + atomOffset, (uint32_t)(8 + dvcCSize));
    memcpy(description + atomOffset + 4, "dvcC", 4);
    memcpy(description + atomOffset + 8, CFDataGetBytePtr(dvcC), dvcCSize);

    OSStatus status = CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData(
        kCFAllocatorDefault,
        description,
        descriptionSize,
        CFStringGetSystemEncoding(),
        NULL,
        formatOut
    );
    free(description);
    return status;
}

static OSStatus create_compressed_format(
    const AVCodecParameters *parameters,
    AVRational sampleAspectRatio,
    CMVideoFormatDescriptionRef *formatOut,
    bool *convertsAnnexBOut
) {
    OSType type = codec_type(parameters);
    CFStringRef atom = atom_name(parameters);
    bool isProRes = parameters->codec_id == AV_CODEC_ID_PRORES;
    if (type == 0 ||
        (!isProRes &&
         (atom == NULL || parameters->extradata == NULL || parameters->extradata_size <= 0))) {
        return kCMFormatDescriptionError_InvalidParameter;
    }

    CFMutableDictionaryRef extensions = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
    );
    CFMutableDictionaryRef atoms = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
    );
    if (!extensions || !atoms) {
        if (extensions) CFRelease(extensions);
        if (atoms) CFRelease(atoms);
        return kCMFormatDescriptionError_AllocationFailed;
    }

    CFStringRef primaries = color_primaries(parameters->color_primaries);
    CFStringRef transfer = transfer_function(parameters->color_trc);
    CFStringRef matrix = ycbcr_matrix(parameters->color_space);
    if (primaries) CFDictionarySetValue(extensions, kCMFormatDescriptionExtension_ColorPrimaries, primaries);
    if (transfer) CFDictionarySetValue(extensions, kCMFormatDescriptionExtension_TransferFunction, transfer);
    if (matrix) CFDictionarySetValue(extensions, kCMFormatDescriptionExtension_YCbCrMatrix, matrix);
    if (parameters->color_range == AVCOL_RANGE_JPEG) {
        CFDictionarySetValue(extensions, kCMFormatDescriptionExtension_FullRangeVideo, kCFBooleanTrue);
    } else if (parameters->color_range == AVCOL_RANGE_MPEG) {
        CFDictionarySetValue(extensions, kCMFormatDescriptionExtension_FullRangeVideo, kCFBooleanFalse);
    }
    add_static_hdr_extensions(parameters, extensions);
    add_projected_media_extensions(parameters, extensions);
    add_pixel_aspect_ratio_extension(sampleAspectRatio, extensions);
    add_dovi_configuration_atom(parameters, atoms);

    bool annexB = (parameters->codec_id == AV_CODEC_ID_HEVC || parameters->codec_id == AV_CODEC_ID_H264)
        && parameters->extradata[0] != 1;
    OSStatus status;
    if (isProRes) {
        status = CMVideoFormatDescriptionCreate(
            kCFAllocatorDefault,
            type,
            parameters->width,
            parameters->height,
            extensions,
            formatOut
        );
    } else if (annexB) {
        if (CFDictionaryGetCount(atoms) > 0) {
            CFDictionarySetValue(
                extensions,
                kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms,
                atoms
            );
        }
        status = create_annexb_format(parameters, extensions, formatOut);
    } else {
        CFDataRef configuration = parameters->codec_id == AV_CODEC_ID_AV1
            ? create_av1_configuration(parameters)
            : CFDataCreate(
                kCFAllocatorDefault, parameters->extradata, parameters->extradata_size
            );
        if (!configuration) {
            CFRelease(atoms);
            CFRelease(extensions);
            return kCMFormatDescriptionError_AllocationFailed;
        }
        CFDictionarySetValue(atoms, atom, configuration);
        CFDictionarySetValue(extensions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms, atoms);
        if (type == kCMVideoCodecType_DolbyVisionHEVC) {
            CMVideoFormatDescriptionRef baseFormat = NULL;
            status = create_dolby_vision_format(parameters, atoms, &baseFormat);
            if (status == noErr && baseFormat) {
                status = create_format_by_adding_pixel_aspect_ratio(
                    baseFormat,
                    extensions,
                    formatOut
                );
                CFRelease(baseFormat);
            }
        } else {
            status = CMVideoFormatDescriptionCreate(
                kCFAllocatorDefault,
                type,
                parameters->width,
                parameters->height,
                extensions,
                formatOut
            );
        }
        CFRelease(configuration);
    }
    if (convertsAnnexBOut) *convertsAnnexBOut = annexB;
    CFRelease(atoms);
    CFRelease(extensions);
    return status;
}

PBFFmpegReader *PBFFmpegReaderAllocate(void) {
    PBFFmpegReader *reader = calloc(1, sizeof(PBFFmpegReader));
    if (reader) atomic_init(&reader->cancelled, false);
    return reader;
}

void PBFFmpegReaderSetSourceReadMonitor(
    PBFFmpegReader *reader,
    PBFFmpegSourceReadMonitor *monitor
) {
    if (reader) reader->sourceReadContext.monitor = monitor;
}

static void normalize_mov_dolby_vision_av1_codec_id(AVFormatContext *context) {
    if (!context) return;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVCodecParameters *parameters = context->streams[index]->codecpar;
        if (parameters->codec_type == AVMEDIA_TYPE_VIDEO &&
            parameters->codec_id == AV_CODEC_ID_NONE &&
            parameters->codec_tag == MKTAG('d', 'a', 'v', '1')) {
            // FFmpeg 8.0.1 preserves the dav1 sample entry, av1C extradata, and
            // Dolby Vision configuration but does not classify the track as AV1.
            // Normalize only that incomplete MOV result before stream probing.
            parameters->codec_id = AV_CODEC_ID_AV1;
        }
    }
}

static PBFFmpegMediaStreamCategory media_stream_category(enum AVMediaType type) {
    switch (type) {
        case AVMEDIA_TYPE_VIDEO: return PBFFmpegMediaStreamCategoryVideo;
        case AVMEDIA_TYPE_AUDIO: return PBFFmpegMediaStreamCategoryAudio;
        case AVMEDIA_TYPE_SUBTITLE: return PBFFmpegMediaStreamCategorySubtitle;
        default: return PBFFmpegMediaStreamCategoryOther;
    }
}

static const char *media_stream_projection_kind(const AVCodecParameters *parameters) {
    const AVPacketSideData *data = codec_side_data(
        parameters,
        AV_PKT_DATA_SPHERICAL
    );
    if (!data || data->size < sizeof(AVSphericalMapping)) return "unknown";
    const AVSphericalMapping *mapping = (const AVSphericalMapping *)data->data;
    switch (mapping->projection) {
        case AV_SPHERICAL_RECTILINEAR: return "rectilinear";
        case AV_SPHERICAL_EQUIRECTANGULAR: return "equirectangular";
        case AV_SPHERICAL_HALF_EQUIRECTANGULAR: return "half-equirectangular";
        case AV_SPHERICAL_PARAMETRIC_IMMERSIVE: return "parametric-immersive";
        default: return "unknown";
    }
}

static double media_source_duration_seconds(const AVFormatContext *context) {
    int videoIndex = av_find_best_stream(
        (AVFormatContext *)context,
        AVMEDIA_TYPE_VIDEO,
        -1,
        -1,
        NULL,
        0
    );
    if (videoIndex >= 0) {
        const AVStream *stream = context->streams[videoIndex];
        if (stream->duration != AV_NOPTS_VALUE && stream->duration > 0) {
            return stream->duration * av_q2d(stream->time_base);
        }
    }
    return context->duration > 0
        ? (double)context->duration / AV_TIME_BASE
        : 0;
}

static void copy_media_information_text(
    char *buffer,
    size_t bufferSize,
    const char *value
) {
    if (!buffer || bufferSize == 0) return;
    snprintf(buffer, bufferSize, "%s", value ? value : "");
}

static void fill_media_stream_storage(
    PBFFmpegMediaStreamStorage *storage,
    const AVStream *stream
) {
    const AVCodecParameters *parameters = stream->codecpar;
    storage->info.streamIndex = stream->index;
    storage->info.category = media_stream_category(parameters->codec_type);
    storage->info.codecID = parameters->codec_id;
    storage->info.codecTag = parameters->codec_tag;
    storage->info.disposition = stream->disposition;
    storage->info.width = parameters->width;
    storage->info.height = parameters->height;
    storage->info.nominalFrameRate = av_q2d(stream->avg_frame_rate);
    if (!isfinite(storage->info.nominalFrameRate) ||
        storage->info.nominalFrameRate <= 0) {
        storage->info.nominalFrameRate = av_q2d(stream->r_frame_rate);
    }
    if (!isfinite(storage->info.nominalFrameRate) ||
        storage->info.nominalFrameRate <= 0) {
        storage->info.nominalFrameRate = 0;
    }
    storage->info.sampleRate = parameters->sample_rate;
    storage->info.channelCount = parameters->ch_layout.nb_channels;

    const AVCodecDescriptor *descriptor = avcodec_descriptor_get(parameters->codec_id);
    copy_media_information_text(
        storage->codecName,
        sizeof(storage->codecName),
        descriptor ? descriptor->name : "unknown"
    );
    const AVDictionaryEntry *language = av_dict_get(
        stream->metadata,
        "language",
        NULL,
        0
    );
    const AVDictionaryEntry *title = av_dict_get(
        stream->metadata,
        "title",
        NULL,
        0
    );
    copy_media_information_text(
        storage->language,
        sizeof(storage->language),
        language ? language->value : ""
    );
    copy_media_information_text(
        storage->title,
        sizeof(storage->title),
        title ? title->value : ""
    );
    copy_media_information_text(
        storage->colorPrimaries,
        sizeof(storage->colorPrimaries),
        av_color_primaries_name(parameters->color_primaries) ?: "unknown"
    );
    copy_media_information_text(
        storage->transferFunction,
        sizeof(storage->transferFunction),
        av_color_transfer_name(parameters->color_trc) ?: "unknown"
    );
    copy_media_information_text(
        storage->yCbCrMatrix,
        sizeof(storage->yCbCrMatrix),
        av_color_space_name(parameters->color_space) ?: "unknown"
    );
    copy_media_information_text(
        storage->colorRange,
        sizeof(storage->colorRange),
        av_color_range_name(parameters->color_range) ?: "unknown"
    );
    copy_media_information_text(
        storage->projectionKind,
        sizeof(storage->projectionKind),
        media_stream_projection_kind(parameters)
    );
}

PBFFmpegMediaSourceInformation *PBFFmpegMediaSourceInformationCreate(
    const char *path,
    char *errorBuffer,
    size_t errorBufferSize
) {
    return PBFFmpegMediaSourceInformationCreateWithSourceReadMonitor(
        path,
        NULL,
        errorBuffer,
        errorBufferSize
    );
}

PBFFmpegMediaSourceInformation *PBFFmpegMediaSourceInformationCreateWithSourceReadMonitor(
    const char *path,
    PBFFmpegSourceReadMonitor *monitor,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!path) {
        set_error(errorBuffer, errorBufferSize, "Invalid media source information call");
        return NULL;
    }
    PBFFmpegSourceReadContext sourceReadContext = {.monitor = monitor};
    AVFormatContext *context = allocate_format_context(NULL, &sourceReadContext);
    if (!context) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate media information context");
        return NULL;
    }
    int result = open_media_source(&context, path, &sourceReadContext);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open media information source", result);
        close_media_source(&context, &sourceReadContext);
        return NULL;
    }
    normalize_mov_apac_codec_id(context);
    normalize_mov_dolby_vision_av1_codec_id(context);
    PBStreamInformationRead informationRead = {0};
    result = read_stream_information(
        context,
        &sourceReadContext,
        &informationRead
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read media stream information", result);
        close_media_source(&context, &sourceReadContext);
        return NULL;
    }

    bool needsAudioProbe = false;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        if (audio_stream_needs_more_probe(context->streams[index])) {
            needsAudioProbe = true;
            break;
        }
    }
    if (needsAudioProbe && informationRead.skippedProbe) {
        result = avformat_find_stream_info(context, NULL);
        publish_source_bytes(&sourceReadContext);
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Read audio stream information", result);
            close_media_source(&context, &sourceReadContext);
            return NULL;
        }
        normalize_mov_apac_codec_id(context);
    }
    if (needsAudioProbe) {
        probe_delayed_audio_parameters(context);
        publish_source_bytes(&sourceReadContext);
    }

    if (context->nb_streams > INT_MAX) {
        set_error(errorBuffer, errorBufferSize, "Media source has too many streams");
        close_media_source(&context, &sourceReadContext);
        return NULL;
    }
    PBFFmpegMediaSourceInformation *information = calloc(1, sizeof(*information));
    if (!information) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate media source information");
        close_media_source(&context, &sourceReadContext);
        return NULL;
    }
    information->streamCount = (int)context->nb_streams;
    if (information->streamCount > 0) {
        information->streams = calloc(
            (size_t)information->streamCount,
            sizeof(*information->streams)
        );
    }
    if (information->streamCount > 0 && !information->streams) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate media stream information");
        PBFFmpegMediaSourceInformationDestroy(information);
        close_media_source(&context, &sourceReadContext);
        return NULL;
    }
    copy_media_information_text(
        information->containerFormat,
        sizeof(information->containerFormat),
        context->iformat && context->iformat->name ? context->iformat->name : "unknown"
    );
    information->durationSeconds = media_source_duration_seconds(context);
    for (int index = 0; index < information->streamCount; index++) {
        fill_media_stream_storage(&information->streams[index], context->streams[index]);
    }
    close_media_source(&context, &sourceReadContext);
    return information;
}

void PBFFmpegMediaSourceInformationDestroy(
    PBFFmpegMediaSourceInformation *information
) {
    if (!information) return;
    free(information->streams);
    free(information);
}

const char *PBFFmpegMediaSourceInformationGetContainerFormat(
    const PBFFmpegMediaSourceInformation *information
) {
    return information ? information->containerFormat : "unknown";
}

double PBFFmpegMediaSourceInformationGetDurationSeconds(
    const PBFFmpegMediaSourceInformation *information
) {
    return information ? information->durationSeconds : 0;
}

int PBFFmpegMediaSourceInformationGetStreamCount(
    const PBFFmpegMediaSourceInformation *information
) {
    return information ? information->streamCount : 0;
}

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
) {
    if (!information || ordinal < 0 || ordinal >= information->streamCount) return false;
    const PBFFmpegMediaStreamStorage *stream = &information->streams[ordinal];
    if (infoOut) *infoOut = stream->info;
    copy_media_information_text(
        codecNameBuffer,
        codecNameBufferSize,
        stream->codecName
    );
    copy_media_information_text(languageBuffer, languageBufferSize, stream->language);
    copy_media_information_text(titleBuffer, titleBufferSize, stream->title);
    copy_media_information_text(
        colorPrimariesBuffer,
        colorPrimariesBufferSize,
        stream->colorPrimaries
    );
    copy_media_information_text(
        transferFunctionBuffer,
        transferFunctionBufferSize,
        stream->transferFunction
    );
    copy_media_information_text(
        yCbCrMatrixBuffer,
        yCbCrMatrixBufferSize,
        stream->yCbCrMatrix
    );
    copy_media_information_text(
        colorRangeBuffer,
        colorRangeBufferSize,
        stream->colorRange
    );
    copy_media_information_text(
        projectionKindBuffer,
        projectionKindBufferSize,
        stream->projectionKind
    );
    return true;
}

bool PBFFmpegReaderOpen(
    PBFFmpegReader *reader,
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg reader");
        return false;
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    reader->mode = mode;
    reader->videoStreamIndex = -1;
    reader->formatContext = allocate_format_context(
        &reader->cancelled,
        &reader->sourceReadContext
    );
    if (reader->formatContext == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg format context");
        return false;
    }

    int result = open_media_source(
        &reader->formatContext,
        path,
        &reader->sourceReadContext
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open media source", result);
        return false;
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    normalize_mov_dolby_vision_av1_codec_id(reader->formatContext);
    result = read_stream_information(
        reader->formatContext,
        &reader->sourceReadContext,
        NULL
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read stream information", result);
        return false;
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    reader->videoStreamIndex = av_find_best_stream(
        reader->formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0
    );
    if (reader->videoStreamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "The selected source has no video stream");
        return false;
    }

    detect_dolby_vision(reader);

    AVStream *stream = reader->formatContext->streams[reader->videoStreamIndex];
    reader->timeBase = stream->time_base;
    reader->startTimestamp = stream_start_timestamp(reader->formatContext, stream);
    reader->durationSeconds = stream->duration != AV_NOPTS_VALUE &&
        stream->duration > 0
        ? stream->duration * av_q2d(stream->time_base)
        : (reader->formatContext->duration > 0
            ? (double)reader->formatContext->duration / AV_TIME_BASE
            : 0);
    reader->nominalFrameRate = av_q2d(stream->avg_frame_rate);
    if (!isfinite(reader->nominalFrameRate) || reader->nominalFrameRate < 0) {
        reader->nominalFrameRate = 0;
    }
    snprintf(reader->codecName, sizeof(reader->codecName), "%s", avcodec_get_name(stream->codecpar->codec_id));
    uint32_t tag = stream->codecpar->codec_tag;
    reader->codecTag[0] = (char)(tag & 0xff);
    reader->codecTag[1] = (char)((tag >> 8) & 0xff);
    reader->codecTag[2] = (char)((tag >> 16) & 0xff);
    reader->codecTag[3] = (char)((tag >> 24) & 0xff);
    reader->codecTag[4] = '\0';
    snprintf(
        reader->containerFormat,
        sizeof(reader->containerFormat),
        "%s",
        reader->formatContext->iformat && reader->formatContext->iformat->name
            ? reader->formatContext->iformat->name
            : "unknown"
    );
    reader->width = stream->codecpar->width;
    reader->height = stream->codecpar->height;
    snprintf(
        reader->colorPrimaries,
        sizeof(reader->colorPrimaries),
        "%s",
        av_color_primaries_name(stream->codecpar->color_primaries) ?: "unknown"
    );
    snprintf(
        reader->transferFunction,
        sizeof(reader->transferFunction),
        "%s",
        av_color_transfer_name(stream->codecpar->color_trc) ?: "unknown"
    );
    snprintf(
        reader->yCbCrMatrix,
        sizeof(reader->yCbCrMatrix),
        "%s",
        av_color_space_name(stream->codecpar->color_space) ?: "unknown"
    );
    snprintf(
        reader->colorRange,
        sizeof(reader->colorRange),
        "%s",
        av_color_range_name(stream->codecpar->color_range) ?: "unknown"
    );

    if (mode == PBFFmpegModeCompressed) {
        OSType compressedType = codec_type(stream->codecpar);
        if (!compressed_codec_is_renderable(compressedType)) {
            char message[256];
            snprintf(
                message,
                sizeof(message),
                "Unsupported codec: %s is not available for compressed sample rendering on this device",
                avcodec_get_name(stream->codecpar->codec_id)
            );
            set_error(errorBuffer, errorBufferSize, message);
            return false;
        }
        bool neededBitstreamBootstrap =
            stream->codecpar->codec_id != AV_CODEC_ID_PRORES &&
            (reader->forceBitstreamExtradataBootstrap ||
             !video_codec_configuration_is_usable(stream->codecpar));
        result = bootstrap_video_extradata(reader, stream, errorBuffer, errorBufferSize);
        if (result < 0) return false;
        reader->usedBitstreamExtradataBootstrap = neededBitstreamBootstrap;
        if (cancellation_requested(&reader->cancelled)) return false;
        AVRational sampleAspectRatio = av_guess_sample_aspect_ratio(
            reader->formatContext,
            stream,
            NULL
        );
        OSStatus status = create_compressed_format(
            stream->codecpar,
            sampleAspectRatio,
            &reader->compressedFormat,
            &reader->convertsAnnexB
        );
        if (status != noErr) {
            const AVPacketSideData *doviConfiguration = codec_side_data(
                stream->codecpar, AV_PKT_DATA_DOVI_CONF
            );
            char message[256];
            snprintf(
                message,
                sizeof(message),
                "Create compressed CMVideoFormatDescription failed (%d); codec=%s tag=%s extradata=%d dovi=%s bootstrapPackets=%zu",
                (int)status,
                avcodec_get_name(stream->codecpar->codec_id),
                reader->codecTag[0] ? reader->codecTag : "unknown",
                stream->codecpar->extradata_size,
                doviConfiguration ? "yes" : "no",
                reader->bootstrapPacketCount
            );
            set_error(errorBuffer, errorBufferSize, message);
            return false;
        }
        if (reader->bootstrapPacketCount > 0) {
            reader->convertsAnnexB = reader->bootstrapPacketsAreAnnexB;
        }
        CFStringRef projection = CMFormatDescriptionGetExtension(
            reader->compressedFormat,
            kCMFormatDescriptionExtension_ProjectionKind
        );
        if (projection) {
            CFStringGetCString(
                projection,
                reader->projectionKind,
                sizeof(reader->projectionKind),
                kCFStringEncodingUTF8
            );
        }
        CFStringRef packing = CMFormatDescriptionGetExtension(
            reader->compressedFormat,
            kCMFormatDescriptionExtension_ViewPackingKind
        );
        if (packing) {
            CFStringGetCString(
                packing,
                reader->viewPackingKind,
                sizeof(reader->viewPackingKind),
                kCFStringEncodingUTF8
            );
        }
    }

    reader->packet = av_packet_alloc();
    if (reader->packet == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg packet");
        return false;
    }

    if (startSeconds > 0) {
        int64_t timestamp = reader->startTimestamp +
            (int64_t)(startSeconds / av_q2d(reader->timeBase));
        result = avformat_seek_file(
            reader->formatContext,
            reader->videoStreamIndex,
            INT64_MIN,
            timestamp,
            INT64_MAX,
            AVSEEK_FLAG_BACKWARD
        );
        publish_source_bytes(&reader->sourceReadContext);
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Seek media source", result);
            return false;
        }
        if (cancellation_requested(&reader->cancelled)) return false;
        discard_bootstrap_packets(reader);
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    return true;
}

PBFFmpegReader *PBFFmpegReaderCreate(
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
) {
    PBFFmpegReader *reader = PBFFmpegReaderAllocate();
    if (!reader) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg reader");
        return NULL;
    }
    if (!PBFFmpegReaderOpen(
            reader, path, mode, startSeconds, errorBuffer, errorBufferSize
        )) {
        PBFFmpegReaderDestroy(reader);
        return NULL;
    }
    return reader;
}

void PBFFmpegReaderCancel(PBFFmpegReader *reader) {
    if (reader) atomic_store_explicit(&reader->cancelled, true, memory_order_relaxed);
}

void PBFFmpegReaderForceBitstreamExtradataBootstrap(PBFFmpegReader *reader) {
    if (reader) reader->forceBitstreamExtradataBootstrap = true;
}

bool PBFFmpegReaderUsedBitstreamExtradataBootstrap(const PBFFmpegReader *reader) {
    return reader && reader->usedBitstreamExtradataBootstrap;
}

void PBFFmpegReaderDestroy(PBFFmpegReader *reader) {
    if (reader == NULL) return;
    if (reader->compressedFormat) CFRelease(reader->compressedFormat);
    discard_bootstrap_packets(reader);
    av_packet_free(&reader->packet);
    close_media_source(&reader->formatContext, &reader->sourceReadContext);
    free(reader);
}

bool PBFFmpegReaderCopyCompressedFormatDescription(
    const PBFFmpegReader *reader,
    CMVideoFormatDescriptionRef *formatOut
) {
    if (!formatOut) return false;
    *formatOut = NULL;
    if (!reader || !reader->compressedFormat) return false;
    *formatOut = (CMVideoFormatDescriptionRef)CFRetain(reader->compressedFormat);
    return true;
}

static bool reader_format_has_atom(const PBFFmpegReader *reader, CFStringRef atom) {
    if (!reader || !reader->compressedFormat) return false;
    CFDictionaryRef atoms = CMFormatDescriptionGetExtension(
        reader->compressedFormat,
        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
    );
    return atoms && CFDictionaryContainsKey(atoms, atom);
}

bool PBFFmpegReaderFormatHasHvcC(const PBFFmpegReader *reader) {
    return reader_format_has_atom(reader, CFSTR("hvcC"));
}

bool PBFFmpegReaderFormatHasDvcC(const PBFFmpegReader *reader) {
    return reader_format_has_atom(reader, CFSTR("dvcC"));
}

bool PBFFmpegReaderFormatHasDvvC(const PBFFmpegReader *reader) {
    return reader_format_has_atom(reader, CFSTR("dvvC"));
}

bool PBFFmpegReaderIsMVHEVC(const PBFFmpegReader *reader) {
    if (!reader || !reader->compressedFormat) return false;
    FourCharCode subtype = CMFormatDescriptionGetMediaSubType(reader->compressedFormat);
    if (subtype != kCMVideoCodecType_HEVC &&
        subtype != kCMVideoCodecType_DolbyVisionHEVC) {
        return false;
    }
    CFArrayRef tagCollections = NULL;
    OSStatus status = CMVideoFormatDescriptionCopyTagCollectionArray(
        reader->compressedFormat,
        &tagCollections
    );
    bool isMVHEVC = status == noErr &&
        tagCollections != NULL &&
        CFArrayGetCount(tagCollections) > 1;
    if (tagCollections) CFRelease(tagCollections);
    return isMVHEVC;
}

static uint8_t *copy_annexb_as_length_prefixed(
    const uint8_t *source,
    size_t sourceSize,
    size_t *outputSize
) {
    if (sourceSize > (SIZE_MAX - 4) / 2) return NULL;
    uint8_t *output = malloc(sourceSize * 2 + 4);
    if (!output) return NULL;
    const uint8_t *cursor = source;
    const uint8_t *end = source + sourceSize;
    size_t offset = 0;
    bool found = false;
    while (cursor < end) {
        size_t startLength = 0;
        const uint8_t *start = find_start_code(cursor, end, &startLength);
        if (!start) break;
        const uint8_t *nal = start + startLength;
        size_t nextLength = 0;
        const uint8_t *next = find_start_code(nal, end, &nextLength);
        const uint8_t *nalEnd = next ?: end;
        while (nalEnd > nal && nalEnd[-1] == 0) nalEnd--;
        size_t nalSize = (size_t)(nalEnd - nal);
        if (nalSize > 0 && nalSize <= UINT32_MAX) {
            output[offset] = (uint8_t)((nalSize >> 24) & 0xff);
            output[offset + 1] = (uint8_t)((nalSize >> 16) & 0xff);
            output[offset + 2] = (uint8_t)((nalSize >> 8) & 0xff);
            output[offset + 3] = (uint8_t)(nalSize & 0xff);
            memcpy(output + offset + 4, nal, nalSize);
            offset += 4 + nalSize;
            found = true;
        }
        cursor = next ?: end;
    }
    if (!found) { free(output); return NULL; }
    *outputSize = offset;
    return output;
}

static PBFFmpegReadResult copy_compressed_sample(
    PBFFmpegReader *reader,
    CMSampleBufferRef *sampleOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    AVPacket *packet = reader->packet;
    while (true) {
        if (atomic_load_explicit(&reader->cancelled, memory_order_relaxed)) {
            return PBFFmpegReadResultCancelled;
        }
        int readResult = 0;
        if (reader->bootstrapPacketIndex < reader->bootstrapPacketCount) {
            AVPacket **buffered = &reader->bootstrapPackets[reader->bootstrapPacketIndex++];
            av_packet_move_ref(packet, *buffered);
            av_packet_free(buffered);
        } else {
            readResult = av_read_frame(reader->formatContext, packet);
            publish_source_bytes(&reader->sourceReadContext);
        }
        if (readResult < 0) {
            if (readResult == AVERROR_EXIT
                || atomic_load_explicit(&reader->cancelled, memory_order_relaxed)) {
                return PBFFmpegReadResultCancelled;
            }
            return PBFFmpegReadResultEnd;
        }
        if (packet->stream_index != reader->videoStreamIndex) {
            av_packet_unref(packet);
            continue;
        }

        const uint8_t *sampleBytes = packet->data;
        size_t sampleByteCount = (size_t)packet->size;
        uint8_t *convertedBytes = NULL;
        if (reader->convertsAnnexB) {
            convertedBytes = copy_annexb_as_length_prefixed(
                packet->data, (size_t)packet->size, &sampleByteCount
            );
            if (!convertedBytes) {
                av_packet_unref(packet);
                set_error(errorBuffer, errorBufferSize, "Convert Annex-B packet to length-prefixed sample failed");
                return PBFFmpegReadResultError;
            }
            sampleBytes = convertedBytes;
        }
        CMBlockBufferRef block = NULL;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(
            kCFAllocatorDefault,
            NULL,
            sampleByteCount,
            kCFAllocatorDefault,
            NULL,
            0,
            sampleByteCount,
            0,
            &block
        );
        if (status == noErr) {
            status = CMBlockBufferReplaceDataBytes(sampleBytes, block, 0, sampleByteCount);
        }
        int64_t presentationTimestamp = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;
        int64_t decodeTimestamp = packet->dts != AV_NOPTS_VALUE ? packet->dts : presentationTimestamp;
        if (presentationTimestamp != AV_NOPTS_VALUE) presentationTimestamp -= reader->startTimestamp;
        if (decodeTimestamp != AV_NOPTS_VALUE) decodeTimestamp -= reader->startTimestamp;
        CMTime sampleDuration = cm_time(packet->duration, reader->timeBase);
        if (!CMTIME_IS_VALID(sampleDuration) && reader->nominalFrameRate > 0) {
            sampleDuration = CMTimeMake(1, (int32_t)llround(reader->nominalFrameRate));
        }
        CMSampleTimingInfo timing = {
            .duration = sampleDuration,
            .presentationTimeStamp = cm_time(presentationTimestamp, reader->timeBase),
            .decodeTimeStamp = cm_time(decodeTimestamp, reader->timeBase),
        };
        size_t sampleSize = sampleByteCount;
        if (status == noErr) {
            status = CMSampleBufferCreateReady(
                kCFAllocatorDefault,
                block,
                reader->compressedFormat,
                1,
                1,
                &timing,
                1,
                &sampleSize,
                sampleOut
            );
        }
        if (status == noErr) {
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(*sampleOut, true);
            if (!(packet->flags & AV_PKT_FLAG_KEY) &&
                attachments && CFArrayGetCount(attachments) > 0) {
                CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
                CFDictionarySetValue(attachment, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
            }
        }
        if (block) CFRelease(block);
        free(convertedBytes);
        av_packet_unref(packet);
        if (status != noErr) {
            char message[128];
            snprintf(message, sizeof(message), "Create compressed CMSampleBuffer failed (%d)", (int)status);
            set_error(errorBuffer, errorBufferSize, message);
            return PBFFmpegReadResultError;
        }
        return PBFFmpegReadResultSample;
    }
}

PBFFmpegReadResult PBFFmpegReaderCopyNextSample(
    PBFFmpegReader *reader,
    CMSampleBufferRef *sampleOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader == NULL || sampleOut == NULL) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg reader call");
        return PBFFmpegReadResultError;
    }
    *sampleOut = NULL;
    return copy_compressed_sample(reader, sampleOut, errorBuffer, errorBufferSize);
}

double PBFFmpegReaderGetDurationSeconds(const PBFFmpegReader *reader) {
    return reader ? reader->durationSeconds : 0;
}

double PBFFmpegReaderGetNominalFrameRate(const PBFFmpegReader *reader) {
    return reader ? reader->nominalFrameRate : 0;
}

const char *PBFFmpegReaderGetCodecName(const PBFFmpegReader *reader) {
    return reader ? reader->codecName : "unknown";
}

const char *PBFFmpegReaderGetCodecTag(const PBFFmpegReader *reader) {
    return reader && reader->codecTag[0] ? reader->codecTag : "unknown";
}

const char *PBFFmpegReaderGetContainerFormat(const PBFFmpegReader *reader) {
    return reader ? reader->containerFormat : "unknown";
}

const char *PBFFmpegReaderGetColorPrimaries(const PBFFmpegReader *reader) {
    return reader ? reader->colorPrimaries : "unknown";
}

const char *PBFFmpegReaderGetTransferFunction(const PBFFmpegReader *reader) {
    return reader ? reader->transferFunction : "unknown";
}

int PBFFmpegReaderGetDolbyVisionProfile(const PBFFmpegReader *reader) {
    return reader ? reader->dolbyVisionProfile : 0;
}

int PBFFmpegReaderGetDolbyVisionCrossCompatibilityID(const PBFFmpegReader *reader) {
    return reader ? reader->dolbyVisionCrossCompatibilityID : 0;
}

bool PBFFmpegReaderDolbyVisionHasEnhancementLayer(const PBFFmpegReader *reader) {
    return reader ? reader->dolbyVisionHasEnhancementLayer : false;
}


const char *PBFFmpegReaderGetYCbCrMatrix(const PBFFmpegReader *reader) {
    return reader ? reader->yCbCrMatrix : "unknown";
}

const char *PBFFmpegReaderGetColorRange(const PBFFmpegReader *reader) {
    return reader ? reader->colorRange : "unknown";
}

const char *PBFFmpegReaderGetProjectionKind(const PBFFmpegReader *reader) {
    return reader && reader->projectionKind[0] ? reader->projectionKind : "unknown";
}

const char *PBFFmpegReaderGetViewPackingKind(const PBFFmpegReader *reader) {
    return reader && reader->viewPackingKind[0] ? reader->viewPackingKind : "unknown";
}

int PBFFmpegReaderGetWidth(const PBFFmpegReader *reader) {
    return reader ? reader->width : 0;
}

int PBFFmpegReaderGetHeight(const PBFFmpegReader *reader) {
    return reader ? reader->height : 0;
}

int PBFFmpegReaderGetVideoStreamIndex(const PBFFmpegReader *reader) {
    return reader ? reader->videoStreamIndex : -1;
}

int PBFFmpegReaderGetTimeBaseNumerator(const PBFFmpegReader *reader) {
    return reader ? reader->timeBase.num : 0;
}

int PBFFmpegReaderGetTimeBaseDenominator(const PBFFmpegReader *reader) {
    return reader ? reader->timeBase.den : 0;
}

PBFFmpegAudioReader *PBFFmpegAudioReaderAllocate(void) {
    PBFFmpegAudioReader *reader = calloc(1, sizeof(PBFFmpegAudioReader));
    if (reader) atomic_init(&reader->cancelled, false);
    return reader;
}

void PBFFmpegAudioReaderSetSourceReadMonitor(
    PBFFmpegAudioReader *reader,
    PBFFmpegSourceReadMonitor *monitor
) {
    if (reader) reader->sourceReadContext.monitor = monitor;
}

bool PBFFmpegAudioReaderOpen(
    PBFFmpegAudioReader *reader,
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio reader");
        return false;
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    reader->audioStreamIndex = -1;

    int result = open_media_source_for_audio(
        path,
        &reader->formatContext,
        &reader->cancelled,
        &reader->sourceReadContext,
        errorBuffer,
        errorBufferSize
    );
    if (result < 0) {
        return false;
    }
    if (cancellation_requested(&reader->cancelled)) return false;

    if (preferredStreamIndex >= 0) {
        if (preferredStreamIndex < (int)reader->formatContext->nb_streams &&
            audio_stream_is_supported(reader->formatContext->streams[preferredStreamIndex])) {
            reader->audioStreamIndex = preferredStreamIndex;
        } else {
            set_error(errorBuffer, errorBufferSize, "The selected audio stream codec is not supported by PlaybackCore");
            return false;
        }
    } else {
        reader->audioStreamIndex = av_find_best_stream(
            reader->formatContext, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0
        );
        if (reader->audioStreamIndex >= 0 &&
            !audio_stream_is_supported(reader->formatContext->streams[reader->audioStreamIndex])) {
            reader->audioStreamIndex = -1;
        }
        if (reader->audioStreamIndex < 0) {
            for (unsigned int index = 0; index < reader->formatContext->nb_streams; index++) {
                if (audio_stream_is_supported(reader->formatContext->streams[index])) {
                    reader->audioStreamIndex = (int)index;
                    break;
                }
            }
        }
    }
    if (reader->audioStreamIndex < 0) {
        set_audio_stream_selection_error(
            reader->formatContext,
            errorBuffer,
            errorBufferSize
        );
        return false;
    }

    AVStream *stream = reader->formatContext->streams[reader->audioStreamIndex];
    reader->sampleRate = stream->codecpar->sample_rate;
    reader->channelCount = stream->codecpar->ch_layout.nb_channels;
    if (reader->sampleRate <= 0 || reader->channelCount <= 0) {
        set_error(errorBuffer, errorBufferSize, "Audio stream has invalid sample rate or channel layout");
        return false;
    }
    if (stream->codecpar->codec_id == AV_CODEC_ID_APAC) {
        reader->codecMagicCookie = copy_apac_magic_cookie(path);
        if (!reader->codecMagicCookie) {
            set_error(
                errorBuffer,
                errorBufferSize,
                "Apple Positional Audio dapa codec configuration is unavailable"
            );
            return false;
        }
    }
    reader->packet = av_packet_alloc();
    reader->filteredPacket = av_packet_alloc();
    reader->outputsPCM = audio_codec_is_source_pcm(stream->codecpar->codec_id);
    reader->timeBase = stream->time_base;
    reader->startTimestamp = stream_start_timestamp(reader->formatContext, stream);
    snprintf(reader->codecName, sizeof(reader->codecName), "%s", avcodec_get_name(stream->codecpar->codec_id));
    if (reader->packet == NULL || reader->filteredPacket == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio packet");
        return false;
    }

    if (stream->codecpar->codec_id == AV_CODEC_ID_AAC) {
        const AVBitStreamFilter *filter = av_bsf_get_by_name("aac_adtstoasc");
        if (filter == NULL || av_bsf_alloc(filter, &reader->bitstreamFilter) < 0) {
            set_error(errorBuffer, errorBufferSize, "Unable to create AAC compressed-audio filter");
            return false;
        }
        result = avcodec_parameters_copy(reader->bitstreamFilter->par_in, stream->codecpar);
        if (result >= 0) {
            reader->bitstreamFilter->time_base_in = stream->time_base;
            result = av_bsf_init(reader->bitstreamFilter);
        }
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Initialize AAC compressed-audio filter", result);
            return false;
        }
        if (reader->bitstreamFilter->time_base_out.num > 0 &&
            reader->bitstreamFilter->time_base_out.den > 0 &&
            av_cmp_q(reader->timeBase, reader->bitstreamFilter->time_base_out) != 0) {
            reader->startTimestamp = av_rescale_q(
                reader->startTimestamp,
                reader->timeBase,
                reader->bitstreamFilter->time_base_out
            );
            reader->timeBase = reader->bitstreamFilter->time_base_out;
        }
    }

    if (startSeconds > 0) {
        int64_t timestamp = reader->startTimestamp +
            (int64_t)(startSeconds / av_q2d(reader->timeBase));
        result = avformat_seek_file(
            reader->formatContext,
            reader->audioStreamIndex,
            INT64_MIN,
            timestamp,
            INT64_MAX,
            AVSEEK_FLAG_BACKWARD
        );
        publish_source_bytes(&reader->sourceReadContext);
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Seek audio media source", result);
            return false;
        }
        if (cancellation_requested(&reader->cancelled)) return false;
        if (reader->bitstreamFilter) av_bsf_flush(reader->bitstreamFilter);
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    return true;
}

PBFFmpegAudioReader *PBFFmpegAudioReaderCreate(
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    PBFFmpegAudioReader *reader = PBFFmpegAudioReaderAllocate();
    if (!reader) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio reader");
        return NULL;
    }
    if (!PBFFmpegAudioReaderOpen(
            reader, path, startSeconds, preferredStreamIndex,
            errorBuffer, errorBufferSize
        )) {
        PBFFmpegAudioReaderDestroy(reader);
        return NULL;
    }
    return reader;
}

void PBFFmpegAudioReaderCancel(PBFFmpegAudioReader *reader) {
    if (reader) atomic_store_explicit(&reader->cancelled, true, memory_order_relaxed);
}

void PBFFmpegAudioReaderDestroy(PBFFmpegAudioReader *reader) {
    if (reader == NULL) return;
    if (reader->formatDescription) CFRelease(reader->formatDescription);
    if (reader->codecMagicCookie) CFRelease(reader->codecMagicCookie);
    av_bsf_free(&reader->bitstreamFilter);
    av_packet_free(&reader->filteredPacket);
    av_packet_free(&reader->packet);
    close_media_source(&reader->formatContext, &reader->sourceReadContext);
    free(reader);
}

static UInt32 audio_frames_per_packet(const AVCodecParameters *parameters) {
    if (aac_is_usac(parameters)) return 2048;
    if (parameters->frame_size > 0) return (UInt32)parameters->frame_size;
    switch (parameters->codec_id) {
        case AV_CODEC_ID_AAC: return 1024;
        case AV_CODEC_ID_AC3:
        case AV_CODEC_ID_EAC3: return 1536;
        case AV_CODEC_ID_MP2:
        case AV_CODEC_ID_MP3: return 1152;
        // Opus packets may represent 2.5 through 120 ms. The packet timestamp
        // duration below is authoritative, so the ASBD must not claim a fixed
        // number of PCM frames for every packet.
        case AV_CODEC_ID_OPUS: return 0;
        case AV_CODEC_ID_APAC: return 1024;
        case AV_CODEC_ID_FLAC:
            if (parameters->extradata && parameters->extradata_size >= 4) {
                return (UInt32)(
                    ((uint16_t)parameters->extradata[2] << 8) |
                    parameters->extradata[3]
                );
            }
            return 0;
        default: return 0;
    }
}

static AudioFormatFlags audio_format_flags(const AVCodecParameters *parameters) {
    if (parameters->codec_id != AV_CODEC_ID_ALAC &&
        parameters->codec_id != AV_CODEC_ID_FLAC) return 0;
    switch (parameters->bits_per_raw_sample) {
        case 20: return kAppleLosslessFormatFlag_20BitSourceData;
        case 24: return kAppleLosslessFormatFlag_24BitSourceData;
        case 32: return kAppleLosslessFormatFlag_32BitSourceData;
        default: return kAppleLosslessFormatFlag_16BitSourceData;
    }
}

static CFDataRef create_flac_magic_cookie(const AVCodecParameters *parameters) {
    if (!parameters->extradata || parameters->extradata_size != 34) return NULL;
    size_t cookieSize = 16 + (size_t)parameters->extradata_size;
    uint8_t *cookie = calloc(1, cookieSize);
    if (!cookie) return NULL;
    write_be32(cookie, (uint32_t)cookieSize);
    memcpy(cookie + 4, "dfLa", 4);
    cookie[12] = 0x80;
    cookie[13] = (uint8_t)(parameters->extradata_size >> 16);
    cookie[14] = (uint8_t)(parameters->extradata_size >> 8);
    cookie[15] = (uint8_t)parameters->extradata_size;
    memcpy(cookie + 16, parameters->extradata, (size_t)parameters->extradata_size);
    CFDataRef result = CFDataCreate(kCFAllocatorDefault, cookie, cookieSize);
    free(cookie);
    return result;
}

static int aac_sample_rate_index(int sampleRate) {
    for (int index = 0; index < 13; index++) {
        if (aac_sample_rates[index] == sampleRate) return index;
    }
    return -1;
}

static size_t audio_descriptor_length_size(size_t value) {
    size_t length = 1;
    while (value >= 0x80) {
        value >>= 7;
        length++;
    }
    return length;
}

static uint8_t *write_audio_descriptor_length(uint8_t *destination, size_t value) {
    size_t length = audio_descriptor_length_size(value);
    for (size_t index = length; index > 0; index--) {
        unsigned shift = (unsigned)((index - 1) * 7);
        *destination++ = (uint8_t)((value >> shift) & 0x7f) |
            (index > 1 ? 0x80 : 0);
    }
    return destination;
}

static CFDataRef create_aac_magic_cookie(
    const AVCodecParameters *parameters,
    const void *configuration,
    size_t configurationSize
) {
    if (configurationSize == 0 || configuration == NULL) return NULL;

    size_t decoderSpecificSize =
        1 + audio_descriptor_length_size(configurationSize) + configurationSize;
    size_t decoderConfigPayloadSize = 13 + decoderSpecificSize;
    size_t decoderConfigSize =
        1 + audio_descriptor_length_size(decoderConfigPayloadSize) +
        decoderConfigPayloadSize;
    size_t slConfigSize = 1 + 1 + 1;
    size_t esPayloadSize = 3 + decoderConfigSize + slConfigSize;
    size_t totalSize = 1 + audio_descriptor_length_size(esPayloadSize) + esPayloadSize;
    uint8_t *bytes = calloc(1, totalSize);
    if (!bytes) return NULL;

    uint8_t *cursor = bytes;
    *cursor++ = 0x03;
    cursor = write_audio_descriptor_length(cursor, esPayloadSize);
    *cursor++ = 0;
    *cursor++ = 0;
    *cursor++ = 0;
    *cursor++ = 0x04;
    cursor = write_audio_descriptor_length(cursor, decoderConfigPayloadSize);
    *cursor++ = 0x40;
    *cursor++ = 0x15;
    *cursor++ = 0;
    *cursor++ = 6;
    *cursor++ = 0;
    uint32_t bitrate = parameters->bit_rate > 0 &&
            parameters->bit_rate <= UINT32_MAX
        ? (uint32_t)parameters->bit_rate
        : 0;
    write_be32(cursor, bitrate);
    cursor += 4;
    write_be32(cursor, bitrate);
    cursor += 4;
    *cursor++ = 0x05;
    cursor = write_audio_descriptor_length(cursor, configurationSize);
    memcpy(cursor, configuration, configurationSize);
    cursor += configurationSize;
    *cursor++ = 0x06;
    *cursor++ = 1;
    *cursor++ = 2;

    CFDataRef cookie = CFDataCreate(
        kCFAllocatorDefault,
        bytes,
        (CFIndex)(cursor - bytes)
    );
    free(bytes);
    return cookie;
}

static AudioChannelLabel audio_channel_label(enum AVChannel channel) {
    switch (channel) {
        case AV_CHAN_FRONT_LEFT: return kAudioChannelLabel_Left;
        case AV_CHAN_FRONT_RIGHT: return kAudioChannelLabel_Right;
        case AV_CHAN_FRONT_CENTER: return kAudioChannelLabel_Center;
        case AV_CHAN_LOW_FREQUENCY: return kAudioChannelLabel_LFEScreen;
        case AV_CHAN_BACK_LEFT: return kAudioChannelLabel_LeftSurround;
        case AV_CHAN_BACK_RIGHT: return kAudioChannelLabel_RightSurround;
        case AV_CHAN_FRONT_LEFT_OF_CENTER: return kAudioChannelLabel_LeftCenter;
        case AV_CHAN_FRONT_RIGHT_OF_CENTER: return kAudioChannelLabel_RightCenter;
        case AV_CHAN_BACK_CENTER: return kAudioChannelLabel_CenterSurround;
        case AV_CHAN_SIDE_LEFT: return kAudioChannelLabel_LeftSideSurround;
        case AV_CHAN_SIDE_RIGHT: return kAudioChannelLabel_RightSideSurround;
        case AV_CHAN_TOP_CENTER: return kAudioChannelLabel_TopCenterSurround;
        case AV_CHAN_TOP_FRONT_LEFT: return kAudioChannelLabel_LeftTopFront;
        case AV_CHAN_TOP_FRONT_CENTER: return kAudioChannelLabel_CenterTopFront;
        case AV_CHAN_TOP_FRONT_RIGHT: return kAudioChannelLabel_RightTopFront;
        case AV_CHAN_TOP_BACK_LEFT: return kAudioChannelLabel_LeftTopRear;
        case AV_CHAN_TOP_BACK_CENTER: return kAudioChannelLabel_CenterTopRear;
        case AV_CHAN_TOP_BACK_RIGHT: return kAudioChannelLabel_RightTopRear;
        case AV_CHAN_WIDE_LEFT: return kAudioChannelLabel_LeftWide;
        case AV_CHAN_WIDE_RIGHT: return kAudioChannelLabel_RightWide;
        case AV_CHAN_SURROUND_DIRECT_LEFT: return kAudioChannelLabel_LeftSurroundDirect;
        case AV_CHAN_SURROUND_DIRECT_RIGHT: return kAudioChannelLabel_RightSurroundDirect;
        case AV_CHAN_LOW_FREQUENCY_2: return kAudioChannelLabel_LFE2;
        case AV_CHAN_TOP_SIDE_LEFT: return kAudioChannelLabel_LeftTopMiddle;
        case AV_CHAN_TOP_SIDE_RIGHT: return kAudioChannelLabel_RightTopMiddle;
        case AV_CHAN_BOTTOM_FRONT_LEFT: return kAudioChannelLabel_LeftBottom;
        case AV_CHAN_BOTTOM_FRONT_CENTER: return kAudioChannelLabel_CenterBottom;
        case AV_CHAN_BOTTOM_FRONT_RIGHT: return kAudioChannelLabel_RightBottom;
        default: return kAudioChannelLabel_Unknown;
    }
}

static AudioChannelLayout *copy_audio_channel_layout(
    const AVChannelLayout *source,
    size_t *layoutSizeOut
) {
    if (!source || source->nb_channels <= 0 || !layoutSizeOut) return NULL;
    UInt32 channelCount = (UInt32)source->nb_channels;
    size_t layoutSize = sizeof(AudioChannelLayout);
    AudioChannelLayout *layout = NULL;
    if (channelCount == 1 || channelCount == 2 ||
        source->order == AV_CHANNEL_ORDER_UNSPEC) {
        layout = calloc(1, layoutSize);
        if (!layout) return NULL;
        if (channelCount == 1) {
            layout->mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
        } else if (channelCount == 2) {
            layout->mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
        } else {
            layout->mChannelLayoutTag =
                kAudioChannelLayoutTag_DiscreteInOrder | channelCount;
        }
    } else {
        layoutSize = offsetof(AudioChannelLayout, mChannelDescriptions) +
            channelCount * sizeof(AudioChannelDescription);
        layout = calloc(1, layoutSize);
        if (!layout) return NULL;
        layout->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
        layout->mNumberChannelDescriptions = channelCount;
        for (UInt32 index = 0; index < channelCount; index++) {
            layout->mChannelDescriptions[index].mChannelLabel = audio_channel_label(
                av_channel_layout_channel_from_index(source, index)
            );
        }
    }
    *layoutSizeOut = layoutSize;
    return layout;
}

static int ensure_compressed_audio_format(
    PBFFmpegAudioReader *reader,
    const AVCodecParameters *parameters,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader->formatDescription) return 0;
    AudioFormatID formatID = compressed_audio_format_id(parameters);
    if (formatID == 0) {
        set_error(errorBuffer, errorBufferSize, "The selected compressed audio codec is not supported");
        return AVERROR(ENOSYS);
    }
    AudioStreamBasicDescription asbd = {
        .mSampleRate = parameters->sample_rate,
        .mFormatID = formatID,
        .mFormatFlags = audio_format_flags(parameters),
        .mBytesPerPacket = 0,
        .mFramesPerPacket = audio_frames_per_packet(parameters),
        .mBytesPerFrame = 0,
        .mChannelsPerFrame = (UInt32)parameters->ch_layout.nb_channels,
        .mBitsPerChannel = 0,
        .mReserved = 0,
    };
    size_t channelLayoutSize = 0;
    AudioChannelLayout *channelLayout = copy_audio_channel_layout(
        &parameters->ch_layout,
        &channelLayoutSize
    );
    if (!channelLayout) {
        set_error(errorBuffer, errorBufferSize, "Audio channel layout is unavailable");
        return AVERROR_INVALIDDATA;
    }
    uint8_t synthesizedAACCookie[2] = {0};
    CFDataRef synthesizedAACMagicCookie = NULL;
    CFDataRef synthesizedFLACMagicCookie = NULL;
    const void *cookie = parameters->extradata_size > 0 ? parameters->extradata : NULL;
    size_t cookieSize = parameters->extradata_size > 0
        ? (size_t)parameters->extradata_size
        : 0;
    if (parameters->codec_id == AV_CODEC_ID_APAC && reader->codecMagicCookie) {
        cookie = CFDataGetBytePtr(reader->codecMagicCookie);
        cookieSize = (size_t)CFDataGetLength(reader->codecMagicCookie);
    }
    if (parameters->codec_id == AV_CODEC_ID_AAC && cookieSize == 0) {
        int sampleRateIndex = aac_sample_rate_index(parameters->sample_rate);
        int channelConfiguration = parameters->ch_layout.nb_channels;
        int profile = parameters->profile == AV_PROFILE_UNKNOWN
            ? AV_PROFILE_AAC_LOW
            : parameters->profile;
        if (sampleRateIndex < 0 || channelConfiguration < 1 || channelConfiguration > 7 ||
            profile < AV_PROFILE_AAC_MAIN || profile > AV_PROFILE_AAC_LTP) {
            free(channelLayout);
            set_error(errorBuffer, errorBufferSize, "Compressed AAC codec configuration is unavailable");
            return AVERROR_INVALIDDATA;
        }
        int audioObjectType = profile + 1;
        synthesizedAACCookie[0] = (uint8_t)((audioObjectType << 3) | (sampleRateIndex >> 1));
        synthesizedAACCookie[1] = (uint8_t)(((sampleRateIndex & 1) << 7) | (channelConfiguration << 3));
        cookie = synthesizedAACCookie;
        cookieSize = sizeof(synthesizedAACCookie);
    }
    if (parameters->codec_id == AV_CODEC_ID_AAC && cookieSize > 0) {
        synthesizedAACMagicCookie = create_aac_magic_cookie(
            parameters,
            cookie,
            cookieSize
        );
        if (synthesizedAACMagicCookie) {
            cookie = CFDataGetBytePtr(synthesizedAACMagicCookie);
            cookieSize = (size_t)CFDataGetLength(synthesizedAACMagicCookie);
        }
    }
    if (parameters->codec_id == AV_CODEC_ID_FLAC) {
        synthesizedFLACMagicCookie = create_flac_magic_cookie(parameters);
        if (!synthesizedFLACMagicCookie) {
            free(channelLayout);
            if (synthesizedAACMagicCookie) CFRelease(synthesizedAACMagicCookie);
            set_error(errorBuffer, errorBufferSize, "Compressed FLAC STREAMINFO is unavailable");
            return AVERROR_INVALIDDATA;
        }
        cookie = CFDataGetBytePtr(synthesizedFLACMagicCookie);
        cookieSize = (size_t)CFDataGetLength(synthesizedFLACMagicCookie);
    }
    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault,
        &asbd,
        channelLayoutSize,
        channelLayout,
        cookieSize,
        cookie,
        NULL,
        &reader->formatDescription
    );
    free(channelLayout);
    if (synthesizedAACMagicCookie) CFRelease(synthesizedAACMagicCookie);
    if (synthesizedFLACMagicCookie) CFRelease(synthesizedFLACMagicCookie);
    if (status != noErr) {
        char message[160];
        snprintf(
            message,
            sizeof(message),
            "Create compressed audio format description failed (%d)",
            (int)status
        );
        set_error(errorBuffer, errorBufferSize, message);
        return AVERROR_INVALIDDATA;
    }
    return 0;
}

static int ensure_source_pcm_audio_format(
    PBFFmpegAudioReader *reader,
    const AVCodecParameters *parameters,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader->formatDescription) return 0;
    SourcePCMFormat sourceFormat;
    if (!source_pcm_format(parameters->codec_id, &sourceFormat)) {
        set_error(errorBuffer, errorBufferSize, "The selected source PCM representation is not supported");
        return AVERROR(ENOSYS);
    }
    UInt32 channelCount = (UInt32)parameters->ch_layout.nb_channels;
    UInt32 bytesPerFrame = channelCount * sourceFormat.bytesPerSample;
    AudioStreamBasicDescription asbd = {
        .mSampleRate = parameters->sample_rate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = sourceFormat.flags,
        .mBytesPerPacket = bytesPerFrame,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = bytesPerFrame,
        .mChannelsPerFrame = channelCount,
        .mBitsPerChannel = sourceFormat.bitsPerChannel,
        .mReserved = 0,
    };
    size_t channelLayoutSize = 0;
    AudioChannelLayout *channelLayout = copy_audio_channel_layout(
        &parameters->ch_layout,
        &channelLayoutSize
    );
    if (!channelLayout) {
        set_error(errorBuffer, errorBufferSize, "Source PCM channel layout is unavailable");
        return AVERROR_INVALIDDATA;
    }
    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault,
        &asbd,
        channelLayoutSize,
        channelLayout,
        0,
        NULL,
        NULL,
        &reader->formatDescription
    );
    free(channelLayout);
    if (status != noErr) {
        char message[160];
        snprintf(
            message,
            sizeof(message),
            "Create source PCM audio format description failed (%d)",
            (int)status
        );
        set_error(errorBuffer, errorBufferSize, message);
        return AVERROR_INVALIDDATA;
    }
    return 0;
}

static int ensure_audio_format(
    PBFFmpegAudioReader *reader,
    const AVCodecParameters *parameters,
    char *errorBuffer,
    size_t errorBufferSize
) {
    return audio_codec_is_source_pcm(parameters->codec_id)
        ? ensure_source_pcm_audio_format(reader, parameters, errorBuffer, errorBufferSize)
        : ensure_compressed_audio_format(reader, parameters, errorBuffer, errorBufferSize);
}

static PBFFmpegReadResult create_audio_sample(
    PBFFmpegAudioReader *reader,
    AVPacket *packet,
    const AVCodecParameters *parameters,
    PBFFmpegAudioCookieSource cookieSource,
    int64_t originalPTS,
    int64_t originalDTS,
    int64_t originalDuration,
    CMSampleBufferRef *sampleOut,
    PBFFmpegAudioSampleMetadata *metadataOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    int formatResult = ensure_audio_format(
        reader, parameters, errorBuffer, errorBufferSize
    );
    if (formatResult < 0) return PBFFmpegReadResultError;
    if (packet->size <= 0 || packet->data == NULL) {
        set_error(errorBuffer, errorBufferSize, "Compressed audio packet is empty");
        return PBFFmpegReadResultError;
    }
    size_t byteCount = (size_t)packet->size;
    CMBlockBufferRef block = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault,
        NULL,
        byteCount,
        kCFAllocatorDefault,
        NULL,
        0,
        byteCount,
        0,
        &block
    );
    if (status == noErr) {
        status = CMBlockBufferReplaceDataBytes(packet->data, block, 0, byteCount);
    }
    bool isSourcePCM = audio_codec_is_source_pcm(parameters->codec_id);
    SourcePCMFormat sourcePCMFormat = {0};
    if (isSourcePCM) {
        source_pcm_format(parameters->codec_id, &sourcePCMFormat);
    }
    size_t bytesPerPCMFrame = isSourcePCM
        ? (size_t)parameters->ch_layout.nb_channels * sourcePCMFormat.bytesPerSample
        : 0;
    if (isSourcePCM &&
        (bytesPerPCMFrame == 0 || byteCount % bytesPerPCMFrame != 0)) {
        if (block) CFRelease(block);
        set_error(errorBuffer, errorBufferSize, "Source PCM packet does not contain whole audio frames");
        return PBFFmpegReadResultError;
    }
    CMItemCount sampleCount = isSourcePCM
        ? (CMItemCount)(byteCount / bytesPerPCMFrame)
        : 1;
    UInt32 framesPerPacket = audio_frames_per_packet(parameters);
    CMTime packetDuration = cm_time(packet->duration, reader->timeBase);
    CMTime duration = isSourcePCM
        ? CMTimeMake(1, parameters->sample_rate)
        : packet->duration > 0
        ? packetDuration
        : framesPerPacket > 0 && parameters->sample_rate > 0
        ? CMTimeMake(framesPerPacket, parameters->sample_rate)
        : kCMTimeInvalid;
    CMSampleTimingInfo timing = {
        .duration = duration,
        .presentationTimeStamp = cm_time(
            packet->pts == AV_NOPTS_VALUE
                ? AV_NOPTS_VALUE
                : packet->pts - reader->startTimestamp,
            reader->timeBase
        ),
        .decodeTimeStamp = cm_time(
            packet->dts == AV_NOPTS_VALUE
                ? AV_NOPTS_VALUE
                : packet->dts - reader->startTimestamp,
            reader->timeBase
        ),
    };
    size_t sampleSize = isSourcePCM ? bytesPerPCMFrame : byteCount;
    if (status == noErr) {
        status = CMSampleBufferCreateReady(
            kCFAllocatorDefault,
            block,
            reader->formatDescription,
            sampleCount,
            1,
            &timing,
            1,
            &sampleSize,
            sampleOut
        );
    }
    if (block) CFRelease(block);
    if (status != noErr) {
        char message[128];
        snprintf(message, sizeof(message), "Create audio CMSampleBuffer failed (%d)", (int)status);
        set_error(errorBuffer, errorBufferSize, message);
        return PBFFmpegReadResultError;
    }
    if (metadataOut) {
        metadataOut->packetPTS = originalPTS;
        metadataOut->packetDTS = originalDTS;
        metadataOut->packetDuration = originalDuration;
        metadataOut->timeBaseNumerator = reader->timeBase.num;
        metadataOut->timeBaseDenominator = reader->timeBase.den;
        metadataOut->payloadByteCount = byteCount;
        metadataOut->cookieSource = isSourcePCM
            ? PBFFmpegAudioCookieSourceUnavailable
            : cookieSource;
    }
    return PBFFmpegReadResultSample;
}

PBFFmpegReadResult PBFFmpegAudioReaderCopyNextSample(
    PBFFmpegAudioReader *reader,
    CMSampleBufferRef *sampleOut,
    PBFFmpegAudioSampleMetadata *metadataOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader == NULL || sampleOut == NULL) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg audio reader call");
        return PBFFmpegReadResultError;
    }
    *sampleOut = NULL;
    if (metadataOut) memset(metadataOut, 0, sizeof(*metadataOut));
    if (cancellation_requested(&reader->cancelled)) {
        return PBFFmpegReadResultCancelled;
    }
    AVStream *stream = reader->formatContext->streams[reader->audioStreamIndex];
    while (true) {
        if (cancellation_requested(&reader->cancelled)) {
            return PBFFmpegReadResultCancelled;
        }
        if (reader->bitstreamFilter) {
            int result = av_bsf_receive_packet(reader->bitstreamFilter, reader->filteredPacket);
            if (result == 0) {
                PBFFmpegReadResult readResult = create_audio_sample(
                    reader,
                    reader->filteredPacket,
                    reader->bitstreamFilter->par_out,
                    PBFFmpegAudioCookieSourceFilterOutput,
                    reader->pendingOriginalPTS,
                    reader->pendingOriginalDTS,
                    reader->pendingOriginalDuration,
                    sampleOut,
                    metadataOut,
                    errorBuffer,
                    errorBufferSize
                );
                av_packet_unref(reader->filteredPacket);
                return readResult;
            }
            if (result == AVERROR_EOF) return PBFFmpegReadResultEnd;
            if (result == AVERROR_INVALIDDATA) {
                av_packet_unref(reader->filteredPacket);
                av_bsf_flush(reader->bitstreamFilter);
                continue;
            }
            if (result != AVERROR(EAGAIN)) {
                set_av_error(errorBuffer, errorBufferSize, "Read filtered compressed audio packet", result);
                return PBFFmpegReadResultError;
            }
            if (reader->inputEnded) {
                if (!reader->filterDrained) {
                    result = av_bsf_send_packet(reader->bitstreamFilter, NULL);
                    reader->filterDrained = true;
                    if (result < 0 && result != AVERROR_EOF) {
                        set_av_error(errorBuffer, errorBufferSize, "Finish compressed audio filter", result);
                        return PBFFmpegReadResultError;
                    }
                    continue;
                }
                return PBFFmpegReadResultEnd;
            }
        }

        int result = av_read_frame(reader->formatContext, reader->packet);
        publish_source_bytes(&reader->sourceReadContext);
        if (result < 0) {
            if (result == AVERROR_EXIT || cancellation_requested(&reader->cancelled)) {
                return PBFFmpegReadResultCancelled;
            }
            reader->inputEnded = true;
            if (reader->bitstreamFilter) continue;
            return PBFFmpegReadResultEnd;
        }
        if (reader->packet->stream_index != reader->audioStreamIndex) {
            av_packet_unref(reader->packet);
            continue;
        }
        if (!reader->bitstreamFilter) {
            PBFFmpegReadResult readResult = create_audio_sample(
                reader,
                reader->packet,
                stream->codecpar,
                stream->codecpar->extradata_size > 0
                    ? PBFFmpegAudioCookieSourceExtradata
                    : PBFFmpegAudioCookieSourceSynthesized,
                reader->packet->pts,
                reader->packet->dts,
                reader->packet->duration,
                sampleOut,
                metadataOut,
                errorBuffer,
                errorBufferSize
            );
            av_packet_unref(reader->packet);
            return readResult;
        }
        reader->pendingOriginalPTS = reader->packet->pts;
        reader->pendingOriginalDTS = reader->packet->dts;
        reader->pendingOriginalDuration = reader->packet->duration;
        result = av_bsf_send_packet(reader->bitstreamFilter, reader->packet);
        av_packet_unref(reader->packet);
        if (result < 0) {
            if (result == AVERROR_INVALIDDATA) {
                av_bsf_flush(reader->bitstreamFilter);
                continue;
            }
            set_av_error(errorBuffer, errorBufferSize, "Filter compressed audio packet", result);
            return PBFFmpegReadResultError;
        }
    }
}

int PBFFmpegAudioReaderGetStreamIndex(const PBFFmpegAudioReader *reader) {
    return reader ? reader->audioStreamIndex : -1;
}

int PBFFmpegAudioReaderGetSampleRate(const PBFFmpegAudioReader *reader) {
    return reader ? reader->sampleRate : 0;
}

int PBFFmpegAudioReaderGetChannelCount(const PBFFmpegAudioReader *reader) {
    return reader ? reader->channelCount : 0;
}

const char *PBFFmpegAudioReaderGetCodecName(const PBFFmpegAudioReader *reader) {
    return reader ? reader->codecName : "unknown";
}

bool PBFFmpegAudioReaderOutputsPCM(const PBFFmpegAudioReader *reader) {
    return reader && reader->outputsPCM;
}

PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreate(
    const char *path,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    return PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
        path, streamIndex, errorBuffer, errorBufferSize, NULL
    );
}

PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
    const char *path,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize,
    PBFFmpegSourceReadMonitor *monitor
) {
    if (!path || streamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg subtitle reader call");
        return NULL;
    }
    PBFFmpegSubtitleReader *reader = calloc(1, sizeof(PBFFmpegSubtitleReader));
    if (!reader) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg subtitle reader");
        return NULL;
    }
    reader->subtitleStreamIndex = streamIndex;
    reader->sourceReadContext.monitor = monitor;
    reader->formatContext = allocate_format_context(
        NULL,
        &reader->sourceReadContext
    );
    if (!reader->formatContext) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg subtitle context");
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    int result = open_media_source(
        &reader->formatContext,
        path,
        &reader->sourceReadContext
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open subtitle media source", result);
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    result = read_stream_information(
        reader->formatContext,
        &reader->sourceReadContext,
        NULL
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read subtitle stream information", result);
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    if (streamIndex >= (int)reader->formatContext->nb_streams ||
        !subtitle_stream_is_supported(reader->formatContext->streams[streamIndex])) {
        set_error(
            errorBuffer,
            errorBufferSize,
            "The selected subtitle stream codec is unsupported"
        );
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    AVStream *stream = reader->formatContext->streams[streamIndex];
    reader->codecID = stream->codecpar->codec_id;
    reader->timeBase = stream->time_base;
    reader->startTimestamp = stream_start_timestamp(reader->formatContext, stream);
    const AVCodec *decoder = avcodec_find_decoder(reader->codecID);
    if (!decoder) {
        set_error(errorBuffer, errorBufferSize, "The selected subtitle decoder is unavailable");
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    reader->decoder = avcodec_alloc_context3(decoder);
    if (!reader->decoder) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg subtitle decoder");
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    result = avcodec_parameters_to_context(reader->decoder, stream->codecpar);
    if (result >= 0) {
        reader->decoder->pkt_timebase = stream->time_base;
        result = avcodec_open2(reader->decoder, decoder, NULL);
    }
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open FFmpeg subtitle decoder", result);
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    reader->packet = av_packet_alloc();
    if (!reader->packet) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg subtitle packet");
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    return reader;
}

void PBFFmpegSubtitleReaderDestroy(PBFFmpegSubtitleReader *reader) {
    if (!reader) return;
    av_packet_free(&reader->packet);
    avcodec_free_context(&reader->decoder);
    close_media_source(&reader->formatContext, &reader->sourceReadContext);
    free(reader);
}

static CFStringRef decoded_ass_plain_text(const char *ass) {
    const char *body = ass;
    int commas = 0;
    while (*body && commas < 8) {
        if (*body++ == ',') commas++;
    }
    size_t length = strlen(body);
    char *plain = calloc(length + 1, 1);
    if (!plain) return NULL;
    size_t output = 0;
    bool inOverride = false;
    for (size_t index = 0; index < length; index++) {
        char value = body[index];
        if (value == '{') {
            inOverride = true;
            continue;
        }
        if (value == '}' && inOverride) {
            inOverride = false;
            continue;
        }
        if (inOverride) continue;
        if (value == '\\' && index + 1 < length) {
            char escaped = body[index + 1];
            if (escaped == 'N' || escaped == 'n') {
                plain[output++] = '\n';
                index++;
                continue;
            }
            if (escaped == 'h') {
                plain[output++] = ' ';
                index++;
                continue;
            }
        }
        plain[output++] = value;
    }
    CFStringRef text = CFStringCreateWithCString(
        kCFAllocatorDefault,
        plain,
        kCFStringEncodingUTF8
    );
    free(plain);
    return text;
}

static CFStringRef subtitle_text(const AVSubtitle *subtitle) {
    CFMutableStringRef text = CFStringCreateMutable(kCFAllocatorDefault, 0);
    if (!text) return NULL;
    for (unsigned int index = 0; index < subtitle->num_rects; index++) {
        AVSubtitleRect *rect = subtitle->rects[index];
        if (!rect) continue;
        CFStringRef part = rect->text
            ? CFStringCreateWithCString(
                kCFAllocatorDefault,
                rect->text,
                kCFStringEncodingUTF8
            )
            : (rect->ass ? decoded_ass_plain_text(rect->ass) : NULL);
        if (!part) continue;
        if (CFStringGetLength(text) > 0) CFStringAppend(text, CFSTR("\n"));
        CFStringAppend(text, part);
        CFRelease(part);
    }
    return text;
}

PBFFmpegReadResult PBFFmpegSubtitleReaderCopyNextCue(
    PBFFmpegSubtitleReader *reader,
    double *startSecondsOut,
    double *durationSecondsOut,
    CFStringRef *textOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!reader || !startSecondsOut || !durationSecondsOut || !textOut) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg subtitle reader call");
        return PBFFmpegReadResultError;
    }
    *textOut = NULL;
    while (av_read_frame(reader->formatContext, reader->packet) >= 0) {
        publish_source_bytes(&reader->sourceReadContext);
        if (reader->packet->stream_index != reader->subtitleStreamIndex) {
            av_packet_unref(reader->packet);
            continue;
        }
        if (reader->packet->size <= 0 || !reader->packet->data) {
            av_packet_unref(reader->packet);
            continue;
        }
        int64_t timestamp = reader->packet->pts != AV_NOPTS_VALUE
            ? reader->packet->pts
            : reader->packet->dts;
        double packetStart = timestamp != AV_NOPTS_VALUE
            ? (double)(timestamp - reader->startTimestamp) * av_q2d(reader->timeBase)
            : 0;
        AVSubtitle subtitle = {0};
        int produced = 0;
        double packetDuration = reader->packet->duration > 0
            ? reader->packet->duration * av_q2d(reader->timeBase)
            : 60.0;
        int result = avcodec_decode_subtitle2(
            reader->decoder,
            &subtitle,
            &produced,
            reader->packet
        );
        if (result < 0) {
            av_packet_unref(reader->packet);
            set_av_error(errorBuffer, errorBufferSize, "Decode FFmpeg subtitle cue", result);
            return PBFFmpegReadResultError;
        }
        av_packet_unref(reader->packet);
        if (!produced || subtitle.num_rects == 0) {
            avsubtitle_free(&subtitle);
            continue;
        }
        double start = packetStart + subtitle.start_display_time / 1000.0;
        double end = packetStart + subtitle.end_display_time / 1000.0;
        if (end <= start) {
            end = start + packetDuration;
        }
        CFStringRef text = subtitle_text(&subtitle);
        avsubtitle_free(&subtitle);
        if (!text) {
            set_error(errorBuffer, errorBufferSize, "Create decoded subtitle cue text");
            return PBFFmpegReadResultError;
        }
        *startSecondsOut = start;
        *durationSecondsOut = end - start;
        *textOut = text;
        return PBFFmpegReadResultSample;
    }
    return PBFFmpegReadResultEnd;
}
