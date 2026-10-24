
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#include <Limelight.h>

@class MLCVideoSampleBuilder;

@protocol MLCVideoSampleBuilderDelegate <NSObject>

- (void)videoSampleBuilder:(MLCVideoSampleBuilder*)builder
          didProduceSample:(CMSampleBufferRef)sampleBuffer
                 frameType:(int)frameType
         presentationTimeUs:(uint64_t)presentationTimeUs;

@end

@interface MLCVideoSampleBuilder : NSObject

@property (nonatomic, weak) id<MLCVideoSampleBuilderDelegate> delegate;

@property (class, nonatomic, readonly) BOOL isAV1PlaybackSupported;

- (void)setupWithVideoFormat:(int)videoFormat;
- (int)submitDecodeBuffer:(unsigned char*)data length:(int)length bufferType:(int)bufferType decodeUnit:(PDECODE_UNIT)du;
- (void)setHdrMode:(BOOL)enabled;

- (void)invalidateFormatDescription;

- (CMSampleBufferRef)createZeroCopySampleBufferForPulledUnit:(PDECODE_UNIT)du CF_RETURNS_RETAINED;

- (BOOL)attachFrameCompletion:(void*)handle toSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end
