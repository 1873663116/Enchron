#include "PlaybackFFmpegBridge.h"

#include <AudioToolbox/AudioToolbox.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/pixdesc.h>
#include <libavutil/spherical.h>
#include <libavutil/stereo3d.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct PBFFmpegReader {
    AVFormatContext *formatContext;
    AVPacket *packet;
    int videoStreamIndex;
    AVRational timeBase;
    int64_t startTimestamp;
    PBFFmpegMode mode;
    CMVideoFormatDescriptionRef compressedFormat;
    bool convertsAnnexB;
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
};

struct PBFFmpegAudioReader {
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
    CMAudioFormatDescriptionRef formatDescription;
    char codecName[64];
};

static AudioFormatID audio_format_id(enum AVCodecID codecID) {
    switch (codecID) {
        case AV_CODEC_ID_AAC: return kAudioFormatMPEG4AAC;
        case AV_CODEC_ID_AC3: return kAudioFormatAC3;
        case AV_CODEC_ID_EAC3: return kAudioFormatEnhancedAC3;
        case AV_CODEC_ID_MP2: return kAudioFormatMPEGLayer2;
        case AV_CODEC_ID_MP3: return kAudioFormatMPEGLayer3;
        case AV_CODEC_ID_ALAC: return kAudioFormatAppleLossless;
        case AV_CODEC_ID_FLAC: return kAudioFormatFLAC;
        case AV_CODEC_ID_OPUS: return kAudioFormatOpus;
        default: return 0;
    }
}

static bool audio_stream_is_supported(const AVStream *stream) {
    if (!stream || stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) return false;
    return audio_format_id(stream->codecpar->codec_id) != 0 &&
        stream->codecpar->sample_rate > 0 &&
        stream->codecpar->ch_layout.nb_channels > 0;
}

static void set_error(char *buffer, size_t size, const char *message);

static bool audio_stream_needs_more_probe(const AVStream *stream) {
    if (!stream || stream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) return false;
    return audio_format_id(stream->codecpar->codec_id) != 0 &&
        (stream->codecpar->sample_rate <= 0 ||
         stream->codecpar->ch_layout.nb_channels <= 0);
}

static bool is_audio_stream(const AVStream *stream) {
    return stream && stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO;
}

static bool audio_stream_has_supported_codec(const AVStream *stream) {
    return is_audio_stream(stream) &&
        audio_format_id(stream->codecpar->codec_id) != 0;
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
        set_error(errorBuffer, errorBufferSize, "The selected compressed audio codec is not supported");
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

static int open_media_source_for_audio(
    const char *path,
    AVFormatContext **contextOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    AVFormatContext *context = NULL;
    int result = avformat_open_input(&context, path, NULL, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open audio media source", result);
        return result;
    }
    result = avformat_find_stream_info(context, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read audio stream information", result);
        avformat_close_input(&context);
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

    avformat_close_input(&context);
    context = avformat_alloc_context();
    if (context == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate extended audio probe context");
        return AVERROR(ENOMEM);
    }
    context->probesize = 100LL * 1024 * 1024;
    context->max_analyze_duration = 30LL * AV_TIME_BASE;
    context->max_probe_packets = 100000;
    result = avformat_open_input(&context, path, NULL, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Reopen audio media source", result);
        avformat_close_input(&context);
        return result;
    }
    result = avformat_find_stream_info(context, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read extended audio stream information", result);
        avformat_close_input(&context);
        return result;
    }
    probe_delayed_audio_parameters(context);
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

static OSType codec_type(const AVCodecParameters *parameters) {
    switch (parameters->codec_id) {
        case AV_CODEC_ID_H264: return kCMVideoCodecType_H264;
        case AV_CODEC_ID_HEVC:
            if (parameters->codec_tag == MKTAG('d', 'v', 'h', '1') ||
                parameters->codec_tag == MKTAG('d', 'v', 'h', 'e')) {
                return kCMVideoCodecType_DolbyVisionHEVC;
            }
            return kCMVideoCodecType_HEVC;
        case AV_CODEC_ID_AV1: return kCMVideoCodecType_AV1;
        case AV_CODEC_ID_VP9: return kCMVideoCodecType_VP9;
        case AV_CODEC_ID_MPEG4: return kCMVideoCodecType_MPEG4Video;
        default: return 0;
    }
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
    if (!sideData || sideData->size < sizeof(AVDOVIDecoderConfigurationRecord)) return false;
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
        case AV_CODEC_ID_VP9: return CFSTR("vpcC");
        case AV_CODEC_ID_MPEG4: return CFSTR("esds");
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

static size_t descriptor_length_size(size_t value) {
    (void)value;
    return 4;
}

static void write_be16(uint8_t *destination, uint16_t value);
static void write_be32(uint8_t *destination, uint32_t value);

static uint8_t *write_descriptor_length(uint8_t *destination, size_t value) {
    for (size_t index = 4; index > 0; index--) {
        unsigned shift = (unsigned)((index - 1) * 7);
        *destination++ = (uint8_t)((value >> shift) & 0x7f) | (index > 1 ? 0x80 : 0);
    }
    return destination;
}

static CFDataRef create_mpeg4_esds(const AVCodecParameters *parameters, uint32_t bitRate) {
    size_t configurationSize = (size_t)parameters->extradata_size;
    size_t decoderSpecificSize = 1 + descriptor_length_size(configurationSize) + configurationSize;
    size_t decoderConfigPayloadSize = 13 + decoderSpecificSize;
    size_t decoderConfigSize = 1 + descriptor_length_size(decoderConfigPayloadSize) + decoderConfigPayloadSize;
    size_t slConfigSize = 1 + descriptor_length_size(1) + 1;
    size_t esPayloadSize = 3 + decoderConfigSize + slConfigSize;
    size_t totalSize = 4 + 1 + descriptor_length_size(esPayloadSize) + esPayloadSize;
    uint8_t *bytes = calloc(1, totalSize);
    if (!bytes) return NULL;
    uint8_t *cursor = bytes + 4;
    *cursor++ = 0x03;
    cursor = write_descriptor_length(cursor, esPayloadSize);
    *cursor++ = 0; *cursor++ = 1; *cursor++ = 0;
    *cursor++ = 0x04;
    cursor = write_descriptor_length(cursor, decoderConfigPayloadSize);
    *cursor++ = 0x20;
    *cursor++ = 0x11;
    cursor += 3;
    write_be32(cursor, bitRate); cursor += 4;
    write_be32(cursor, bitRate); cursor += 4;
    *cursor++ = 0x05;
    cursor = write_descriptor_length(cursor, configurationSize);
    memcpy(cursor, parameters->extradata, configurationSize);
    cursor += configurationSize;
    *cursor++ = 0x06;
    cursor = write_descriptor_length(cursor, 1);
    *cursor++ = 0x02;
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)(cursor - bytes));
    free(bytes);
    return data;
}

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

static OSStatus create_mpeg4_format(
    const AVCodecParameters *parameters,
    uint32_t bitRate,
    CMVideoFormatDescriptionRef *formatOut
) {
    CFDataRef esds = create_mpeg4_esds(parameters, bitRate);
    if (!esds) return kCMFormatDescriptionError_AllocationFailed;
    size_t esdsSize = (size_t)CFDataGetLength(esds);
    size_t descriptionSize = 86 + 8 + esdsSize + 20 + 16 + 4;
    uint8_t *description = calloc(1, descriptionSize);
    if (!description) {
        CFRelease(esds);
        return kCMFormatDescriptionError_AllocationFailed;
    }
    write_be32(description, (uint32_t)descriptionSize);
    memcpy(description + 4, "mp4v", 4);
    write_be16(description + 14, UINT16_MAX);
    write_be16(description + 32, (uint16_t)parameters->width);
    write_be16(description + 34, (uint16_t)parameters->height);
    write_be32(description + 36, 72 << 16);
    write_be32(description + 40, 72 << 16);
    write_be16(description + 48, 1);
    description[50] = 6;
    memcpy(description + 51, "'mp4v'", 6);
    write_be16(description + 82, 24);
    write_be16(description + 84, UINT16_MAX);
    write_be32(description + 86, (uint32_t)(8 + esdsSize));
    memcpy(description + 90, "esds", 4);
    memcpy(description + 94, CFDataGetBytePtr(esds), esdsSize);
    size_t atomOffset = 94 + esdsSize;
    write_be32(description + atomOffset, 20);
    memcpy(description + atomOffset + 4, "btrt", 4);
    write_be32(description + atomOffset + 12, bitRate);
    write_be32(description + atomOffset + 16, bitRate);
    atomOffset += 20;
    write_be32(description + atomOffset, 16);
    memcpy(description + atomOffset + 4, "pasp", 4);
    write_be32(description + atomOffset + 8, 1);
    write_be32(description + atomOffset + 12, 1);
    OSStatus status = CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData(
        kCFAllocatorDefault,
        description,
        descriptionSize,
        CFStringGetSystemEncoding(),
        NULL,
        formatOut
    );
    free(description);
    CFRelease(esds);
    return status;
}

static CFStringRef color_primaries(enum AVColorPrimaries value) {
    switch (value) {
        case AVCOL_PRI_BT709: return kCMFormatDescriptionColorPrimaries_ITU_R_709_2;
        case AVCOL_PRI_BT2020: return kCMFormatDescriptionColorPrimaries_ITU_R_2020;
        case AVCOL_PRI_SMPTE432: return kCMFormatDescriptionColorPrimaries_P3_D65;
        default: return NULL;
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
        switch (mapping->projection) {
            case AV_SPHERICAL_RECTILINEAR:
                projection = kCMFormatDescriptionProjectionKind_Rectilinear;
                break;
            case AV_SPHERICAL_EQUIRECTANGULAR:
                projection = kCMFormatDescriptionProjectionKind_Equirectangular;
                break;
            case AV_SPHERICAL_HALF_EQUIRECTANGULAR:
                projection = kCMFormatDescriptionProjectionKind_HalfEquirectangular;
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
    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
        kCFAllocatorDefault, required, sets, sizes, 4, formatOut
    );
}

static OSStatus create_compressed_format(
    const AVCodecParameters *parameters,
    uint32_t bitRate,
    CMVideoFormatDescriptionRef *formatOut,
    bool *convertsAnnexBOut
) {
    OSType type = codec_type(parameters);
    CFStringRef atom = atom_name(parameters);
    if (type == 0 || atom == NULL || parameters->extradata == NULL || parameters->extradata_size <= 0) {
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
    }
    add_projected_media_extensions(parameters, extensions);
    add_dovi_configuration_atom(parameters, atoms);

    bool annexB = (parameters->codec_id == AV_CODEC_ID_HEVC || parameters->codec_id == AV_CODEC_ID_H264)
        && parameters->extradata[0] != 1;
    OSStatus status;
    if (parameters->codec_id == AV_CODEC_ID_MPEG4) {
        status = create_mpeg4_format(parameters, bitRate, formatOut);
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
        status = CMVideoFormatDescriptionCreate(
            kCFAllocatorDefault, type, parameters->width, parameters->height, extensions, formatOut
        );
        CFRelease(configuration);
    }
    if (convertsAnnexBOut) *convertsAnnexBOut = annexB;
    CFRelease(atoms);
    CFRelease(extensions);
    return status;
}

static uint32_t estimate_video_bitrate(
    AVFormatContext *formatContext,
    int streamIndex,
    AVRational timeBase,
    int64_t declaredBitRate
) {
    if (declaredBitRate > 0 && declaredBitRate <= UINT32_MAX) return (uint32_t)declaredBitRate;
    AVPacket *packet = av_packet_alloc();
    if (!packet) return 0;
    int64_t firstTimestamp = AV_NOPTS_VALUE;
    int64_t lastTimestamp = AV_NOPTS_VALUE;
    uint64_t totalBytes = 0;
    int videoPacketCount = 0;
    while (videoPacketCount < 240 && av_read_frame(formatContext, packet) >= 0) {
        if (packet->stream_index == streamIndex) {
            int64_t timestamp = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;
            if (timestamp != AV_NOPTS_VALUE) {
                if (firstTimestamp == AV_NOPTS_VALUE) firstTimestamp = timestamp;
                lastTimestamp = timestamp + (packet->duration > 0 ? packet->duration : 0);
            }
            if (packet->size > 0) totalBytes += (uint64_t)packet->size;
            videoPacketCount++;
        }
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    av_seek_frame(formatContext, streamIndex, 0, AVSEEK_FLAG_BACKWARD);
    avformat_flush(formatContext);
    if (firstTimestamp == AV_NOPTS_VALUE || lastTimestamp <= firstTimestamp || totalBytes == 0) return 0;
    double seconds = (double)(lastTimestamp - firstTimestamp) * av_q2d(timeBase);
    double bitsPerSecond = (double)totalBytes * 8.0 / seconds;
    if (!isfinite(bitsPerSecond) || bitsPerSecond <= 0 || bitsPerSecond > UINT32_MAX) return 0;
    return (uint32_t)llround(bitsPerSecond);
}

PBFFmpegReader *PBFFmpegReaderCreate(
    const char *path,
    PBFFmpegMode mode,
    double startSeconds,
    char *errorBuffer,
    size_t errorBufferSize
) {
    PBFFmpegReader *reader = calloc(1, sizeof(PBFFmpegReader));
    if (reader == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg reader");
        return NULL;
    }
    reader->mode = mode;
    reader->videoStreamIndex = -1;

    int result = avformat_open_input(&reader->formatContext, path, NULL, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Open media source", result);
        PBFFmpegReaderDestroy(reader);
        return NULL;
    }
    result = avformat_find_stream_info(reader->formatContext, NULL);
    if (result < 0) {
        set_av_error(errorBuffer, errorBufferSize, "Read stream information", result);
        PBFFmpegReaderDestroy(reader);
        return NULL;
    }
    reader->videoStreamIndex = av_find_best_stream(
        reader->formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0
    );
    if (reader->videoStreamIndex < 0) {
        set_error(errorBuffer, errorBufferSize, "The selected source has no video stream");
        PBFFmpegReaderDestroy(reader);
        return NULL;
    }

    AVStream *stream = reader->formatContext->streams[reader->videoStreamIndex];
    reader->timeBase = stream->time_base;
    reader->startTimestamp = stream_start_timestamp(reader->formatContext, stream);
    reader->durationSeconds = reader->formatContext->duration > 0
        ? (double)reader->formatContext->duration / AV_TIME_BASE
        : 0;
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
        uint32_t bitRate = stream->codecpar->codec_id == AV_CODEC_ID_MPEG4
            ? estimate_video_bitrate(
                reader->formatContext,
                reader->videoStreamIndex,
                reader->timeBase,
                stream->codecpar->bit_rate
            )
            : 0;
        OSStatus status = create_compressed_format(
            stream->codecpar, bitRate, &reader->compressedFormat, &reader->convertsAnnexB
        );
        if (status != noErr) {
            char message[128];
            snprintf(message, sizeof(message), "Create compressed CMVideoFormatDescription failed (%d)", (int)status);
            set_error(errorBuffer, errorBufferSize, message);
            PBFFmpegReaderDestroy(reader);
            return NULL;
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
        PBFFmpegReaderDestroy(reader);
        return NULL;
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
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Seek media source", result);
            PBFFmpegReaderDestroy(reader);
            return NULL;
        }
    }
    return reader;
}

void PBFFmpegReaderDestroy(PBFFmpegReader *reader) {
    if (reader == NULL) return;
    if (reader->compressedFormat) CFRelease(reader->compressedFormat);
    av_packet_free(&reader->packet);
    avformat_close_input(&reader->formatContext);
    free(reader);
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
    while (av_read_frame(reader->formatContext, packet) >= 0) {
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
        if (status == noErr && !(packet->flags & AV_PKT_FLAG_KEY)) {
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(*sampleOut, true);
            if (attachments && CFArrayGetCount(attachments) > 0) {
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
    return PBFFmpegReadResultEnd;
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

PBFFmpegAudioReader *PBFFmpegAudioReaderCreate(
    const char *path,
    double startSeconds,
    int preferredStreamIndex,
    char *errorBuffer,
    size_t errorBufferSize
) {
    PBFFmpegAudioReader *reader = calloc(1, sizeof(PBFFmpegAudioReader));
    if (reader == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio reader");
        return NULL;
    }
    reader->audioStreamIndex = -1;

    int result = open_media_source_for_audio(
        path,
        &reader->formatContext,
        errorBuffer,
        errorBufferSize
    );
    if (result < 0) {
        PBFFmpegAudioReaderDestroy(reader);
        return NULL;
    }

    if (preferredStreamIndex >= 0) {
        if (preferredStreamIndex < (int)reader->formatContext->nb_streams &&
            audio_stream_is_supported(reader->formatContext->streams[preferredStreamIndex])) {
            reader->audioStreamIndex = preferredStreamIndex;
        } else {
            set_error(errorBuffer, errorBufferSize, "The selected audio stream cannot be demuxed as a supported compressed format");
            PBFFmpegAudioReaderDestroy(reader);
            return NULL;
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
        PBFFmpegAudioReaderDestroy(reader);
        return NULL;
    }

    AVStream *stream = reader->formatContext->streams[reader->audioStreamIndex];
    reader->sampleRate = stream->codecpar->sample_rate;
    reader->channelCount = stream->codecpar->ch_layout.nb_channels;
    if (reader->sampleRate <= 0 || reader->channelCount <= 0) {
        set_error(errorBuffer, errorBufferSize, "Audio stream has invalid sample rate or channel layout");
        PBFFmpegAudioReaderDestroy(reader);
        return NULL;
    }
    reader->packet = av_packet_alloc();
    reader->filteredPacket = av_packet_alloc();
    reader->timeBase = stream->time_base;
    reader->startTimestamp = stream_start_timestamp(reader->formatContext, stream);
    snprintf(reader->codecName, sizeof(reader->codecName), "%s", avcodec_get_name(stream->codecpar->codec_id));
    if (reader->packet == NULL || reader->filteredPacket == NULL) {
        set_error(errorBuffer, errorBufferSize, "Unable to allocate FFmpeg audio packet");
        PBFFmpegAudioReaderDestroy(reader);
        return NULL;
    }

    if (stream->codecpar->codec_id == AV_CODEC_ID_AAC) {
        const AVBitStreamFilter *filter = av_bsf_get_by_name("aac_adtstoasc");
        if (filter == NULL || av_bsf_alloc(filter, &reader->bitstreamFilter) < 0) {
            set_error(errorBuffer, errorBufferSize, "Unable to create AAC compressed-audio filter");
            PBFFmpegAudioReaderDestroy(reader);
            return NULL;
        }
        result = avcodec_parameters_copy(reader->bitstreamFilter->par_in, stream->codecpar);
        if (result >= 0) {
            reader->bitstreamFilter->time_base_in = stream->time_base;
            result = av_bsf_init(reader->bitstreamFilter);
        }
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Initialize AAC compressed-audio filter", result);
            PBFFmpegAudioReaderDestroy(reader);
            return NULL;
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
        if (result < 0) {
            set_av_error(errorBuffer, errorBufferSize, "Seek audio media source", result);
            PBFFmpegAudioReaderDestroy(reader);
            return NULL;
        }
        if (reader->bitstreamFilter) av_bsf_flush(reader->bitstreamFilter);
    }
    return reader;
}

void PBFFmpegAudioReaderDestroy(PBFFmpegAudioReader *reader) {
    if (reader == NULL) return;
    if (reader->formatDescription) CFRelease(reader->formatDescription);
    av_bsf_free(&reader->bitstreamFilter);
    av_packet_free(&reader->filteredPacket);
    av_packet_free(&reader->packet);
    avformat_close_input(&reader->formatContext);
    free(reader);
}

static UInt32 audio_frames_per_packet(const AVCodecParameters *parameters) {
    if (parameters->frame_size > 0) return (UInt32)parameters->frame_size;
    switch (parameters->codec_id) {
        case AV_CODEC_ID_AAC: return 1024;
        case AV_CODEC_ID_AC3:
        case AV_CODEC_ID_EAC3: return 1536;
        case AV_CODEC_ID_MP2:
        case AV_CODEC_ID_MP3: return 1152;
        case AV_CODEC_ID_OPUS: return 960;
        default: return 0;
    }
}

static AudioFormatFlags audio_format_flags(const AVCodecParameters *parameters) {
    if (parameters->codec_id != AV_CODEC_ID_ALAC) return 0;
    switch (parameters->bits_per_raw_sample) {
        case 20: return kAppleLosslessFormatFlag_20BitSourceData;
        case 24: return kAppleLosslessFormatFlag_24BitSourceData;
        case 32: return kAppleLosslessFormatFlag_32BitSourceData;
        default: return kAppleLosslessFormatFlag_16BitSourceData;
    }
}

static int aac_sample_rate_index(int sampleRate) {
    for (int index = 0; index < 13; index++) {
        if (aac_sample_rates[index] == sampleRate) return index;
    }
    return -1;
}

static int ensure_compressed_audio_format(
    PBFFmpegAudioReader *reader,
    const AVCodecParameters *parameters,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader->formatDescription) return 0;
    AudioFormatID formatID = audio_format_id(parameters->codec_id);
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
    uint8_t synthesizedAACCookie[2] = {0};
    const void *cookie = parameters->extradata_size > 0 ? parameters->extradata : NULL;
    size_t cookieSize = parameters->extradata_size > 0
        ? (size_t)parameters->extradata_size
        : 0;
    if (parameters->codec_id == AV_CODEC_ID_AAC && cookieSize == 0) {
        int sampleRateIndex = aac_sample_rate_index(parameters->sample_rate);
        int channelConfiguration = parameters->ch_layout.nb_channels;
        int profile = parameters->profile == AV_PROFILE_UNKNOWN
            ? AV_PROFILE_AAC_LOW
            : parameters->profile;
        if (sampleRateIndex < 0 || channelConfiguration < 1 || channelConfiguration > 7 ||
            profile < AV_PROFILE_AAC_MAIN || profile > AV_PROFILE_AAC_LTP) {
            set_error(errorBuffer, errorBufferSize, "Compressed AAC codec configuration is unavailable");
            return AVERROR_INVALIDDATA;
        }
        int audioObjectType = profile + 1;
        synthesizedAACCookie[0] = (uint8_t)((audioObjectType << 3) | (sampleRateIndex >> 1));
        synthesizedAACCookie[1] = (uint8_t)(((sampleRateIndex & 1) << 7) | (channelConfiguration << 3));
        cookie = synthesizedAACCookie;
        cookieSize = sizeof(synthesizedAACCookie);
    }
    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault,
        &asbd,
        0,
        NULL,
        cookieSize,
        cookie,
        NULL,
        &reader->formatDescription
    );
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

static PBFFmpegReadResult create_audio_sample(
    PBFFmpegAudioReader *reader,
    AVPacket *packet,
    const AVCodecParameters *parameters,
    CMSampleBufferRef *sampleOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    int formatResult = ensure_compressed_audio_format(
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
    UInt32 framesPerPacket = audio_frames_per_packet(parameters);
    CMTime duration = framesPerPacket > 0 && parameters->sample_rate > 0
        ? CMTimeMake(framesPerPacket, parameters->sample_rate)
        : cm_time(packet->duration, reader->timeBase);
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
            1,
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
        snprintf(message, sizeof(message), "Create compressed audio CMSampleBuffer failed (%d)", (int)status);
        set_error(errorBuffer, errorBufferSize, message);
        return PBFFmpegReadResultError;
    }
    return PBFFmpegReadResultSample;
}

PBFFmpegReadResult PBFFmpegAudioReaderCopyNextSample(
    PBFFmpegAudioReader *reader,
    CMSampleBufferRef *sampleOut,
    char *errorBuffer,
    size_t errorBufferSize
) {
    if (reader == NULL || sampleOut == NULL) {
        set_error(errorBuffer, errorBufferSize, "Invalid FFmpeg audio reader call");
        return PBFFmpegReadResultError;
    }
    *sampleOut = NULL;
    AVStream *stream = reader->formatContext->streams[reader->audioStreamIndex];
    while (true) {
        if (reader->bitstreamFilter) {
            int result = av_bsf_receive_packet(reader->bitstreamFilter, reader->filteredPacket);
            if (result == 0) {
                PBFFmpegReadResult readResult = create_audio_sample(
                    reader,
                    reader->filteredPacket,
                    reader->bitstreamFilter->par_out,
                    sampleOut,
                    errorBuffer,
                    errorBufferSize
                );
                av_packet_unref(reader->filteredPacket);
                return readResult;
            }
            if (result == AVERROR_EOF) return PBFFmpegReadResultEnd;
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
        if (result < 0) {
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
                sampleOut,
                errorBuffer,
                errorBufferSize
            );
            av_packet_unref(reader->packet);
            return readResult;
        }
        result = av_bsf_send_packet(reader->bitstreamFilter, reader->packet);
        av_packet_unref(reader->packet);
        if (result < 0) {
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

int PBFFmpegAudioTrackCount(const char *path) {
    AVFormatContext *context = NULL;
    if (!path || open_media_source_for_audio(path, &context, NULL, 0) < 0) return -1;
    int count = 0;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        if (audio_stream_is_supported(context->streams[index])) count++;
    }
    avformat_close_input(&context);
    return count;
}

bool PBFFmpegAudioTrackCopyInfo(
    const char *path,
    int ordinal,
    int *streamIndexOut,
    int *sampleRateOut,
    int *channelCountOut,
    char *codecBuffer,
    size_t codecBufferSize,
    char *languageBuffer,
    size_t languageBufferSize,
    char *titleBuffer,
    size_t titleBufferSize
) {
    AVFormatContext *context = NULL;
    if (!path || ordinal < 0 ||
        open_media_source_for_audio(path, &context, NULL, 0) < 0) return false;
    AVStream *selected = NULL;
    int current = 0;
    for (unsigned int index = 0; index < context->nb_streams; index++) {
        AVStream *stream = context->streams[index];
        if (!audio_stream_is_supported(stream)) continue;
        if (current++ == ordinal) { selected = stream; break; }
    }
    if (!selected) { avformat_close_input(&context); return false; }
    if (streamIndexOut) *streamIndexOut = selected->index;
    if (sampleRateOut) *sampleRateOut = selected->codecpar->sample_rate;
    if (channelCountOut) *channelCountOut = selected->codecpar->ch_layout.nb_channels;
    const AVCodecDescriptor *descriptor = avcodec_descriptor_get(selected->codecpar->codec_id);
    snprintf(codecBuffer, codecBufferSize, "%s", descriptor ? descriptor->name : "unknown");
    AVDictionaryEntry *language = av_dict_get(selected->metadata, "language", NULL, 0);
    AVDictionaryEntry *title = av_dict_get(selected->metadata, "title", NULL, 0);
    snprintf(languageBuffer, languageBufferSize, "%s", language ? language->value : "");
    snprintf(titleBuffer, titleBufferSize, "%s", title ? title->value : "");
    avformat_close_input(&context);
    return true;
}
