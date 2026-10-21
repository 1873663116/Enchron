
#import "MLCConnection.h"
#import "MLCLogger.h"
#import "MLCUtils.h"

#import <QuartzCore/QuartzCore.h>

#include <arpa/inet.h>

#include <Limelight.h>

#import <opus/opus_multistream.h>

#include <pthread/qos.h>

void ArCleanup(void);


@interface MLCConnection () <MLCVideoSampleBuilderDelegate>
@end

@implementation MLCConnection {
    SERVER_INFORMATION _serverInfo;
    STREAM_CONFIGURATION _streamConfig;
    CONNECTION_LISTENER_CALLBACKS _clCallbacks;
    DECODER_RENDERER_CALLBACKS _drCallbacks;
    AUDIO_RENDERER_CALLBACKS _arCallbacks;
    char _hostString[256];
    char _appVersionString[32];
    char _gfeVersionString[32];
    char _rtspSessionUrl[128];
    BOOL _videoContentShown;
    NSThread* _pullThread;
}

static NSLock* initLock;
static OpusMSDecoder* opusDecoder;
static id<MLCConnectionDelegate> _callbacks;
static int lastFrameNumber;
static int activeVideoFormat;
static video_stats_t currentVideoStats;
static CFTimeInterval lastDecodeSubmitTime;
static video_stats_t lastVideoStats;
static NSLock* videoStatsLock;
static volatile BOOL pullThreadRunning = NO;

static OPUS_MULTISTREAM_CONFIGURATION audioConfig;
static void* audioBuffer;

static MLCVideoSampleBuilder* sampleBuilder;
static __weak MLCConnection* activeConnection;

int DrDecoderSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)
{
    [sampleBuilder setupWithVideoFormat:videoFormat];
    lastFrameNumber = 0;
    activeVideoFormat = videoFormat;
    memset(&currentVideoStats, 0, sizeof(currentVideoStats));
    memset(&lastVideoStats, 0, sizeof(lastVideoStats));
    lastDecodeSubmitTime = 0;
    return 0;
}

int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit)
{
    int offset = 0;
    int ret;
    unsigned char* data = (unsigned char*) malloc(decodeUnit->fullLength);
    if (data == NULL) {
        return DR_NEED_IDR;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (lastDecodeSubmitTime != 0) {
        double submitGapMs = (now - lastDecodeSubmitTime) * 1000.0;
        if (submitGapMs > 40.0) {
            currentVideoStats.submitGapCount++;
            if ((int)submitGapMs > currentVideoStats.submitGapMaxMs) {
                currentVideoStats.submitGapMaxMs = (int)submitGapMs;
            }
        }
    }
    lastDecodeSubmitTime = now;
    if (!lastFrameNumber) {
        currentVideoStats.startTime = now;
        lastFrameNumber = decodeUnit->frameNumber;
    }
    else {
        if (now - currentVideoStats.startTime >= 1.0f) {
            currentVideoStats.endTime = now;

            [videoStatsLock lock];
            lastVideoStats = currentVideoStats;
            [videoStatsLock unlock];

            memset(&currentVideoStats, 0, sizeof(currentVideoStats));
            currentVideoStats.startTime = now;
        }

        currentVideoStats.networkDroppedFrames += decodeUnit->frameNumber - (lastFrameNumber + 1);
        currentVideoStats.totalFrames += decodeUnit->frameNumber - (lastFrameNumber + 1);
        lastFrameNumber = decodeUnit->frameNumber;
    }

    if (decodeUnit->frameHostProcessingLatency != 0) {
        if (currentVideoStats.minHostProcessingLatency == 0 || decodeUnit->frameHostProcessingLatency < currentVideoStats.minHostProcessingLatency) {
            currentVideoStats.minHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }

        if (decodeUnit->frameHostProcessingLatency > currentVideoStats.maxHostProcessingLatency) {
            currentVideoStats.maxHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }

        currentVideoStats.framesWithHostProcessingLatency++;
        currentVideoStats.totalHostProcessingLatency += decodeUnit->frameHostProcessingLatency;
    }

    currentVideoStats.receivedFrames++;
    currentVideoStats.totalFrames++;

    PLENTRY entry = decodeUnit->bufferList;
    while (entry != NULL) {
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            ret = [sampleBuilder submitDecodeBuffer:(unsigned char*)entry->data
                                             length:entry->length
                                         bufferType:entry->bufferType
                                          decodeUnit:decodeUnit];
            if (ret != DR_OK) {
                free(data);
                return ret;
            }
        }
        else {
            memcpy(&data[offset], entry->data, entry->length);
            offset += entry->length;
        }

        entry = entry->next;
    }

    return [sampleBuilder submitDecodeBuffer:data
                                      length:offset
                                  bufferType:BUFFER_TYPE_PICDATA
                                   decodeUnit:decodeUnit];
}

int ArInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int flags)
{
    int err;

    audioConfig = *opusConfig;

    audioBuffer = malloc(opusConfig->samplesPerFrame * sizeof(short) * opusConfig->channelCount);
    if (audioBuffer == NULL) {
        Log(LOG_E, @"Failed to allocate audio frame buffer");
        ArCleanup();
        return -1;
    }

    opusDecoder = opus_multistream_decoder_create(opusConfig->sampleRate,
                                                  opusConfig->channelCount,
                                                  opusConfig->streams,
                                                  opusConfig->coupledStreams,
                                                  opusConfig->mapping,
                                                  &err);
    if (opusDecoder == NULL) {
        Log(LOG_E, @"Failed to create Opus decoder");
        ArCleanup();
        return -1;
    }

    if (activeConnection.audioStarted) {
        activeConnection.audioStarted(opusConfig->channelCount, opusConfig->sampleRate, opusConfig->samplesPerFrame);
    }

    return 0;
}

void ArCleanup(void)
{
    if (opusDecoder != NULL) {
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
    }

    if (audioBuffer != NULL) {
        free(audioBuffer);
        audioBuffer = NULL;
    }

    if (activeConnection.audioStopped) {
        activeConnection.audioStopped();
    }
}

void ArDecodeAndPlaySample(char* sampleData, int sampleLength)
{
    int decodeLen;

    if (LiGetPendingAudioDuration() > 30) {
        return;
    }

    decodeLen = opus_multistream_decode(opusDecoder, (unsigned char *)sampleData, sampleLength,
                                        (short*)audioBuffer, audioConfig.samplesPerFrame, 0);
    if (decodeLen > 0) {
        void (^handler)(NSData*, uint32_t, uint32_t, uint32_t) = activeConnection.audioFrameHandler;
        if (handler != nil) {
            NSData* pcm = [NSData dataWithBytes:audioBuffer
                                         length:sizeof(short) * decodeLen * audioConfig.channelCount];
            handler(pcm, audioConfig.channelCount, audioConfig.sampleRate, decodeLen);
        }
    }
}

void ClStageStarting(int stage)
{
    [_callbacks stageStarting:LiGetStageName(stage)];
}

void ClStageComplete(int stage)
{
    [_callbacks stageComplete:LiGetStageName(stage)];
}

void ClStageFailed(int stage, int errorCode)
{
    [_callbacks stageFailed:LiGetStageName(stage) withError:errorCode portTestFlags:LiGetPortFlagsFromStage(stage)];
}

void ClConnectionStarted(void)
{
    [_callbacks connectionStarted];
}

void ClConnectionTerminated(int errorCode)
{
    [_callbacks connectionTerminated: errorCode];
}

void ClLogMessage(const char* format, ...)
{
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
}

void ClConnectionStatusUpdate(int status)
{
    [_callbacks connectionStatusUpdate:status];
}

void ClSetHdrMode(bool enabled)
{
    [sampleBuilder setHdrMode:enabled];
    [_callbacks setHdrMode:enabled];
}

- (void)videoSampleBuilder:(MLCVideoSampleBuilder*)builder
          didProduceSample:(CMSampleBufferRef)sampleBuffer
                 frameType:(int)frameType
         presentationTimeUs:(uint64_t)presentationTimeUs {
    BOOL contentShown = frameType == FRAME_TYPE_IDR && !_videoContentShown;
    if (contentShown) {
        _videoContentShown = YES;
    }

    [self.videoConsumer videoSampleBuilder:builder
                          didProduceSample:sampleBuffer
                                 frameType:frameType
                         presentationTimeUs:presentationTimeUs];

    if (contentShown) {
        [_callbacks videoContentShown];
    }
}

- (void)videoDecoderDidFail {
    [sampleBuilder invalidateFormatDescription];
    _videoContentShown = NO;
    LiRequestIdrFrame();
}

- (void)terminate
{
    LiInterruptConnection();

    pullThreadRunning = NO;
    LiWakeWaitForVideoFrame();

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [initLock lock];
        LiStopConnection();
        [initLock unlock];
    });
}

- (instancetype)initWithConfig:(MLCStreamConfiguration*)config delegate:(id<MLCConnectionDelegate>)delegate
{
    self = [super init];

    if (initLock == nil) {
        initLock = [[NSLock alloc] init];
    }

    if (videoStatsLock == nil) {
        videoStatsLock = [[NSLock alloc] init];
    }

    NSString *rawAddress = [MLCUtils addressPortStringToAddress:config.host];
    strncpy(_hostString,
            [rawAddress cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_hostString) - 1);
    strncpy(_appVersionString,
            [config.appVersion cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_appVersionString) - 1);
    if (config.gfeVersion != nil) {
        strncpy(_gfeVersionString,
                [config.gfeVersion cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_gfeVersionString) - 1);
    }
    if (config.rtspSessionUrl != nil) {
        strncpy(_rtspSessionUrl,
                [config.rtspSessionUrl cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_rtspSessionUrl) - 1);
    }

    LiInitializeServerInformation(&_serverInfo);
    _serverInfo.address = _hostString;
    _serverInfo.serverInfoAppVersion = _appVersionString;
    if (config.gfeVersion != nil) {
        _serverInfo.serverInfoGfeVersion = _gfeVersionString;
    }
    if (config.rtspSessionUrl != nil) {
        _serverInfo.rtspSessionUrl = _rtspSessionUrl;
    }
    _serverInfo.serverCodecModeSupport = config.serverCodecModeSupport;

    sampleBuilder = [[MLCVideoSampleBuilder alloc] init];
    sampleBuilder.delegate = self;
    activeConnection = self;

    _callbacks = delegate;
    _videoContentShown = NO;

    LiInitializeStreamConfiguration(&_streamConfig);
    _streamConfig.width = config.width;
    _streamConfig.height = config.height;
    _streamConfig.fps = config.frameRate;
    _streamConfig.bitrate = config.bitRate;
    _streamConfig.supportedVideoFormats = config.supportedVideoFormats;
    _streamConfig.audioConfiguration = config.audioConfiguration;

    _streamConfig.encryptionFlags = ENCFLG_ALL;

    _streamConfig.streamingRemotely = STREAM_CFG_AUTO;
    _streamConfig.packetSize = 1392;

    memcpy(_streamConfig.remoteInputAesKey, [config.riKey bytes], [config.riKey length]);
    memset(_streamConfig.remoteInputAesIv, 0, 16);
    int riKeyId = htonl(config.riKeyId);
    memcpy(_streamConfig.remoteInputAesIv, &riKeyId, sizeof(riKeyId));

    LiInitializeVideoCallbacks(&_drCallbacks);
    _drCallbacks.setup = DrDecoderSetup;
    _drCallbacks.submitDecodeUnit = DrSubmitDecodeUnit;
    _drCallbacks.capabilities = CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC |
                                CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1;

    LiInitializeAudioCallbacks(&_arCallbacks);
    _arCallbacks.init = ArInit;
    _arCallbacks.cleanup = ArCleanup;
    _arCallbacks.decodeAndPlaySample = ArDecodeAndPlaySample;
    _arCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    LiInitializeConnectionCallbacks(&_clCallbacks);
    _clCallbacks.stageStarting = ClStageStarting;
    _clCallbacks.stageComplete = ClStageComplete;
    _clCallbacks.stageFailed = ClStageFailed;
    _clCallbacks.connectionStarted = ClConnectionStarted;
    _clCallbacks.connectionTerminated = ClConnectionTerminated;
    _clCallbacks.logMessage = ClLogMessage;
    _clCallbacks.connectionStatusUpdate = ClConnectionStatusUpdate;
    _clCallbacks.setHdrMode = ClSetHdrMode;

    return self;
}

- (BOOL)getVideoStats:(video_stats_t*)stats
{
    [videoStatsLock lock];
    if (lastVideoStats.endTime != 0) {
        memcpy(stats, &lastVideoStats, sizeof(*stats));
        [videoStatsLock unlock];
        return YES;
    }

    [videoStatsLock unlock];
    return NO;
}

- (NSString*)getActiveCodecName
{
    switch (activeVideoFormat)
    {
        case VIDEO_FORMAT_H264:
            return @"H.264";
        case VIDEO_FORMAT_H264_HIGH8_444:
            return @"H.264 (4:4:4)";
        case VIDEO_FORMAT_H265:
            return @"HEVC";
        case VIDEO_FORMAT_H265_REXT8_444:
            return @"HEVC (4:4:4)";
        case VIDEO_FORMAT_H265_MAIN10:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"HEVC Main 10 HDR";
            }
            else {
                return @"HEVC Main 10 SDR";
            }
        case VIDEO_FORMAT_H265_REXT10_444:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"HEVC Main 10 HDR (4:4:4)";
            }
            else {
                return @"HEVC Main 10 SDR (4:4:4)";
            }
        case VIDEO_FORMAT_AV1_MAIN8:
            return @"AV1";
        case VIDEO_FORMAT_AV1_HIGH8_444:
            return @"AV1 (4:4:4)";
        case VIDEO_FORMAT_AV1_MAIN10:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"AV1 10-bit HDR";
            }
            else {
                return @"AV1 10-bit SDR";
            }
        case VIDEO_FORMAT_AV1_HIGH10_444:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"AV1 10-bit HDR (4:4:4)";
            }
            else {
                return @"AV1 10-bit SDR (4:4:4)";
            }
        default:
            return @"UNKNOWN";
    }
}

- (void)main
{
    [initLock lock];
    int err = LiStartConnection(&_serverInfo,
                                &_streamConfig,
                                &_clCallbacks,
                                &_drCallbacks,
                                &_arCallbacks,
                                NULL, 0,
                                NULL, 0);
    [initLock unlock];

    if (err == 0 && NO) {
        pullThreadRunning = YES;
        _pullThread = [[NSThread alloc] initWithTarget:self selector:@selector(videoPullLoop) object:nil];
        _pullThread.name = @"VideoPull";
        [_pullThread start];
    }
}

- (void)recordPulledUnitStats:(PDECODE_UNIT)decodeUnit
{
    CFTimeInterval now = CACurrentMediaTime();
    if (lastDecodeSubmitTime != 0) {
        double submitGapMs = (now - lastDecodeSubmitTime) * 1000.0;
        if (submitGapMs > 40.0) {
            currentVideoStats.submitGapCount++;
            if ((int)submitGapMs > currentVideoStats.submitGapMaxMs) {
                currentVideoStats.submitGapMaxMs = (int)submitGapMs;
            }
        }
    }
    lastDecodeSubmitTime = now;

    if (!lastFrameNumber) {
        currentVideoStats.startTime = now;
        lastFrameNumber = decodeUnit->frameNumber;
    }
    else {
        if (now - currentVideoStats.startTime >= 1.0f) {
            currentVideoStats.endTime = now;
            [videoStatsLock lock];
            lastVideoStats = currentVideoStats;
            [videoStatsLock unlock];
            memset(&currentVideoStats, 0, sizeof(currentVideoStats));
            currentVideoStats.startTime = now;
        }
        currentVideoStats.networkDroppedFrames += decodeUnit->frameNumber - (lastFrameNumber + 1);
        currentVideoStats.totalFrames += decodeUnit->frameNumber - (lastFrameNumber + 1);
        lastFrameNumber = decodeUnit->frameNumber;
    }

    if (decodeUnit->frameHostProcessingLatency != 0) {
        if (currentVideoStats.minHostProcessingLatency == 0 ||
            decodeUnit->frameHostProcessingLatency < currentVideoStats.minHostProcessingLatency) {
            currentVideoStats.minHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        if (decodeUnit->frameHostProcessingLatency > currentVideoStats.maxHostProcessingLatency) {
            currentVideoStats.maxHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        currentVideoStats.framesWithHostProcessingLatency++;
        currentVideoStats.totalHostProcessingLatency += decodeUnit->frameHostProcessingLatency;
    }

    currentVideoStats.receivedFrames++;
    currentVideoStats.totalFrames++;
}

- (void)videoPullLoop
{
    [[NSThread currentThread] setThreadPriority:0.95];
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);

    while (pullThreadRunning) {
        VIDEO_FRAME_HANDLE handle = NULL;
        PDECODE_UNIT decodeUnit = NULL;

        if (!LiWaitForNextVideoFrame(&handle, &decodeUnit)) {
            break;
        }

        @autoreleasepool {
            CMSampleBufferRef sampleBuffer = [sampleBuilder createZeroCopySampleBufferForPulledUnit:decodeUnit];
            if (sampleBuffer == NULL) {
                currentVideoStats.zeroCopyFallbacks++;
                int status = DrSubmitDecodeUnit(decodeUnit);
                LiCompleteVideoFrame(handle, status);
                continue;
            }

            currentVideoStats.zeroCopyFrames++;
            [self recordPulledUnitStats:decodeUnit];
            BOOL attached = [sampleBuilder attachFrameCompletion:handle toSampleBuffer:sampleBuffer];
            [self videoSampleBuilder:sampleBuilder
                    didProduceSample:sampleBuffer
                           frameType:decodeUnit->frameType
                   presentationTimeUs:decodeUnit->presentationTimeUs];
            CFRelease(sampleBuffer);
            if (!attached) {
                LiCompleteVideoFrame(handle, DR_OK);
            }
        }
    }
}

@end
