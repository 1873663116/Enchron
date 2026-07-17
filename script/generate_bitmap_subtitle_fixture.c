#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/error.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fail(const char *operation, int error) {
    char message[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(error, message, sizeof(message));
    fprintf(stderr, "%s: %s (%d)\n", operation, message, error);
    return 1;
}

static void draw_rect(
    uint8_t *pixels,
    int stride,
    int x,
    int y,
    int width,
    int height,
    uint8_t color
) {
    for (int row = y; row < y + height; row++) {
        memset(pixels + row * stride + x, color, (size_t)width);
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s output.mks\n", argv[0]);
        return 2;
    }

    const AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_DVB_SUBTITLE);
    if (!codec) return fail("Find DVB subtitle encoder", AVERROR_ENCODER_NOT_FOUND);
    AVCodecContext *encoder = avcodec_alloc_context3(codec);
    if (!encoder) return fail("Allocate DVB subtitle encoder", AVERROR(ENOMEM));
    encoder->flags |= AV_CODEC_FLAG_BITEXACT;
    encoder->width = 1280;
    encoder->height = 720;
    encoder->time_base = (AVRational){1, 1000};
    int result = avcodec_open2(encoder, codec, NULL);
    if (result < 0) return fail("Open DVB subtitle encoder", result);

    AVFormatContext *format = NULL;
    result = avformat_alloc_output_context2(&format, NULL, "matroska", argv[1]);
    if (result < 0 || !format) return fail("Create Matroska output", result);
    format->flags |= AVFMT_FLAG_BITEXACT;
    AVStream *stream = avformat_new_stream(format, NULL);
    if (!stream) return fail("Create bitmap subtitle stream", AVERROR(ENOMEM));
    stream->time_base = encoder->time_base;
    result = avcodec_parameters_from_context(stream->codecpar, encoder);
    if (result < 0) return fail("Copy bitmap subtitle parameters", result);
    av_dict_set(&stream->metadata, "language", "eng", 0);
    av_dict_set(&stream->metadata, "title", "Enchron generated bitmap proof", 0);

    if (!(format->oformat->flags & AVFMT_NOFILE)) {
        result = avio_open(&format->pb, argv[1], AVIO_FLAG_WRITE);
        if (result < 0) return fail("Open bitmap subtitle output", result);
    }
    result = avformat_write_header(format, NULL);
    if (result < 0) return fail("Write bitmap subtitle header", result);

    const int width = 640;
    const int height = 96;
    uint8_t *pixels = calloc((size_t)width * height, 1);
    uint32_t *palette = calloc(4, sizeof(uint32_t));
    AVSubtitleRect *rect = calloc(1, sizeof(AVSubtitleRect));
    AVSubtitleRect **rects = calloc(1, sizeof(AVSubtitleRect *));
    uint8_t *encoded = calloc(1, 1024 * 1024);
    if (!pixels || !palette || !rect || !rects || !encoded) {
        return fail("Allocate generated bitmap subtitle", AVERROR(ENOMEM));
    }

    palette[0] = 0x00000000;
    palette[1] = 0xFFFF00FF;
    palette[2] = 0xFFFFFFFF;
    palette[3] = 0xFF000000;
    draw_rect(pixels, width, 0, 0, width, height, 3);
    draw_rect(pixels, width, 5, 5, width - 10, height - 10, 1);
    for (int column = 0; column < 11; column++) {
        draw_rect(pixels, width, 36 + column * 54, 20, 28, 56, column % 2 ? 1 : 2);
    }

    rect->x = 320;
    rect->y = 72;
    rect->w = width;
    rect->h = height;
    rect->nb_colors = 4;
    rect->data[0] = pixels;
    rect->linesize[0] = width;
    rect->data[1] = (uint8_t *)palette;
    rect->type = SUBTITLE_BITMAP;
    rects[0] = rect;
    AVSubtitle subtitle = {
        .format = 0,
        .start_display_time = 0,
        .end_display_time = 30000,
        .num_rects = 1,
        .rects = rects,
        .pts = 0,
    };
    int encodedSize = avcodec_encode_subtitle(
        encoder,
        encoded,
        1024 * 1024,
        &subtitle
    );
    if (encodedSize < 0) return fail("Encode generated bitmap subtitle", encodedSize);

    AVPacket *packet = av_packet_alloc();
    if (!packet) return fail("Allocate bitmap subtitle packet", AVERROR(ENOMEM));
    result = av_new_packet(packet, encodedSize);
    if (result < 0) return fail("Allocate bitmap subtitle packet data", result);
    memcpy(packet->data, encoded, (size_t)encodedSize);
    packet->stream_index = stream->index;
    packet->pts = 500;
    packet->dts = 500;
    packet->duration = 29000;
    result = av_interleaved_write_frame(format, packet);
    if (result < 0) return fail("Write bitmap subtitle packet", result);

    result = av_write_trailer(format);
    if (result < 0) return fail("Write bitmap subtitle trailer", result);
    av_packet_free(&packet);
    free(encoded);
    free(rects);
    free(rect);
    free(palette);
    free(pixels);
    avio_closep(&format->pb);
    avformat_free_context(format);
    avcodec_free_context(&encoder);
    return 0;
}
