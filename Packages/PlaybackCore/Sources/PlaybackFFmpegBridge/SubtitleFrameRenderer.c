#include "PlaybackFFmpegBridge.h"

#include <ass/ass.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <math.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct PBSubtitlePacket {
    AVPacket *packet;
    double startSeconds;
} PBSubtitlePacket;

struct PBSubtitleFrameRenderer {
    enum AVCodecID codecID;
    AVCodecContext *decoder;
    PBSubtitlePacket *packets;
    size_t packetCount;
    size_t nextPacketIndex;
    double lastRequestSeconds;
    double bitmapStartSeconds;
    double bitmapEndSeconds;
    uint8_t *bitmapPixels;
    PBSubtitleFrameInfo bitmapInfo;
    int sourceWidth;
    int sourceHeight;
    ASS_Library *assLibrary;
    ASS_Renderer *assRenderer;
    ASS_Track *assTrack;
    uint64_t lastHash;
    uint64_t changeIdentifier;
    bool hadFrame;
};

static const char *default_ass_header =
    "[Script Info]\n"
    "ScriptType: v4.00+\n"
    "PlayResX: 1920\n"
    "PlayResY: 1080\n"
    "ScaledBorderAndShadow: yes\n"
    "[V4+ Styles]\n"
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    "Style: Default,Helvetica Neue,64,&H00FFFFFF,&H000000FF,&H00101010,&H80000000,0,0,0,0,100,100,0,0,1,3,1,2,80,80,54,1\n"
    "[Events]\n"
    "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n";

static void set_error(char *buffer, size_t size, const char *message) {
    if (buffer && size > 0) snprintf(buffer, size, "%s", message);
}

static void set_av_error(
    char *buffer,
    size_t size,
    const char *operation,
    int code
) {
    char detail[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, detail, sizeof(detail));
    if (buffer && size > 0) {
        snprintf(buffer, size, "%s: %s (%d)", operation, detail, code);
    }
}

static bool is_bitmap_codec(enum AVCodecID codecID) {
    return codecID == AV_CODEC_ID_HDMV_PGS_SUBTITLE ||
        codecID == AV_CODEC_ID_DVD_SUBTITLE ||
        codecID == AV_CODEC_ID_DVB_SUBTITLE;
}

static bool is_text_codec(enum AVCodecID codecID) {
    return codecID == AV_CODEC_ID_ASS ||
        codecID == AV_CODEC_ID_SSA ||
        codecID == AV_CODEC_ID_SUBRIP ||
        codecID == AV_CODEC_ID_WEBVTT ||
        codecID == AV_CODEC_ID_MOV_TEXT;
}

static int64_t stream_start_timestamp(
    const AVFormatContext *format,
    const AVStream *stream
) {
    if (stream->start_time != AV_NOPTS_VALUE) return stream->start_time;
    if (format->start_time != AV_NOPTS_VALUE) {
        return av_rescale_q(
            format->start_time,
            AV_TIME_BASE_Q,
            stream->time_base
        );
    }
    return 0;
}

static uint64_t fnv1a(const uint8_t *bytes, size_t count, uint64_t seed) {
    uint64_t hash = seed;
    for (size_t index = 0; index < count; index++) {
        hash ^= bytes[index];
        hash *= 1099511628211ULL;
    }
    return hash;
}

static void blend_premultiplied_bgra(uint8_t *destination, const uint8_t *source) {
    unsigned int sourceAlpha = source[3];
    unsigned int inverseAlpha = 255 - sourceAlpha;
    destination[0] = (uint8_t)(source[0] + destination[0] * inverseAlpha / 255);
    destination[1] = (uint8_t)(source[1] + destination[1] * inverseAlpha / 255);
    destination[2] = (uint8_t)(source[2] + destination[2] * inverseAlpha / 255);
    destination[3] = (uint8_t)(sourceAlpha + destination[3] * inverseAlpha / 255);
}

static void clear_bitmap_frame(PBSubtitleFrameRenderer *renderer) {
    free(renderer->bitmapPixels);
    renderer->bitmapPixels = NULL;
    memset(&renderer->bitmapInfo, 0, sizeof(renderer->bitmapInfo));
    renderer->bitmapStartSeconds = INFINITY;
    renderer->bitmapEndSeconds = -INFINITY;
}

static bool make_bitmap_frame(
    PBSubtitleFrameRenderer *renderer,
    const AVSubtitle *subtitle,
    double startSeconds,
    double endSeconds
) {
    int minX = INT_MAX;
    int minY = INT_MAX;
    int maxX = 0;
    int maxY = 0;
    for (unsigned int index = 0; index < subtitle->num_rects; index++) {
        const AVSubtitleRect *rect = subtitle->rects[index];
        if (!rect || rect->type != SUBTITLE_BITMAP || rect->w <= 0 || rect->h <= 0) {
            continue;
        }
        if (!rect->data[0] || !rect->data[1] || rect->nb_colors <= 0) continue;
        minX = rect->x < minX ? rect->x : minX;
        minY = rect->y < minY ? rect->y : minY;
        maxX = rect->x + rect->w > maxX ? rect->x + rect->w : maxX;
        maxY = rect->y + rect->h > maxY ? rect->y + rect->h : maxY;
    }
    if (minX == INT_MAX || maxX <= minX || maxY <= minY) {
        clear_bitmap_frame(renderer);
        return true;
    }

    int width = maxX - minX;
    int height = maxY - minY;
    size_t byteCount = (size_t)width * (size_t)height * 4;
    uint8_t *pixels = calloc(1, byteCount);
    if (!pixels) return false;

    for (unsigned int index = 0; index < subtitle->num_rects; index++) {
        const AVSubtitleRect *rect = subtitle->rects[index];
        if (!rect || rect->type != SUBTITLE_BITMAP || rect->w <= 0 || rect->h <= 0 ||
            !rect->data[0] || !rect->data[1] || rect->nb_colors <= 0) {
            continue;
        }
        const uint32_t *palette = (const uint32_t *)rect->data[1];
        for (int y = 0; y < rect->h; y++) {
            const uint8_t *indices = rect->data[0] + y * rect->linesize[0];
            for (int x = 0; x < rect->w; x++) {
                unsigned int paletteIndex = indices[x];
                if (paletteIndex >= (unsigned int)rect->nb_colors) continue;
                uint32_t color = palette[paletteIndex];
                unsigned int alpha = (color >> 24) & 0xff;
                uint8_t source[4] = {
                    (uint8_t)((color & 0xff) * alpha / 255),
                    (uint8_t)(((color >> 8) & 0xff) * alpha / 255),
                    (uint8_t)(((color >> 16) & 0xff) * alpha / 255),
                    (uint8_t)alpha,
                };
                size_t destinationIndex = (
                    (size_t)(rect->y - minY + y) * (size_t)width +
                    (size_t)(rect->x - minX + x)
                ) * 4;
                blend_premultiplied_bgra(pixels + destinationIndex, source);
            }
        }
    }

    clear_bitmap_frame(renderer);
    renderer->bitmapPixels = pixels;
    renderer->bitmapStartSeconds = startSeconds;
    renderer->bitmapEndSeconds = endSeconds;
    renderer->bitmapInfo = (PBSubtitleFrameInfo) {
        .kind = PBSubtitleFrameKindBitmap,
        .canvasWidth = renderer->sourceWidth > 0 ? renderer->sourceWidth : maxX,
        .canvasHeight = renderer->sourceHeight > 0 ? renderer->sourceHeight : maxY,
        .contentX = minX,
        .contentY = minY,
        .contentWidth = width,
        .contentHeight = height,
        .bytesPerRow = width * 4,
    };
    return true;
}

static bool append_packet(
    PBSubtitleFrameRenderer *renderer,
    const AVPacket *packet,
    double startSeconds
) {
    PBSubtitlePacket *packets = realloc(
        renderer->packets,
        (renderer->packetCount + 1) * sizeof(PBSubtitlePacket)
    );
    if (!packets) return false;
    renderer->packets = packets;
    AVPacket *copy = av_packet_clone(packet);
    if (!copy) return false;
    renderer->packets[renderer->packetCount++] = (PBSubtitlePacket) {
        .packet = copy,
        .startSeconds = startSeconds,
    };
    return true;
}

static bool process_text_packet(
    PBSubtitleFrameRenderer *renderer,
    AVPacket *packet,
    double packetStartSeconds
) {
    AVSubtitle subtitle = {0};
    int produced = 0;
    int result = avcodec_decode_subtitle2(renderer->decoder, &subtitle, &produced, packet);
    if (result < 0) return false;
    if (!produced) return true;
    double startSeconds = packetStartSeconds + subtitle.start_display_time / 1000.0;
    double endSeconds = packetStartSeconds + subtitle.end_display_time / 1000.0;
    if (endSeconds <= startSeconds) {
        double packetDuration = packet->duration > 0
            ? packet->duration * av_q2d(renderer->decoder->pkt_timebase)
            : 5.0;
        endSeconds = startSeconds + packetDuration;
    }
    long long startMilliseconds = llround(startSeconds * 1000.0);
    long long durationMilliseconds = llround((endSeconds - startSeconds) * 1000.0);
    for (unsigned int index = 0; index < subtitle.num_rects; index++) {
        AVSubtitleRect *rect = subtitle.rects[index];
        if (!rect || !rect->ass) continue;
        ass_process_chunk(
            renderer->assTrack,
            rect->ass,
            (int)strlen(rect->ass),
            startMilliseconds,
            durationMilliseconds
        );
    }
    avsubtitle_free(&subtitle);
    return true;
}

PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreate(
    const char *path,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!path || streamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid subtitle frame renderer call");
        return NULL;
    }
    AVFormatContext *format = NULL;
    int result = avformat_open_input(&format, path, NULL, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open subtitle frame source", result);
        return NULL;
    }
    result = avformat_find_stream_info(format, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read subtitle frame stream information", result);
        avformat_close_input(&format);
        return NULL;
    }
    if (streamIndex >= (int)format->nb_streams) {
        set_error(errorBuffer, errorBufferSize, "Subtitle frame stream index is unavailable");
        avformat_close_input(&format);
        return NULL;
    }
    AVStream *stream = format->streams[streamIndex];
    enum AVCodecID codecID = stream->codecpar->codec_id;
    if (!is_text_codec(codecID) && !is_bitmap_codec(codecID)) {
        set_error(errorBuffer, errorBufferSize, "Subtitle frame codec is unsupported");
        avformat_close_input(&format);
        return NULL;
    }
    const AVCodec *codec = avcodec_find_decoder(codecID);
    if (!codec) {
        set_error(errorBuffer, errorBufferSize, "Subtitle frame decoder is unavailable");
        avformat_close_input(&format);
        return NULL;
    }

    PBSubtitleFrameRenderer *renderer = calloc(1, sizeof(PBSubtitleFrameRenderer));
    if (!renderer) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate subtitle frame renderer");
        avformat_close_input(&format);
        return NULL;
    }
    renderer->codecID = codecID;
    renderer->lastRequestSeconds = -INFINITY;
    renderer->bitmapStartSeconds = INFINITY;
    renderer->bitmapEndSeconds = -INFINITY;
    renderer->decoder = avcodec_alloc_context3(codec);
    if (!renderer->decoder) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate subtitle decoder");
        avformat_close_input(&format);
        PBSubtitleFrameRendererDestroy(renderer);
        return NULL;
    }
    result = avcodec_parameters_to_context(renderer->decoder, stream->codecpar);
    if (result >= 0) {
        renderer->decoder->pkt_timebase = stream->time_base;
        result = avcodec_open2(renderer->decoder, codec, NULL);
    }
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open subtitle frame decoder", result);
        avformat_close_input(&format);
        PBSubtitleFrameRendererDestroy(renderer);
        return NULL;
    }

    renderer->sourceWidth = renderer->decoder->width;
    renderer->sourceHeight = renderer->decoder->height;
    if (renderer->sourceWidth <= 0 || renderer->sourceHeight <= 0) {
        for (unsigned int index = 0; index < format->nb_streams; index++) {
            AVCodecParameters *parameters = format->streams[index]->codecpar;
            if (parameters->codec_type == AVMEDIA_TYPE_VIDEO &&
                parameters->width > 0 && parameters->height > 0) {
                renderer->sourceWidth = parameters->width;
                renderer->sourceHeight = parameters->height;
                break;
            }
        }
    }

    if (is_text_codec(codecID)) {
        renderer->assLibrary = ass_library_init();
        renderer->assRenderer = renderer->assLibrary
            ? ass_renderer_init(renderer->assLibrary)
            : NULL;
        renderer->assTrack = renderer->assLibrary
            ? ass_new_track(renderer->assLibrary)
            : NULL;
        if (!renderer->assLibrary || !renderer->assRenderer || !renderer->assTrack) {
            set_error(errorBuffer, errorBufferSize, "Initialize libass subtitle renderer");
            avformat_close_input(&format);
            PBSubtitleFrameRendererDestroy(renderer);
            return NULL;
        }
        ass_set_fonts(
            renderer->assRenderer,
            NULL,
            "Helvetica Neue",
            ASS_FONTPROVIDER_AUTODETECT,
            NULL,
            1
        );
        if (stream->codecpar->extradata && stream->codecpar->extradata_size > 0) {
            ass_process_codec_private(
                renderer->assTrack,
                (char *)stream->codecpar->extradata,
                stream->codecpar->extradata_size
            );
        } else {
            ass_process_data(
                renderer->assTrack,
                (char *)default_ass_header,
                (int)strlen(default_ass_header)
            );
        }
    }

    int64_t startTimestamp = stream_start_timestamp(format, stream);
    AVPacket *packet = av_packet_alloc();
    if (!packet) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate subtitle frame packet");
        avformat_close_input(&format);
        PBSubtitleFrameRendererDestroy(renderer);
        return NULL;
    }
    while (av_read_frame(format, packet) >= 0) {
        if (packet->stream_index == streamIndex && packet->size > 0 && packet->data) {
            int64_t timestamp = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;
            double startSeconds = timestamp != AV_NOPTS_VALUE
                ? (timestamp - startTimestamp) * av_q2d(stream->time_base)
                : 0;
            bool succeeded = is_text_codec(codecID)
                ? process_text_packet(renderer, packet, startSeconds)
                : append_packet(renderer, packet, startSeconds);
            if (!succeeded) {
                av_packet_free(&packet);
                avformat_close_input(&format);
                set_error(errorBuffer, errorBufferSize, "Decode subtitle frame packet");
                PBSubtitleFrameRendererDestroy(renderer);
                return NULL;
            }
        }
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    avformat_close_input(&format);
    if (is_text_codec(codecID)) avcodec_flush_buffers(renderer->decoder);
    return renderer;
}

void PBSubtitleFrameRendererDestroy(PBSubtitleFrameRenderer *renderer) {
    if (!renderer) return;
    clear_bitmap_frame(renderer);
    for (size_t index = 0; index < renderer->packetCount; index++) {
        av_packet_free(&renderer->packets[index].packet);
    }
    free(renderer->packets);
    avcodec_free_context(&renderer->decoder);
    if (renderer->assTrack) ass_free_track(renderer->assTrack);
    if (renderer->assRenderer) ass_renderer_done(renderer->assRenderer);
    if (renderer->assLibrary) ass_library_done(renderer->assLibrary);
    free(renderer);
}

static PBSubtitleFrameResult copy_pixels(
    PBSubtitleFrameRenderer *renderer,
    const uint8_t *pixels,
    PBSubtitleFrameInfo info,
    CFDataRef *dataOut,
    PBSubtitleFrameInfo *infoOut
) {
    size_t byteCount = (size_t)info.bytesPerRow * (size_t)info.contentHeight;
    uint64_t hash = fnv1a(
        (const uint8_t *)&info,
        offsetof(PBSubtitleFrameInfo, changeIdentifier),
        1469598103934665603ULL
    );
    hash = fnv1a(pixels, byteCount, hash);
    if (!renderer->hadFrame || renderer->lastHash != hash) {
        renderer->changeIdentifier++;
        renderer->lastHash = hash;
    }
    renderer->hadFrame = true;
    info.changeIdentifier = renderer->changeIdentifier;
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, pixels, (CFIndex)byteCount);
    if (!data) return PBSubtitleFrameResultError;
    *dataOut = data;
    *infoOut = info;
    return PBSubtitleFrameResultFrame;
}

static PBSubtitleFrameResult copy_empty_frame(
    PBSubtitleFrameRenderer *renderer,
    PBSubtitleFrameInfo *infoOut
) {
    if (renderer->hadFrame) renderer->changeIdentifier++;
    renderer->hadFrame = false;
    memset(infoOut, 0, sizeof(*infoOut));
    infoOut->kind = is_bitmap_codec(renderer->codecID)
        ? PBSubtitleFrameKindBitmap
        : PBSubtitleFrameKindLibass;
    infoOut->changeIdentifier = renderer->changeIdentifier;
    return PBSubtitleFrameResultEmpty;
}

static PBSubtitleFrameResult copy_ass_frame(
    PBSubtitleFrameRenderer *renderer,
    double timeSeconds,
    int viewportWidth,
    int viewportHeight,
    CFDataRef *dataOut,
    PBSubtitleFrameInfo *infoOut
) {
    int width = viewportWidth > 0 ? viewportWidth : 1920;
    int height = viewportHeight > 0 ? viewportHeight : 1080;
    ass_set_frame_size(renderer->assRenderer, width, height);
    ass_set_storage_size(renderer->assRenderer, width, height);
    int changed = 0;
    ASS_Image *images = ass_render_frame(
        renderer->assRenderer,
        renderer->assTrack,
        llround(timeSeconds * 1000.0),
        &changed
    );
    (void)changed;
    int minX = width;
    int minY = height;
    int maxX = 0;
    int maxY = 0;
    for (ASS_Image *image = images; image; image = image->next) {
        int x0 = image->dst_x < 0 ? 0 : image->dst_x;
        int y0 = image->dst_y < 0 ? 0 : image->dst_y;
        int x1 = image->dst_x + image->w > width ? width : image->dst_x + image->w;
        int y1 = image->dst_y + image->h > height ? height : image->dst_y + image->h;
        if (x1 <= x0 || y1 <= y0) continue;
        minX = x0 < minX ? x0 : minX;
        minY = y0 < minY ? y0 : minY;
        maxX = x1 > maxX ? x1 : maxX;
        maxY = y1 > maxY ? y1 : maxY;
    }
    if (maxX <= minX || maxY <= minY) return copy_empty_frame(renderer, infoOut);

    int contentWidth = maxX - minX;
    int contentHeight = maxY - minY;
    size_t byteCount = (size_t)contentWidth * (size_t)contentHeight * 4;
    uint8_t *pixels = calloc(1, byteCount);
    if (!pixels) return PBSubtitleFrameResultError;
    for (ASS_Image *image = images; image; image = image->next) {
        unsigned int red = (image->color >> 24) & 0xff;
        unsigned int green = (image->color >> 16) & 0xff;
        unsigned int blue = (image->color >> 8) & 0xff;
        unsigned int opacity = 255 - (image->color & 0xff);
        for (int y = 0; y < image->h; y++) {
            int destinationY = image->dst_y + y;
            if (destinationY < minY || destinationY >= maxY) continue;
            const uint8_t *coverage = image->bitmap + y * image->stride;
            for (int x = 0; x < image->w; x++) {
                int destinationX = image->dst_x + x;
                if (destinationX < minX || destinationX >= maxX) continue;
                unsigned int alpha = coverage[x] * opacity / 255;
                if (alpha == 0) continue;
                uint8_t source[4] = {
                    (uint8_t)(blue * alpha / 255),
                    (uint8_t)(green * alpha / 255),
                    (uint8_t)(red * alpha / 255),
                    (uint8_t)alpha,
                };
                size_t destinationIndex = (
                    (size_t)(destinationY - minY) * (size_t)contentWidth +
                    (size_t)(destinationX - minX)
                ) * 4;
                blend_premultiplied_bgra(pixels + destinationIndex, source);
            }
        }
    }
    PBSubtitleFrameInfo info = {
        .kind = PBSubtitleFrameKindLibass,
        .canvasWidth = width,
        .canvasHeight = height,
        .contentX = minX,
        .contentY = minY,
        .contentWidth = contentWidth,
        .contentHeight = contentHeight,
        .bytesPerRow = contentWidth * 4,
    };
    PBSubtitleFrameResult result = copy_pixels(renderer, pixels, info, dataOut, infoOut);
    free(pixels);
    return result;
}

static PBSubtitleFrameResult copy_bitmap_frame(
    PBSubtitleFrameRenderer *renderer,
    double timeSeconds,
    CFDataRef *dataOut,
    PBSubtitleFrameInfo *infoOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (timeSeconds + 0.001 < renderer->lastRequestSeconds) {
        avcodec_flush_buffers(renderer->decoder);
        renderer->nextPacketIndex = 0;
        clear_bitmap_frame(renderer);
    }
    renderer->lastRequestSeconds = timeSeconds;

    while (renderer->nextPacketIndex < renderer->packetCount &&
           renderer->packets[renderer->nextPacketIndex].startSeconds <= timeSeconds + 0.001) {
        PBSubtitlePacket *item = &renderer->packets[renderer->nextPacketIndex++];
        AVSubtitle subtitle = {0};
        int produced = 0;
        int result = avcodec_decode_subtitle2(
            renderer->decoder,
            &subtitle,
            &produced,
            item->packet
        );
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Decode bitmap subtitle", result);
            return PBSubtitleFrameResultError;
        }
        if (!produced) continue;
        double startSeconds = item->startSeconds + subtitle.start_display_time / 1000.0;
        double endSeconds = item->startSeconds + subtitle.end_display_time / 1000.0;
        if (endSeconds <= startSeconds) {
            double packetDuration = item->packet->duration > 0
                ? item->packet->duration * av_q2d(renderer->decoder->pkt_timebase)
                : 60.0;
            endSeconds = startSeconds + packetDuration;
        }
        bool succeeded = make_bitmap_frame(renderer, &subtitle, startSeconds, endSeconds);
        avsubtitle_free(&subtitle);
        if (!succeeded) {
            set_error(errorBuffer, errorBufferSize, "Compose bitmap subtitle frame");
            return PBSubtitleFrameResultError;
        }
    }

    if (!renderer->bitmapPixels ||
        timeSeconds + 0.001 < renderer->bitmapStartSeconds ||
        timeSeconds >= renderer->bitmapEndSeconds - 0.001) {
        return copy_empty_frame(renderer, infoOut);
    }
    return copy_pixels(
        renderer,
        renderer->bitmapPixels,
        renderer->bitmapInfo,
        dataOut,
        infoOut
    );
}

PBSubtitleFrameResult PBSubtitleFrameRendererCopyFrame(
    PBSubtitleFrameRenderer *renderer,
    double timeSeconds,
    int viewportWidth,
    int viewportHeight,
    CFDataRef *bgraDataOut,
    PBSubtitleFrameInfo *infoOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!renderer || !isfinite(timeSeconds) || !bgraDataOut || !infoOut) {
        set_error(errorBuffer, errorBufferSize, "Invalid subtitle frame copy call");
        return PBSubtitleFrameResultError;
    }
    *bgraDataOut = NULL;
    if (is_bitmap_codec(renderer->codecID)) {
        return copy_bitmap_frame(
            renderer,
            timeSeconds,
            bgraDataOut,
            infoOut,
            errorBuffer,
            errorBufferSize
        );
    }
    return copy_ass_frame(
        renderer,
        timeSeconds,
        viewportWidth,
        viewportHeight,
        bgraDataOut,
        infoOut
    );
}
