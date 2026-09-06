#include "PlaybackFFmpegBridge.h"
#include "PlaybackFFmpegBridgeInternal.h"

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

typedef struct PBSubtitleTextCue {
    double startSeconds;
    double durationSeconds;
    CFStringRef text;
} PBSubtitleTextCue;

// Identity of a packet already folded into the renderer. A shared demux
// source re-reads packets after every seek, so ingestion has to be
// idempotent per packet rather than per pass.
typedef struct PBSubtitlePacketIdentity {
    int64_t timestamp;
    int size;
} PBSubtitlePacketIdentity;

struct PBSubtitleFrameRenderer {
    enum AVCodecID codecID;
    AVCodecContext *decoder;
    PBSubtitlePacket *packets;
    size_t packetCount;
    PBSubtitleTextCue *textCues;
    size_t textCueCount;
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
    // Incremental ingestion over a shared demux source. NULL for a renderer
    // that owns its own format context and scanned the file at creation.
    PBFFmpegDemuxSource *demuxSource;
    int streamIndex;
    AVRational streamTimeBase;
    int64_t streamStartTimestamp;
    AVPacket *ingestPacket;
    PBSubtitlePacketIdentity *ingestedPackets;
    size_t ingestedPacketCount;
};

static const char *default_ass_header =
    "[Script Info]\n"
    "ScriptType: v4.00+\n"
    "PlayResX: 1920\n"
    "PlayResY: 1080\n"
    "ScaledBorderAndShadow: yes\n"
    "[V4+ Styles]\n"
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    "Style: Default,Helvetica Neue,54,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,3.24,0,2,96,96,54,1\n"
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
    // Bitmap frames are decoded sequentially by presentation time, so a
    // packet that arrives after a backward seek is inserted in order and
    // the sequential decode restarts when it lands before the cursor.
    size_t index = renderer->packetCount;
    while (index > 0 && renderer->packets[index - 1].startSeconds > startSeconds) {
        renderer->packets[index] = renderer->packets[index - 1];
        index--;
    }
    renderer->packets[index] = (PBSubtitlePacket) {
        .packet = copy,
        .startSeconds = startSeconds,
    };
    renderer->packetCount++;
    if (index < renderer->nextPacketIndex) {
        avcodec_flush_buffers(renderer->decoder);
        renderer->nextPacketIndex = 0;
        clear_bitmap_frame(renderer);
    }
    return true;
}

static bool packet_was_ingested(
    const PBSubtitleFrameRenderer *renderer,
    int64_t timestamp,
    int size
) {
    for (size_t index = 0; index < renderer->ingestedPacketCount; index++) {
        const PBSubtitlePacketIdentity *identity = &renderer->ingestedPackets[index];
        if (identity->timestamp == timestamp && identity->size == size) return true;
    }
    return false;
}

static bool remember_ingested_packet(
    PBSubtitleFrameRenderer *renderer,
    int64_t timestamp,
    int size
) {
    PBSubtitlePacketIdentity *identities = realloc(
        renderer->ingestedPackets,
        (renderer->ingestedPacketCount + 1) * sizeof(*identities)
    );
    if (!identities) return false;
    renderer->ingestedPackets = identities;
    renderer->ingestedPackets[renderer->ingestedPacketCount++] =
        (PBSubtitlePacketIdentity) { .timestamp = timestamp, .size = size };
    return true;
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

static CFStringRef subtitle_plain_text(const AVSubtitle *subtitle) {
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

static bool append_text_cue(
    PBSubtitleFrameRenderer *renderer,
    const AVSubtitle *subtitle,
    double startSeconds,
    double endSeconds
) {
    CFStringRef text = subtitle_plain_text(subtitle);
    if (!text) return false;
    PBSubtitleTextCue *cues = realloc(
        renderer->textCues,
        (renderer->textCueCount + 1) * sizeof(*cues)
    );
    if (!cues) {
        CFRelease(text);
        return false;
    }
    renderer->textCues = cues;
    renderer->textCues[renderer->textCueCount++] = (PBSubtitleTextCue) {
        .startSeconds = startSeconds,
        .durationSeconds = endSeconds - startSeconds,
        .text = text,
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
    bool storedCue = append_text_cue(
        renderer,
        &subtitle,
        startSeconds,
        endSeconds
    );
    avsubtitle_free(&subtitle);
    return storedCue;
}

// Folds one packet of the renderer's stream into the cue and frame state.
// Packets of other streams and packets seen before are ignored, so the same
// routine serves the one-pass scan of an owned format context and the
// repeated pumps of a shared demux source.
static bool ingest_packet(
    PBSubtitleFrameRenderer *renderer,
    AVPacket *packet
) {
    if (packet->stream_index != renderer->streamIndex ||
        packet->size <= 0 || !packet->data) return true;
    int64_t timestamp = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;
    if (packet_was_ingested(renderer, timestamp, packet->size)) return true;
    double startSeconds = timestamp != AV_NOPTS_VALUE
        ? (timestamp - renderer->streamStartTimestamp) * av_q2d(renderer->streamTimeBase)
        : 0;
    bool succeeded = is_text_codec(renderer->codecID)
        ? process_text_packet(renderer, packet, startSeconds)
        : append_packet(renderer, packet, startSeconds);
    if (!succeeded) return false;
    return remember_ingested_packet(renderer, timestamp, packet->size);
}

// Drains every packet the shared demux source has queued for the subtitle
// stream without waiting for more. Returns the number of packets folded in,
// or -1 with an error message.
static int ingest_available_packets(
    PBSubtitleFrameRenderer *renderer,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!renderer->demuxSource || !renderer->ingestPacket) return 0;
    int ingested = 0;
    while (true) {
        int result = PBFFmpegDemuxSourceCopyNextPacketIfAvailable(
            renderer->demuxSource,
            renderer->streamIndex,
            renderer->ingestPacket
        );
        if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) break;
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Read shared subtitle packet", result);
            return -1;
        }
        bool succeeded = ingest_packet(renderer, renderer->ingestPacket);
        av_packet_unref(renderer->ingestPacket);
        if (!succeeded) {
            set_error(errorBuffer, errorBufferSize, "Decode subtitle frame packet");
            return -1;
        }
        ingested++;
    }
    return ingested;
}

static PBSubtitleFrameRenderer *create_subtitle_frame_renderer(
    AVFormatContext *format,
    PBFFmpegDemuxSource *demuxSource,
    bool ownsFormat,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!format || streamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid subtitle frame renderer call");
        return NULL;
    }
    int result = 0;
    if (streamIndex >= (int)format->nb_streams) {
        set_error(errorBuffer, errorBufferSize, "Subtitle frame stream index is unavailable");
        if (ownsFormat) avformat_close_input(&format);
        return NULL;
    }
    AVStream *stream = format->streams[streamIndex];
    enum AVCodecID codecID = stream->codecpar->codec_id;
    if (!is_text_codec(codecID) && !is_bitmap_codec(codecID)) {
        set_error(errorBuffer, errorBufferSize, "Subtitle frame codec is unsupported");
        if (ownsFormat) avformat_close_input(&format);
        return NULL;
    }
    const AVCodec *codec = avcodec_find_decoder(codecID);
    if (!codec) {
        set_error(errorBuffer, errorBufferSize, "Subtitle frame decoder is unavailable");
        if (ownsFormat) avformat_close_input(&format);
        return NULL;
    }

    PBSubtitleFrameRenderer *renderer = calloc(1, sizeof(PBSubtitleFrameRenderer));
    if (!renderer) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate subtitle frame renderer");
        if (ownsFormat) avformat_close_input(&format);
        return NULL;
    }
    renderer->codecID = codecID;
    renderer->streamIndex = streamIndex;
    renderer->streamTimeBase = stream->time_base;
    renderer->lastRequestSeconds = -INFINITY;
    renderer->bitmapStartSeconds = INFINITY;
    renderer->bitmapEndSeconds = -INFINITY;
    renderer->decoder = avcodec_alloc_context3(codec);
    if (!renderer->decoder) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate subtitle decoder");
        if (ownsFormat) avformat_close_input(&format);
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
        if (ownsFormat) avformat_close_input(&format);
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
            if (ownsFormat) avformat_close_input(&format);
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

    renderer->streamStartTimestamp = stream_start_timestamp(format, stream);
    AVPacket *packet = av_packet_alloc();
    if (!packet) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate subtitle frame packet");
        if (ownsFormat) avformat_close_input(&format);
        PBSubtitleFrameRendererDestroy(renderer);
        return NULL;
    }
    if (demuxSource) {
        // The shared source feeds live playback and only advances at the
        // playhead's pace, so the renderer takes what is queued now and
        // folds in the rest through PBSubtitleFrameRendererIngestAvailablePackets.
        renderer->demuxSource = demuxSource;
        renderer->ingestPacket = packet;
        if (ingest_available_packets(renderer, errorBuffer, errorBufferSize) < 0) {
            PBSubtitleFrameRendererDestroy(renderer);
            return NULL;
        }
        return renderer;
    }
    while ((result = av_read_frame(format, packet)) >= 0) {
        bool succeeded = ingest_packet(renderer, packet);
        av_packet_unref(packet);
        if (!succeeded) {
            av_packet_free(&packet);
            if (ownsFormat) avformat_close_input(&format);
            set_error(errorBuffer, errorBufferSize, "Decode subtitle frame packet");
            PBSubtitleFrameRendererDestroy(renderer);
            return NULL;
        }
    }
    av_packet_free(&packet);
    if (ownsFormat) avformat_close_input(&format);
    if (is_text_codec(codecID)) avcodec_flush_buffers(renderer->decoder);
    return renderer;
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
    return create_subtitle_frame_renderer(
        format,
        NULL,
        true,
        streamIndex,
        errorBuffer,
        errorBufferSize
    );
}

PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreateWithDemuxSource(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    AVFormatContext *format = PBFFmpegDemuxSourceGetFormatContext(source);
    if (!format || streamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "Invalid shared subtitle frame renderer call");
        return NULL;
    }
    if (!PBFFmpegDemuxSourceSubscribe(source, streamIndex)) {
        set_error(errorBuffer, errorBufferSize, "The shared subtitle stream already has a reader");
        return NULL;
    }
    PBSubtitleFrameRenderer *renderer = create_subtitle_frame_renderer(
        format,
        source,
        false,
        streamIndex,
        errorBuffer,
        errorBufferSize
    );
    // The subscription lives as long as the renderer: the source keeps
    // queueing the stream and the renderer drains it on every ingest.
    if (!renderer) PBFFmpegDemuxSourceUnsubscribe(source, streamIndex);
    return renderer;
}

int PBSubtitleFrameRendererIngestAvailablePackets(
    PBSubtitleFrameRenderer *renderer,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (!renderer) {
        set_error(errorBuffer, errorBufferSize, "Invalid subtitle ingest call");
        return -1;
    }
    return ingest_available_packets(renderer, errorBuffer, errorBufferSize);
}

void PBSubtitleFrameRendererDestroy(PBSubtitleFrameRenderer *renderer) {
    if (!renderer) return;
    if (renderer->demuxSource) {
        PBFFmpegDemuxSourceUnsubscribe(renderer->demuxSource, renderer->streamIndex);
    }
    av_packet_free(&renderer->ingestPacket);
    free(renderer->ingestedPackets);
    clear_bitmap_frame(renderer);
    for (size_t index = 0; index < renderer->packetCount; index++) {
        av_packet_free(&renderer->packets[index].packet);
    }
    free(renderer->packets);
    for (size_t index = 0; index < renderer->textCueCount; index++) {
        CFRelease(renderer->textCues[index].text);
    }
    free(renderer->textCues);
    avcodec_free_context(&renderer->decoder);
    if (renderer->assTrack) ass_free_track(renderer->assTrack);
    if (renderer->assRenderer) ass_renderer_done(renderer->assRenderer);
    if (renderer->assLibrary) ass_library_done(renderer->assLibrary);
    free(renderer);
}

int PBSubtitleFrameRendererGetTextCueCount(
    const PBSubtitleFrameRenderer *renderer
) {
    return renderer && renderer->textCueCount <= INT_MAX
        ? (int)renderer->textCueCount
        : 0;
}

bool PBSubtitleFrameRendererCopyTextCue(
    const PBSubtitleFrameRenderer *renderer,
    int index,
    double *startSecondsOut,
    double *durationSecondsOut,
    CFStringRef *textOut
) {
    if (!renderer || index < 0 ||
        (size_t)index >= renderer->textCueCount ||
        !startSecondsOut || !durationSecondsOut || !textOut) return false;
    const PBSubtitleTextCue *cue = &renderer->textCues[index];
    *startSecondsOut = cue->startSeconds;
    *durationSecondsOut = cue->durationSeconds;
    *textOut = CFRetain(cue->text);
    return true;
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
