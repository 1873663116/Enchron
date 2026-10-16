//
//  MLCConnection.h
//  Adapted from moonlight-ios Limelight/Stream/Connection.{h,m} at 02dc9780.
//

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
} video_stats_t;

@interface MLCConnection : NSOperation

// Decoded Opus PCM handed to the audio output. Fires on the audio decode thread.
@property (nonatomic, copy) void (^audioFrameHandler)(NSData* pcm, uint32_t channelCount, uint32_t sampleRate, uint32_t frameCount);
@property (nonatomic, copy) void (^audioStarted)(void);
@property (nonatomic, copy) void (^audioStopped)(void);

// Receives every sample the connection builds, on the video decode thread.
@property (nonatomic, weak) id<MLCVideoSampleBuilderDelegate> videoConsumer;

- (instancetype)initWithConfig:(MLCStreamConfiguration*)config delegate:(id<MLCConnectionDelegate>)delegate;
- (void)terminate;
- (BOOL)getVideoStats:(video_stats_t*)stats;
- (NSString*)getActiveCodecName;

// Drops the cached format description and requests a keyframe. Call after the
// video consumer's decoder fails.
- (void)videoDecoderDidFail;

@end
