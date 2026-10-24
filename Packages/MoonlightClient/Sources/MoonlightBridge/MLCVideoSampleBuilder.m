
#import "MLCVideoSampleBuilder.h"
#import "MLCLogger.h"

#include <simd/simd.h>

#if MLC_ENABLE_AV1
#include <libavcodec/avcodec.h>
#include <libavcodec/cbs.h>
#include <libavcodec/cbs_av1.h>
#include <libavformat/avio.h>
#include <libavutil/mem.h>

extern int ff_isom_write_av1c(AVIOContext *pb, const uint8_t *buf, int size,
                              int write_seq_header);
#endif

#define NALU_START_PREFIX_SIZE 3
#define NAL_LENGTH_PREFIX_SIZE 4

@interface MLCFrameCompletion : NSObject
@property (nonatomic, assign) void* frameHandle;
@end

@implementation MLCFrameCompletion
- (void)dealloc {
    LiCompleteVideoFrame(_frameHandle, DR_OK);
}
@end

@implementation MLCVideoSampleBuilder {
    int videoFormat;

    NSMutableArray* parameterSetBuffers;
    NSData* masteringDisplayColorVolume;
    NSData* contentLightLevelInfo;
    BOOL hdrModeEnabled;
    CMVideoFormatDescriptionRef formatDesc;
}

- (instancetype)init {
    self = [super init];

    parameterSetBuffers = [[NSMutableArray alloc] init];

    return self;
}

+ (BOOL)isAV1PlaybackSupported {
#if MLC_ENABLE_AV1
    return YES;
#else
    return NO;
#endif
}

- (void)dealloc {
    if (formatDesc != nil) {
        CFRelease(formatDesc);
    }
}

- (void)setupWithVideoFormat:(int)videoFormat {
    self->videoFormat = videoFormat;
}

- (void)invalidateFormatDescription {
    if (formatDesc != nil) {
        CFRelease(formatDesc);
        formatDesc = nil;
    }

    [parameterSetBuffers removeAllObjects];
}

- (void)updateAnnexBBufferForRange:(CMBlockBufferRef)frameBuffer dataBlock:(CMBlockBufferRef)dataBuffer offset:(int)offset length:(int)nalLength {
    OSStatus status;
    size_t oldOffset = CMBlockBufferGetDataLength(frameBuffer);

    status = CMBlockBufferAppendMemoryBlock(frameBuffer, NULL,
                                            NAL_LENGTH_PREFIX_SIZE,
                                            kCFAllocatorDefault, NULL, 0,
                                            NAL_LENGTH_PREFIX_SIZE, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendMemoryBlock failed: %d", (int)status);
        return;
    }

    const int dataLength = nalLength - NALU_START_PREFIX_SIZE;
    const uint8_t lengthBytes[] = {(uint8_t)(dataLength >> 24), (uint8_t)(dataLength >> 16),
        (uint8_t)(dataLength >> 8), (uint8_t)dataLength};
    status = CMBlockBufferReplaceDataBytes(lengthBytes, frameBuffer,
                                           oldOffset, NAL_LENGTH_PREFIX_SIZE);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferReplaceDataBytes failed: %d", (int)status);
        return;
    }

    status = CMBlockBufferAppendBufferReference(frameBuffer, dataBuffer, offset + NALU_START_PREFIX_SIZE, dataLength, 0);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
        return;
    }
}

#if MLC_ENABLE_AV1
- (NSData*)getAv1CodecConfigurationBox:(NSData*)frameData {
    AVIOContext* ioctx = NULL;
    int err;

    err = avio_open_dyn_buf(&ioctx);
    if (err < 0) {
        Log(LOG_E, @"avio_open_dyn_buf() failed: %d", err);
        return nil;
    }

    err = ff_isom_write_av1c(ioctx, (uint8_t*)frameData.bytes, (int)frameData.length, 1);
    if (err < 0) {
        Log(LOG_E, @"ff_isom_write_av1c() failed: %d", err);
    }

    uint8_t* av1cBuf = NULL;
    int av1cBufLen = avio_close_dyn_buf(ioctx, &av1cBuf);

    Log(LOG_I, @"av1C block is %d bytes", av1cBufLen);

    NSData* data = nil;
    if (err >= 0 && av1cBufLen > 0) {
        data = [NSData dataWithBytes:av1cBuf length:av1cBufLen];
    }

    av_free(av1cBuf);
    return data;
}

- (CMVideoFormatDescriptionRef)createAV1FormatDescriptionForIDRFrame:(NSData*)frameData {
    NSMutableDictionary* extensions = [[NSMutableDictionary alloc] init];

    CodedBitstreamContext* cbsCtx = NULL;
    int err = ff_cbs_init(&cbsCtx, AV_CODEC_ID_AV1, NULL);
    if (err < 0) {
        Log(LOG_E, @"ff_cbs_init() failed: %d", err);
        return nil;
    }

    AVPacket avPacket = {};
    avPacket.data = (uint8_t*)frameData.bytes;
    avPacket.size = (int)frameData.length;

    CodedBitstreamFragment cbsFrag = {};
    err = ff_cbs_read_packet(cbsCtx, &cbsFrag, &avPacket);
    if (err < 0) {
        Log(LOG_E, @"ff_cbs_read_packet() failed: %d", err);
        ff_cbs_close(&cbsCtx);
        return nil;
    }

#define SET_CFSTR_EXTENSION(key, value) extensions[(__bridge NSString*)key] = (__bridge NSString*)(value)
#define SET_EXTENSION(key, value) extensions[(__bridge NSString*)key] = (value)

    SET_EXTENSION(kCMFormatDescriptionExtension_FormatName, @"av01");

    SET_EXTENSION(kCMFormatDescriptionExtension_Depth, @24);

    CodedBitstreamAV1Context* bitstreamCtx = (CodedBitstreamAV1Context*)cbsCtx->priv_data;
    AV1RawSequenceHeader* seqHeader = bitstreamCtx->sequence_header;
    if (seqHeader == NULL) {
        Log(LOG_E, @"AV1 sequence header not found in IDR frame!");
        ff_cbs_fragment_free(&cbsFrag);
        ff_cbs_close(&cbsCtx);
        return nil;
    }

    switch (seqHeader->color_config.color_primaries) {
        case 1:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_ITU_R_709_2);
            break;

        case 6:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_SMPTE_C);
            break;

        case 9:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ColorPrimaries,
                                kCMFormatDescriptionColorPrimaries_ITU_R_2020);
            break;

        default:
            Log(LOG_W, @"Unsupported color_primaries value: %d", seqHeader->color_config.color_primaries);
            break;
    }

    switch (seqHeader->color_config.transfer_characteristics) {
        case 1:
        case 6:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_709_2);
            break;

        case 7:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_SMPTE_240M_1995);
            break;

        case 8:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_Linear);
            break;

        case 14:
        case 15:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_2020);
            break;

        case 16:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ);
            break;

        case 17:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_TransferFunction,
                                kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG);
            break;

        default:
            Log(LOG_W, @"Unsupported transfer_characteristics value: %d", seqHeader->color_config.transfer_characteristics);
            break;
    }

    switch (seqHeader->color_config.matrix_coefficients) {
        case 1:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2);
            break;

        case 6:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4);
            break;

        case 7:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995);
            break;

        case 9:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_YCbCrMatrix,
                                kCMFormatDescriptionYCbCrMatrix_ITU_R_2020);
            break;

        default:
            Log(LOG_W, @"Unsupported matrix_coefficients value: %d", seqHeader->color_config.matrix_coefficients);
            break;
    }

    SET_EXTENSION(kCMFormatDescriptionExtension_FullRangeVideo, @(seqHeader->color_config.color_range == 1));

    SET_EXTENSION(kCMFormatDescriptionExtension_FieldCount, @(1));

    switch (seqHeader->color_config.chroma_sample_position) {
        case 1:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ChromaLocationTopField,
                                kCMFormatDescriptionChromaLocation_Left);
            break;

        case 2:
            SET_CFSTR_EXTENSION(kCMFormatDescriptionExtension_ChromaLocationTopField,
                                kCMFormatDescriptionChromaLocation_TopLeft);
            break;

        default:
            Log(LOG_W, @"Unsupported chroma_sample_position value: %d", seqHeader->color_config.chroma_sample_position);
            break;
    }

    if (contentLightLevelInfo) {
        SET_EXTENSION(kCMFormatDescriptionExtension_ContentLightLevelInfo, contentLightLevelInfo);
    }

    if (masteringDisplayColorVolume) {
        SET_EXTENSION(kCMFormatDescriptionExtension_MasteringDisplayColorVolume, masteringDisplayColorVolume);
    }

    extensions[(__bridge NSString*)kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] =
    @{
        @"av1C" : [self getAv1CodecConfigurationBox:frameData],
    };
    extensions[@"BitsPerComponent"] = @(bitstreamCtx->bit_depth);

#undef SET_EXTENSION
#undef SET_CFSTR_EXTENSION

    CMVideoFormatDescriptionRef newFormatDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCMVideoCodecType_AV1,
                                                     bitstreamCtx->frame_width, bitstreamCtx->frame_height,
                                                     (__bridge CFDictionaryRef)extensions,
                                                     &newFormatDesc);
    if (status != noErr) {
        Log(LOG_E, @"Failed to create AV1 format description: %d", (int)status);
        newFormatDesc = NULL;
    }

    ff_cbs_fragment_free(&cbsFrag);
    ff_cbs_close(&cbsCtx);
    return newFormatDesc;
}
#endif

- (int)submitDecodeBuffer:(unsigned char*)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du {
    OSStatus status;

    if (du->frameType == FRAME_TYPE_IDR) {
        if (bufferType != BUFFER_TYPE_PICDATA) {
            if (bufferType == BUFFER_TYPE_VPS || bufferType == BUFFER_TYPE_SPS || bufferType == BUFFER_TYPE_PPS) {
                int startLen = data[2] == 0x01 ? 3 : 4;
                [parameterSetBuffers addObject:[NSData dataWithBytes:&data[startLen] length:length - startLen]];
            }


            return DR_OK;
        }


        if (formatDesc != NULL) {
            CFRelease(formatDesc);
            formatDesc = NULL;
        }

        if (videoFormat & VIDEO_FORMAT_MASK_H264) {
            size_t parameterSetCount = [parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }

            Log(LOG_I, @"Constructing new H264 format description");
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         &formatDesc);
            if (status != noErr) {
                Log(LOG_E, @"Failed to create H264 format description: %d", (int)status);
                formatDesc = NULL;
            }

            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_H265) {
            size_t parameterSetCount = [parameterSetBuffers count];
            const uint8_t* parameterSetPointers[parameterSetCount];
            size_t parameterSetSizes[parameterSetCount];
            for (int i = 0; i < parameterSetCount; i++) {
                NSData* parameterSet = parameterSetBuffers[i];
                parameterSetPointers[i] = parameterSet.bytes;
                parameterSetSizes[i] = parameterSet.length;
            }

            Log(LOG_I, @"Constructing new HEVC format description");

            NSMutableDictionary* videoFormatParams = [[NSMutableDictionary alloc] init];

            if (hdrModeEnabled) {
                [videoFormatParams setObject:(__bridge NSString*)kCMFormatDescriptionColorPrimaries_ITU_R_2020
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_ColorPrimaries];
                [videoFormatParams setObject:(__bridge NSString*)kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_TransferFunction];
                [videoFormatParams setObject:(__bridge NSString*)kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_YCbCrMatrix];
                [videoFormatParams setObject:@NO
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_FullRangeVideo];
                [videoFormatParams setObject:@(1)
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_FieldCount];
                [videoFormatParams setObject:@(10) forKey:@"BitsPerComponent"];
            }

            if (contentLightLevelInfo) {
                [videoFormatParams setObject:contentLightLevelInfo forKey:(__bridge NSString*)kCMFormatDescriptionExtension_ContentLightLevelInfo];
            }

            if (masteringDisplayColorVolume) {
                [videoFormatParams setObject:masteringDisplayColorVolume forKey:(__bridge NSString*)kCMFormatDescriptionExtension_MasteringDisplayColorVolume];
            }

            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                         parameterSetCount,
                                                                         parameterSetPointers,
                                                                         parameterSetSizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         (__bridge CFDictionaryRef)videoFormatParams,
                                                                         &formatDesc);

            if (status != noErr) {
                Log(LOG_E, @"Failed to create HEVC format description: %d", (int)status);
                formatDesc = NULL;
            }

            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_AV1) {
#if MLC_ENABLE_AV1
            NSData* fullFrameData = [NSData dataWithBytesNoCopy:data length:length freeWhenDone:NO];

            Log(LOG_I, @"Constructing new AV1 format description");
            formatDesc = [self createAV1FormatDescriptionForIDRFrame:fullFrameData];
            [parameterSetBuffers removeAllObjects];
#else
            Log(LOG_E, @"AV1 format description construction is not compiled in");
#endif
        }
        else {
            abort();
        }
    }

    if (formatDesc == NULL) {
        free(data);
        return DR_NEED_IDR;
    }

    CMBlockBufferRef frameBlockBuffer;
    CMBlockBufferRef dataBlockBuffer;

    status = CMBlockBufferCreateWithMemoryBlock(NULL, data, length, kCFAllocatorDefault, NULL, 0, length, 0, &dataBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        free(data);
        return DR_NEED_IDR;
    }


    status = CMBlockBufferCreateEmpty(NULL, 0, 0, &frameBlockBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMBlockBufferCreateEmpty failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        return DR_NEED_IDR;
    }

    if (videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265)) {
        int lastOffset = -1;
        for (int i = 0; i < length - NALU_START_PREFIX_SIZE; i++) {
            if (data[i] == 0 && data[i+1] == 0 && data[i+2] == 1) {
                if (lastOffset != -1) {
                    [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:i - lastOffset];
                }

                lastOffset = i;
            }
        }

        if (lastOffset != -1) {
            [self updateAnnexBBufferForRange:frameBlockBuffer dataBlock:dataBlockBuffer offset:lastOffset length:length - lastOffset];
        }
    }
    else {
        status = CMBlockBufferAppendBufferReference(frameBlockBuffer, dataBlockBuffer, 0, length, 0);
        if (status != noErr) {
            Log(LOG_E, @"CMBlockBufferAppendBufferReference failed: %d", (int)status);
            return DR_NEED_IDR;
        }
    }

    CMSampleBufferRef sampleBuffer;

    CMSampleTimingInfo sampleTiming = {kCMTimeInvalid, CMTimeMake(du->presentationTimeUs, 1000000), kCMTimeInvalid};

    status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                  frameBlockBuffer,
                                  formatDesc, 1, 1,
                                  &sampleTiming, 0, NULL,
                                  &sampleBuffer);
    if (status != noErr) {
        Log(LOG_E, @"CMSampleBufferCreate failed: %d", (int)status);
        CFRelease(dataBlockBuffer);
        CFRelease(frameBlockBuffer);
        return DR_NEED_IDR;
    }

    [self.delegate videoSampleBuilder:self
                     didProduceSample:sampleBuffer
                            frameType:du->frameType
                    presentationTimeUs:du->presentationTimeUs];

    CFRelease(dataBlockBuffer);
    CFRelease(frameBlockBuffer);
    CFRelease(sampleBuffer);

    return DR_OK;
}

- (void)setHdrMode:(BOOL)enabled {
    SS_HDR_METADATA hdrMetadata;

    BOOL hasMetadata = enabled && LiGetHdrMetadata(&hdrMetadata);
    BOOL metadataChanged = NO;

    if (hdrModeEnabled != enabled) {
        hdrModeEnabled = enabled;
        metadataChanged = YES;
    }

    if (hasMetadata && hdrMetadata.displayPrimaries[0].x != 0 && hdrMetadata.maxDisplayLuminance != 0) {
        struct {
          vector_ushort2 primaries[3];
          vector_ushort2 white_point;
          uint32_t luminance_max;
          uint32_t luminance_min;
        } __attribute__((packed, aligned(4))) mdcv;

        mdcv.primaries[0].x = __builtin_bswap16(hdrMetadata.displayPrimaries[1].x);
        mdcv.primaries[0].y = __builtin_bswap16(hdrMetadata.displayPrimaries[1].y);
        mdcv.primaries[1].x = __builtin_bswap16(hdrMetadata.displayPrimaries[2].x);
        mdcv.primaries[1].y = __builtin_bswap16(hdrMetadata.displayPrimaries[2].y);
        mdcv.primaries[2].x = __builtin_bswap16(hdrMetadata.displayPrimaries[0].x);
        mdcv.primaries[2].y = __builtin_bswap16(hdrMetadata.displayPrimaries[0].y);

        mdcv.white_point.x = __builtin_bswap16(hdrMetadata.whitePoint.x);
        mdcv.white_point.y = __builtin_bswap16(hdrMetadata.whitePoint.y);

        mdcv.luminance_max = __builtin_bswap32((uint32_t)hdrMetadata.maxDisplayLuminance * 10000);
        mdcv.luminance_min = __builtin_bswap32(hdrMetadata.minDisplayLuminance);

        NSData* newMdcv = [NSData dataWithBytes:&mdcv length:sizeof(mdcv)];
        if (masteringDisplayColorVolume == nil || ![newMdcv isEqualToData:masteringDisplayColorVolume]) {
            masteringDisplayColorVolume = newMdcv;
            metadataChanged = YES;
        }
    }
    else if (masteringDisplayColorVolume != nil) {
        masteringDisplayColorVolume = nil;
        metadataChanged = YES;
    }

    if (hasMetadata && hdrMetadata.maxContentLightLevel != 0 && hdrMetadata.maxFrameAverageLightLevel != 0) {
        struct {
            uint16_t max_content_light_level;
            uint16_t max_frame_average_light_level;
        } __attribute__((packed, aligned(2))) cll;

        cll.max_content_light_level = __builtin_bswap16(hdrMetadata.maxContentLightLevel);
        cll.max_frame_average_light_level = __builtin_bswap16(hdrMetadata.maxFrameAverageLightLevel);

        NSData* newCll = [NSData dataWithBytes:&cll length:sizeof(cll)];
        if (contentLightLevelInfo == nil || ![newCll isEqualToData:contentLightLevelInfo]) {
            contentLightLevelInfo = newCll;
            metadataChanged = YES;
        }
    }
    else if (contentLightLevelInfo != nil) {
        contentLightLevelInfo = nil;
        metadataChanged = YES;
    }

    if (metadataChanged) {
        LiRequestIdrFrame();
    }
}


- (void)appendZeroCopyNAL:(const uint8_t*)nal length:(int)length to:(CMBlockBufferRef)frameBlockBuffer {
    OSStatus status;
    const int prefixLength = NAL_LENGTH_PREFIX_SIZE;

    size_t oldOffset = CMBlockBufferGetDataLength(frameBlockBuffer);
    status = CMBlockBufferAppendMemoryBlock(frameBlockBuffer, NULL, prefixLength,
                                            kCFAllocatorDefault, NULL, 0, prefixLength, 0);
    if (status != noErr) {
        return;
    }

    const uint8_t prefix[] = {(uint8_t)(length >> 24), (uint8_t)(length >> 16),
                              (uint8_t)(length >> 8), (uint8_t)length};
    CMBlockBufferReplaceDataBytes(prefix, frameBlockBuffer, oldOffset, prefixLength);

    CMBlockBufferRef block = NULL;
    status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorNull, (void*)nal, length,
                                                kCFAllocatorNull, NULL, 0, length, 0, &block);
    if (status != noErr) {
        return;
    }
    CMBlockBufferAppendBufferReference(frameBlockBuffer, block, 0, length, 0);
    CFRelease(block);
}

- (void)appendZeroCopyBlock:(const uint8_t*)bytes length:(int)length to:(CMBlockBufferRef)frameBlockBuffer {
    CMBlockBufferRef block = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorNull, (void*)bytes, length,
                                                         kCFAllocatorNull, NULL, 0, length, 0, &block);
    if (status != noErr) {
        return;
    }
    CMBlockBufferAppendBufferReference(frameBlockBuffer, block, 0, length, 0);
    CFRelease(block);
}

- (CMSampleBufferRef)createZeroCopySampleBufferForPulledUnit:(PDECODE_UNIT)du CF_RETURNS_RETAINED {
    OSStatus status = noErr;

    if (du->frameType == FRAME_TYPE_IDR) {
        for (PLENTRY entry = du->bufferList; entry != NULL; entry = entry->next) {
            if (entry->bufferType == BUFFER_TYPE_PICDATA) {
                continue;
            }
            if (entry->bufferType == BUFFER_TYPE_VPS || entry->bufferType == BUFFER_TYPE_SPS ||
                entry->bufferType == BUFFER_TYPE_PPS) {
                unsigned char* bytes = (unsigned char*)entry->data;
                int startLen = bytes[2] == 0x01 ? 3 : 4;
                if (entry->length > startLen) {
                    [parameterSetBuffers addObject:[NSData dataWithBytes:&bytes[startLen]
                                                                  length:entry->length - startLen]];
                }
            }
        }

        if (formatDesc != NULL) {
            CFRelease(formatDesc);
            formatDesc = NULL;
        }

        if (videoFormat & VIDEO_FORMAT_MASK_H264) {
            size_t count = [parameterSetBuffers count];
            const uint8_t* pointers[count];
            size_t sizes[count];
            for (size_t i = 0; i < count; i++) {
                NSData* set = parameterSetBuffers[i];
                pointers[i] = set.bytes;
                sizes[i] = set.length;
            }
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, count,
                                                                        pointers, sizes,
                                                                        NAL_LENGTH_PREFIX_SIZE, &formatDesc);
            if (status != noErr) {
                formatDesc = NULL;
            }
            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_H265) {
            size_t count = [parameterSetBuffers count];
            const uint8_t* pointers[count];
            size_t sizes[count];
            for (size_t i = 0; i < count; i++) {
                NSData* set = parameterSetBuffers[i];
                pointers[i] = set.bytes;
                sizes[i] = set.length;
            }

            NSMutableDictionary* videoFormatParams = [[NSMutableDictionary alloc] init];
            if (hdrModeEnabled) {
                [videoFormatParams setObject:(__bridge NSString*)kCMFormatDescriptionColorPrimaries_ITU_R_2020
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_ColorPrimaries];
                [videoFormatParams setObject:(__bridge NSString*)kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_TransferFunction];
                [videoFormatParams setObject:(__bridge NSString*)kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_YCbCrMatrix];
                [videoFormatParams setObject:@NO
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_FullRangeVideo];
                [videoFormatParams setObject:@(1)
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_FieldCount];
                [videoFormatParams setObject:@(10) forKey:@"BitsPerComponent"];
            }
            if (contentLightLevelInfo) {
                [videoFormatParams setObject:contentLightLevelInfo
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_ContentLightLevelInfo];
            }
            if (masteringDisplayColorVolume) {
                [videoFormatParams setObject:masteringDisplayColorVolume
                                      forKey:(__bridge NSString*)kCMFormatDescriptionExtension_MasteringDisplayColorVolume];
            }
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault, count,
                                                                         pointers, sizes,
                                                                         NAL_LENGTH_PREFIX_SIZE,
                                                                         (__bridge CFDictionaryRef)videoFormatParams,
                                                                         &formatDesc);
            if (status != noErr) {
                formatDesc = NULL;
            }
            [parameterSetBuffers removeAllObjects];
        }
        else if (videoFormat & VIDEO_FORMAT_MASK_AV1) {
#if MLC_ENABLE_AV1
            NSMutableData* frameData = [[NSMutableData alloc] initWithCapacity:du->fullLength];
            for (PLENTRY entry = du->bufferList; entry != NULL; entry = entry->next) {
                if (entry->bufferType == BUFFER_TYPE_PICDATA) {
                    [frameData appendBytes:entry->data length:entry->length];
                }
            }
            formatDesc = [self createAV1FormatDescriptionForIDRFrame:frameData];
#endif
            [parameterSetBuffers removeAllObjects];
        }
    }

    if (formatDesc == NULL) {
        return NULL;
    }

    CMBlockBufferRef frameBlockBuffer = NULL;
    status = CMBlockBufferCreateEmpty(kCFAllocatorDefault, 16, 0, &frameBlockBuffer);
    if (status != noErr) {
        return NULL;
    }

    for (PLENTRY entry = du->bufferList; entry != NULL; entry = entry->next) {
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            continue;
        }

        if (videoFormat & (VIDEO_FORMAT_MASK_H264 | VIDEO_FORMAT_MASK_H265)) {
            const uint8_t* bytes = (const uint8_t*)entry->data;
            int length = entry->length;
            int offset = 0;
            while (offset + 3 < length) {
                int startLength = 0;
                if (bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 1) {
                    startLength = 3;
                }
                else if (offset + 4 < length && bytes[offset] == 0 && bytes[offset + 1] == 0 &&
                         bytes[offset + 2] == 0 && bytes[offset + 3] == 1) {
                    startLength = 4;
                }
                if (startLength == 0) {
                    offset++;
                    continue;
                }

                int nalStart = offset + startLength;
                int next = nalStart;
                while (next + 2 < length) {
                    if (bytes[next] == 0 && bytes[next + 1] == 0 && bytes[next + 2] == 1) {
                        break;
                    }
                    next++;
                }
                int nalEnd = (next + 2 < length) ? next : length;
                if (nalEnd > nalStart) {
                    [self appendZeroCopyNAL:&bytes[nalStart] length:nalEnd - nalStart to:frameBlockBuffer];
                }
                offset = nalEnd;
            }
        }
        else {
            [self appendZeroCopyBlock:(const uint8_t*)entry->data
                               length:entry->length
                                   to:frameBlockBuffer];
        }
    }

    CMSampleTimingInfo sampleTiming = {kCMTimeInvalid, CMTimeMake(du->presentationTimeUs, 1000000), kCMTimeInvalid};
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreateReady(kCFAllocatorDefault, frameBlockBuffer, formatDesc, 1, 1,
                                       &sampleTiming, 0, NULL, &sampleBuffer);
    CFRelease(frameBlockBuffer);
    if (status != noErr) {
        return NULL;
    }
    return sampleBuffer;
}

- (BOOL)attachFrameCompletion:(void*)handle toSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    MLCFrameCompletion* completion = [[MLCFrameCompletion alloc] init];
    completion.frameHandle = handle;
    CMSetAttachment(sampleBuffer, CFSTR("MLCFrameCompletion"),
                    (__bridge CFTypeRef)completion,
                    kCMAttachmentMode_ShouldNotPropagate);
    return YES;
}

@end
