// Reproduces the open-then-seek that PBFFmpegReaderOpen performs for a resume
// start, against the vendored FFmpeg rather than a system one, so the return
// code a wearer sees in the failure alert can be read on the Mac.
//
// The bridge's own seek call is the thing under test, so the arguments here are
// copied from it verbatim: whole-range bounds, the video stream, and a
// timestamp rescaled from the container start through the stream time base.

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libavformat/avformat.h"
#include "libavutil/error.h"
#include "libavutil/mathematics.h"

static void print_error(const char *label, int code) {
    char text[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, text, sizeof(text));
    printf("%s: %s (%d)\n", label, text, code);
}

static int64_t stream_start_timestamp(AVFormatContext *context, AVStream *stream) {
    if (context->start_time != AV_NOPTS_VALUE) {
        return av_rescale_q(context->start_time, AV_TIME_BASE_Q, stream->time_base);
    }
    if (stream->start_time != AV_NOPTS_VALUE) return stream->start_time;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <url-or-path> <start-seconds> [end-offset-bytes]\n", argv[0]);
        return 2;
    }
    const char *path = argv[1];
    double startSeconds = atof(argv[2]);
    const char *endSpec = argc > 3 ? argv[3] : NULL;
    int64_t endOffset = 0;

    avformat_network_init();

    if (endSpec && strcmp(endSpec, "auto") == 0) {
        AVIOContext *sizeProbe = NULL;
        int sizeResult = avio_open2(&sizeProbe, path, AVIO_FLAG_READ, NULL, NULL);
        if (sizeResult >= 0) {
            int64_t size = avio_size(sizeProbe);
            if (size > 0) endOffset = size;
            avio_closep(&sizeProbe);
        }
        printf("auto_size_probe=%" PRId64 " result=%d\n", endOffset, sizeResult);
    } else if (endSpec) {
        endOffset = strtoll(endSpec, NULL, 10);
    }

    AVDictionary *options = NULL;
    if (endOffset > 0) {
        av_dict_set_int(&options, "end_offset", endOffset, 0);
    }
    printf("end_offset=%" PRId64 "\n", endOffset);

    AVFormatContext *context = NULL;
    int result = avformat_open_input(&context, path, NULL, &options);
    av_dict_free(&options);
    if (result < 0) {
        print_error("open", result);
        return 1;
    }
    result = avformat_find_stream_info(context, NULL);
    if (result < 0) {
        print_error("find_stream_info", result);
        avformat_close_input(&context);
        return 1;
    }

    int videoStreamIndex = av_find_best_stream(context, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (videoStreamIndex < 0) {
        print_error("find_best_stream", videoStreamIndex);
        avformat_close_input(&context);
        return 1;
    }
    AVStream *stream = context->streams[videoStreamIndex];

    int64_t startTimestamp = stream_start_timestamp(context, stream);
    double timeBase = av_q2d(stream->time_base);
    int64_t timestamp = startTimestamp + (int64_t)(startSeconds / timeBase);

    printf("format=%s\n", context->iformat && context->iformat->name ? context->iformat->name : "unknown");
    printf("io_seekable=%d io_is_streamed=%d\n",
           context->pb ? context->pb->seekable : -1,
           context->pb ? (int)(context->pb->seekable == 0) : -1);
    printf("container_start_time=%" PRId64 " stream_start_time=%" PRId64 "\n",
           context->start_time, stream->start_time);
    printf("stream_time_base=%d/%d duration=%" PRId64 "\n",
           stream->time_base.num, stream->time_base.den, context->duration);
    printf("video_stream_index=%d start_timestamp=%" PRId64 "\n", videoStreamIndex, startTimestamp);
    printf("requested_seconds=%f seek_timestamp=%" PRId64 "\n", startSeconds, timestamp);

    result = avformat_seek_file(
        context,
        videoStreamIndex,
        INT64_MIN,
        timestamp,
        INT64_MAX,
        AVSEEK_FLAG_BACKWARD
    );
    print_error("avformat_seek_file", result);

    int bridgeVerdict = result;

    result = av_seek_frame(context, videoStreamIndex, timestamp, AVSEEK_FLAG_BACKWARD);
    print_error("av_seek_frame", result);

    avformat_close_input(&context);
    avformat_network_deinit();
    return bridgeVerdict < 0 ? 1 : 0;
}
