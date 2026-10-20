//
//  MLCVideoSampleBuilder.h
//  Adapted from moonlight-ios Limelight/Stream/VideoDecoderRenderer.{h,m} at 02dc9780.
//
//  Owns the video sample construction half of the upstream decoder renderer; the
//  display layer, frame pacing and display link are gone.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#include <Limelight.h>

@class MLCVideoSampleBuilder;

@protocol MLCVideoSampleBuilderDelegate <NSObject>

// Invoked synchronously on the thread that submitted the decode unit. The sample
// buffer stays valid for the duration of the call.
- (void)videoSampleBuilder:(MLCVideoSampleBuilder*)builder
          didProduceSample:(CMSampleBufferRef)sampleBuffer
                 frameType:(int)frameType
         presentationTimeUs:(uint64_t)presentationTimeUs;

@end

@interface MLCVideoSampleBuilder : NSObject

@property (nonatomic, weak) id<MLCVideoSampleBuilderDelegate> delegate;

// Reports whether this build can turn AV1 decode units into sample buffers.
// False unless the AV1 format description path is compiled in.
@property (class, nonatomic, readonly) BOOL isAV1PlaybackSupported;

- (void)setupWithVideoFormat:(int)videoFormat;
- (int)submitDecodeBuffer:(unsigned char*)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du;
- (void)setHdrMode:(BOOL)enabled;

// Drops the cached format description and parameter sets so that the next IDR
// frame rebuilds them. Call after a decoder failure.
- (void)invalidateFormatDescription;

// Pull-renderer path. Builds a sample buffer whose block buffer references the
// decode unit's own memory, so the decode unit must stay alive until the sample
// buffer is released. Returns a retained sample buffer or NULL when the format
// description is not available yet.
- (CMSampleBufferRef)createZeroCopySampleBufferForPulledUnit:(PDECODE_UNIT)du CF_RETURNS_RETAINED;

// Keeps the decode unit alive until the sample buffer is released, then hands it
// back to Moonlight. Returns NO when the completion could not be attached, in
// which case the caller must complete the frame itself.
- (BOOL)attachFrameCompletion:(void*)handle toSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
