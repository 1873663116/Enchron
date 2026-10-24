
#import <Foundation/Foundation.h>

#import "MLCConnectionDelegate.h"
#import "MLCStreamConfiguration.h"
#import "MLCVideoSampleBuilder.h"

typedef struct {
    CFTimeInterval startTime;
    CFTimeInterval endTime;
    int totalFrames;
    int receivedFrames;
    int networkDroppedFrames;
    int totalHostProcessingLatency;
    int framesWithHostProcessingLatency;
    int maxHostProcessingLatency;
    int minHostProcessingLatency;
    int submitGapCount;
    int submitGapMaxMs;
    int zeroCopyFrames;
    int zeroCopyFallbacks;
    int assembleMaxMs;
    int queueWaitMaxMs;
    int callbackMaxMs;
    int pendingMax;
} video_stats_t;

@interface MLCConnection : NSOperation

@property (nonatomic, copy) void (^audioFrameHandler)(NSData* pcm, uint32_t channelCount, uint32_t sampleRate, uint32_t frameCount);
@property (nonatomic, copy) void (^audioStarted)(uint32_t channelCount, uint32_t sampleRate, uint32_t samplesPerFrame);
@property (nonatomic, copy) void (^audioStopped)(void);

@property (nonatomic, weak) id<MLCVideoSampleBuilderDelegate> videoConsumer;

- (instancetype)initWithConfig:(MLCStreamConfiguration*)config delegate:(id<MLCConnectionDelegate>)delegate;
- (void)terminate;
- (BOOL)getVideoStats:(video_stats_t*)stats;
- (NSString*)getActiveCodecName;

- (void)videoDecoderDidFail;

@end
