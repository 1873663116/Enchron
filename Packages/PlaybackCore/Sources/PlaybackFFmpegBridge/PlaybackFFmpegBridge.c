#include "PlaybackFFmpegBridge.h"
#include "PlaybackFFmpegBridgeInternal.h"

#include <AudioToolbox/AudioToolbox.h>
#include <errno.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavformat/avformat.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/avutil.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/mastering_display_metadata.h>
#include <libavutil/mem.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libavutil/spherical.h>
#include <libavutil/stereo3d.h>
#include <libswresample/swresample.h>
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <stddef.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

struct PBFFmpegSourceReadMonitor {
    atomic_uint_fast64_t totalBytesRead;
    atomic_bool interrupted;
};

struct PBFFmpegReadCancellation {
    atomic_bool cancelled;
};

typedef struct {
    PBFFmpegSourceReadMonitor *monitor;
    atomic_bool *cancelled;
    AVFormatContext *formatContext;
    int64_t accountedBytesRead;
} PBFFmpegSourceReadContext;

typedef struct PBFFmpegPacketNode {
    AVPacket packet;
    int64_t timestampMicroseconds;
    int64_t durationMicroseconds;
    int64_t byteCount;
    struct PBFFmpegPacketNode *next;
} PBFFmpegPacketNode;

enum { PB_PACKET_NODE_POOL_CHUNK_SIZE = 256 };
enum { PB_AUDIO_PACKET_BATCH_LIMIT = 256 };
enum { PB_TRUEHD_DECODER_PACKET_BATCH_LIMIT = 120 };
static const int64_t PB_AUDIO_PACKET_BATCH_DURATION_MICROSECONDS =
    AV_TIME_BASE / 4;

typedef struct PBFFmpegPacketNodePoolChunk {
    PBFFmpegPacketNode nodes[PB_PACKET_NODE_POOL_CHUNK_SIZE];
    struct PBFFmpegPacketNodePoolChunk *next;
} PBFFmpegPacketNodePoolChunk;

typedef struct {
    PBFFmpegPacketNode *head;
    PBFFmpegPacketNode *tail;
    unsigned int subscribers;
    unsigned int waiters;
    int64_t summedDurationMicroseconds;
    int64_t bufferedDurationMicroseconds;
    int64_t bufferedByteCount;
    bool isAuxiliary;
    uint64_t droppedPacketCount;
} PBFFmpegPacketQueue;

struct PBFFmpegDemuxSource {
    atomic_bool interrupted;
    atomic_bool permanentlyInterrupted;
    pthread_mutex_t lock;
    pthread_cond_t changed;
    pthread_t readThread;
    bool readThreadStarted;
    bool stopsReadThread;
    bool reachedEnd;
    int readResult;
    PBFFmpegSourceReadContext readContexts[2];
    PBFFmpegSourceReadContext *sourceReadContext;
    AVFormatContext *formatContext;
    PBFFmpegPacketQueue *queues;
    unsigned int queueCount;
    int64_t retainedByteCount;
    int videoStreamIndex;
    char *path;
    bool prebuffersAudio;
    bool isRemote;
    int64_t knownByteLength;
    int64_t *lastQueuedTimestamps;
    int64_t *replayThroughTimestamps;
    bool *replayCaughtUp;
    PBFFmpegDemuxBufferConfiguration bufferConfiguration;
    int64_t forwardBufferedByteCount;
    int64_t auxiliaryBufferedByteCount;
    PBFFmpegPacketNode *freePacketNodes;
    PBFFmpegPacketNodePoolChunk *packetNodePoolChunks;
    unsigned int reconnectAttemptCount;
    uint64_t readFrameCount;
};

static const int64_t PB_DEMUX_DEFAULT_FORWARD_BYTE_LIMIT = 150LL * 1024 * 1024;
static const int64_t PB_DEMUX_DEFAULT_BACKWARD_BYTE_LIMIT = 50LL * 1024 * 1024;
static const double PB_DEMUX_DEFAULT_NON_CACHE_TARGET_SECONDS = 1.0;
static const double PB_DEMUX_UNCAPPED_CACHE_TARGET_SECONDS = 1000.0 * 60 * 60;
static const long PB_DEMUX_RECONNECT_BACKOFF_MILLISECONDS[] = {250, 500, 1000};
static const unsigned int PB_DEMUX_RECONNECT_ATTEMPT_LIMIT =
    sizeof(PB_DEMUX_RECONNECT_BACKOFF_MILLISECONDS) /
    sizeof(PB_DEMUX_RECONNECT_BACKOFF_MILLISECONDS[0]);

const char *PBFFmpegBuildConfiguration(void) {
    return avformat_configuration();
}

PBFFmpegDemuxBufferConfiguration PBFFmpegDemuxBufferConfigurationMake(
    PBFFmpegDemuxBufferMode mode,
    int64_t explicitForwardByteLimit
) {
    PBFFmpegDemuxBufferConfiguration configuration = {
        .mode = mode,
        .forwardByteLimit = PB_DEMUX_DEFAULT_FORWARD_BYTE_LIMIT,
        .backwardByteLimit = PB_DEMUX_DEFAULT_BACKWARD_BYTE_LIMIT,
        .targetDurationSeconds = mode == PBFFmpegDemuxBufferModeNone
            ? PB_DEMUX_DEFAULT_NON_CACHE_TARGET_SECONDS
            : PB_DEMUX_UNCAPPED_CACHE_TARGET_SECONDS,
    };
    if (mode == PBFFmpegDemuxBufferModeBytes) {
        configuration.forwardByteLimit = explicitForwardByteLimit;
    }
    return configuration;
}

typedef struct {
    bool movFamily;
    bool skippedProbe;
} PBStreamInformationRead;

static int read_stream_information(
    AVFormatContext *context,
    PBFFmpegSourceReadContext *sourceReadContext,
    PBStreamInformationRead *readOut
);
static int open_media_source(
    AVFormatContext **context,
    const char *path,
    PBFFmpegSourceReadContext *sourceReadContext
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
    bool containerSupportsSourceFormatDescription;
    int dolbyVisionProfile;
    int dolbyVisionCrossCompatibilityID;
    bool dolbyVisionHasEnhancementLayer;
    bool hasStereoVideoEnhancementLayer;
    int streamCount;
    PBFFmpegMediaStreamStorage *streams;
};

struct PBFFmpegReader {
    atomic_bool cancelled;
    PBFFmpegSourceReadContext sourceReadContext;
    AVFormatContext *formatContext;
    PBFFmpegDemuxSource *demuxSource;
    AVPacket *packet;
    AVPacket *filteredPacket;
    AVBSFContext *dolbyVisionSplitFilter;
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
    bool unsupportedVideoCodec;
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
    bool reordersProfile7BaseLayerParameterSets;
    size_t hevcNALLengthSize;
    uint8_t *pendingHEVCParameterSets;
    size_t pendingHEVCParameterSetSize;
    bool inputEnded;
    bool filterDrained;
    PBFFmpegActiveFailureCause lastActiveFailureCause;
};

struct PBFFmpegAudioReader {
    atomic_bool cancelled;
    PBFFmpegSourceReadContext sourceReadContext;
    AVFormatContext *formatContext;
    PBFFmpegDemuxSource *demuxSource;
    PBFFmpegPacketNode *demuxPacketBatch;
    PBFFmpegPacketNode *consumedDemuxPacketBatch;
    AVPacket *packet;
    AVPacket *decoderBatchPacket;
    AVCodecContext *decoder;
    AVFrame *decodedFrame;
    SwrContext *resampler;
    AVChannelLayout outputChannelLayout;
    int audioStreamIndex;
    AVRational timeBase;
    int64_t startTimestamp;
    int sampleRate;
    int channelCount;
    bool inputEnded;
    int inputReadResult;
    bool decoderDrained;
    bool outputsPCM;
    int64_t nextPCMSample;
    uint8_t *pendingPCMData;
    size_t pendingPCMByteCount;
    size_t pendingPCMCapacity;
    int pendingPCMFrameCount;
    int64_t pendingPCMStartSample;
    PBFFmpegAudioSampleMetadata pendingPCMMetadata;
    AVAudioFifo *decodedAudioFifo;
    uint8_t **decodedBatchData;
    int decodedBatchCapacity;
    enum AVSampleFormat decodedInputFormat;
    int64_t decodedFifoStartSample;
    int64_t decodedFifoStartTimestamp;
    CMAudioFormatDescriptionRef formatDescription;
    char codecName[64];
    AVCodecParameters *codecParameters;
    uint64_t trueHDDecoderInputPacketCount;
    uint64_t trueHDDecoderBatchCount;
    uint64_t trueHDAggregatedDecoderBatchCount;
    uint64_t trueHDOutputSampleBufferCount;
    uint32_t trueHDLastDecoderBatchInputPacketCount;
    PBFFmpegActiveFailureCause lastActiveFailureCause;
};

static void publish_source_bytes(PBFFmpegSourceReadContext *context) {
    if (!context || !context->monitor) return;
    AVIOContext *meteredIO = context->formatContext
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
    if (context && context->monitor &&
        atomic_load_explicit(&context->monitor->interrupted, memory_order_relaxed)) {
        return 1;
    }
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
}

PBFFmpegReadCancellation *PBFFmpegReadCancellationCreate(void) {
    PBFFmpegReadCancellation *cancellation = calloc(1, sizeof(PBFFmpegReadCancellation));
    if (!cancellation) return NULL;
    atomic_init(&cancellation->cancelled, false);
    return cancellation;
}

void PBFFmpegReadCancellationCancel(PBFFmpegReadCancellation *cancellation) {
    if (!cancellation) return;
    atomic_store_explicit(&cancellation->cancelled, true, memory_order_relaxed);
}

void PBFFmpegReadCancellationDestroy(PBFFmpegReadCancellation *cancellation) {
    free(cancellation);
}

PBFFmpegSourceReadMonitor *PBFFmpegSourceReadMonitorCreate(void) {
    PBFFmpegSourceReadMonitor *monitor = calloc(1, sizeof(PBFFmpegSourceReadMonitor));
    if (!monitor) return NULL;
    atomic_init(&monitor->totalBytesRead, 0);
    atomic_init(&monitor->interrupted, false);
    return monitor;
}

void PBFFmpegSourceReadMonitorInterrupt(PBFFmpegSourceReadMonitor *monitor) {
    if (!monitor) return;
    atomic_store_explicit(&monitor->interrupted, true, memory_order_seq_cst);
}

void PBFFmpegSourceReadMonitorDestroy(PBFFmpegSourceReadMonitor *monitor) {
    free(monitor);
}

uint64_t PBFFmpegSourceReadMonitorGetTotalBytesRead(
    const PBFFmpegSourceReadMonitor *monitor
) {
    return monitor
        ? atomic_load_explicit(&monitor->totalBytesRead, memory_order_relaxed)
        : 0;
}

static PBFFmpegPacketNode *take_packet_node(PBFFmpegDemuxSource *source) {
    if (!source) return NULL;
    if (!source->freePacketNodes) {
        PBFFmpegPacketNodePoolChunk *chunk = calloc(1, sizeof(*chunk));
        if (!chunk) return NULL;
        chunk->next = source->packetNodePoolChunks;
        source->packetNodePoolChunks = chunk;
        for (size_t index = 0; index < PB_PACKET_NODE_POOL_CHUNK_SIZE; index++) {
            chunk->nodes[index].next = source->freePacketNodes;
            source->freePacketNodes = &chunk->nodes[index];
        }
    }
    PBFFmpegPacketNode *node = source->freePacketNodes;
    source->freePacketNodes = node->next;
    node->next = NULL;
    node->timestampMicroseconds = AV_NOPTS_VALUE;
    node->durationMicroseconds = 0;
    return node;
}

static void return_packet_node(
    PBFFmpegDemuxSource *source,
    PBFFmpegPacketNode *node
) {
    if (!source || !node) return;
    av_packet_unref(&node->packet);
    node->byteCount = 0;
    node->next = source->freePacketNodes;
    source->freePacketNodes = node;
}

static int64_t *packet_queue_byte_pool(
    PBFFmpegDemuxSource *source,
    const PBFFmpegPacketQueue *queue
) {
    if (queue->subscribers == 0) return &source->retainedByteCount;
    return queue->isAuxiliary
        ? &source->auxiliaryBufferedByteCount
        : &source->forwardBufferedByteCount;
}

static void release_packet_queue_bytes(
    PBFFmpegDemuxSource *source,
    PBFFmpegPacketQueue *queue,
    int64_t byteCount
) {
    int64_t *pool = packet_queue_byte_pool(source, queue);
    *pool -= byteCount;
    if (*pool < 0) *pool = 0;
    queue->bufferedByteCount -= byteCount;
    if (queue->bufferedByteCount < 0) queue->bufferedByteCount = 0;
}

static void clear_packet_queue(
    PBFFmpegDemuxSource *source,
    PBFFmpegPacketQueue *queue
) {
    if (!queue) return;
    PBFFmpegPacketNode *node = queue->head;
    while (node) {
        PBFFmpegPacketNode *next = node->next;
        return_packet_node(source, node);
        node = next;
    }
    queue->head = NULL;
    queue->tail = NULL;
    queue->summedDurationMicroseconds = 0;
    queue->bufferedDurationMicroseconds = 0;
    release_packet_queue_bytes(source, queue, queue->bufferedByteCount);
    queue->bufferedByteCount = 0;
}

static void update_packet_queue_buffered_duration(PBFFmpegPacketQueue *queue) {
    if (!queue || !queue->head || !queue->tail) {
        if (queue) queue->bufferedDurationMicroseconds = 0;
        return;
    }
    int64_t timestampSpan = 0;
    if (queue->head->timestampMicroseconds != AV_NOPTS_VALUE &&
        queue->tail->timestampMicroseconds != AV_NOPTS_VALUE &&
        queue->tail->timestampMicroseconds >= queue->head->timestampMicroseconds) {
        timestampSpan = queue->tail->timestampMicroseconds -
            queue->head->timestampMicroseconds +
            queue->tail->durationMicroseconds;
    }
    queue->bufferedDurationMicroseconds = FFMAX(
        queue->summedDurationMicroseconds,
        timestampSpan
    );
}

static const int64_t PB_DEMUX_AUXILIARY_BYTE_LIMIT = 16LL * 1024 * 1024;

static bool demux_source_needs_more_data(const PBFFmpegDemuxSource *source) {
    if (source->forwardBufferedByteCount >=
        source->bufferConfiguration.forwardByteLimit) return false;
    int64_t targetDurationMicroseconds = (int64_t)llround(
        source->bufferConfiguration.targetDurationSeconds * AV_TIME_BASE
    );
    for (unsigned int index = 0; index < source->queueCount; index++) {
        const PBFFmpegPacketQueue *queue = &source->queues[index];
        if (queue->subscribers == 0) continue;
        if (queue->bufferedDurationMicroseconds >=
            targetDurationMicroseconds) continue;
        if (queue->isAuxiliary &&
            source->auxiliaryBufferedByteCount >=
                PB_DEMUX_AUXILIARY_BYTE_LIMIT) continue;
        return true;
    }
    return false;
}

static const int64_t PB_DEMUX_RETAINED_WINDOW_MICROSECONDS =
    300LL * AV_TIME_BASE;

static void trim_retained_packet_queue(
    PBFFmpegDemuxSource *source,
    PBFFmpegPacketQueue *queue
) {
    if (!queue || queue->subscribers > 0) return;
    while (queue->head && queue->head != queue->tail) {
        bool agedOut = queue->head->timestampMicroseconds != AV_NOPTS_VALUE &&
            queue->tail->timestampMicroseconds != AV_NOPTS_VALUE &&
            queue->tail->timestampMicroseconds - queue->head->timestampMicroseconds >
                PB_DEMUX_RETAINED_WINDOW_MICROSECONDS;
        bool overBudget = source->retainedByteCount >
            source->bufferConfiguration.backwardByteLimit;
        if (!agedOut && !overBudget) break;
        PBFFmpegPacketNode *node = queue->head;
        queue->head = node->next;
        queue->summedDurationMicroseconds -= node->durationMicroseconds;
        if (queue->summedDurationMicroseconds < 0) {
            queue->summedDurationMicroseconds = 0;
        }
        release_packet_queue_bytes(source, queue, node->byteCount);
        return_packet_node(source, node);
    }
    update_packet_queue_buffered_duration(queue);
}

static void trim_auxiliary_packet_queue(
    PBFFmpegDemuxSource *source,
    PBFFmpegPacketQueue *queue
) {
    if (!queue || queue->subscribers == 0 || !queue->isAuxiliary) return;
    while (queue->head && queue->head != queue->tail &&
           source->auxiliaryBufferedByteCount > PB_DEMUX_AUXILIARY_BYTE_LIMIT) {
        PBFFmpegPacketNode *node = queue->head;
        queue->head = node->next;
        queue->summedDurationMicroseconds -= node->durationMicroseconds;
        if (queue->summedDurationMicroseconds < 0) {
            queue->summedDurationMicroseconds = 0;
        }
        release_packet_queue_bytes(source, queue, node->byteCount);
        return_packet_node(source, node);
        queue->droppedPacketCount++;
    }
    update_packet_queue_buffered_duration(queue);
}

static int64_t packet_timestamp_microseconds(
    const PBFFmpegDemuxSource *source,
    const AVPacket *packet
) {
    if (!source || !source->formatContext || !packet || packet->stream_index < 0 ||
        (unsigned int)packet->stream_index >= source->formatContext->nb_streams) {
        return AV_NOPTS_VALUE;
    }
    int64_t timestamp = packet->dts != AV_NOPTS_VALUE ? packet->dts : packet->pts;
    if (timestamp == AV_NOPTS_VALUE) return AV_NOPTS_VALUE;
    return av_rescale_q(
        timestamp,
        source->formatContext->streams[packet->stream_index]->time_base,
        AV_TIME_BASE_Q
    );
}

static int64_t packet_duration_microseconds(
    const PBFFmpegDemuxSource *source,
    const AVPacket *packet
) {
    if (!source || !source->formatContext || !packet || packet->duration <= 0 ||
        packet->stream_index < 0 ||
        (unsigned int)packet->stream_index >= source->formatContext->nb_streams) return 0;
    return av_rescale_q(
        packet->duration,
        source->formatContext->streams[packet->stream_index]->time_base,
        AV_TIME_BASE_Q
    );
}

static bool demux_source_reached_known_end(const PBFFmpegDemuxSource *source) {
    if (!source || source->knownByteLength <= 0 || !source->formatContext ||
        !source->formatContext->pb) return false;
    return source->formatContext->pb->error >= 0;
}

static bool wait_for_reconnect_backoff(
    PBFFmpegDemuxSource *source,
    long milliseconds
) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += milliseconds / 1000;
    deadline.tv_nsec += (milliseconds % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec++;
        deadline.tv_nsec -= 1000000000L;
    }
    pthread_mutex_lock(&source->lock);
    while (!source->stopsReadThread) {
        int result = pthread_cond_timedwait(&source->changed, &source->lock, &deadline);
        if (result == ETIMEDOUT) break;
    }
    bool continues = !source->stopsReadThread;
    pthread_mutex_unlock(&source->lock);
    return continues;
}

static int64_t demux_source_resume_timestamp(
    const PBFFmpegDemuxSource *source
) {
    int64_t resume = AV_NOPTS_VALUE;
    for (unsigned int index = 0; index < source->queueCount; index++) {
        int64_t timestamp = source->lastQueuedTimestamps[index];
        if (timestamp != AV_NOPTS_VALUE &&
            (resume == AV_NOPTS_VALUE || timestamp < resume)) resume = timestamp;
    }
    return resume;
}

static int reopen_demux_source(PBFFmpegDemuxSource *source) {
    int64_t resumeTimestamp = demux_source_resume_timestamp(source);
    PBFFmpegSourceReadContext *replacementReadContext =
        source->sourceReadContext == &source->readContexts[0]
            ? &source->readContexts[1]
            : &source->readContexts[0];
    memset(replacementReadContext, 0, sizeof(*replacementReadContext));
    replacementReadContext->monitor = source->sourceReadContext->monitor;
    AVFormatContext *replacement = allocate_format_context(
        &source->interrupted,
        replacementReadContext
    );
    if (!replacement) return AVERROR(ENOMEM);
    int result = open_media_source(
        &replacement,
        source->path,
        replacementReadContext
    );
    if (result >= 0) {
        result = read_stream_information(
            replacement,
            replacementReadContext,
            NULL
        );
    }
    if (result >= 0 && replacement->nb_streams != source->queueCount) {
        result = AVERROR_INVALIDDATA;
    }
    int64_t knownByteLength = source->knownByteLength;
    if (result >= 0) {
        int64_t length = replacement->pb
            ? avio_size(replacement->pb)
            : AVERROR(ENOSYS);
        if (length > 0) knownByteLength = length;
    }
    if (result >= 0 && resumeTimestamp != AV_NOPTS_VALUE) {
        result = avformat_seek_file(
            replacement,
            -1,
            INT64_MIN,
            resumeTimestamp,
            INT64_MAX,
            AVSEEK_FLAG_BACKWARD
        );
        publish_source_bytes(replacementReadContext);
    }
    if (result < 0) {
        close_media_source(&replacement, replacementReadContext);
        return result;
    }
    pthread_mutex_lock(&source->lock);
    AVFormatContext *previous = source->formatContext;
    PBFFmpegSourceReadContext *previousReadContext = source->sourceReadContext;
    source->formatContext = replacement;
    source->sourceReadContext = replacementReadContext;
    source->knownByteLength = knownByteLength;
    for (unsigned int index = 0; index < source->queueCount; index++) {
        source->replayThroughTimestamps[index] = source->lastQueuedTimestamps[index];
        source->replayCaughtUp[index] =
            source->replayThroughTimestamps[index] == AV_NOPTS_VALUE;
    }
    pthread_mutex_unlock(&source->lock);
    close_media_source(&previous, previousReadContext);
    return 0;
}

static void *demux_source_read_loop(void *opaque) {
    PBFFmpegDemuxSource *source = opaque;
    AVPacket *packet = av_packet_alloc();
    if (!packet) {
        pthread_mutex_lock(&source->lock);
        source->readResult = AVERROR(ENOMEM);
        source->reachedEnd = true;
        pthread_cond_broadcast(&source->changed);
        pthread_mutex_unlock(&source->lock);
        return NULL;
    }
    unsigned int consecutiveReconnectAttempts = 0;
    while (true) {
        pthread_mutex_lock(&source->lock);
        while (!source->stopsReadThread &&
               !source->reachedEnd &&
               !demux_source_needs_more_data(source)) {
            pthread_cond_wait(&source->changed, &source->lock);
        }
        bool stop = source->stopsReadThread || source->reachedEnd;
        pthread_mutex_unlock(&source->lock);
        if (stop) break;

        int result = av_read_frame(source->formatContext, packet);
        publish_source_bytes(source->sourceReadContext);

        pthread_mutex_lock(&source->lock);
        source->readFrameCount++;
        if (source->stopsReadThread) {
            av_packet_unref(packet);
            pthread_cond_broadcast(&source->changed);
            pthread_mutex_unlock(&source->lock);
            break;
        }
        if (result < 0) {
            bool reachedEnd = result == AVERROR_EOF &&
                demux_source_reached_known_end(source);
            bool retries = source->isRemote && !reachedEnd;
            pthread_mutex_unlock(&source->lock);
            if (retries) {
                bool reconnected = false;
                while (consecutiveReconnectAttempts <
                       PB_DEMUX_RECONNECT_ATTEMPT_LIMIT) {
                    long backoff = PB_DEMUX_RECONNECT_BACKOFF_MILLISECONDS[
                        consecutiveReconnectAttempts
                    ];
                    consecutiveReconnectAttempts++;
                    pthread_mutex_lock(&source->lock);
                    source->reconnectAttemptCount++;
                    pthread_mutex_unlock(&source->lock);
                    if (!wait_for_reconnect_backoff(source, backoff)) break;
                    int reconnectResult = reopen_demux_source(source);
                    if (reconnectResult >= 0) {
                        reconnected = true;
                        break;
                    }
                    result = reconnectResult;
                }
                if (reconnected) continue;
                pthread_mutex_lock(&source->lock);
                if (source->stopsReadThread) {
                    pthread_mutex_unlock(&source->lock);
                    break;
                }
                pthread_mutex_unlock(&source->lock);
            }
            pthread_mutex_lock(&source->lock);
            source->readResult = reachedEnd
                ? AVERROR_EOF
                : (result == AVERROR_EOF ? AVERROR(EIO) : result);
            source->reachedEnd = true;
            pthread_cond_broadcast(&source->changed);
            pthread_mutex_unlock(&source->lock);
            break;
        }
        if (packet->stream_index >= 0 &&
            (unsigned int)packet->stream_index < source->queueCount) {
            int64_t timestamp = packet_timestamp_microseconds(source, packet);
            unsigned int streamIndex = (unsigned int)packet->stream_index;
            if (!source->replayCaughtUp[streamIndex]) {
                int64_t replayThrough = source->replayThroughTimestamps[streamIndex];
                if (timestamp != AV_NOPTS_VALUE && timestamp <= replayThrough) {
                    av_packet_unref(packet);
                    pthread_cond_broadcast(&source->changed);
                    pthread_mutex_unlock(&source->lock);
                    continue;
                }
                source->replayCaughtUp[streamIndex] = true;
            }
            consecutiveReconnectAttempts = 0;
            PBFFmpegPacketQueue *queue = &source->queues[packet->stream_index];
            bool prebuffersAudio = source->prebuffersAudio &&
                source->formatContext->streams[packet->stream_index]
                    ->codecpar->codec_type == AVMEDIA_TYPE_AUDIO;
            bool prebuffersSubtitle = source->formatContext
                ->streams[packet->stream_index]->codecpar->codec_type ==
                    AVMEDIA_TYPE_SUBTITLE;
            if (queue->subscribers > 0 || prebuffersAudio || prebuffersSubtitle) {
                PBFFmpegPacketNode *node = take_packet_node(source);
                if (!node) {
                    source->readResult = AVERROR(ENOMEM);
                    source->reachedEnd = true;
                } else {
                    node->timestampMicroseconds = timestamp;
                    node->durationMicroseconds =
                        packet_duration_microseconds(source, packet);
                    node->byteCount = FFMAX(packet->size, 0);
                    av_packet_move_ref(&node->packet, packet);
                    if (queue->tail) {
                        queue->tail->next = node;
                    } else {
                        queue->head = node;
                    }
                    queue->tail = node;
                    queue->summedDurationMicroseconds +=
                        node->durationMicroseconds;
                    queue->bufferedByteCount += node->byteCount;
                    *packet_queue_byte_pool(source, queue) += node->byteCount;
                    update_packet_queue_buffered_duration(queue);
                    trim_retained_packet_queue(source, queue);
                    trim_auxiliary_packet_queue(source, queue);
                    source->lastQueuedTimestamps[streamIndex] = timestamp;
                }
            }
        }
        av_packet_unref(packet);
        pthread_cond_broadcast(&source->changed);
        pthread_mutex_unlock(&source->lock);
    }
    av_packet_free(&packet);
    return NULL;
}

static bool start_demux_source_read_thread(PBFFmpegDemuxSource *source) {
    if (source->readThreadStarted) return true;
    source->stopsReadThread = false;
    if (pthread_create(
            &source->readThread,
            NULL,
            demux_source_read_loop,
            source
        ) != 0) return false;
    source->readThreadStarted = true;
    return true;
}

static void stop_demux_source_read_thread(PBFFmpegDemuxSource *source) {
    pthread_mutex_lock(&source->lock);
    bool join = source->readThreadStarted;
    source->stopsReadThread = true;
    atomic_store_explicit(&source->interrupted, true, memory_order_relaxed);
    pthread_cond_broadcast(&source->changed);
    pthread_mutex_unlock(&source->lock);
    if (join) pthread_join(source->readThread, NULL);
    pthread_mutex_lock(&source->lock);
    source->readThreadStarted = false;
    atomic_store_explicit(&source->interrupted, false, memory_order_seq_cst);
    if (atomic_load_explicit(
            &source->permanentlyInterrupted,
            memory_order_seq_cst
        )) {
        atomic_store_explicit(&source->interrupted, true, memory_order_seq_cst);
    }
    pthread_mutex_unlock(&source->lock);
}

static bool subscribe_to_demux_stream(
    PBFFmpegDemuxSource *source,
    int streamIndex
) {
    if (!source || streamIndex < 0 ||
        (unsigned int)streamIndex >= source->queueCount) return false;
    pthread_mutex_lock(&source->lock);
    PBFFmpegPacketQueue *queue = &source->queues[streamIndex];
    bool subscribed = queue->subscribers == 0;
    if (subscribed) {
        source->retainedByteCount -= queue->bufferedByteCount;
        if (source->retainedByteCount < 0) source->retainedByteCount = 0;
        queue->subscribers = 1;
        *packet_queue_byte_pool(source, queue) += queue->bufferedByteCount;
    }
    pthread_mutex_unlock(&source->lock);
    return subscribed;
}

static bool begin_demux_source_prefetch(PBFFmpegDemuxSource *source) {
    if (!source) return false;
    pthread_mutex_lock(&source->lock);
    bool started = start_demux_source_read_thread(source);
    pthread_cond_broadcast(&source->changed);
    pthread_mutex_unlock(&source->lock);
    return started;
}

static void unsubscribe_from_demux_stream(
    PBFFmpegDemuxSource *source,
    int streamIndex
) {
    if (!source || streamIndex < 0 ||
        (unsigned int)streamIndex >= source->queueCount) return;
    pthread_mutex_lock(&source->lock);
    PBFFmpegPacketQueue *queue = &source->queues[streamIndex];
    clear_packet_queue(source, queue);
    queue->subscribers = 0;
    source->lastQueuedTimestamps[streamIndex] = AV_NOPTS_VALUE;
    source->replayThroughTimestamps[streamIndex] = AV_NOPTS_VALUE;
    source->replayCaughtUp[streamIndex] = true;
    pthread_cond_broadcast(&source->changed);
    pthread_mutex_unlock(&source->lock);
}

static void dequeue_demux_packet_locked(
    PBFFmpegDemuxSource *source,
    PBFFmpegPacketQueue *queue,
    AVPacket *packet
) {
    PBFFmpegPacketNode *node = queue->head;
    queue->head = node->next;
    if (!queue->head) queue->tail = NULL;
    queue->summedDurationMicroseconds -= node->durationMicroseconds;
    if (queue->summedDurationMicroseconds < 0) {
        queue->summedDurationMicroseconds = 0;
    }
    release_packet_queue_bytes(source, queue, node->byteCount);
    update_packet_queue_buffered_duration(queue);
    av_packet_move_ref(packet, &node->packet);
    return_packet_node(source, node);
}

static int copy_next_demux_packet(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    atomic_bool *cancelled,
    AVPacket *packet
) {
    if (!source || !packet || streamIndex < 0 ||
        (unsigned int)streamIndex >= source->queueCount) return AVERROR(EINVAL);
    pthread_mutex_lock(&source->lock);
    PBFFmpegPacketQueue *queue = &source->queues[streamIndex];
    queue->waiters++;
    if (!start_demux_source_read_thread(source)) {
        queue->waiters--;
        pthread_mutex_unlock(&source->lock);
        return AVERROR(ENOMEM);
    }
    pthread_cond_broadcast(&source->changed);
    while (!queue->head && !source->reachedEnd &&
           !cancellation_requested(cancelled)) {
        pthread_cond_wait(&source->changed, &source->lock);
    }
    queue->waiters--;
    if (cancellation_requested(cancelled)) {
        pthread_mutex_unlock(&source->lock);
        return AVERROR_EXIT;
    }
    if (!queue->head) {
        int result = source->readResult < 0 ? source->readResult : AVERROR_EOF;
        pthread_mutex_unlock(&source->lock);
        return result;
    }
    dequeue_demux_packet_locked(source, queue, packet);
    pthread_cond_broadcast(&source->changed);
    pthread_mutex_unlock(&source->lock);
    return 0;
}

static int copy_next_demux_packet_if_available(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    AVPacket *packet
) {
    if (!source || !packet || streamIndex < 0 ||
        (unsigned int)streamIndex >= source->queueCount) return AVERROR(EINVAL);
    pthread_mutex_lock(&source->lock);
    PBFFmpegPacketQueue *queue = &source->queues[streamIndex];
    if (!queue->head) {
        int result;
        if (source->reachedEnd) {
            result = source->readResult < 0 ? source->readResult : AVERROR_EOF;
        } else if (!start_demux_source_read_thread(source)) {
            result = AVERROR(ENOMEM);
        } else {
            result = AVERROR(EAGAIN);
            pthread_cond_broadcast(&source->changed);
        }
        pthread_mutex_unlock(&source->lock);
        return result;
    }
    dequeue_demux_packet_locked(source, queue, packet);
    pthread_cond_broadcast(&source->changed);
    pthread_mutex_unlock(&source->lock);
    return 0;
}

static void return_packet_node_list(
    PBFFmpegDemuxSource *source,
    PBFFmpegPacketNode **nodes
) {
    if (!source || !nodes || !*nodes) return;
    pthread_mutex_lock(&source->lock);
    PBFFmpegPacketNode *node = *nodes;
    *nodes = NULL;
    while (node) {
        PBFFmpegPacketNode *next = node->next;
        return_packet_node(source, node);
        node = next;
    }
    pthread_cond_broadcast(&source->changed);
    pthread_mutex_unlock(&source->lock);
}

static int copy_next_demux_packet_batch(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    atomic_bool *cancelled,
    PBFFmpegPacketNode **availableNodes,
    PBFFmpegPacketNode **consumedNodes,
    AVPacket *packet
) {
    if (!source || !packet || !availableNodes || !consumedNodes ||
        streamIndex < 0 ||
        (unsigned int)streamIndex >= source->queueCount) {
        return AVERROR(EINVAL);
    }
    if (cancellation_requested(cancelled)) return AVERROR_EXIT;

    if (!*availableNodes) {
        pthread_mutex_lock(&source->lock);
        PBFFmpegPacketNode *consumedNode = *consumedNodes;
        *consumedNodes = NULL;
        while (consumedNode) {
            PBFFmpegPacketNode *next = consumedNode->next;
            return_packet_node(source, consumedNode);
            consumedNode = next;
        }

        PBFFmpegPacketQueue *queue = &source->queues[streamIndex];
        queue->waiters++;
        if (!start_demux_source_read_thread(source)) {
            queue->waiters--;
            pthread_mutex_unlock(&source->lock);
            return AVERROR(ENOMEM);
        }
        pthread_cond_broadcast(&source->changed);
        while (!queue->head && !source->reachedEnd &&
               !cancellation_requested(cancelled)) {
            pthread_cond_wait(&source->changed, &source->lock);
        }
        queue->waiters--;
        if (cancellation_requested(cancelled)) {
            pthread_mutex_unlock(&source->lock);
            return AVERROR_EXIT;
        }
        if (!queue->head) {
            int result = source->readResult < 0
                ? source->readResult
                : AVERROR_EOF;
            pthread_mutex_unlock(&source->lock);
            return result;
        }

        PBFFmpegPacketNode *batchHead = queue->head;
        PBFFmpegPacketNode *batchTail = batchHead;
        unsigned int batchCount = 1;
        int64_t batchDurationMicroseconds = batchHead->durationMicroseconds;
        int64_t batchByteCount = batchHead->byteCount;
        while (batchTail->next && batchCount < PB_AUDIO_PACKET_BATCH_LIMIT &&
               batchDurationMicroseconds <
                   PB_AUDIO_PACKET_BATCH_DURATION_MICROSECONDS) {
            batchTail = batchTail->next;
            batchCount++;
            batchDurationMicroseconds += batchTail->durationMicroseconds;
            batchByteCount += batchTail->byteCount;
        }
        queue->head = batchTail->next;
        batchTail->next = NULL;
        if (!queue->head) queue->tail = NULL;
        queue->summedDurationMicroseconds -= batchDurationMicroseconds;
        if (queue->summedDurationMicroseconds < 0) {
            queue->summedDurationMicroseconds = 0;
        }
        release_packet_queue_bytes(source, queue, batchByteCount);
        update_packet_queue_buffered_duration(queue);
        *availableNodes = batchHead;
        pthread_cond_broadcast(&source->changed);
        pthread_mutex_unlock(&source->lock);
    }

    PBFFmpegPacketNode *node = *availableNodes;
    *availableNodes = node->next;
    av_packet_move_ref(packet, &node->packet);
    node->next = *consumedNodes;
    *consumedNodes = node;
    return 0;
}

AVFormatContext *PBFFmpegDemuxSourceGetFormatContext(
    PBFFmpegDemuxSource *source
) {
    return source ? source->formatContext : NULL;
}

int PBFFmpegDemuxSourceCopyNextPacket(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    AVPacket *packet
) {
    return copy_next_demux_packet(source, streamIndex, NULL, packet);
}

int PBFFmpegDemuxSourceCopyNextPacketIfAvailable(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    AVPacket *packet
) {
    return copy_next_demux_packet_if_available(source, streamIndex, packet);
}

bool PBFFmpegDemuxSourceSubscribe(
    PBFFmpegDemuxSource *source,
    int streamIndex
) {
    return subscribe_to_demux_stream(source, streamIndex);
}

void PBFFmpegDemuxSourceUnsubscribe(
    PBFFmpegDemuxSource *source,
    int streamIndex
) {
    unsubscribe_from_demux_stream(source, streamIndex);
}

struct PBFFmpegSubtitleReader {
    PBFFmpegSourceReadContext sourceReadContext;
    AVFormatContext *formatContext;
    PBFFmpegDemuxSource *demuxSource;
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

typedef enum {
    PBCompressedAudioCodecNone = 0,
    PBCompressedAudioCodecAC3,
    PBCompressedAudioCodecEAC3,
    PBCompressedAudioCodecAppleAPAC,
} PBCompressedAudioCodec;

static PBCompressedAudioCodec compressed_audio_codec(
    const AVCodecParameters *parameters
) {
    if (!parameters) return PBCompressedAudioCodecNone;
    switch (parameters->codec_id) {
        case AV_CODEC_ID_AC3: return PBCompressedAudioCodecAC3;
        case AV_CODEC_ID_EAC3: return PBCompressedAudioCodecEAC3;
        case AV_CODEC_ID_APAC:
            return parameters->codec_tag == MKTAG('a', 'p', 'a', 'c')
                ? PBCompressedAudioCodecAppleAPAC
                : PBCompressedAudioCodecNone;
        default: return PBCompressedAudioCodecNone;
    }
}

static AudioFormatID compressed_audio_format_id(
    PBCompressedAudioCodec codec
) {
    switch (codec) {
        case PBCompressedAudioCodecAC3: return kAudioFormatAC3;
        case PBCompressedAudioCodecEAC3: return kAudioFormatEnhancedAC3;
        case PBCompressedAudioCodecAppleAPAC: return kAudioFormatAPAC;
        case PBCompressedAudioCodecNone: return 0;
    }
}

static bool audio_codec_uses_compressed_passthrough(
    const AVCodecParameters *parameters
) {
    return compressed_audio_codec(parameters) != PBCompressedAudioCodecNone;
}

static bool audio_codec_is_supported(const AVCodecParameters *parameters) {
    return audio_codec_uses_compressed_passthrough(parameters) ||
        (parameters && avcodec_find_decoder(parameters->codec_id) != NULL);
}

static bool audio_stream_is_supported(const AVStream *stream) {
    if (!stream || stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) return false;
    return audio_codec_is_supported(stream->codecpar) &&
        stream->codecpar->sample_rate > 0 &&
        stream->codecpar->ch_layout.nb_channels > 0;
}

static void set_error(char *buffer, size_t size, const char *message);

static bool audio_stream_needs_more_probe(const AVStream *stream) {
    if (!stream || stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) return false;
    return audio_codec_is_supported(stream->codecpar) &&
        (stream->codecpar->sample_rate <= 0 ||
         stream->codecpar->ch_layout.nb_channels <= 0);
}

static bool is_audio_stream(const AVStream *stream) {
    return stream && stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO;
}

static bool audio_stream_has_supported_codec(const AVStream *stream) {
    return is_audio_stream(stream) &&
        audio_codec_is_supported(stream->codecpar);
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
    enum AVCodecID unsupportedCodec = AV_CODEC_ID_NONE;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVStream *stream = context->streams[index];
        hasAudioStream = hasAudioStream || is_audio_stream(stream);
        hasSupportedCodec = hasSupportedCodec || audio_stream_has_supported_codec(stream);
        if (is_audio_stream(stream) &&
            !audio_codec_is_supported(stream->codecpar) &&
            unsupportedCodec == AV_CODEC_ID_NONE) {
            unsupportedCodec = stream->codecpar->codec_id;
        }
    }
    if (!hasAudioStream) {
        set_error(errorBuffer, errorBufferSize, "The selected source has no audio stream");
    } else if (!hasSupportedCodec) {
        char message[160];
        snprintf(
            message,
            sizeof(message),
            "Audio codec %s is unsupported because FFmpeg has no decoder",
            avcodec_get_name(unsupportedCodec)
        );
        set_error(errorBuffer, errorBufferSize, message);
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

static PBFFmpegActiveFailureCause active_failure_cause_for_av_error(int code) {
    switch (code) {
        case AVERROR(ECONNABORTED):
        case AVERROR(ECONNRESET):
        case AVERROR(ENETDOWN):
        case AVERROR(ENETRESET):
        case AVERROR(ENETUNREACH):
        case AVERROR(ENOTCONN):
        case AVERROR(ETIMEDOUT):
        case AVERROR(EHOSTDOWN):
        case AVERROR(EHOSTUNREACH):
        case AVERROR(EPIPE):
            return PBFFmpegActiveFailureCauseConnectionInterrupted;
        case AVERROR(ENOENT):
        case AVERROR(ENOTDIR):
        case AVERROR(ESTALE):
        case AVERROR_HTTP_NOT_FOUND:
            return PBFFmpegActiveFailureCauseSourceFileMissing;
        case AVERROR(EACCES):
        case AVERROR(EPERM):
        case AVERROR_HTTP_UNAUTHORIZED:
        case AVERROR_HTTP_FORBIDDEN:
            return PBFFmpegActiveFailureCauseSourceAccessDenied;
        case AVERROR_INVALIDDATA:
            return PBFFmpegActiveFailureCauseMediaDataCorrupt;
        default:
            return PBFFmpegActiveFailureCauseNone;
    }
}

static PBFFmpegActiveFailureCause active_failure_cause_for_decoder_error(int code) {
    switch (code) {
        case AVERROR(EINVAL):
        case AVERROR_INVALIDDATA:
            return PBFFmpegActiveFailureCauseMediaDataCorrupt;
        default:
            return PBFFmpegActiveFailureCauseNone;
    }
}

static void normalize_mov_codec_ids(AVFormatContext *context) {
    if (!context) return;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVCodecParameters *parameters = context->streams[index]->codecpar;
        if (parameters->codec_type == AVMEDIA_TYPE_AUDIO &&
            (parameters->codec_id == AV_CODEC_ID_NONE ||
             parameters->codec_id == AV_CODEC_ID_APPLE_APAC) &&
            parameters->codec_tag == MKTAG('a', 'p', 'a', 'c')) {
            parameters->codec_id = AV_CODEC_ID_APAC;
        }
        if (parameters->codec_type == AVMEDIA_TYPE_VIDEO &&
            parameters->codec_id == AV_CODEC_ID_NONE &&
            parameters->codec_tag == MKTAG('d', 'a', 'v', '1')) {
            parameters->codec_id = AV_CODEC_ID_AV1;
        }
    }
}

static int finalize_stream_information(
    AVFormatContext *context,
    PBFFmpegSourceReadContext *sourceReadContext,
    bool probesStreamInformation
) {
    int result = probesStreamInformation
        ? avformat_find_stream_info(context, NULL)
        : 0;
    if (probesStreamInformation) publish_source_bytes(sourceReadContext);
    normalize_mov_codec_ids(context);
    return result;
}

enum {
    PB_UDF_VOLUME_RECOGNITION_SEQUENCE_OFFSET = 32768,
    PB_UDF_VOLUME_DESCRIPTOR_SIZE = 2048,
    PB_UDF_VOLUME_IDENTIFIER_OFFSET = 1,
    PB_UDF_VOLUME_IDENTIFIER_LENGTH = 5,
};
static const int64_t PB_DISC_IMAGE_RESYNC_SIZE = 16LL * 1024 * 1024;

static const AVInputFormat *disc_image_input_format(const char *path) {
    if (!path) return NULL;
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    uint8_t descriptors[2][PB_UDF_VOLUME_DESCRIPTOR_SIZE];
    const uint8_t *firstIdentifier =
        descriptors[0] + PB_UDF_VOLUME_IDENTIFIER_OFFSET;
    const uint8_t *secondIdentifier =
        descriptors[1] + PB_UDF_VOLUME_IDENTIFIER_OFFSET;
    bool isUDF = false;
    if (fseek(file, PB_UDF_VOLUME_RECOGNITION_SEQUENCE_OFFSET, SEEK_SET) == 0
        && fread(descriptors, sizeof(descriptors[0]), 2, file) == 2
        && memcmp(
               firstIdentifier, "BEA01", PB_UDF_VOLUME_IDENTIFIER_LENGTH
           ) == 0) {
        isUDF = memcmp(
                    secondIdentifier, "NSR02", PB_UDF_VOLUME_IDENTIFIER_LENGTH
                ) == 0
            || memcmp(
                   secondIdentifier, "NSR03", PB_UDF_VOLUME_IDENTIFIER_LENGTH
               ) == 0;
    }
    fclose(file);
    return isUDF ? av_find_input_format("mpegts") : NULL;
}

static int open_media_source(
    AVFormatContext **context,
    const char *path,
    PBFFmpegSourceReadContext *sourceReadContext
) {
    AVDictionary *options = NULL;
    int result = 0;
    const AVInputFormat *format = disc_image_input_format(path);
    if (format) {
        av_dict_set_int(&options, "resync_size", PB_DISC_IMAGE_RESYNC_SIZE, 0);
    }
    result = avformat_open_input(context, path, format, &options);
    av_dict_free(&options);
    if (sourceReadContext) {
        sourceReadContext->formatContext = result >= 0 ? *context : NULL;
        publish_source_bytes(sourceReadContext);
    }
    return result;
}

struct PBFFmpegMonitoredSource {
    PBFFmpegSourceReadContext readContext;
    AVFormatContext *formatContext;
};

PBFFmpegMonitoredSource *PBFFmpegMonitoredSourceOpen(
    const char *path,
    PBFFmpegSourceReadMonitor *monitor,
    PBFFmpegReadCancellation *cancellation,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!path) {
        set_error(errorBuffer, errorBufferSize, "Invalid monitored source call");
        return NULL;
    }
    atomic_bool *cancelled = cancellation ? &cancellation->cancelled : NULL;
    if (cancellation_requested(cancelled)) {
        set_error(errorBuffer, errorBufferSize, "The monitored source read was cancelled");
        return NULL;
    }
    PBFFmpegMonitoredSource *source = calloc(1, sizeof(PBFFmpegMonitoredSource));
    if (!source) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate monitored source");
        return NULL;
    }
    source->readContext.monitor = monitor;
    source->formatContext = allocate_format_context(cancelled, &source->readContext);
    if (!source->formatContext) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate monitored source context");
        free(source);
        return NULL;
    }
    int result = open_media_source(&source->formatContext, path, &source->readContext);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open monitored source", result);
        PBFFmpegMonitoredSourceClose(&source);
        return NULL;
    }
    result = finalize_stream_information(source->formatContext, &source->readContext, true);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read monitored source stream information", result);
        PBFFmpegMonitoredSourceClose(&source);
        return NULL;
    }
    return source;
}

AVFormatContext *PBFFmpegMonitoredSourceGetFormatContext(PBFFmpegMonitoredSource *source) {
    return source ? source->formatContext : NULL;
}

void PBFFmpegMonitoredSourceClose(PBFFmpegMonitoredSource **source) {
    if (!source || !*source) return;
    close_media_source(&(*source)->formatContext, &(*source)->readContext);
    free(*source);
    *source = NULL;
}

static void apply_extended_audio_probe_limits(AVFormatContext *context) {
    if (!context) return;
    context->probesize = 100LL * 1024 * 1024;
    context->max_analyze_duration = 30LL * AV_TIME_BASE;
    context->max_probe_packets = 100000;
}

static bool adopt_probed_audio_parameters(AVStream *destination, const AVStream *probed) {
    if (!destination || !probed || !audio_stream_is_supported(probed)) return false;
    if (probed->codecpar->codec_id != destination->codecpar->codec_id) return false;
    if (av_channel_layout_copy(
            &destination->codecpar->ch_layout,
            &probed->codecpar->ch_layout
        ) < 0) return false;
    destination->codecpar->sample_rate = probed->codecpar->sample_rate;
    destination->codecpar->format = probed->codecpar->format;
    destination->codecpar->frame_size = probed->codecpar->frame_size;
    destination->codecpar->profile = probed->codecpar->profile;
    destination->codecpar->bit_rate = probed->codecpar->bit_rate;
    destination->codecpar->block_align = probed->codecpar->block_align;
    destination->codecpar->bits_per_coded_sample = probed->codecpar->bits_per_coded_sample;
    return audio_stream_is_supported(destination);
}

static bool probe_extended_audio_parameters(
    AVStream *stream,
    const char *path,
    atomic_bool *cancelled,
    PBFFmpegSourceReadMonitor *monitor
) {
    if (!stream || !path || !audio_stream_needs_more_probe(stream)) return false;
    PBFFmpegSourceReadContext readContext = { .monitor = monitor };
    AVFormatContext *context = allocate_format_context(cancelled, &readContext);
    if (context == NULL) return false;
    apply_extended_audio_probe_limits(context);
    int result = open_media_source(&context, path, &readContext);
    if (result >= 0) result = read_stream_information(context, &readContext, NULL);
    bool resolved = false;
    if (result >= 0 && !cancellation_requested(cancelled)) {
        probe_delayed_audio_parameters(context);
        if (stream->index >= 0 && stream->index < (int)context->nb_streams) {
            resolved = adopt_probed_audio_parameters(
                stream,
                context->streams[stream->index]
            );
        }
    }
    close_media_source(&context, &readContext);
    return resolved;
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
            result = finalize_stream_information(
                context,
                sourceReadContext,
                true
            );
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
    apply_extended_audio_probe_limits(context);
    result = open_media_source(&context, path, sourceReadContext);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Reopen audio media source", result);
        close_media_source(&context, sourceReadContext);
        return result;
    }
    result = read_stream_information(context, sourceReadContext, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read extended audio stream information", result);
        close_media_source(&context, sourceReadContext);
        return result;
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

typedef enum {
    PBDOVIDeclarationAbsent,
    PBDOVIDeclarationHEVCNative,
    PBDOVIDeclarationHEVCBackwardCompatible,
    PBDOVIDeclarationHEVCDualLayer,
    PBDOVIDeclarationAV1,
    PBDOVIDeclarationUnknown,
} PBDOVIDeclarationShape;

static PBDOVIDeclarationShape dovi_declaration_shape(
    const AVCodecParameters *parameters
) {
    const AVPacketSideData *sideData = av_packet_side_data_get(
        parameters->coded_side_data,
        parameters->nb_coded_side_data,
        AV_PKT_DATA_DOVI_CONF
    );
    if (!sideData) return PBDOVIDeclarationAbsent;
    if (sideData->size < sizeof(AVDOVIDecoderConfigurationRecord)) {
        return PBDOVIDeclarationUnknown;
    }
    const AVDOVIDecoderConfigurationRecord *record =
        (const AVDOVIDecoderConfigurationRecord *)sideData->data;
    if (record->rpu_present_flag == 0 || record->bl_present_flag == 0) {
        return PBDOVIDeclarationUnknown;
    }
    if (parameters->codec_id == AV_CODEC_ID_HEVC) {
        if (record->el_present_flag != 0) {
            return record->dv_profile == 7 &&
                    record->dv_bl_signal_compatibility_id != 0
                ? PBDOVIDeclarationHEVCDualLayer
                : PBDOVIDeclarationUnknown;
        }
        return record->dv_bl_signal_compatibility_id == 0
            ? PBDOVIDeclarationHEVCNative
            : PBDOVIDeclarationHEVCBackwardCompatible;
    }
    if (parameters->codec_id == AV_CODEC_ID_AV1 &&
        record->dv_profile == 10 &&
        record->el_present_flag == 0) {
        return PBDOVIDeclarationAV1;
    }
    return PBDOVIDeclarationUnknown;
}

static void describe_dovi_declaration(
    const AVCodecParameters *parameters,
    char *buffer,
    size_t bufferSize
) {
    const AVPacketSideData *sideData = av_packet_side_data_get(
        parameters->coded_side_data,
        parameters->nb_coded_side_data,
        AV_PKT_DATA_DOVI_CONF
    );
    if (!sideData) {
        snprintf(buffer, bufferSize, "dovi=absent");
        return;
    }
    if (sideData->size < sizeof(AVDOVIDecoderConfigurationRecord)) {
        snprintf(buffer, bufferSize, "dovi_size=%zu", sideData->size);
        return;
    }
    const AVDOVIDecoderConfigurationRecord *record =
        (const AVDOVIDecoderConfigurationRecord *)sideData->data;
    snprintf(
        buffer,
        bufferSize,
        "dovi_version=%u.%u profile=%u level=%u rpu=%u el=%u bl=%u compatibility_id=%u md_compression=%u",
        record->dv_version_major,
        record->dv_version_minor,
        record->dv_profile,
        record->dv_level,
        record->rpu_present_flag,
        record->el_present_flag,
        record->bl_present_flag,
        record->dv_bl_signal_compatibility_id,
        record->dv_md_compression
    );
}

static bool has_usable_dovi_configuration(const AVCodecParameters *parameters) {
    PBDOVIDeclarationShape shape = dovi_declaration_shape(parameters);
    return shape == PBDOVIDeclarationHEVCNative ||
        shape == PBDOVIDeclarationHEVCBackwardCompatible ||
        shape == PBDOVIDeclarationAV1;
}

static bool requires_dolby_vision_base_layer_split(
    const AVCodecParameters *parameters
) {
    return dovi_declaration_shape(parameters) == PBDOVIDeclarationHEVCDualLayer;
}

static OSType codec_type(const AVCodecParameters *parameters) {
    switch (parameters->codec_id) {
        case AV_CODEC_ID_H264: return kCMVideoCodecType_H264;
        case AV_CODEC_ID_HEVC:
            if (dovi_declaration_shape(parameters) == PBDOVIDeclarationHEVCNative) {
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
    PBDOVIDeclarationShape shape = dovi_declaration_shape(parameters);
    CFDictionarySetValue(
        atoms,
        shape == PBDOVIDeclarationHEVCNative ? CFSTR("dvcC") : CFSTR("dvvC"),
        data
    );
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

static const AVPacketSideData *codec_side_data(
    const AVCodecParameters *parameters,
    enum AVPacketSideDataType type
);

typedef struct {
    int dolbyVisionProfile;
    int dolbyVisionCrossCompatibilityID;
    bool dolbyVisionHasEnhancementLayer;
    bool hasStereoVideoEnhancementLayer;
} PBVideoSourceFacts;

static PBVideoSourceFacts video_source_facts(
    const AVFormatContext *context,
    int decodedStreamIndex
) {
    PBVideoSourceFacts facts = {0};
    if (!context || decodedStreamIndex < 0 ||
        decodedStreamIndex >= (int)context->nb_streams) {
        return facts;
    }
    const AVCodecParameters *decodedParameters =
        context->streams[decodedStreamIndex]->codecpar;
    const AVPacketSideData *stereoData = codec_side_data(
        decodedParameters,
        AV_PKT_DATA_STEREO3D
    );
    if (stereoData && stereoData->size >= sizeof(AVStereo3D)) {
        const AVStereo3D *stereo = (const AVStereo3D *)stereoData->data;
        facts.hasStereoVideoEnhancementLayer =
            stereo->view == AV_STEREO3D_VIEW_PACKED;
    }
    for (unsigned index = 0; index < context->nb_streams; index++) {
        AVStream *candidate = context->streams[index];
        if (candidate->codecpar->codec_type != AVMEDIA_TYPE_VIDEO) continue;
        const AVPacketSideData *entry = av_packet_side_data_get(
            candidate->codecpar->coded_side_data,
            candidate->codecpar->nb_coded_side_data,
            AV_PKT_DATA_DOVI_CONF
        );
        if (!entry || entry->size < sizeof(AVDOVIDecoderConfigurationRecord)) continue;
        const AVDOVIDecoderConfigurationRecord *record =
            (const AVDOVIDecoderConfigurationRecord *)entry->data;
        bool onDecodedStream = (int)index == decodedStreamIndex;
        bool describesPureEnhancementLayer = record->bl_present_flag == 0;
        bool aRecordWasAlreadyTaken = facts.dolbyVisionProfile != 0;
        if (!onDecodedStream) {
            if (!describesPureEnhancementLayer) continue;
            if (aRecordWasAlreadyTaken) continue;
        }
        facts.dolbyVisionProfile = record->dv_profile;
        facts.dolbyVisionCrossCompatibilityID =
            record->dv_bl_signal_compatibility_id;
        facts.dolbyVisionHasEnhancementLayer = record->el_present_flag != 0;
        if (onDecodedStream) return facts;
    }
    return facts;
}

static void detect_dolby_vision(PBFFmpegReader *reader) {
    PBVideoSourceFacts facts = video_source_facts(
        reader->formatContext,
        reader->videoStreamIndex
    );
    reader->dolbyVisionProfile = facts.dolbyVisionProfile;
    reader->dolbyVisionCrossCompatibilityID =
        facts.dolbyVisionCrossCompatibilityID;
    reader->dolbyVisionHasEnhancementLayer =
        facts.dolbyVisionHasEnhancementLayer;
}

static bool context_uses_mov_demuxer(const AVFormatContext *context);

static int configure_dolby_vision_base_layer_split(
    PBFFmpegReader *reader,
    AVStream *stream,
    char *errorBuffer,
    size_t errorBufferSize
) {
    reader->reordersProfile7BaseLayerParameterSets =
        reader->dolbyVisionProfile == 7 &&
        reader->usedBitstreamExtradataBootstrap &&
        stream->codecpar->codec_id == AV_CODEC_ID_HEVC &&
        context_uses_mov_demuxer(reader->formatContext);
    if (reader->reordersProfile7BaseLayerParameterSets) {
        if (!stream->codecpar->extradata || stream->codecpar->extradata_size <= 21) {
            set_error(errorBuffer, errorBufferSize, "Profile 7 base-layer hvcC is incomplete");
            return AVERROR_INVALIDDATA;
        }
        reader->hevcNALLengthSize =
            (size_t)(stream->codecpar->extradata[21] & 0x03) + 1;
    }
    if (!requires_dolby_vision_base_layer_split(stream->codecpar)) return 0;
    const AVBitStreamFilter *filter = av_bsf_get_by_name("dovi_split");
    if (!filter) {
        set_error(errorBuffer, errorBufferSize, "FFmpeg dovi_split filter is unavailable");
        return AVERROR(ENOSYS);
    }
    AVBSFContext *context = NULL;
    int result = av_bsf_alloc(filter, &context);
    if (result >= 0) {
        result = av_opt_set(context->priv_data, "mode", "bl", 0);
    }
    if (result >= 0) {
        result = avcodec_parameters_copy(context->par_in, stream->codecpar);
    }
    if (result >= 0) {
        context->time_base_in = stream->time_base;
        result = av_bsf_init(context);
    }
    if (result < 0) {
        av_bsf_free(&context);
        set_av_error(
            errorBuffer,
            errorBufferSize,
            "Initialize Dolby Vision Profile 7 base-layer split",
            result
        );
        return result;
    }
    reader->dolbyVisionSplitFilter = context;
    return 0;
}

static CFStringRef transfer_function(enum AVColorTransferCharacteristic value) {
    switch (value) {
        case AVCOL_TRC_BT709: return kCMFormatDescriptionTransferFunction_ITU_R_709_2;
        case AVCOL_TRC_IEC61966_2_1: return kCMFormatDescriptionTransferFunction_sRGB;
        case AVCOL_TRC_SMPTE2084: return kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ;
        case AVCOL_TRC_ARIB_STD_B67: return kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG;
        default: return NULL;
    }
}

#define PB_CM_YCBCR_MATRIX_IPT_C2 CFSTR("IPT_C2")

static CFStringRef ycbcr_matrix(enum AVColorSpace value) {
    switch (value) {
        case AVCOL_SPC_BT709: return kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2;
        case AVCOL_SPC_BT2020_NCL:
        case AVCOL_SPC_BT2020_CL:
            return kCMFormatDescriptionYCbCrMatrix_ITU_R_2020;
        case AVCOL_SPC_IPT_C2: return PB_CM_YCBCR_MATRIX_IPT_C2;
        default: return NULL;
    }
}

static void add_color_extensions(
    const AVCodecParameters *parameters,
    CFMutableDictionaryRef extensions
) {
    const AVDOVIDecoderConfigurationRecord *dovi =
        has_usable_dovi_configuration(parameters)
            ? (const AVDOVIDecoderConfigurationRecord *)codec_side_data(
                parameters,
                AV_PKT_DATA_DOVI_CONF
            )->data
            : NULL;
    bool usesProfileFiveColorConstants = dovi && dovi->dv_profile == 5;
    CFStringRef primaries = usesProfileFiveColorConstants
        ? kCMFormatDescriptionColorPrimaries_ITU_R_2020
        : color_primaries(parameters->color_primaries);
    CFStringRef transfer = usesProfileFiveColorConstants
        ? kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        : transfer_function(parameters->color_trc);
    CFStringRef matrix = usesProfileFiveColorConstants
        ? NULL
        : ycbcr_matrix(parameters->color_space);
    if (dovi && !usesProfileFiveColorConstants) {
        if (!primaries && dovi->dv_bl_signal_compatibility_id == 0) {
            primaries = kCMFormatDescriptionColorPrimaries_ITU_R_2020;
        }
        if (!transfer && dovi->dv_bl_signal_compatibility_id == 0) {
            transfer = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ;
        }
        if (!primaries &&
            (dovi->dv_bl_signal_compatibility_id == 1 ||
             dovi->dv_bl_signal_compatibility_id == 4)) {
            primaries = kCMFormatDescriptionColorPrimaries_ITU_R_2020;
        }
        if (!transfer && dovi->dv_bl_signal_compatibility_id == 1) {
            transfer = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ;
        } else if (!transfer && dovi->dv_bl_signal_compatibility_id == 4) {
            transfer = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG;
        }
        if (!matrix &&
            (dovi->dv_bl_signal_compatibility_id == 1 ||
             dovi->dv_bl_signal_compatibility_id == 4)) {
            matrix = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020;
        }
    }
    if (primaries) {
        CFDictionarySetValue(
            extensions,
            kCMFormatDescriptionExtension_ColorPrimaries,
            primaries
        );
    }
    if (transfer) {
        CFDictionarySetValue(
            extensions,
            kCMFormatDescriptionExtension_TransferFunction,
            transfer
        );
    }
    if (matrix) {
        CFDictionarySetValue(
            extensions,
            kCMFormatDescriptionExtension_YCbCrMatrix,
            matrix
        );
    }
    if (usesProfileFiveColorConstants ||
        parameters->color_range == AVCOL_RANGE_JPEG ||
        (dovi &&
         parameters->color_range == AVCOL_RANGE_UNSPECIFIED &&
         dovi->dv_bl_signal_compatibility_id == 0)) {
        CFDictionarySetValue(
            extensions,
            kCMFormatDescriptionExtension_FullRangeVideo,
            kCFBooleanTrue
        );
    } else if (parameters->color_range == AVCOL_RANGE_MPEG ||
               (dovi &&
                (dovi->dv_bl_signal_compatibility_id == 1 ||
                 dovi->dv_bl_signal_compatibility_id == 4))) {
        CFDictionarySetValue(
            extensions,
            kCMFormatDescriptionExtension_FullRangeVideo,
            kCFBooleanFalse
        );
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

enum {
    PB_FFMPEG_DISPLAY_PRIMARY_RED = 0,
    PB_FFMPEG_DISPLAY_PRIMARY_GREEN = 1,
    PB_FFMPEG_DISPLAY_PRIMARY_BLUE = 2,
};

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
        const int serializedPrimaryOrder[3] = {
            PB_FFMPEG_DISPLAY_PRIMARY_GREEN,
            PB_FFMPEG_DISPLAY_PRIMARY_BLUE,
            PB_FFMPEG_DISPLAY_PRIMARY_RED,
        };
        bool usable = metadata->has_primaries && metadata->has_luminance;
        for (int outputPrimary = 0; usable && outputPrimary < 3; outputPrimary++) {
            int sourcePrimary = serializedPrimaryOrder[outputPrimary];
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

static void merge_format_extension(
    const void *key,
    const void *value,
    void *context
) {
    CFDictionarySetValue((CFMutableDictionaryRef)context, key, value);
}

static OSStatus create_format_by_adding_extensions(
    CMVideoFormatDescriptionRef source,
    CFDictionaryRef additions,
    CMVideoFormatDescriptionRef *formatOut
) {
    if (!additions || CFDictionaryGetCount(additions) == 0) {
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
    CFDictionaryApplyFunction(
        additions,
        merge_format_extension,
        merged
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

static CFDictionaryRef decoder_configuration_atoms(
    CMVideoFormatDescriptionRef format
) {
    if (!format) return NULL;
    CFTypeRef atoms = CMFormatDescriptionGetExtension(
        format,
        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
    );
    return atoms && CFGetTypeID(atoms) == CFDictionaryGetTypeID()
        ? (CFDictionaryRef)atoms
        : NULL;
}

static OSStatus create_format_from_source(
    CMVideoFormatDescriptionRef sourceFormat,
    CMVideoFormatDescriptionRef bridgeFormat,
    CFDictionaryRef replacementExtensions,
    CMVideoFormatDescriptionRef *formatOut
) {
    if (!formatOut) return kCMFormatDescriptionError_InvalidParameter;
    *formatOut = NULL;
    if ((bridgeFormat != NULL) == (replacementExtensions != NULL)) {
        return kCMFormatDescriptionError_InvalidParameter;
    }
    if (!sourceFormat ||
        CMFormatDescriptionGetMediaType(sourceFormat) != kCMMediaType_Video) {
        return kCMFormatDescriptionError_InvalidParameter;
    }
    if (bridgeFormat &&
        CMFormatDescriptionGetMediaType(bridgeFormat) != kCMMediaType_Video) {
        return kCMFormatDescriptionError_InvalidParameter;
    }

    FourCharCode sourceType = CMFormatDescriptionGetMediaSubType(sourceFormat);
    FourCharCode targetType = bridgeFormat
        ? CMFormatDescriptionGetMediaSubType(bridgeFormat)
        : sourceType;

    CFDictionaryRef sourceExtensions = CMFormatDescriptionGetExtensions(sourceFormat);
    CFMutableDictionaryRef extensions = replacementExtensions && !bridgeFormat
        ? CFDictionaryCreateMutableCopy(
            kCFAllocatorDefault,
            0,
            replacementExtensions
        )
        : (sourceExtensions
            ? CFDictionaryCreateMutableCopy(
                kCFAllocatorDefault,
                0,
                sourceExtensions
            )
            : CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            ));
    if (!extensions) return kCMFormatDescriptionError_AllocationFailed;

    if (bridgeFormat) {
        CFDictionaryRef sourceAtoms = decoder_configuration_atoms(sourceFormat);
        CFDictionaryRef bridgeAtoms = decoder_configuration_atoms(bridgeFormat);
        CFMutableDictionaryRef mergedAtoms = sourceAtoms
            ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, sourceAtoms)
            : CFDictionaryCreateMutable(
                kCFAllocatorDefault,
                0,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks
            );
        if (!mergedAtoms) {
            CFRelease(extensions);
            return kCMFormatDescriptionError_AllocationFailed;
        }
        const CFStringRef configurationAtoms[] = {
            CFSTR("avcC"), CFSTR("hvcC"), CFSTR("lhvC"),
            CFSTR("dvcC"), CFSTR("dvvC"), CFSTR("av1C"),
        };
        if (bridgeAtoms) {
            for (size_t index = 0;
                 index < sizeof(configurationAtoms) / sizeof(configurationAtoms[0]);
                 index++) {
                CFStringRef atom = configurationAtoms[index];
                if (CFDictionaryContainsKey(mergedAtoms, atom)) continue;
                CFTypeRef value = CFDictionaryGetValue(bridgeAtoms, atom);
                if (value) CFDictionarySetValue(mergedAtoms, atom, value);
            }
        }
        if (CFDictionaryGetCount(mergedAtoms) > 0) {
            CFDictionarySetValue(
                extensions,
                kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms,
                mergedAtoms
            );
        }
        CFRelease(mergedAtoms);
    }

    CMVideoDimensions dimensions = bridgeFormat
        ? CMVideoFormatDescriptionGetDimensions(bridgeFormat)
        : CMVideoFormatDescriptionGetDimensions(sourceFormat);
    OSStatus status = CMVideoFormatDescriptionCreate(
        kCFAllocatorDefault,
        targetType,
        dimensions.width,
        dimensions.height,
        extensions,
        formatOut
    );
    CFRelease(extensions);
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
        enum AVCodecID codecID = parameters->codec_id;
        if (codecID == AV_CODEC_ID_NONE &&
            parameters->codec_tag == MKTAG('d', 'a', 'v', '1')) {
            codecID = AV_CODEC_ID_AV1;
        }
        if (codecID == AV_CODEC_ID_NONE ||
            parameters->width <= 0 || parameters->height <= 0) {
            return false;
        }
        switch (codecID) {
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

static void fill_video_facts_from_codec_configuration(AVFormatContext *context) {
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVCodecParameters *parameters = context->streams[index]->codecpar;
        if (parameters->codec_type != AVMEDIA_TYPE_VIDEO ||
            !parameters->extradata || parameters->extradata_size <= 0) continue;
        if (parameters->color_primaries != AVCOL_PRI_UNSPECIFIED &&
            parameters->color_trc != AVCOL_TRC_UNSPECIFIED &&
            parameters->color_space != AVCOL_SPC_UNSPECIFIED &&
            parameters->color_range != AVCOL_RANGE_UNSPECIFIED &&
            parameters->format != AV_PIX_FMT_NONE) continue;
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
            if (parameters->format == AV_PIX_FMT_NONE) {
                parameters->format = codecContext->pix_fmt != AV_PIX_FMT_NONE
                    ? codecContext->pix_fmt
                    : codecContext->sw_pix_fmt;
            }
            if (parameters->bits_per_raw_sample == 0) {
                parameters->bits_per_raw_sample = codecContext->bits_per_raw_sample;
            }
            if (parameters->profile == AV_PROFILE_UNKNOWN) {
                parameters->profile = codecContext->profile;
            }
            if (parameters->video_delay == 0) {
                parameters->video_delay = codecContext->has_b_frames;
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
    int result;
    if (read.movFamily && mov_stream_table_is_qualified(context)) {
        result = finalize_stream_information(context, sourceReadContext, false);
        fill_video_facts_from_codec_configuration(context);
        read.skippedProbe = true;
    } else {
        result = finalize_stream_information(context, sourceReadContext, true);
    }
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
        result = reader->demuxSource
            ? copy_next_demux_packet(
                reader->demuxSource,
                reader->videoStreamIndex,
                &reader->cancelled,
                input
            )
            : av_read_frame(reader->formatContext, input);
        if (!reader->demuxSource) publish_source_bytes(&reader->sourceReadContext);
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
    status = create_format_by_adding_extensions(
        baseFormat,
        extensions,
        formatOut
    );
    CFRelease(baseFormat);
    return status;
}

static OSStatus create_h264_format_from_avcc(
    const AVCodecParameters *parameters,
    CFDictionaryRef extensions,
    CMVideoFormatDescriptionRef *formatOut
) {
    if (!parameters->extradata || parameters->extradata_size < 7 ||
        parameters->extradata[0] != 1) {
        return kCMFormatDescriptionError_InvalidParameter;
    }
    const uint8_t *configuration = parameters->extradata;
    size_t configurationSize = (size_t)parameters->extradata_size;
    const uint8_t *sets[31 + 255] = {0};
    size_t sizes[31 + 255] = {0};
    size_t setCount = 0;
    size_t offset = 6;
    size_t spsCount = configuration[5] & 0x1f;
    if (spsCount == 0) return kCMFormatDescriptionError_InvalidParameter;
    for (size_t index = 0; index < spsCount; index++) {
        if (offset > configurationSize - 2) {
            return kCMFormatDescriptionError_InvalidParameter;
        }
        size_t size = ((size_t)configuration[offset] << 8) |
            configuration[offset + 1];
        offset += 2;
        if (size == 0 || size > configurationSize - offset) {
            return kCMFormatDescriptionError_InvalidParameter;
        }
        sets[setCount] = configuration + offset;
        sizes[setCount++] = size;
        offset += size;
    }
    if (offset >= configurationSize) {
        return kCMFormatDescriptionError_InvalidParameter;
    }
    size_t ppsCount = configuration[offset++];
    if (ppsCount == 0) return kCMFormatDescriptionError_InvalidParameter;
    for (size_t index = 0; index < ppsCount; index++) {
        if (offset > configurationSize - 2) {
            return kCMFormatDescriptionError_InvalidParameter;
        }
        size_t size = ((size_t)configuration[offset] << 8) |
            configuration[offset + 1];
        offset += 2;
        if (size == 0 || size > configurationSize - offset) {
            return kCMFormatDescriptionError_InvalidParameter;
        }
        sets[setCount] = configuration + offset;
        sizes[setCount++] = size;
        offset += size;
    }

    CMVideoFormatDescriptionRef baseFormat = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
        kCFAllocatorDefault,
        setCount,
        sets,
        sizes,
        (int)(configuration[4] & 0x03) + 1,
        &baseFormat
    );
    if (status != noErr || !baseFormat) return status;
    status = create_format_by_adding_extensions(
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
        kCMImageDescriptionFlavor_ISOFamily,
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

    add_color_extensions(parameters, extensions);
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
        if (parameters->codec_id == AV_CODEC_ID_H264) {
            status = create_h264_format_from_avcc(
                parameters,
                extensions,
                formatOut
            );
        } else if (type == kCMVideoCodecType_DolbyVisionHEVC) {
            CMVideoFormatDescriptionRef baseFormat = NULL;
            status = create_dolby_vision_format(parameters, atoms, &baseFormat);
            if (status == noErr && baseFormat) {
                status = create_format_by_adding_extensions(
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

OSStatus PBFFmpegVideoFormatDescriptionCreate(
    PBFFmpegReader *reader,
    CMVideoFormatDescriptionRef sourceFormat,
    CMVideoFormatDescriptionRef bridgeFormat,
    CFDictionaryRef replacementExtensions,
    CMVideoFormatDescriptionRef *formatOut
) {
    if (!formatOut) return kCMFormatDescriptionError_InvalidParameter;
    *formatOut = NULL;
    if (reader) {
        if (sourceFormat || bridgeFormat || replacementExtensions) {
            return kCMFormatDescriptionError_InvalidParameter;
        }
        if (reader->compressedFormat) {
            *formatOut = (CMVideoFormatDescriptionRef)CFRetain(
                reader->compressedFormat
            );
            return noErr;
        }
        if (!reader->formatContext || reader->videoStreamIndex < 0 ||
            reader->videoStreamIndex >= (int)reader->formatContext->nb_streams) {
            return kCMFormatDescriptionError_InvalidParameter;
        }
        AVStream *stream = reader->formatContext->streams[reader->videoStreamIndex];
        AVRational sampleAspectRatio = av_guess_sample_aspect_ratio(
            reader->formatContext,
            stream,
            NULL
        );
        return create_compressed_format(
            stream->codecpar,
            sampleAspectRatio,
            formatOut,
            &reader->convertsAnnexB
        );
    }
    return create_format_from_source(
        sourceFormat,
        bridgeFormat,
        replacementExtensions,
        formatOut
    );
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

enum {
    PB_CHROMA_LOG2_FULL_RESOLUTION = 0,
    PB_CHROMA_LOG2_HALF_RESOLUTION = 1,
};
enum { PB_CHROMA_PLANE_COUNT = 2 };
enum { PB_SAMPLE_WORD_BYTES_ABOVE_EIGHT_BIT = 2 };
enum { PB_SAMPLE_WORD_BYTES_AT_EIGHT_BIT = 1 };

static double samples_per_pixel_for_chroma(int log2ChromaWidth, int log2ChromaHeight) {
    double lumaSamplesPerPixel = 1.0;
    double chromaSamplesPerPixelPerPlane = 1.0
        / (double)(1 << log2ChromaWidth)
        / (double)(1 << log2ChromaHeight);
    return lumaSamplesPerPixel
        + (double)PB_CHROMA_PLANE_COUNT * chromaSamplesPerPixelPerPlane;
}

static double samples_per_pixel_for_chroma420(void) {
    return samples_per_pixel_for_chroma(
        PB_CHROMA_LOG2_HALF_RESOLUTION,
        PB_CHROMA_LOG2_HALF_RESOLUTION
    );
}

static double samples_per_pixel_for_h264_profile(int profile) {
    switch (profile) {
        case AV_PROFILE_H264_HIGH_422:
        case AV_PROFILE_H264_HIGH_422_INTRA:
            return samples_per_pixel_for_chroma(
                PB_CHROMA_LOG2_HALF_RESOLUTION,
                PB_CHROMA_LOG2_FULL_RESOLUTION
            );
        case AV_PROFILE_H264_HIGH_444:
        case AV_PROFILE_H264_HIGH_444_PREDICTIVE:
        case AV_PROFILE_H264_HIGH_444_INTRA:
            return samples_per_pixel_for_chroma(
                PB_CHROMA_LOG2_FULL_RESOLUTION,
                PB_CHROMA_LOG2_FULL_RESOLUTION
            );
        default:
            return samples_per_pixel_for_chroma420();
    }
}

static double decoded_bytes_per_pixel(const AVCodecParameters *parameters) {
    double samplesPerPixel = 0;
    int depth = 0;
    const AVPixFmtDescriptor *descriptor = av_pix_fmt_desc_get(parameters->format);
    if (descriptor && descriptor->nb_components > 0 && descriptor->comp[0].depth > 0) {
        depth = descriptor->comp[0].depth;
        int bitsPerPixel = av_get_bits_per_pixel(descriptor);
        if (bitsPerPixel > 0) samplesPerPixel = (double)bitsPerPixel / (double)depth;
    }
    if (samplesPerPixel <= 0) {
        depth = parameters->bits_per_raw_sample > 0
            ? parameters->bits_per_raw_sample
            : 8;
        samplesPerPixel = parameters->codec_id == AV_CODEC_ID_H264
            ? samples_per_pixel_for_h264_profile(parameters->profile)
            : samples_per_pixel_for_chroma420();
    }
    if (samplesPerPixel <= 0 || depth <= 0) return 0;
    double bytesPerSample = depth > 8
        ? (double)PB_SAMPLE_WORD_BYTES_ABOVE_EIGHT_BIT
        : (double)PB_SAMPLE_WORD_BYTES_AT_EIGHT_BIT;
    return samplesPerPixel * bytesPerSample;
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
    storage->info.reorderDepth = parameters->video_delay > 0
        ? parameters->video_delay
        : 0;
    storage->info.decodedBytesPerPixel = decoded_bytes_per_pixel(parameters);
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

static PBFFmpegMediaSourceInformation *copy_media_source_information(
    AVFormatContext *context,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!context || context->nb_streams > INT_MAX) {
        set_error(errorBuffer, errorBufferSize, "Media source has too many streams");
        return NULL;
    }
    PBFFmpegMediaSourceInformation *information = calloc(1, sizeof(*information));
    if (!information) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate media source information");
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
        return NULL;
    }
    copy_media_information_text(
        information->containerFormat,
        sizeof(information->containerFormat),
        context->iformat && context->iformat->name ? context->iformat->name : "unknown"
    );
    information->durationSeconds = media_source_duration_seconds(context);
    information->containerSupportsSourceFormatDescription =
        context_uses_mov_demuxer(context);
    int videoStreamIndex = av_find_best_stream(
        context,
        AVMEDIA_TYPE_VIDEO,
        -1,
        -1,
        NULL,
        0
    );
    PBVideoSourceFacts facts = video_source_facts(context, videoStreamIndex);
    information->dolbyVisionProfile = facts.dolbyVisionProfile;
    information->dolbyVisionCrossCompatibilityID =
        facts.dolbyVisionCrossCompatibilityID;
    information->dolbyVisionHasEnhancementLayer =
        facts.dolbyVisionHasEnhancementLayer;
    information->hasStereoVideoEnhancementLayer =
        facts.hasStereoVideoEnhancementLayer;
    for (int index = 0; index < information->streamCount; index++) {
        fill_media_stream_storage(&information->streams[index], context->streams[index]);
    }
    return information;
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
        result = finalize_stream_information(context, &sourceReadContext, true);
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Read audio stream information", result);
            close_media_source(&context, &sourceReadContext);
            return NULL;
        }
    }
    if (needsAudioProbe) {
        probe_delayed_audio_parameters(context);
        publish_source_bytes(&sourceReadContext);
    }

    PBFFmpegMediaSourceInformation *information = copy_media_source_information(
        context,
        errorBuffer,
        errorBufferSize
    );
    close_media_source(&context, &sourceReadContext);
    return information;
}

PBFFmpegDemuxSource *PBFFmpegDemuxSourceCreate(
    const char *path,
    bool isRemote,
    PBFFmpegDemuxBufferConfiguration bufferConfiguration,
    PBFFmpegSourceReadMonitor *monitor,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!path ||
        bufferConfiguration.mode < PBFFmpegDemuxBufferModeNone ||
        bufferConfiguration.mode > PBFFmpegDemuxBufferModeBytes ||
        bufferConfiguration.forwardByteLimit <= 0 ||
        bufferConfiguration.backwardByteLimit < 0 ||
        !isfinite(bufferConfiguration.targetDurationSeconds) ||
        bufferConfiguration.targetDurationSeconds <= 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg demux source call");
        return NULL;
    }
    PBFFmpegDemuxSource *source = calloc(1, sizeof(*source));
    if (!source) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg demux source");
        return NULL;
    }
    source->isRemote = isRemote;
    source->bufferConfiguration = bufferConfiguration;
    atomic_init(&source->interrupted, false);
    atomic_init(&source->permanentlyInterrupted, false);
    if (pthread_mutex_init(&source->lock, NULL) != 0) {
        set_error(errorBuffer, errorBufferSize, "Unable to initialize FFmpeg demux source");
        free(source);
        return NULL;
    }
    if (pthread_cond_init(&source->changed, NULL) != 0) {
        set_error(errorBuffer, errorBufferSize, "Unable to initialize FFmpeg demux source");
        pthread_mutex_destroy(&source->lock);
        free(source);
        return NULL;
    }
    source->path = av_strdup(path);
    source->sourceReadContext = &source->readContexts[0];
    source->sourceReadContext->monitor = monitor;
    source->formatContext = allocate_format_context(
        &source->interrupted,
        source->sourceReadContext
    );
    if (!source->path || !source->formatContext) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg demux context");
        PBFFmpegDemuxSourceDestroy(source);
        return NULL;
    }
    int result = open_media_source(
        &source->formatContext,
        path,
        source->sourceReadContext
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open demux media source", result);
        PBFFmpegDemuxSourceDestroy(source);
        return NULL;
    }
    PBStreamInformationRead informationRead = {0};
    result = read_stream_information(
        source->formatContext,
        source->sourceReadContext,
        &informationRead
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read demux stream information", result);
        PBFFmpegDemuxSourceDestroy(source);
        return NULL;
    }
    bool needsAudioProbe = false;
    for (unsigned int index = 0; index < source->formatContext->nb_streams; index++) {
        if (audio_stream_needs_more_probe(source->formatContext->streams[index])) {
            needsAudioProbe = true;
            break;
        }
    }
    if (needsAudioProbe && informationRead.skippedProbe) {
        result = finalize_stream_information(
            source->formatContext,
            source->sourceReadContext,
            true
        );
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Read demux audio information", result);
            PBFFmpegDemuxSourceDestroy(source);
            return NULL;
        }
    }
    if (needsAudioProbe) {
        probe_delayed_audio_parameters(source->formatContext);
        publish_source_bytes(source->sourceReadContext);
        result = avformat_seek_file(
            source->formatContext,
            -1,
            INT64_MIN,
            0,
            INT64_MAX,
            AVSEEK_FLAG_BACKWARD
        );
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Rewind demux media source", result);
            PBFFmpegDemuxSourceDestroy(source);
            return NULL;
        }
    }
    source->queueCount = source->formatContext->nb_streams;
    if (source->queueCount > 0) {
        source->queues = calloc(source->queueCount, sizeof(*source->queues));
        source->lastQueuedTimestamps = malloc(
            source->queueCount * sizeof(*source->lastQueuedTimestamps)
        );
        source->replayThroughTimestamps = malloc(
            source->queueCount * sizeof(*source->replayThroughTimestamps)
        );
        source->replayCaughtUp = calloc(
            source->queueCount,
            sizeof(*source->replayCaughtUp)
        );
    }
    if (source->queueCount > 0 &&
        (!source->queues || !source->lastQueuedTimestamps ||
         !source->replayThroughTimestamps || !source->replayCaughtUp)) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg packet queues");
        PBFFmpegDemuxSourceDestroy(source);
        return NULL;
    }
    for (unsigned int index = 0; index < source->queueCount; index++) {
        source->lastQueuedTimestamps[index] = AV_NOPTS_VALUE;
        source->replayThroughTimestamps[index] = AV_NOPTS_VALUE;
        source->replayCaughtUp[index] = true;
        enum AVMediaType type =
            source->formatContext->streams[index]->codecpar->codec_type;
        source->queues[index].isAuxiliary = type != AVMEDIA_TYPE_VIDEO &&
            type != AVMEDIA_TYPE_AUDIO;
    }
    if (source->formatContext->pb) {
        int64_t length = avio_size(source->formatContext->pb);
        if (length > 0) source->knownByteLength = length;
    }
    source->videoStreamIndex = av_find_best_stream(
        source->formatContext,
        AVMEDIA_TYPE_VIDEO,
        -1,
        -1,
        NULL,
        0
    );
    source->prebuffersAudio = true;
    return source;
}

bool PBFFmpegDemuxSourceInterruptTargetsOwnReadContext(
    const PBFFmpegDemuxSource *source
) {
    return source && source->formatContext &&
        source->formatContext->interrupt_callback.opaque == source->sourceReadContext;
}

void PBFFmpegDemuxSourceInterrupt(PBFFmpegDemuxSource *source) {
    if (!source) return;
    atomic_store_explicit(
        &source->permanentlyInterrupted,
        true,
        memory_order_seq_cst
    );
    atomic_store_explicit(&source->interrupted, true, memory_order_seq_cst);
    pthread_cond_broadcast(&source->changed);
}

void PBFFmpegDemuxSourceDestroy(PBFFmpegDemuxSource *source) {
    if (!source) return;
    stop_demux_source_read_thread(source);
    for (unsigned int index = 0; index < source->queueCount; index++) {
        clear_packet_queue(source, &source->queues[index]);
    }
    PBFFmpegPacketNodePoolChunk *chunk = source->packetNodePoolChunks;
    while (chunk) {
        PBFFmpegPacketNodePoolChunk *next = chunk->next;
        free(chunk);
        chunk = next;
    }
    free(source->queues);
    free(source->lastQueuedTimestamps);
    free(source->replayThroughTimestamps);
    free(source->replayCaughtUp);
    close_media_source(&source->formatContext, source->sourceReadContext);
    av_free(source->path);
    pthread_cond_destroy(&source->changed);
    pthread_mutex_destroy(&source->lock);
    free(source);
}

PBFFmpegMediaSourceInformation *PBFFmpegDemuxSourceCopyInformation(
    PBFFmpegDemuxSource *source,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!source || !source->formatContext) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg demux source information call");
        return NULL;
    }
    return copy_media_source_information(
        source->formatContext,
        errorBuffer,
        errorBufferSize
    );
}

bool PBFFmpegDemuxSourceSeek(
    PBFFmpegDemuxSource *source,
    double seconds,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!source || !source->formatContext || !isfinite(seconds) || seconds < 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg demux seek call");
        return false;
    }
    stop_demux_source_read_thread(source);
    pthread_mutex_lock(&source->lock);
    for (unsigned int index = 0; index < source->queueCount; index++) {
        clear_packet_queue(source, &source->queues[index]);
        source->lastQueuedTimestamps[index] = AV_NOPTS_VALUE;
        source->replayThroughTimestamps[index] = AV_NOPTS_VALUE;
        source->replayCaughtUp[index] = true;
    }
    source->reachedEnd = false;
    source->readResult = 0;
    source->prebuffersAudio = true;
    pthread_mutex_unlock(&source->lock);
    int64_t timestamp = (int64_t)llround(seconds * AV_TIME_BASE);
    int result = avformat_seek_file(
        source->formatContext,
        -1,
        INT64_MIN,
        timestamp,
        INT64_MAX,
        AVSEEK_FLAG_BACKWARD
    );
    publish_source_bytes(source->sourceReadContext);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Seek demux media source", result);
        return false;
    }
    return true;
}

double PBFFmpegDemuxSourceGetBufferedDurationSeconds(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    int64_t shortest = INT64_MAX;
    bool found = false;
    for (unsigned int index = 0; index < source->queueCount; index++) {
        const PBFFmpegPacketQueue *queue = &source->queues[index];
        if (queue->subscribers == 0) continue;
        if (queue->bufferedDurationMicroseconds < shortest) {
            shortest = queue->bufferedDurationMicroseconds;
        }
        found = true;
    }
    pthread_mutex_unlock(&source->lock);
    return found ? (double)shortest / AV_TIME_BASE : 0;
}

double PBFFmpegDemuxSourceGetBufferTargetDurationSeconds(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    double seconds = source->bufferConfiguration.targetDurationSeconds;
    pthread_mutex_unlock(&source->lock);
    return seconds;
}

int64_t PBFFmpegDemuxSourceGetForwardBufferedByteCount(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    int64_t count = source->forwardBufferedByteCount;
    pthread_mutex_unlock(&source->lock);
    return count;
}

bool PBFFmpegHasDemuxer(const char *name) {
    if (!name) return false;
    return av_find_input_format(name) != NULL;
}

bool PBFFmpegHasDecoder(const char *name) {
    if (!name) return false;
    return avcodec_find_decoder_by_name(name) != NULL;
}

bool PBFFmpegHasInputProtocol(const char *name) {
    if (!name) return false;
    void *opaque = NULL;
    const char *protocol = NULL;
    while ((protocol = avio_enum_protocols(&opaque, 0)) != NULL) {
        if (strcmp(protocol, name) == 0) return true;
    }
    return false;
}

int64_t PBFFmpegDemuxSourceGetAuxiliaryBufferedByteCount(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    int64_t count = source->auxiliaryBufferedByteCount;
    pthread_mutex_unlock(&source->lock);
    return count;
}

uint64_t PBFFmpegDemuxSourceGetDroppedPacketCount(
    PBFFmpegDemuxSource *source,
    int streamIndex
) {
    if (!source || streamIndex < 0 ||
        (unsigned int)streamIndex >= source->queueCount) return 0;
    pthread_mutex_lock(&source->lock);
    uint64_t count = source->queues[streamIndex].droppedPacketCount;
    pthread_mutex_unlock(&source->lock);
    return count;
}

int64_t PBFFmpegDemuxSourceGetForwardBufferByteLimit(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    int64_t limit = source->bufferConfiguration.forwardByteLimit;
    pthread_mutex_unlock(&source->lock);
    return limit;
}

int64_t PBFFmpegDemuxSourceGetRetainedByteCount(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    int64_t retained = source->retainedByteCount;
    pthread_mutex_unlock(&source->lock);
    return retained;
}

int64_t PBFFmpegDemuxSourceGetBackwardBufferByteLimit(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    int64_t limit = source->bufferConfiguration.backwardByteLimit;
    pthread_mutex_unlock(&source->lock);
    return limit;
}

PBFFmpegDemuxBufferMode PBFFmpegDemuxSourceGetBufferMode(
    PBFFmpegDemuxSource *source
) {
    if (!source) return PBFFmpegDemuxBufferModeNone;
    pthread_mutex_lock(&source->lock);
    PBFFmpegDemuxBufferMode mode = source->bufferConfiguration.mode;
    pthread_mutex_unlock(&source->lock);
    return mode;
}

uint64_t PBFFmpegDemuxSourceGetReadFrameCount(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    uint64_t count = source->readFrameCount;
    pthread_mutex_unlock(&source->lock);
    return count;
}

unsigned int PBFFmpegDemuxSourceGetReconnectAttemptCount(
    PBFFmpegDemuxSource *source
) {
    if (!source) return 0;
    pthread_mutex_lock(&source->lock);
    unsigned int count = source->reconnectAttemptCount;
    pthread_mutex_unlock(&source->lock);
    return count;
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

bool PBFFmpegMediaSourceInformationContainerSupportsSourceFormatDescription(
    const PBFFmpegMediaSourceInformation *information
) {
    return information
        ? information->containerSupportsSourceFormatDescription
        : false;
}

int PBFFmpegMediaSourceInformationGetDolbyVisionProfile(
    const PBFFmpegMediaSourceInformation *information
) {
    return information ? information->dolbyVisionProfile : 0;
}

int PBFFmpegMediaSourceInformationGetDolbyVisionCrossCompatibilityID(
    const PBFFmpegMediaSourceInformation *information
) {
    return information ? information->dolbyVisionCrossCompatibilityID : 0;
}

bool PBFFmpegMediaSourceInformationDolbyVisionHasEnhancementLayer(
    const PBFFmpegMediaSourceInformation *information
) {
    return information ? information->dolbyVisionHasEnhancementLayer : false;
}

bool PBFFmpegMediaSourceInformationHasStereoVideoEnhancementLayer(
    const PBFFmpegMediaSourceInformation *information
) {
    return information ? information->hasStereoVideoEnhancementLayer : false;
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

static bool configure_video_reader(
    PBFFmpegReader *reader,
    PBFFmpegMode mode,
    double startSeconds,
    bool seeksContext,
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
    int result = 0;
    reader->videoStreamIndex = av_find_best_stream(
        reader->formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0
    );
    if (reader->videoStreamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "The selected source has no video stream");
        return false;
    }
    if (reader->demuxSource &&
        !subscribe_to_demux_stream(reader->demuxSource, reader->videoStreamIndex)) {
        set_error(errorBuffer, errorBufferSize, "The shared video stream already has a reader");
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
        if (dovi_declaration_shape(stream->codecpar) == PBDOVIDeclarationUnknown) {
            char declaration[256];
            char message[512];
            describe_dovi_declaration(
                stream->codecpar,
                declaration,
                sizeof(declaration)
            );
            snprintf(
                message,
                sizeof(message),
                "Unknown Dolby Vision declaration shape; codec=%s tag=%s color_primaries=%s transfer=%s matrix=%s range=%s %s",
                avcodec_get_name(stream->codecpar->codec_id),
                reader->codecTag[0] ? reader->codecTag : "unknown",
                reader->colorPrimaries,
                reader->transferFunction,
                reader->yCbCrMatrix,
                reader->colorRange,
                declaration
            );
            set_error(errorBuffer, errorBufferSize, message);
            return false;
        }
        OSType compressedType = codec_type(stream->codecpar);
        if (!compressed_codec_is_renderable(compressedType)) {
            reader->unsupportedVideoCodec = true;
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
        result = configure_dolby_vision_base_layer_split(
            reader,
            stream,
            errorBuffer,
            errorBufferSize
        );
        if (result < 0) return false;
        if (cancellation_requested(&reader->cancelled)) return false;
        OSStatus status = PBFFmpegVideoFormatDescriptionCreate(
            reader,
            NULL,
            NULL,
            NULL,
            &reader->compressedFormat
        );
        if (status != noErr) {
            char declaration[256];
            describe_dovi_declaration(
                stream->codecpar,
                declaration,
                sizeof(declaration)
            );
            char message[512];
            snprintf(
                message,
                sizeof(message),
                "Create compressed CMVideoFormatDescription failed (%d); codec=%s tag=%s extradata=%d bootstrapPackets=%zu color_primaries=%s transfer=%s matrix=%s range=%s %s",
                (int)status,
                avcodec_get_name(stream->codecpar->codec_id),
                reader->codecTag[0] ? reader->codecTag : "unknown",
                stream->codecpar->extradata_size,
                reader->bootstrapPacketCount,
                reader->colorPrimaries,
                reader->transferFunction,
                reader->yCbCrMatrix,
                reader->colorRange,
                declaration
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
    if (reader->dolbyVisionSplitFilter) {
        reader->filteredPacket = av_packet_alloc();
    }
    if (reader->packet == NULL ||
        (reader->dolbyVisionSplitFilter && reader->filteredPacket == NULL)) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg packet");
        return false;
    }

    if (seeksContext && startSeconds > 0) {
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

bool PBFFmpegReaderOpen(
    PBFFmpegReader *reader,
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!reader || !path) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg reader call");
        return false;
    }
    reader->formatContext = allocate_format_context(
        &reader->cancelled,
        &reader->sourceReadContext
    );
    if (!reader->formatContext) {
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
    result = read_stream_information(
        reader->formatContext,
        &reader->sourceReadContext,
        NULL
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read stream information", result);
        return false;
    }
    return configure_video_reader(
        reader,
        mode,
        startSeconds,
        true,
        errorBuffer,
        errorBufferSize
    );
}

bool PBFFmpegReaderOpenWithDemuxSource(
    PBFFmpegReader *reader,
    PBFFmpegDemuxSource *source,
    PBFFmpegMode mode,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!reader || !source || !source->formatContext) {
        set_error(errorBuffer, errorBufferSize, "Invalid shared FFmpeg reader call");
        return false;
    }
    reader->demuxSource = source;
    reader->formatContext = source->formatContext;
    bool opened = configure_video_reader(
        reader,
        mode,
        0,
        false,
        errorBuffer,
        errorBufferSize
    );
    if (opened && !begin_demux_source_prefetch(source)) {
        set_error(errorBuffer, errorBufferSize, "Unable to start FFmpeg demux prefetch");
        return false;
    }
    return opened;
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
    if (!reader) return;
    atomic_store_explicit(&reader->cancelled, true, memory_order_relaxed);
    if (reader->demuxSource) {
        pthread_mutex_lock(&reader->demuxSource->lock);
        pthread_cond_broadcast(&reader->demuxSource->changed);
        pthread_mutex_unlock(&reader->demuxSource->lock);
    }
}

void PBFFmpegReaderForceBitstreamExtradataBootstrapOnNextOpen(PBFFmpegReader *reader) {
    if (reader) reader->forceBitstreamExtradataBootstrap = true;
}

bool PBFFmpegReaderUsedBitstreamExtradataBootstrap(const PBFFmpegReader *reader) {
    return reader && reader->usedBitstreamExtradataBootstrap;
}

void PBFFmpegReaderDestroy(PBFFmpegReader *reader) {
    if (reader == NULL) return;
    if (reader->compressedFormat) CFRelease(reader->compressedFormat);
    discard_bootstrap_packets(reader);
    av_bsf_free(&reader->dolbyVisionSplitFilter);
    free(reader->pendingHEVCParameterSets);
    av_packet_free(&reader->filteredPacket);
    av_packet_free(&reader->packet);
    if (reader->demuxSource) {
        unsubscribe_from_demux_stream(reader->demuxSource, reader->videoStreamIndex);
    } else {
        close_media_source(&reader->formatContext, &reader->sourceReadContext);
    }
    free(reader);
}

PBFFmpegMediaSourceInformation *PBFFmpegReaderCopyMediaSourceInformation(
    const PBFFmpegReader *reader
) {
    if (!reader) return NULL;
    if (reader->demuxSource) {
        pthread_mutex_lock(&reader->demuxSource->lock);
        PBFFmpegMediaSourceInformation *information =
            reader->demuxSource->formatContext
                ? copy_media_source_information(
                    reader->demuxSource->formatContext,
                    NULL,
                    0
                )
                : NULL;
        pthread_mutex_unlock(&reader->demuxSource->lock);
        return information;
    }
    return reader->formatContext
        ? copy_media_source_information(reader->formatContext, NULL, 0)
        : NULL;
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

static int read_next_source_video_packet(PBFFmpegReader *reader) {
    AVPacket *packet = reader->packet;
    while (true) {
        int result = 0;
        if (reader->bootstrapPacketIndex < reader->bootstrapPacketCount) {
            AVPacket **buffered = &reader->bootstrapPackets[reader->bootstrapPacketIndex++];
            av_packet_move_ref(packet, *buffered);
            av_packet_free(buffered);
        } else {
            result = reader->demuxSource
                ? copy_next_demux_packet(
                    reader->demuxSource,
                    reader->videoStreamIndex,
                    &reader->cancelled,
                    packet
                )
                : av_read_frame(reader->formatContext, packet);
            if (!reader->demuxSource) publish_source_bytes(&reader->sourceReadContext);
        }
        if (result < 0) return result;
        if (packet->stream_index == reader->videoStreamIndex) return 0;
        av_packet_unref(packet);
    }
}

static int read_next_compressed_video_packet(
    PBFFmpegReader *reader,
    AVPacket **packetOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!reader->dolbyVisionSplitFilter) {
        int result = read_next_source_video_packet(reader);
        if (result >= 0) *packetOut = reader->packet;
        return result;
    }

    while (true) {
        int result = av_bsf_receive_packet(
            reader->dolbyVisionSplitFilter,
            reader->filteredPacket
        );
        if (result == 0) {
            *packetOut = reader->filteredPacket;
            return 0;
        }
        if (result == AVERROR_EOF) return result;
        if (result != AVERROR(EAGAIN)) {
            set_av_error(
                errorBuffer,
                errorBufferSize,
                "Read Dolby Vision Profile 7 base layer",
                result
            );
            return result;
        }

        if (reader->inputEnded) {
            if (reader->filterDrained) return AVERROR_EOF;
            result = av_bsf_send_packet(reader->dolbyVisionSplitFilter, NULL);
            reader->filterDrained = true;
            if (result < 0 && result != AVERROR_EOF) {
                set_av_error(
                    errorBuffer,
                    errorBufferSize,
                    "Finish Dolby Vision Profile 7 base-layer split",
                    result
                );
                return result;
            }
            continue;
        }

        result = read_next_source_video_packet(reader);
        if (result < 0) {
            if (result == AVERROR_EXIT ||
                atomic_load_explicit(&reader->cancelled, memory_order_relaxed)) {
                return result;
            }
            if (result != AVERROR_EOF) {
                set_av_error(
                    errorBuffer,
                    errorBufferSize,
                    "Read Dolby Vision Profile 7 source packet",
                    result
                );
                return result;
            }
            reader->inputEnded = true;
            continue;
        }
        result = av_bsf_send_packet(reader->dolbyVisionSplitFilter, reader->packet);
        av_packet_unref(reader->packet);
        if (result < 0) {
            set_av_error(
                errorBuffer,
                errorBufferSize,
                "Prepare Dolby Vision Profile 7 base-layer packet",
                result
            );
            return result;
        }
    }
}

enum {
    PB_HEVC_NAL_TYPE_LAST_VCL = 31,
    PB_HEVC_NAL_TYPE_VPS = 32,
    PB_HEVC_NAL_TYPE_SPS = 33,
    PB_HEVC_NAL_TYPE_PPS = 34,
};

static bool is_hevc_parameter_set(uint8_t nalType) {
    return nalType == PB_HEVC_NAL_TYPE_VPS ||
        nalType == PB_HEVC_NAL_TYPE_SPS ||
        nalType == PB_HEVC_NAL_TYPE_PPS;
}

static bool prepare_profile7_base_layer_sample_bytes(
    PBFFmpegReader *reader,
    const AVPacket *packet,
    const uint8_t **bytesOut,
    size_t *byteCountOut,
    uint8_t **allocatedBytesOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    *bytesOut = packet->data;
    *byteCountOut = (size_t)packet->size;
    *allocatedBytesOut = NULL;
    if (!reader->reordersProfile7BaseLayerParameterSets) return true;

    size_t lengthSize = reader->hevcNALLengthSize;
    if (!packet->data || packet->size <= 0 ||
        reader->pendingHEVCParameterSetSize > SIZE_MAX - (size_t)packet->size) {
        set_error(errorBuffer, errorBufferSize, "Profile 7 base-layer sample is empty or too large");
        return false;
    }
    size_t packetSize = (size_t)packet->size;
    uint8_t *output = malloc(reader->pendingHEVCParameterSetSize + packetSize);
    uint8_t *nextParameterSets = malloc(packetSize);
    if (!output || !nextParameterSets) {
        free(output);
        free(nextParameterSets);
        set_error(errorBuffer, errorBufferSize, "Prepare Profile 7 base-layer sample failed");
        return false;
    }

    size_t outputSize = reader->pendingHEVCParameterSetSize;
    if (outputSize > 0) {
        memcpy(output, reader->pendingHEVCParameterSets, outputSize);
    }
    size_t nextParameterSetSize = 0;
    size_t offset = 0;
    bool sawVCL = false;
    while (offset + lengthSize <= packetSize) {
        size_t nalStart = offset;
        uint32_t nalSize = 0;
        for (size_t index = 0; index < lengthSize; index++) {
            nalSize = (nalSize << 8) | packet->data[offset + index];
        }
        offset += lengthSize;
        if (nalSize == 0 || nalSize > packetSize - offset) {
            free(output);
            free(nextParameterSets);
            set_error(errorBuffer, errorBufferSize, "Profile 7 base-layer sample has invalid HEVC NAL lengths");
            return false;
        }
        uint8_t nalType = (packet->data[offset] >> 1) & 0x3f;
        if (nalType <= PB_HEVC_NAL_TYPE_LAST_VCL) sawVCL = true;
        bool belongsToTheNextAccessUnit = sawVCL && is_hevc_parameter_set(nalType);
        size_t encodedNALSize = lengthSize + (size_t)nalSize;
        uint8_t *destination = belongsToTheNextAccessUnit
            ? nextParameterSets + nextParameterSetSize
            : output + outputSize;
        memcpy(destination, packet->data + nalStart, encodedNALSize);
        if (belongsToTheNextAccessUnit) {
            nextParameterSetSize += encodedNALSize;
        } else {
            outputSize += encodedNALSize;
        }
        offset += nalSize;
    }
    if (offset != packetSize || outputSize == 0) {
        free(output);
        free(nextParameterSets);
        set_error(errorBuffer, errorBufferSize, "Profile 7 base-layer sample is not length-prefixed HEVC");
        return false;
    }

    free(reader->pendingHEVCParameterSets);
    reader->pendingHEVCParameterSets = nextParameterSetSize > 0
        ? nextParameterSets
        : NULL;
    reader->pendingHEVCParameterSetSize = nextParameterSetSize;
    if (nextParameterSetSize == 0) free(nextParameterSets);
    *bytesOut = output;
    *byteCountOut = outputSize;
    *allocatedBytesOut = output;
    return true;
}

static PBFFmpegReadResult copy_compressed_sample(
    PBFFmpegReader *reader,
    CMSampleBufferRef *sampleOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    while (true) {
        if (atomic_load_explicit(&reader->cancelled, memory_order_relaxed)) {
            return PBFFmpegReadResultCancelled;
        }
        AVPacket *packet = NULL;
        int readResult = read_next_compressed_video_packet(
            reader,
            &packet,
            errorBuffer,
            errorBufferSize
        );
        if (readResult < 0) {
            if (readResult == AVERROR_EXIT
                || atomic_load_explicit(&reader->cancelled, memory_order_relaxed)) {
                return PBFFmpegReadResultCancelled;
            }
            if (readResult != AVERROR_EOF) {
                set_av_error(
                    errorBuffer,
                    errorBufferSize,
                    "Read demuxed video packet",
                    readResult
                );
                reader->lastActiveFailureCause =
                    active_failure_cause_for_av_error(readResult);
                return PBFFmpegReadResultError;
            }
            return PBFFmpegReadResultEnd;
        }

        const uint8_t *sampleBytes = NULL;
        size_t sampleByteCount = 0;
        uint8_t *preparedBytes = NULL;
        if (!prepare_profile7_base_layer_sample_bytes(
                reader,
                packet,
                &sampleBytes,
                &sampleByteCount,
                &preparedBytes,
                errorBuffer,
                errorBufferSize
            )) {
            av_packet_unref(packet);
            return PBFFmpegReadResultError;
        }
        uint8_t *convertedBytes = NULL;
        if (reader->convertsAnnexB) {
            convertedBytes = copy_annexb_as_length_prefixed(
                sampleBytes, sampleByteCount, &sampleByteCount
            );
            if (!convertedBytes) {
                free(preparedBytes);
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
            if (packet->dts != AV_NOPTS_VALUE) {
                CMSetAttachment(*sampleOut, CFSTR("PBFFmpegExplicitDecodeTime"),
                    kCFBooleanTrue, kCMAttachmentMode_ShouldNotPropagate);
            }
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(*sampleOut, true);
            if (!(packet->flags & AV_PKT_FLAG_KEY) &&
                attachments && CFArrayGetCount(attachments) > 0) {
                CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
                CFDictionarySetValue(attachment, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
            }
        }
        if (block) CFRelease(block);
        free(preparedBytes);
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

CMTime PBFFmpegSampleGetPresentationTimeLowerBound(CMSampleBufferRef sample) {
    if (!sample || CMGetAttachment(sample, CFSTR("PBFFmpegExplicitDecodeTime"), NULL) != kCFBooleanTrue) {
        return kCMTimeInvalid;
    }
    return CMSampleBufferGetDecodeTimeStamp(sample);
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
    reader->lastActiveFailureCause = PBFFmpegActiveFailureCauseNone;
    return copy_compressed_sample(reader, sampleOut, errorBuffer, errorBufferSize);
}

PBFFmpegActiveFailureCause PBFFmpegReaderGetLastActiveFailureCause(
    const PBFFmpegReader *reader
) {
    return reader
        ? reader->lastActiveFailureCause
        : PBFFmpegActiveFailureCauseNone;
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

bool PBFFmpegReaderOpenFailedWithUnsupportedVideoCodec(
    const PBFFmpegReader *reader
) {
    return reader && reader->unsupportedVideoCodec;
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

static int supported_audio_stream_index(AVFormatContext *context) {
    int index = av_find_best_stream(context, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (index >= 0 && audio_stream_is_supported(context->streams[index])) return index;
    for (unsigned int candidate = 0; candidate < context->nb_streams; candidate++) {
        if (audio_stream_is_supported(context->streams[candidate])) return (int)candidate;
    }
    return -1;
}

static bool configure_audio_reader(
    PBFFmpegAudioReader *reader,
    double startSeconds,
    int preferredStreamIndex,
    bool seeksContext,
    const char *path,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio reader");
        return false;
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    reader->audioStreamIndex = -1;
    int result = 0;

    if (preferredStreamIndex >= 0) {
        if (preferredStreamIndex >= (int)reader->formatContext->nb_streams ||
            !is_audio_stream(reader->formatContext->streams[preferredStreamIndex])) {
            set_error(errorBuffer, errorBufferSize, "The selected audio stream is unavailable");
            return false;
        }
        AVStream *preferredStream = reader->formatContext->streams[preferredStreamIndex];
        if (!audio_codec_is_supported(preferredStream->codecpar)) {
            char message[160];
            snprintf(
                message,
                sizeof(message),
                "Audio codec %s is unsupported because FFmpeg has no decoder",
                avcodec_get_name(preferredStream->codecpar->codec_id)
            );
            set_error(errorBuffer, errorBufferSize, message);
            return false;
        }
        if (!audio_stream_is_supported(preferredStream) &&
            !probe_extended_audio_parameters(
                preferredStream,
                path,
                &reader->cancelled,
                reader->sourceReadContext.monitor
            )) {
            set_error(
                errorBuffer,
                errorBufferSize,
                "Audio stream parameters are unavailable after extended probe"
            );
            return false;
        }
        reader->audioStreamIndex = preferredStreamIndex;
    } else {
        reader->audioStreamIndex = supported_audio_stream_index(reader->formatContext);
        if (reader->audioStreamIndex < 0) {
            for (unsigned int index = 0; index < reader->formatContext->nb_streams; index++) {
                if (probe_extended_audio_parameters(
                        reader->formatContext->streams[index],
                        path,
                        &reader->cancelled,
                        reader->sourceReadContext.monitor
                    )) break;
            }
            reader->audioStreamIndex = supported_audio_stream_index(reader->formatContext);
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
    if (reader->demuxSource &&
        !subscribe_to_demux_stream(reader->demuxSource, reader->audioStreamIndex)) {
        set_error(errorBuffer, errorBufferSize, "The shared audio stream already has a reader");
        return false;
    }

    AVStream *stream = reader->formatContext->streams[reader->audioStreamIndex];
    reader->codecParameters = avcodec_parameters_alloc();
    if (!reader->codecParameters ||
        avcodec_parameters_copy(reader->codecParameters, stream->codecpar) < 0) {
        set_error(errorBuffer, errorBufferSize, "Unable to copy audio codec parameters");
        return false;
    }
    reader->sampleRate = stream->codecpar->sample_rate;
    reader->channelCount = stream->codecpar->ch_layout.nb_channels;
    snprintf(
        reader->codecName,
        sizeof(reader->codecName),
        "%s",
        avcodec_get_name(stream->codecpar->codec_id)
    );
    if (reader->sampleRate <= 0 || reader->channelCount <= 0) {
        set_error(errorBuffer, errorBufferSize, "Audio stream has invalid sample rate or channel layout");
        return false;
    }
    reader->packet = av_packet_alloc();
    reader->outputsPCM = !audio_codec_uses_compressed_passthrough(stream->codecpar);
    reader->timeBase = stream->time_base;
    reader->startTimestamp = stream_start_timestamp(reader->formatContext, stream);
    reader->nextPCMSample = 0;
    reader->decodedInputFormat = AV_SAMPLE_FMT_NONE;
    reader->decodedFifoStartTimestamp = AV_NOPTS_VALUE;
    if (reader->packet == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio packet");
        return false;
    }

    if (reader->outputsPCM) {
        const AVCodec *decoder = avcodec_find_decoder(stream->codecpar->codec_id);
        if (!decoder) {
            char message[160];
            snprintf(
                message,
                sizeof(message),
                "Audio codec %s is unsupported because FFmpeg has no decoder",
                reader->codecName
            );
            set_error(errorBuffer, errorBufferSize, message);
            return false;
        }
        reader->decoder = avcodec_alloc_context3(decoder);
        reader->decodedFrame = av_frame_alloc();
        reader->decoderBatchPacket = av_packet_alloc();
        if (!reader->decoder || !reader->decodedFrame ||
            !reader->decoderBatchPacket) {
            set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio decoder");
            return false;
        }
        result = avcodec_parameters_to_context(reader->decoder, stream->codecpar);
        if (result >= 0) {
            reader->decoder->pkt_timebase = stream->time_base;
            result = avcodec_open2(reader->decoder, decoder, NULL);
        }
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Open FFmpeg audio decoder", result);
            return false;
        }
        if (av_channel_layout_copy(
                &reader->outputChannelLayout,
                &stream->codecpar->ch_layout
            ) < 0) {
            set_error(errorBuffer, errorBufferSize, "Unable to copy decoded audio channel layout");
            return false;
        }
    }

    if (seeksContext && startSeconds > 0) {
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
        if (reader->decoder) avcodec_flush_buffers(reader->decoder);
    }
    if (cancellation_requested(&reader->cancelled)) return false;
    return true;
}

bool PBFFmpegAudioReaderOpen(
    PBFFmpegAudioReader *reader,
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!reader || !path) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg audio reader call");
        return false;
    }
    int result = open_media_source_for_audio(
        path,
        &reader->formatContext,
        &reader->cancelled,
        &reader->sourceReadContext,
        errorBuffer,
        errorBufferSize
    );
    if (result < 0) return false;
    return configure_audio_reader(
        reader,
        startSeconds,
        preferredStreamIndex,
        true,
        path,
        errorBuffer,
        errorBufferSize
    );
}

bool PBFFmpegAudioReaderOpenWithDemuxSource(
    PBFFmpegAudioReader *reader,
    PBFFmpegDemuxSource *source,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!reader || !source || !source->formatContext) {
        set_error(errorBuffer, errorBufferSize, "Invalid shared FFmpeg audio reader call");
        return false;
    }
    reader->demuxSource = source;
    reader->formatContext = source->formatContext;
    bool opened = configure_audio_reader(
        reader,
        0,
        preferredStreamIndex,
        false,
        source->path,
        errorBuffer,
        errorBufferSize
    );
    if (opened) {
        pthread_mutex_lock(&source->lock);
        source->prebuffersAudio = false;
        pthread_mutex_unlock(&source->lock);
    }
    if (opened && !begin_demux_source_prefetch(source)) {
        set_error(errorBuffer, errorBufferSize, "Unable to start FFmpeg demux prefetch");
        return false;
    }
    return opened;
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
    if (!reader) return;
    atomic_store_explicit(&reader->cancelled, true, memory_order_relaxed);
    if (reader->demuxSource) {
        pthread_mutex_lock(&reader->demuxSource->lock);
        pthread_cond_broadcast(&reader->demuxSource->changed);
        pthread_mutex_unlock(&reader->demuxSource->lock);
    }
}

void PBFFmpegAudioReaderDestroy(PBFFmpegAudioReader *reader) {
    if (reader == NULL) return;
    if (reader->formatDescription) CFRelease(reader->formatDescription);
    free(reader->pendingPCMData);
    av_audio_fifo_free(reader->decodedAudioFifo);
    if (reader->decodedBatchData) {
        av_freep(&reader->decodedBatchData[0]);
        av_freep(&reader->decodedBatchData);
    }
    swr_free(&reader->resampler);
    av_channel_layout_uninit(&reader->outputChannelLayout);
    av_frame_free(&reader->decodedFrame);
    avcodec_free_context(&reader->decoder);
    avcodec_parameters_free(&reader->codecParameters);
    av_packet_free(&reader->decoderBatchPacket);
    av_packet_free(&reader->packet);
    if (reader->demuxSource) {
        return_packet_node_list(reader->demuxSource, &reader->demuxPacketBatch);
        return_packet_node_list(
            reader->demuxSource,
            &reader->consumedDemuxPacketBatch
        );
        unsubscribe_from_demux_stream(reader->demuxSource, reader->audioStreamIndex);
    } else {
        close_media_source(&reader->formatContext, &reader->sourceReadContext);
    }
    free(reader);
}

static int decoded_audio_minimum_buffer_frames(const PBFFmpegAudioReader *reader) {
    if (!reader || reader->sampleRate <= 0) return 1;
    int frames = reader->codecParameters &&
            reader->codecParameters->codec_id == AV_CODEC_ID_TRUEHD
        ? reader->sampleRate / 10
        : reader->sampleRate / 50;
    return frames > 0 ? frames : 1;
}

static int read_next_audio_packet(
    PBFFmpegAudioReader *reader,
    AVPacket *packet
) {
    int result = reader->demuxSource
        ? copy_next_demux_packet_batch(
            reader->demuxSource,
            reader->audioStreamIndex,
            &reader->cancelled,
            &reader->demuxPacketBatch,
            &reader->consumedDemuxPacketBatch,
            packet
        )
        : av_read_frame(reader->formatContext, packet);
    if (!reader->demuxSource) publish_source_bytes(&reader->sourceReadContext);
    return result;
}

static int aggregate_truehd_decoder_packet(PBFFmpegAudioReader *reader) {
    if (!reader || !reader->packet || !reader->decoderBatchPacket ||
        !reader->codecParameters ||
        reader->codecParameters->codec_id != AV_CODEC_ID_TRUEHD) {
        return 0;
    }
    int64_t targetDuration = av_rescale_q(
        decoded_audio_minimum_buffer_frames(reader),
        (AVRational){1, reader->sampleRate},
        reader->timeBase
    );
    int64_t accumulatedDuration = FFMAX(reader->packet->duration, 0);
    unsigned int packetCount = 1;
    while (accumulatedDuration < targetDuration &&
           packetCount < PB_TRUEHD_DECODER_PACKET_BATCH_LIMIT) {
        int result = read_next_audio_packet(reader, reader->decoderBatchPacket);
        if (result < 0) {
            reader->inputEnded = true;
            reader->inputReadResult = result;
            if (result == AVERROR_EOF) break;
            return result;
        }
        if (reader->decoderBatchPacket->stream_index != reader->audioStreamIndex) {
            av_packet_unref(reader->decoderBatchPacket);
            continue;
        }
        int packetSize = reader->packet->size;
        result = av_grow_packet(
            reader->packet,
            reader->decoderBatchPacket->size
        );
        if (result < 0) {
            av_packet_unref(reader->decoderBatchPacket);
            return result;
        }
        memcpy(
            reader->packet->data + packetSize,
            reader->decoderBatchPacket->data,
            reader->decoderBatchPacket->size
        );
        reader->packet->duration += reader->decoderBatchPacket->duration;
        accumulatedDuration += FFMAX(reader->decoderBatchPacket->duration, 0);
        packetCount++;
        av_packet_unref(reader->decoderBatchPacket);
    }
    reader->trueHDDecoderInputPacketCount += packetCount;
    reader->trueHDDecoderBatchCount++;
    if (packetCount > 1) reader->trueHDAggregatedDecoderBatchCount++;
    reader->trueHDLastDecoderBatchInputPacketCount = packetCount;
    return 0;
}

static PBFFmpegReadResult emit_pending_decoded_audio_sample(
    PBFFmpegAudioReader *reader,
    CMSampleBufferRef *sampleOut,
    PBFFmpegAudioSampleMetadata *metadataOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader->pendingPCMFrameCount <= 0) return PBFFmpegReadResultEnd;
    if (!reader->formatDescription || !reader->pendingPCMData) {
        set_error(errorBuffer, errorBufferSize, "Decoded PCM aggregation state is incomplete");
        return PBFFmpegReadResultError;
    }

    size_t bytesPerFrame = (size_t)reader->channelCount * sizeof(float);
    size_t expectedByteCount = (size_t)reader->pendingPCMFrameCount * bytesPerFrame;
    if (expectedByteCount != reader->pendingPCMByteCount) {
        set_error(errorBuffer, errorBufferSize, "Decoded PCM aggregation size is inconsistent");
        return PBFFmpegReadResultError;
    }

    CMBlockBufferRef block = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault,
        NULL,
        reader->pendingPCMByteCount,
        kCFAllocatorDefault,
        NULL,
        0,
        reader->pendingPCMByteCount,
        0,
        &block
    );
    if (status == noErr) {
        status = CMBlockBufferReplaceDataBytes(
            reader->pendingPCMData,
            block,
            0,
            reader->pendingPCMByteCount
        );
    }
    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, reader->sampleRate),
        .presentationTimeStamp = CMTimeMake(
            reader->pendingPCMStartSample,
            reader->sampleRate
        ),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMItemCount sampleCount = reader->pendingPCMFrameCount;
    if (status == noErr) {
        status = CMSampleBufferCreateReady(
            kCFAllocatorDefault,
            block,
            reader->formatDescription,
            sampleCount,
            1,
            &timing,
            1,
            &bytesPerFrame,
            sampleOut
        );
    }
    if (block) CFRelease(block);
    if (status != noErr) {
        char message[160];
        snprintf(
            message,
            sizeof(message),
            "Create aggregated PCM CMSampleBuffer failed (%d)",
            (int)status
        );
        set_error(errorBuffer, errorBufferSize, message);
        return PBFFmpegReadResultError;
    }

    bool isTrueHD = reader->codecParameters &&
        reader->codecParameters->codec_id == AV_CODEC_ID_TRUEHD;
    if (isTrueHD) reader->trueHDOutputSampleBufferCount++;

    if (metadataOut) {
        *metadataOut = reader->pendingPCMMetadata;
        metadataOut->packetDuration = av_rescale_q(
            reader->pendingPCMFrameCount,
            (AVRational){1, reader->sampleRate},
            reader->timeBase
        );
        metadataOut->payloadByteCount = reader->pendingPCMByteCount;
        if (isTrueHD) {
            metadataOut->trueHDDecoderInputPacketCount =
                reader->trueHDDecoderInputPacketCount;
            metadataOut->trueHDDecoderBatchCount =
                reader->trueHDDecoderBatchCount;
            metadataOut->trueHDAggregatedDecoderBatchCount =
                reader->trueHDAggregatedDecoderBatchCount;
            metadataOut->trueHDOutputSampleBufferCount =
                reader->trueHDOutputSampleBufferCount;
            metadataOut->trueHDLastDecoderBatchInputPacketCount =
                reader->trueHDLastDecoderBatchInputPacketCount;
        }
    }
    reader->pendingPCMByteCount = 0;
    reader->pendingPCMFrameCount = 0;
    memset(&reader->pendingPCMMetadata, 0, sizeof(reader->pendingPCMMetadata));
    return PBFFmpegReadResultSample;
}

static int reserve_pending_decoded_audio_capacity(
    PBFFmpegAudioReader *reader,
    int additionalFrameCapacity,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (additionalFrameCapacity <= 0 || reader->channelCount <= 0) {
        set_error(errorBuffer, errorBufferSize, "Decoded PCM aggregation received no capacity");
        return AVERROR_INVALIDDATA;
    }
    size_t bytesPerFrame = (size_t)reader->channelCount * sizeof(float);
    if ((size_t)additionalFrameCapacity > SIZE_MAX / bytesPerFrame) {
        set_error(errorBuffer, errorBufferSize, "Decoded PCM aggregation size overflowed");
        return AVERROR(EOVERFLOW);
    }
    size_t byteCount = (size_t)additionalFrameCapacity * bytesPerFrame;
    if (reader->pendingPCMByteCount > SIZE_MAX - byteCount) {
        set_error(errorBuffer, errorBufferSize, "Decoded PCM aggregation capacity overflowed");
        return AVERROR(EOVERFLOW);
    }
    size_t requiredCapacity = reader->pendingPCMByteCount + byteCount;
    if (requiredCapacity > reader->pendingPCMCapacity) {
        size_t newCapacity = reader->pendingPCMCapacity > 0
            ? reader->pendingPCMCapacity
            : requiredCapacity;
        while (newCapacity < requiredCapacity) {
            if (newCapacity > SIZE_MAX / 2) {
                newCapacity = requiredCapacity;
                break;
            }
            newCapacity *= 2;
        }
        uint8_t *newData = realloc(reader->pendingPCMData, newCapacity);
        if (!newData) {
            set_error(errorBuffer, errorBufferSize, "Unable to grow decoded PCM aggregation storage");
            return AVERROR(ENOMEM);
        }
        reader->pendingPCMData = newData;
        reader->pendingPCMCapacity = newCapacity;
    }
    return 0;
}

static UInt32 audio_frames_per_packet(const AVCodecParameters *parameters) {
    if (parameters->frame_size > 0) return (UInt32)parameters->frame_size;
    switch (compressed_audio_codec(parameters)) {
        case PBCompressedAudioCodecAC3:
        case PBCompressedAudioCodecEAC3: return 1536;
        default: return 0;
    }
}

static bool apple_apac_magic_cookie_is_valid(
    const uint8_t *cookie,
    size_t cookieSize
) {
    if (!cookie || cookieSize < 8 || cookieSize > UINT32_MAX) return false;
    uint32_t declaredSize =
        ((uint32_t)cookie[0] << 24) |
        ((uint32_t)cookie[1] << 16) |
        ((uint32_t)cookie[2] << 8) |
        (uint32_t)cookie[3];
    return declaredSize == cookieSize &&
        cookie[4] == 'd' && cookie[5] == 'a' &&
        cookie[6] == 'p' && cookie[7] == 'a';
}

static int complete_apple_apac_asbd(
    AudioStreamBasicDescription *asbd,
    const void *cookie,
    size_t cookieSize,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!apple_apac_magic_cookie_is_valid(cookie, cookieSize)) {
        set_error(errorBuffer, errorBufferSize, "Apple APAC dapa magic cookie is unavailable or invalid");
        return AVERROR_INVALIDDATA;
    }
    UInt32 asbdSize = sizeof(*asbd);
    OSStatus status = AudioFormatGetProperty(
        kAudioFormatProperty_FormatInfo,
        (UInt32)cookieSize,
        cookie,
        &asbdSize,
        asbd
    );
    if (status != noErr ||
        asbdSize != sizeof(*asbd) ||
        asbd->mFormatID != kAudioFormatAPAC ||
        asbd->mSampleRate <= 0 ||
        asbd->mChannelsPerFrame == 0 ||
        asbd->mFramesPerPacket == 0) {
        char message[160];
        snprintf(
            message,
            sizeof(message),
            "Derive Apple APAC stream format from dapa failed (%d)",
            (int)status
        );
        set_error(errorBuffer, errorBufferSize, message);
        return AVERROR_INVALIDDATA;
    }
    return 0;
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

static AudioChannelLayoutTag audio_channel_layout_tag(
    const AVChannelLayout *source
) {
    if (!source || source->nb_channels <= 0) return 0;
    if (source->nb_channels == 1) return kAudioChannelLayoutTag_Mono;
    if (source->nb_channels == 2) return kAudioChannelLayoutTag_Stereo;

    AVChannelLayout fivePointOne = AV_CHANNEL_LAYOUT_5POINT1;
    AVChannelLayout fivePointOneBack = AV_CHANNEL_LAYOUT_5POINT1_BACK;
    AVChannelLayout sevenPointOne = AV_CHANNEL_LAYOUT_7POINT1;
    if (av_channel_layout_compare(source, &fivePointOne) == 0) {
        return kAudioChannelLayoutTag_WAVE_5_1_A;
    }
    if (av_channel_layout_compare(source, &fivePointOneBack) == 0) {
        return kAudioChannelLayoutTag_WAVE_5_1_B;
    }
    if (av_channel_layout_compare(source, &sevenPointOne) == 0) {
        return kAudioChannelLayoutTag_WAVE_7_1;
    }
    return 0;
}

static AudioChannelLayout *copy_audio_channel_layout(
    const AVChannelLayout *source,
    size_t *layoutSizeOut
) {
    if (!source || source->nb_channels <= 0 || !layoutSizeOut) return NULL;
    UInt32 channelCount = (UInt32)source->nb_channels;
    size_t layoutSize = sizeof(AudioChannelLayout);
    AudioChannelLayout *layout = NULL;
    AudioChannelLayoutTag standardTag = audio_channel_layout_tag(source);
    if (standardTag != 0 || source->order == AV_CHANNEL_ORDER_UNSPEC) {
        layout = calloc(1, layoutSize);
        if (!layout) return NULL;
        layout->mChannelLayoutTag = standardTag != 0
            ? standardTag
            : kAudioChannelLayoutTag_DiscreteInOrder | channelCount;
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
    PBCompressedAudioCodec codec = compressed_audio_codec(parameters);
    AudioFormatID formatID = compressed_audio_format_id(codec);
    if (formatID == 0) {
        set_error(errorBuffer, errorBufferSize, "The selected compressed audio codec is not supported");
        return AVERROR(ENOSYS);
    }
    AudioStreamBasicDescription asbd = {
        .mSampleRate = parameters->sample_rate,
        .mFormatID = formatID,
        .mFormatFlags = 0,
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
    const void *cookie = parameters->extradata_size > 0 ? parameters->extradata : NULL;
    size_t cookieSize = parameters->extradata_size > 0
        ? (size_t)parameters->extradata_size
        : 0;
    if (codec == PBCompressedAudioCodecAppleAPAC &&
        complete_apple_apac_asbd(
            &asbd,
            cookie,
            cookieSize,
            errorBuffer,
            errorBufferSize
        ) < 0) {
        free(channelLayout);
        return AVERROR_INVALIDDATA;
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

static int ensure_audio_format(
    PBFFmpegAudioReader *reader,
    const AVCodecParameters *parameters,
    char *errorBuffer,
    size_t errorBufferSize
) {
    return ensure_compressed_audio_format(
        reader,
        parameters,
        errorBuffer,
        errorBufferSize
    );
}

static int ensure_decoded_pcm_audio_format(
    PBFFmpegAudioReader *reader,
    const AVChannelLayout *channelLayout,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader->formatDescription) return 0;
    UInt32 channelCount = (UInt32)channelLayout->nb_channels;
    UInt32 bytesPerFrame = channelCount * sizeof(float);
    AudioStreamBasicDescription asbd = {
        .mSampleRate = reader->sampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked,
        .mBytesPerPacket = bytesPerFrame,
        .mFramesPerPacket = 1,
        .mBytesPerFrame = bytesPerFrame,
        .mChannelsPerFrame = channelCount,
        .mBitsPerChannel = 32,
        .mReserved = 0,
    };
    size_t layoutSize = 0;
    AudioChannelLayout *layout = copy_audio_channel_layout(
        channelLayout,
        &layoutSize
    );
    if (!layout) {
        set_error(errorBuffer, errorBufferSize, "Decoded PCM channel layout is unavailable");
        return AVERROR_INVALIDDATA;
    }
    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault,
        &asbd,
        layoutSize,
        layout,
        0,
        NULL,
        NULL,
        &reader->formatDescription
    );
    free(layout);
    if (status != noErr) {
        char message[160];
        snprintf(
            message,
            sizeof(message),
            "Create decoded PCM audio format description failed (%d)",
            (int)status
        );
        set_error(errorBuffer, errorBufferSize, message);
        return AVERROR_INVALIDDATA;
    }
    return 0;
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
    if (formatResult < 0) {
        reader->lastActiveFailureCause =
            active_failure_cause_for_av_error(formatResult);
        return PBFFmpegReadResultError;
    }
    if (packet->size <= 0 || packet->data == NULL) {
        set_error(errorBuffer, errorBufferSize, "Compressed audio packet is empty");
        reader->lastActiveFailureCause =
            PBFFmpegActiveFailureCauseMediaDataCorrupt;
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
    CMItemCount sampleCount = 1;
    const AudioStreamBasicDescription *asbd =
        CMAudioFormatDescriptionGetStreamBasicDescription(reader->formatDescription);
    UInt32 framesPerPacket = asbd ? asbd->mFramesPerPacket : 0;
    int32_t sampleRate = asbd && asbd->mSampleRate > 0 && asbd->mSampleRate <= INT32_MAX
        ? (int32_t)asbd->mSampleRate
        : 0;
    CMTime packetDuration = cm_time(packet->duration, reader->timeBase);
    CMTime duration = packet->duration > 0
        ? packetDuration
        : framesPerPacket > 0 && sampleRate > 0
        ? CMTimeMake(framesPerPacket, sampleRate)
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
    size_t sampleSize = byteCount;
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
        metadataOut->cookieSource = cookieSource;
    }
    return PBFFmpegReadResultSample;
}

static void clear_decoded_audio_conversion(PBFFmpegAudioReader *reader) {
    av_audio_fifo_free(reader->decodedAudioFifo);
    reader->decodedAudioFifo = NULL;
    if (reader->decodedBatchData) {
        av_freep(&reader->decodedBatchData[0]);
        av_freep(&reader->decodedBatchData);
    }
    reader->decodedBatchCapacity = 0;
    reader->decodedInputFormat = AV_SAMPLE_FMT_NONE;
    swr_free(&reader->resampler);
    av_channel_layout_uninit(&reader->outputChannelLayout);
    if (reader->formatDescription) {
        CFRelease(reader->formatDescription);
        reader->formatDescription = NULL;
    }
}

static int configure_decoded_audio_conversion(
    PBFFmpegAudioReader *reader,
    const AVChannelLayout *inputLayout,
    enum AVSampleFormat inputFormat,
    int inputSampleRate,
    char *errorBuffer,
    size_t errorBufferSize
) {
    clear_decoded_audio_conversion(reader);
    if (av_channel_layout_copy(&reader->outputChannelLayout, inputLayout) < 0) {
        set_error(errorBuffer, errorBufferSize, "Unable to preserve decoded audio channel layout");
        return AVERROR(ENOMEM);
    }
    reader->channelCount = inputLayout->nb_channels;
    reader->decodedInputFormat = inputFormat;
    int batchCapacity = decoded_audio_minimum_buffer_frames(reader);
    reader->decodedAudioFifo = av_audio_fifo_alloc(
        inputFormat,
        reader->channelCount,
        batchCapacity
    );
    if (!reader->decodedAudioFifo) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate decoded audio aggregation storage");
        clear_decoded_audio_conversion(reader);
        return AVERROR(ENOMEM);
    }
    int lineSize = 0;
    int result = av_samples_alloc_array_and_samples(
        &reader->decodedBatchData,
        &lineSize,
        reader->channelCount,
        batchCapacity,
        inputFormat,
        0
    );
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Allocate decoded audio batch storage", result);
        clear_decoded_audio_conversion(reader);
        return result;
    }
    reader->decodedBatchCapacity = batchCapacity;
    result = swr_alloc_set_opts2(
        &reader->resampler,
        &reader->outputChannelLayout,
        AV_SAMPLE_FMT_FLT,
        reader->sampleRate,
        inputLayout,
        inputFormat,
        inputSampleRate,
        0,
        NULL
    );
    if (result >= 0) result = swr_init(reader->resampler);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Configure decoded audio conversion", result);
        clear_decoded_audio_conversion(reader);
        return result;
    }
    if (ensure_decoded_pcm_audio_format(
            reader,
            &reader->outputChannelLayout,
            errorBuffer,
            errorBufferSize
        ) < 0) {
        clear_decoded_audio_conversion(reader);
        return AVERROR_INVALIDDATA;
    }
    reader->decodedFifoStartTimestamp = AV_NOPTS_VALUE;
    return 0;
}

static PBFFmpegReadResult convert_decoded_audio_fifo(
    PBFFmpegAudioReader *reader,
    int frameCount,
    CMSampleBufferRef *sampleOut,
    PBFFmpegAudioSampleMetadata *metadataOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!reader->decodedAudioFifo || !reader->resampler ||
        frameCount <= 0 ||
        frameCount > av_audio_fifo_size(reader->decodedAudioFifo)) {
        set_error(errorBuffer, errorBufferSize, "Decoded audio aggregation state is inconsistent");
        return PBFFmpegReadResultError;
    }
    if (frameCount > reader->decodedBatchCapacity) {
        av_freep(&reader->decodedBatchData[0]);
        av_freep(&reader->decodedBatchData);
        int lineSize = 0;
        int allocationResult = av_samples_alloc_array_and_samples(
            &reader->decodedBatchData,
            &lineSize,
            reader->channelCount,
            frameCount,
            reader->decodedInputFormat,
            0
        );
        if (allocationResult < 0) {
            set_av_error(
                errorBuffer,
                errorBufferSize,
                "Grow decoded audio batch storage",
                allocationResult
            );
            return PBFFmpegReadResultError;
        }
        reader->decodedBatchCapacity = frameCount;
    }
    int outputCapacity = swr_get_out_samples(reader->resampler, frameCount);
    if (outputCapacity <= 0 ||
        reserve_pending_decoded_audio_capacity(
            reader,
            outputCapacity,
            errorBuffer,
            errorBufferSize
        ) < 0) {
        if (outputCapacity <= 0) {
            set_error(errorBuffer, errorBufferSize, "Decoded audio conversion produced no capacity");
        }
        return PBFFmpegReadResultError;
    }
    int readSamples = av_audio_fifo_read(
        reader->decodedAudioFifo,
        (void **)reader->decodedBatchData,
        frameCount
    );
    if (readSamples != frameCount) {
        set_error(errorBuffer, errorBufferSize, "Decoded audio aggregation could not read a complete batch");
        return PBFFmpegReadResultError;
    }
    uint8_t *outputData[1] = {
        reader->pendingPCMData + reader->pendingPCMByteCount,
    };
    int convertedSamples = swr_convert(
        reader->resampler,
        outputData,
        outputCapacity,
        (const uint8_t **)reader->decodedBatchData,
        readSamples
    );
    if (convertedSamples <= 0) {
        if (convertedSamples < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Convert decoded audio to interleaved PCM", convertedSamples);
        } else {
            set_error(errorBuffer, errorBufferSize, "Decoded audio conversion produced no samples");
        }
        return PBFFmpegReadResultError;
    }
    reader->pendingPCMStartSample = reader->decodedFifoStartSample;
    reader->pendingPCMMetadata.packetPTS = reader->decodedFifoStartTimestamp;
    reader->pendingPCMMetadata.packetDTS = AV_NOPTS_VALUE;
    reader->pendingPCMMetadata.timeBaseNumerator = reader->timeBase.num;
    reader->pendingPCMMetadata.timeBaseDenominator = reader->timeBase.den;
    reader->pendingPCMMetadata.cookieSource = PBFFmpegAudioCookieSourceUnavailable;
    reader->pendingPCMByteCount =
        (size_t)convertedSamples * (size_t)reader->channelCount * sizeof(float);
    reader->pendingPCMFrameCount = convertedSamples;
    reader->decodedFifoStartSample += convertedSamples;
    if (reader->decodedFifoStartTimestamp != AV_NOPTS_VALUE) {
        reader->decodedFifoStartTimestamp += av_rescale_q(
            convertedSamples,
            (AVRational){1, reader->sampleRate},
            reader->timeBase
        );
    }
    return emit_pending_decoded_audio_sample(
        reader,
        sampleOut,
        metadataOut,
        errorBuffer,
        errorBufferSize
    );
}

static PBFFmpegReadResult create_decoded_audio_sample(
    PBFFmpegAudioReader *reader,
    AVFrame *frame,
    CMSampleBufferRef *sampleOut,
    PBFFmpegAudioSampleMetadata *metadataOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    const AVChannelLayout *inputLayout = frame->ch_layout.nb_channels > 0
        ? &frame->ch_layout
        : reader->decoder->ch_layout.nb_channels > 0
        ? &reader->decoder->ch_layout
        : &reader->outputChannelLayout;
    int inputSampleRate = frame->sample_rate > 0
        ? frame->sample_rate
        : reader->decoder->sample_rate > 0
        ? reader->decoder->sample_rate
        : reader->sampleRate;
    enum AVSampleFormat inputFormat = (enum AVSampleFormat)frame->format;
    if (inputLayout->nb_channels <= 0 || inputSampleRate <= 0 ||
        inputFormat == AV_SAMPLE_FMT_NONE || frame->nb_samples <= 0) {
        char message[192];
        snprintf(
            message,
            sizeof(message),
            "Decoded audio codec %s frame has invalid parameters (%d Hz, %d channels, %d samples)",
            reader->codecName,
            inputSampleRate,
            inputLayout->nb_channels,
            frame->nb_samples
        );
        set_error(errorBuffer, errorBufferSize, message);
        reader->lastActiveFailureCause =
            PBFFmpegActiveFailureCauseMediaDataCorrupt;
        return PBFFmpegReadResultError;
    }
    if (inputSampleRate != reader->sampleRate) {
        set_error(errorBuffer, errorBufferSize, "Decoded audio changed the declared sample rate");
        reader->lastActiveFailureCause =
            PBFFmpegActiveFailureCauseMediaDataCorrupt;
        return PBFFmpegReadResultError;
    }

    CMSampleBufferRef completedPreviousFormatSample = NULL;
    PBFFmpegAudioSampleMetadata completedPreviousFormatMetadata = {0};
    bool needsConfiguration = !reader->decodedAudioFifo ||
        reader->decodedInputFormat != inputFormat ||
        av_channel_layout_compare(inputLayout, &reader->outputChannelLayout) != 0;
    if (needsConfiguration && reader->decodedAudioFifo &&
        av_audio_fifo_size(reader->decodedAudioFifo) > 0) {
        PBFFmpegReadResult flushResult = convert_decoded_audio_fifo(
            reader,
            av_audio_fifo_size(reader->decodedAudioFifo),
            &completedPreviousFormatSample,
            &completedPreviousFormatMetadata,
            errorBuffer,
            errorBufferSize
        );
        if (flushResult != PBFFmpegReadResultSample) return flushResult;
    }
    if (needsConfiguration && configure_decoded_audio_conversion(
            reader,
            inputLayout,
            inputFormat,
            inputSampleRate,
            errorBuffer,
            errorBufferSize
        ) < 0) {
        if (completedPreviousFormatSample) CFRelease(completedPreviousFormatSample);
        return PBFFmpegReadResultError;
    }

    int64_t frameTimestamp = frame->pts != AV_NOPTS_VALUE
        ? frame->pts
        : frame->best_effort_timestamp;
    int64_t startSample = reader->nextPCMSample;
    if (frameTimestamp != AV_NOPTS_VALUE) {
        startSample = av_rescale_q(
            frameTimestamp - reader->startTimestamp,
            reader->timeBase,
            (AVRational){1, reader->sampleRate}
        );
        if (startSample < reader->nextPCMSample) startSample = reader->nextPCMSample;
    }
    if (av_audio_fifo_size(reader->decodedAudioFifo) == 0) {
        reader->decodedFifoStartSample = startSample;
        reader->decodedFifoStartTimestamp = frameTimestamp;
    }
    int writtenSamples = av_audio_fifo_write(
        reader->decodedAudioFifo,
        (void * const *)frame->extended_data,
        frame->nb_samples
    );
    if (writtenSamples != frame->nb_samples) {
        if (completedPreviousFormatSample) CFRelease(completedPreviousFormatSample);
        set_error(errorBuffer, errorBufferSize, "Decoded audio aggregation could not append a complete frame");
        return PBFFmpegReadResultError;
    }
    reader->nextPCMSample = startSample + writtenSamples;
    if (completedPreviousFormatSample) {
        *sampleOut = completedPreviousFormatSample;
        if (metadataOut) *metadataOut = completedPreviousFormatMetadata;
        return PBFFmpegReadResultSample;
    }
    int minimumFrames = decoded_audio_minimum_buffer_frames(reader);
    int availableFrames = av_audio_fifo_size(reader->decodedAudioFifo);
    if (availableFrames < minimumFrames) {
        return PBFFmpegReadResultEnd;
    }
    int conversionFrames = frame->nb_samples >= minimumFrames &&
            availableFrames == frame->nb_samples
        ? frame->nb_samples
        : minimumFrames;
    return convert_decoded_audio_fifo(
        reader,
        conversionFrames,
        sampleOut,
        metadataOut,
        errorBuffer,
        errorBufferSize
    );
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
    reader->lastActiveFailureCause = PBFFmpegActiveFailureCauseNone;
    if (cancellation_requested(&reader->cancelled)) {
        return PBFFmpegReadResultCancelled;
    }
    while (true) {
        if (cancellation_requested(&reader->cancelled)) {
            return PBFFmpegReadResultCancelled;
        }
        if (reader->decoder) {
            if (reader->decodedAudioFifo &&
                av_audio_fifo_size(reader->decodedAudioFifo) >=
                    decoded_audio_minimum_buffer_frames(reader)) {
                return convert_decoded_audio_fifo(
                    reader,
                    decoded_audio_minimum_buffer_frames(reader),
                    sampleOut,
                    metadataOut,
                    errorBuffer,
                    errorBufferSize
                );
            }
            if (reader->pendingPCMFrameCount >= decoded_audio_minimum_buffer_frames(reader)) {
                return emit_pending_decoded_audio_sample(
                    reader,
                    sampleOut,
                    metadataOut,
                    errorBuffer,
                    errorBufferSize
                );
            }
            int result = avcodec_receive_frame(reader->decoder, reader->decodedFrame);
            if (result == 0) {
                if (reader->decodedFrame->nb_samples <= 0) {
                    av_frame_unref(reader->decodedFrame);
                    continue;
                }
                PBFFmpegReadResult readResult = create_decoded_audio_sample(
                    reader,
                    reader->decodedFrame,
                    sampleOut,
                    metadataOut,
                    errorBuffer,
                    errorBufferSize
                );
                av_frame_unref(reader->decodedFrame);
                if (readResult == PBFFmpegReadResultEnd) continue;
                return readResult;
            }
            if (result == AVERROR_EOF) {
                if (reader->decodedAudioFifo &&
                    av_audio_fifo_size(reader->decodedAudioFifo) > 0) {
                    return convert_decoded_audio_fifo(
                        reader,
                        FFMIN(
                            av_audio_fifo_size(reader->decodedAudioFifo),
                            reader->decodedBatchCapacity
                        ),
                        sampleOut,
                        metadataOut,
                        errorBuffer,
                        errorBufferSize
                    );
                }
                if (reader->pendingPCMFrameCount > 0) {
                    return emit_pending_decoded_audio_sample(
                        reader,
                        sampleOut,
                        metadataOut,
                        errorBuffer,
                        errorBufferSize
                    );
                }
                if (reader->inputReadResult < 0 &&
                    reader->inputReadResult != AVERROR_EOF) {
                    set_av_error(
                        errorBuffer,
                        errorBufferSize,
                        "Read demuxed audio packet",
                        reader->inputReadResult
                    );
                    reader->lastActiveFailureCause =
                        active_failure_cause_for_av_error(reader->inputReadResult);
                    return PBFFmpegReadResultError;
                }
                return PBFFmpegReadResultEnd;
            }
            if (result != AVERROR(EAGAIN)) {
                set_av_error(errorBuffer, errorBufferSize, "Decode audio frame", result);
                reader->lastActiveFailureCause =
                    active_failure_cause_for_decoder_error(result);
                return PBFFmpegReadResultError;
            }
            if (reader->inputEnded) {
                if (!reader->decoderDrained) {
                    result = avcodec_send_packet(reader->decoder, NULL);
                    reader->decoderDrained = true;
                    if (result < 0 && result != AVERROR_EOF) {
                        set_av_error(errorBuffer, errorBufferSize, "Finish FFmpeg audio decoder", result);
                        reader->lastActiveFailureCause =
                            active_failure_cause_for_decoder_error(result);
                        return PBFFmpegReadResultError;
                    }
                    continue;
                }
                return PBFFmpegReadResultEnd;
            }
        }
        int result = read_next_audio_packet(reader, reader->packet);
        if (result < 0) {
            if (result == AVERROR_EXIT || cancellation_requested(&reader->cancelled)) {
                return PBFFmpegReadResultCancelled;
            }
            reader->inputEnded = true;
            reader->inputReadResult = result;
            if (reader->decoder) continue;
            if (result == AVERROR_EOF) return PBFFmpegReadResultEnd;
            set_av_error(errorBuffer, errorBufferSize, "Read demuxed audio packet", result);
            reader->lastActiveFailureCause = active_failure_cause_for_av_error(result);
            return PBFFmpegReadResultError;
        }
        if (reader->packet->stream_index != reader->audioStreamIndex) {
            av_packet_unref(reader->packet);
            continue;
        }
        if (reader->decoder) {
            result = aggregate_truehd_decoder_packet(reader);
            if (result == AVERROR_EXIT ||
                cancellation_requested(&reader->cancelled)) {
                av_packet_unref(reader->packet);
                return PBFFmpegReadResultCancelled;
            }
            if (result < 0) {
                av_packet_unref(reader->packet);
                set_av_error(
                    errorBuffer,
                    errorBufferSize,
                    "Aggregate FFmpeg TrueHD decoder packet",
                    result
                );
                reader->lastActiveFailureCause =
                    active_failure_cause_for_av_error(result);
                return PBFFmpegReadResultError;
            }
            result = avcodec_send_packet(reader->decoder, reader->packet);
            av_packet_unref(reader->packet);
            if (result == AVERROR_INVALIDDATA) continue;
            if (result < 0) {
                char operation[128];
                snprintf(
                    operation,
                    sizeof(operation),
                    "Send packet to FFmpeg audio codec %s decoder",
                    reader->codecName
                );
                set_av_error(errorBuffer, errorBufferSize, operation, result);
                reader->lastActiveFailureCause =
                    active_failure_cause_for_decoder_error(result);
                return PBFFmpegReadResultError;
            }
            continue;
        }
        PBFFmpegReadResult readResult = create_audio_sample(
            reader,
            reader->packet,
            reader->codecParameters,
            reader->codecParameters->extradata_size > 0
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
}

PBFFmpegActiveFailureCause PBFFmpegAudioReaderGetLastActiveFailureCause(
    const PBFFmpegAudioReader *reader
) {
    return reader
        ? reader->lastActiveFailureCause
        : PBFFmpegActiveFailureCauseNone;
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

static bool configure_subtitle_reader(
    PBFFmpegSubtitleReader *reader,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (streamIndex >= (int)reader->formatContext->nb_streams ||
        !subtitle_stream_is_supported(reader->formatContext->streams[streamIndex])) {
        set_error(
            errorBuffer,
            errorBufferSize,
            "The selected subtitle stream codec is unsupported"
        );
        return false;
    }
    if (reader->demuxSource &&
        !subscribe_to_demux_stream(reader->demuxSource, streamIndex)) {
        set_error(errorBuffer, errorBufferSize, "The shared subtitle stream already has a reader");
        return false;
    }
    AVStream *stream = reader->formatContext->streams[streamIndex];
    reader->subtitleStreamIndex = streamIndex;
    reader->codecID = stream->codecpar->codec_id;
    reader->timeBase = stream->time_base;
    reader->startTimestamp = stream_start_timestamp(reader->formatContext, stream);
    const AVCodec *decoder = avcodec_find_decoder(reader->codecID);
    if (!decoder) {
        set_error(errorBuffer, errorBufferSize, "The selected subtitle decoder is unavailable");
        return false;
    }
    reader->decoder = avcodec_alloc_context3(decoder);
    if (!reader->decoder) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg subtitle decoder");
        return false;
    }
    int result = avcodec_parameters_to_context(reader->decoder, stream->codecpar);
    if (result >= 0) {
        reader->decoder->pkt_timebase = stream->time_base;
        result = avcodec_open2(reader->decoder, decoder, NULL);
    }
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open FFmpeg subtitle decoder", result);
        return false;
    }
    reader->packet = av_packet_alloc();
    if (!reader->packet) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg subtitle packet");
        return false;
    }
    return true;
}

PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(
    const char *path,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize,
    PBFFmpegSourceReadMonitor *monitor,
    PBFFmpegReadCancellation *cancellation
) {
    if (!path || streamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg subtitle reader call");
        return NULL;
    }
    atomic_bool *cancelled = cancellation ? &cancellation->cancelled : NULL;
    if (cancellation_requested(cancelled)) {
        set_error(errorBuffer, errorBufferSize, "The subtitle read was cancelled");
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
        cancelled,
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
    if (!configure_subtitle_reader(reader, streamIndex, errorBuffer, errorBufferSize)) {
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    return reader;
}

PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreateWithDemuxSource(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!source || !source->formatContext || streamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid shared FFmpeg subtitle reader call");
        return NULL;
    }
    PBFFmpegSubtitleReader *reader = calloc(1, sizeof(*reader));
    if (!reader) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg subtitle reader");
        return NULL;
    }
    reader->demuxSource = source;
    reader->formatContext = source->formatContext;
    if (!configure_subtitle_reader(reader, streamIndex, errorBuffer, errorBufferSize)) {
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    if (!begin_demux_source_prefetch(source)) {
        set_error(errorBuffer, errorBufferSize, "Unable to start FFmpeg demux prefetch");
        PBFFmpegSubtitleReaderDestroy(reader);
        return NULL;
    }
    return reader;
}

void PBFFmpegSubtitleReaderDestroy(PBFFmpegSubtitleReader *reader) {
    if (!reader) return;
    av_packet_free(&reader->packet);
    avcodec_free_context(&reader->decoder);
    if (reader->demuxSource) {
        unsubscribe_from_demux_stream(reader->demuxSource, reader->subtitleStreamIndex);
    } else {
        close_media_source(&reader->formatContext, &reader->sourceReadContext);
    }
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
    int packetResult = 0;
    while ((packetResult = reader->demuxSource
            ? copy_next_demux_packet(
                reader->demuxSource,
                reader->subtitleStreamIndex,
                NULL,
                reader->packet
            )
            : av_read_frame(reader->formatContext, reader->packet)) >= 0) {
        if (!reader->demuxSource) publish_source_bytes(&reader->sourceReadContext);
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
    if (packetResult == AVERROR_EXIT) return PBFFmpegReadResultCancelled;
    if (packetResult != AVERROR_EOF) {
        set_av_error(
            errorBuffer,
            errorBufferSize,
            "Read demuxed subtitle packet",
            packetResult
        );
        return PBFFmpegReadResultError;
    }
    return PBFFmpegReadResultEnd;
}
