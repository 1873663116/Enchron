// Reports the facts that the Dolby Vision handling in PlaybackFFmpegBridge.c
// rests on, measured through the same FFmpeg build the bridge links rather than
// through a command line ffprobe that may be a different version.
//
// Every value here mirrors one decision in the bridge:
//   decodedStreamIndex   av_find_best_stream, which is what PBFFmpegReaderOpen
//                        picks and therefore the only stream that reaches the
//                        decoder;
//   videoStreams[].dolbyVision
//                        the AV_PKT_DATA_DOVI_CONF side data detect_dolby_vision
//                        scans for on every video stream, which is where the
//                        dynamic range line gets its profile and the digit after
//                        it, which is the cross compatibility ID and not the level;
//   videoStreams[].declarable
//                        has_usable_dovi_configuration, the condition that
//                        decides whether codec_type and add_dovi_configuration_atom
//                        declare the track as Dolby Vision to VideoToolbox. A
//                        record with an enhancement layer is not declarable,
//                        because only the base layer reaches one decoder input
//                        and VideoToolbox refuses a track it is told is Profile 7.
//
// Prints one JSON object on stdout. Exits non-zero only when the file cannot be
// opened; a file that fails a premise still reports, because the caller decides
// which premise applies to which fixture.

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/dovi_meta.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void print_json_string(const char *value) {
    putchar('"');
    for (const char *cursor = value; *cursor; cursor++) {
        if (*cursor == '"' || *cursor == '\\') putchar('\\');
        putchar(*cursor);
    }
    putchar('"');
}

static const AVDOVIDecoderConfigurationRecord *dolby_vision_record(const AVStream *stream) {
    const AVPacketSideData *entry = av_packet_side_data_get(
        stream->codecpar->coded_side_data,
        stream->codecpar->nb_coded_side_data,
        AV_PKT_DATA_DOVI_CONF
    );
    if (!entry || entry->size < sizeof(AVDOVIDecoderConfigurationRecord)) return NULL;
    return (const AVDOVIDecoderConfigurationRecord *)entry->data;
}

/// The same condition has_usable_dovi_configuration applies. A record that is
/// present but carries an enhancement layer is deliberately not usable.
static bool declarable(const AVStream *stream) {
    const AVDOVIDecoderConfigurationRecord *record = dolby_vision_record(stream);
    return record != NULL && record->el_present_flag == 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <media-path>\n", argv[0]);
        return 2;
    }
    const char *path = argv[1];

    AVFormatContext *context = NULL;
    int result = avformat_open_input(&context, path, NULL, NULL);
    if (result < 0) {
        char message[256];
        av_strerror(result, message, sizeof(message));
        fprintf(stderr, "cannot open %s: %s\n", path, message);
        return 3;
    }
    result = avformat_find_stream_info(context, NULL);
    if (result < 0) {
        char message[256];
        av_strerror(result, message, sizeof(message));
        fprintf(stderr, "cannot read stream info for %s: %s\n", path, message);
        avformat_close_input(&context);
        return 3;
    }

    int decodedStreamIndex = av_find_best_stream(context, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);

    // The same scan detect_dolby_vision runs, including the rule that ties a record
    // on some other stream to this one: only a pure enhancement layer, which cannot
    // stand alone, is believed. A second stream carrying its own base layer is an
    // unrelated title and its profile is not a fact about the stream being decoded.
    int detectedProfile = 0;
    // The reader publishes the cross compatibility ID and not the level, because the
    // digit after the profile in a Dolby Vision name is the dynamic range the base
    // layer is also readable as. The level counts resolution and bitrate tiers and
    // takes its own values, which happen to coincide on some files and not others.
    int detectedCrossCompatibility = 0;
    bool detectedEnhancementLayer = false;
    int recordStreamIndex = -1;
    for (unsigned index = 0; index < context->nb_streams; index++) {
        AVStream *candidate = context->streams[index];
        if (candidate->codecpar->codec_type != AVMEDIA_TYPE_VIDEO) continue;
        const AVDOVIDecoderConfigurationRecord *record = dolby_vision_record(candidate);
        if (!record) continue;
        bool onDecodedStream = (int)index == decodedStreamIndex;
        if (!onDecodedStream) {
            if (record->bl_present_flag != 0) continue;
            if (detectedProfile != 0) continue;
        }
        detectedProfile = record->dv_profile;
        detectedCrossCompatibility = record->dv_bl_signal_compatibility_id;
        detectedEnhancementLayer = record->el_present_flag != 0;
        recordStreamIndex = (int)index;
        if (onDecodedStream) break;
    }

    printf("{\n  \"path\": ");
    print_json_string(path);
    printf(",\n  \"container\": ");
    print_json_string(context->iformat && context->iformat->name ? context->iformat->name : "");
    printf(",\n  \"libavformatVersion\": %u", avformat_version());
    printf(",\n  \"streamCount\": %u", context->nb_streams);
    printf(",\n  \"decodedStreamIndex\": %d", decodedStreamIndex);
    printf(",\n  \"videoStreams\": [");

    bool firstStream = true;
    for (unsigned index = 0; index < context->nb_streams; index++) {
        AVStream *candidate = context->streams[index];
        AVCodecParameters *parameters = candidate->codecpar;
        if (parameters->codec_type != AVMEDIA_TYPE_VIDEO) continue;
        if (!firstStream) putchar(',');
        firstStream = false;
        printf("\n    {\"index\": %u, \"codec\": ", index);
        const AVCodecDescriptor *descriptor = avcodec_descriptor_get(parameters->codec_id);
        print_json_string(descriptor && descriptor->name ? descriptor->name : "unknown");
        // codec_type reaches its Dolby Vision branch only for a dvh1 or dvhe sample
        // entry; add_dovi_configuration_atom reads no tag at all, which is why the
        // record alone decides whether a descriptor is attached.
        char tag[5] = {0};
        for (int byte = 0; byte < 4; byte++) {
            char value = (char)((parameters->codec_tag >> (byte * 8)) & 0xFF);
            tag[byte] = (value >= 32 && value < 127) ? value : '\0';
        }
        printf(", \"codecTag\": ");
        print_json_string(tag);
        printf(", \"width\": %d, \"height\": %d", parameters->width, parameters->height);
        printf(", \"isDecodedStream\": %s", (int)index == decodedStreamIndex ? "true" : "false");
        const AVDOVIDecoderConfigurationRecord *record = dolby_vision_record(candidate);
        if (record) {
            printf(
                ", \"dolbyVision\": {\"profile\": %u, \"level\": %u, \"rpuPresent\": %s, "
                "\"elPresent\": %s, \"blPresent\": %s, \"blCompatibilityId\": %u}",
                record->dv_profile,
                record->dv_level,
                record->rpu_present_flag ? "true" : "false",
                record->el_present_flag ? "true" : "false",
                record->bl_present_flag ? "true" : "false",
                record->dv_bl_signal_compatibility_id
            );
        } else {
            printf(", \"dolbyVision\": null");
        }
        printf(", \"declarable\": %s}", declarable(candidate) ? "true" : "false");
    }
    printf("\n  ],\n  \"detected\": {\"profile\": %d, \"crossCompatibilityID\": %d, "
           "\"hasEnhancementLayer\": %s, \"recordStreamIndex\": %d}",
           detectedProfile,
           detectedCrossCompatibility,
           detectedEnhancementLayer ? "true" : "false",
           recordStreamIndex);
    printf(",\n  \"decodedStreamDeclaresDolbyVision\": %s\n}\n",
           decodedStreamIndex >= 0 && declarable(context->streams[decodedStreamIndex])
               ? "true"
               : "false");

    avformat_close_input(&context);
    return 0;
}
