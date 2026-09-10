#include <inttypes.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "libavformat/avformat.h"
#include "libavformat/avio.h"
#include "libavutil/opt.h"
#include "libavcodec/codec_desc.h"

static double origin;
static atomic_ullong monitor_total;
static atomic_bool sampling;

static double now(void) {
    struct timespec spec;
    clock_gettime(CLOCK_MONOTONIC, &spec);
    return spec.tv_sec + spec.tv_nsec / 1e9;
}

typedef struct {
    AVFormatContext *formatContext;
    int64_t accountedBytesRead;
} ReadContext;

static void publish_source_bytes(ReadContext *context) {
    if (!context || !context->formatContext || !context->formatContext->pb) return;
    int64_t bytesRead = context->formatContext->pb->bytes_read;
    if (bytesRead < 0) return;
    uint64_t delta = bytesRead >= context->accountedBytesRead
        ? (uint64_t)(bytesRead - context->accountedBytesRead)
        : (uint64_t)bytesRead;
    context->accountedBytesRead = bytesRead;
    if (delta > 0) atomic_fetch_add_explicit(&monitor_total, delta, memory_order_relaxed);
}

static int publish_and_check_cancellation(void *opaque) {
    publish_source_bytes(opaque);
    return 0;
}

static void *sampler(void *unused) {
    (void)unused;
    unsigned long long last = 0;
    while (atomic_load(&sampling)) {
        unsigned long long total = atomic_load(&monitor_total);
        if (total != last) {
            printf("    sample  +%6.2fs  monitor=%10.3f MB  (+%.3f MB)\n",
                   now() - origin, total / 1e6, (total - last) / 1e6);
            last = total;
        }
        struct timespec nap = {0, 200 * 1000 * 1000};
        nanosleep(&nap, NULL);
    }
    return NULL;
}

static int64_t http_source_length(const char *path, const AVIOInterruptCB *interrupt) {
    AVIOContext *probe = NULL;
    if (avio_open2(&probe, path, AVIO_FLAG_READ, interrupt, NULL) < 0) return 0;
    int64_t length = avio_size(probe);
    avio_closep(&probe);
    return length > 0 ? length : 0;
}

typedef struct {
    bool end_offset;
    bool skip_find_stream_info;
    bool late_end_offset;
    int64_t probesize;
    int64_t analyzeduration;
} Options;

static void one_open(const char *path, const Options *options, int index) {
    ReadContext read = {0};
    AVFormatContext *context = avformat_alloc_context();
    read.formatContext = context;
    context->interrupt_callback.callback = publish_and_check_cancellation;
    context->interrupt_callback.opaque = &read;
    if (options->probesize > 0) context->probesize = options->probesize;
    if (options->analyzeduration >= 0) context->max_analyze_duration = options->analyzeduration;

    printf("  open #%d  +%6.2fs  monitor=%.3f MB\n", index, now() - origin, atomic_load(&monitor_total) / 1e6);

    AVDictionary *dictionary = NULL;
    AVIOContext *owned = NULL;
    double t = now();
    int64_t length = 0;
    if (options->late_end_offset) {
        if (avio_open2(&owned, path, AVIO_FLAG_READ, &context->interrupt_callback, NULL) < 0) {
            printf("    avio_open2 FAILED\n");
            return;
        }
        length = avio_size(owned);
        int set = av_opt_set_int(owned, "end_offset", length, AV_OPT_SEARCH_CHILDREN);
        context->pb = owned;
        printf("    avio_open2 + avio_size +%6.2fs  (%.2fs)  length=%" PRId64
               "  av_opt_set_int=%d  bytes_read=%" PRId64 "\n",
               now() - origin, now() - t, length, set, owned->bytes_read);
    } else if (options->end_offset) {
        length = http_source_length(path, &context->interrupt_callback);
        av_dict_set_int(&dictionary, "end_offset", length, 0);
        printf("    http_source_length     +%6.2fs  (%.2fs)  length=%" PRId64 "  bytes_read=n/a (pb still NULL)\n",
               now() - origin, now() - t, length);
    }

    t = now();
    int result = avformat_open_input(&context, path, NULL, &dictionary);
    av_dict_free(&dictionary);
    if (result < 0) {
        char text[AV_ERROR_MAX_STRING_SIZE] = {0};
        av_strerror(result, text, sizeof(text));
        printf("    avformat_open_input FAILED: %s\n", text);
        return;
    }
    read.formatContext = context;
    int64_t after_open = context->pb->bytes_read;
    publish_source_bytes(&read);
    printf("    avformat_open_input    +%6.2fs  (%.2fs)  bytes_read=%10" PRId64 "  nb_streams=%u\n",
           now() - origin, now() - t, after_open, context->nb_streams);

    if (!options->skip_find_stream_info) {
        t = now();
        result = avformat_find_stream_info(context, NULL);
        int64_t after_info = context->pb->bytes_read;
        publish_source_bytes(&read);
        printf("    find_stream_info       +%6.2fs  (%.2fs)  bytes_read=%10" PRId64 "  delta=%" PRId64 " B (%.3f MB)\n",
               now() - origin, now() - t, after_info,
               after_info - after_open, (after_info - after_open) / 1e6);
        if (result < 0) printf("    find_stream_info returned %d\n", result);
    }

    for (unsigned int i = 0; i < context->nb_streams; i++) {
        AVStream *stream = context->streams[i];
        const AVCodecDescriptor *descriptor = avcodec_descriptor_get(stream->codecpar->codec_id);
        printf("      stream %u  %s  %s  %dx%d  ch=%d  dur=%.3fs\n", i,
               av_get_media_type_string(stream->codecpar->codec_type) ?: "?",
               descriptor ? descriptor->name : "?",
               stream->codecpar->width, stream->codecpar->height,
               stream->codecpar->ch_layout.nb_channels,
               stream->duration == AV_NOPTS_VALUE ? -1.0 : stream->duration * av_q2d(stream->time_base));
    }
    printf("    total bytes_read=%" PRId64 " (%.3f MB)\n",
           context->pb->bytes_read, context->pb->bytes_read / 1e6);
    avformat_close_input(&context);
    if (owned) avio_closep(&owned);
}

int main(int argc, char **argv) {
    const char *path = getenv("PROBE_URL");
    if (!path) {
        fprintf(
            stderr,
            "set PROBE_URL; the URL carries credentials and must not appear in argv\n"
        );
        return 2;
    }

    Options options = {.end_offset = true, .probesize = 0, .analyzeduration = -1};
    int opens = 1;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--no-end-offset")) options.end_offset = false;
        else if (!strcmp(argv[i], "--late-end-offset")) options.late_end_offset = true;
        else if (!strcmp(argv[i], "--skip-find-stream-info")) options.skip_find_stream_info = true;
        else if (!strcmp(argv[i], "--opens") && i + 1 < argc) opens = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--probesize") && i + 1 < argc) options.probesize = atoll(argv[++i]);
        else if (!strcmp(argv[i], "--analyzeduration") && i + 1 < argc) options.analyzeduration = atoll(argv[++i]);
        else if (!strcmp(argv[i], "--verbose")) av_log_set_level(AV_LOG_DEBUG);
    }

    printf("libavformat %u.%u.%u  end_offset=%s late=%s find_stream_info=%s opens=%d\n\n",
           LIBAVFORMAT_VERSION_MAJOR, LIBAVFORMAT_VERSION_MINOR, LIBAVFORMAT_VERSION_MICRO,
           options.end_offset ? "yes" : "no",
           options.late_end_offset ? "yes" : "no",
           options.skip_find_stream_info ? "skipped" : "yes", opens);

    origin = now();
    atomic_init(&monitor_total, 0);
    atomic_init(&sampling, true);
    pthread_t thread;
    pthread_create(&thread, NULL, sampler, NULL);

    for (int i = 0; i < opens; i++) one_open(path, &options, i + 1);

    atomic_store(&sampling, false);
    pthread_join(thread, NULL);
    printf("\nmonitor total %.3f MB over %d opens, wall %.2fs\n",
           atomic_load(&monitor_total) / 1e6, opens, now() - origin);
    return 0;
}
