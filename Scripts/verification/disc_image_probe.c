#include <libavformat/avformat.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

/// Mirrors `disc_image_input_format` in PlaybackFFmpegBridge.c. Kept as a mirror
/// rather than a call because the bridge is built for visionOS and this runs on the
/// host, which is the standing limit of every probe here: a matching change on both
/// sides passes. `--reads-nothing` builds the variant that always probes, which is
/// the state before the fix.
/// The resync limit the bridge sets for a disc image. Zero leaves the demuxer
/// default, which is the state that identified the streams and then delivered no
/// packet from them.
#ifdef PROBE_WITHOUT_RESYNC
static const int64_t DISC_IMAGE_RESYNC_SIZE = 0;
#else
static const int64_t DISC_IMAGE_RESYNC_SIZE = 16LL * 1024 * 1024;
#endif

static const AVInputFormat *disc_image_input_format(const char *path) {
#ifdef PROBE_READS_NOTHING
    (void)path;
    return NULL;
#else
    if (!path) return NULL;
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
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
#endif
}

/// Reads until this many packets have arrived from the selected video stream, or
/// until the source stops yielding. Identifying a stream and delivering packets from
/// it are separate things, and a disc image did the first without the second.
static int video_packets_delivered(AVFormatContext *context, int stream) {
    AVPacket *packet = av_packet_alloc();
    int delivered = 0;
    int reads = 0;
    while (delivered < 20 && reads < 4000 && av_read_frame(context, packet) >= 0) {
        reads++;
        if (packet->stream_index == stream) delivered++;
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    return delivered;
}

static void report(const char *label, const char *path, const AVInputFormat *forced) {
    AVFormatContext *context = avformat_alloc_context();
    AVDictionary *options = NULL;
    if (forced && DISC_IMAGE_RESYNC_SIZE > 0) {
        av_dict_set_int(&options, "resync_size", DISC_IMAGE_RESYNC_SIZE, 0);
    }
    int opened = avformat_open_input(&context, path, forced, &options);
    av_dict_free(&options);
    if (opened < 0) {
        printf("%s open=failed\n", label);
        return;
    }
    avformat_find_stream_info(context, NULL);
    int videoStreams = 0;
    for (unsigned index = 0; index < context->nb_streams; index++) {
        if (context->streams[index]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStreams++;
        }
    }
    int best = av_find_best_stream(context, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    printf(
        "%s format=%s videoStreams=%d width=%d height=%d duration=%.2f videoPackets=%d\n",
        label,
        context->iformat->name,
        videoStreams,
        best >= 0 ? context->streams[best]->codecpar->width : 0,
        best >= 0 ? context->streams[best]->codecpar->height : 0,
        (double)context->duration / AV_TIME_BASE,
        best >= 0 ? video_packets_delivered(context, best) : 0
    );
    avformat_close_input(&context);
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    av_log_set_level(AV_LOG_QUIET);
    printf("libavformat=%d\n", avformat_version());
    report("probed", argv[1], NULL);
    report("opened", argv[1], disc_image_input_format(argv[1]));
    return 0;
}
