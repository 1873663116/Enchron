#pragma once

#include "PlaybackFFmpegBridge.h"

#include <libavformat/avformat.h>

AVFormatContext *PBFFmpegDemuxSourceGetFormatContext(
    PBFFmpegDemuxSource *source
);
int PBFFmpegDemuxSourceCopyNextPacket(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    AVPacket *packet
);
int PBFFmpegDemuxSourceCopyNextPacketIfAvailable(
    PBFFmpegDemuxSource *source,
    int streamIndex,
    AVPacket *packet
);
bool PBFFmpegDemuxSourceSubscribe(
    PBFFmpegDemuxSource *source,
    int streamIndex
);
void PBFFmpegDemuxSourceUnsubscribe(
    PBFFmpegDemuxSource *source,
    int streamIndex
);

// The bridge's single door to a format context that is not the shared demux
// source: allocates the context with the interrupt callback that meters bytes
// into the monitor and aborts reads once the monitor is interrupted or the
// caller's cancellation is set, opens the path and reads its stream
// information. The door owns the context; callers borrow it and close the door
// when they are done. An optional cancellation aborts this read alone and has
// to outlive the borrowed context.
typedef struct PBFFmpegMonitoredSource PBFFmpegMonitoredSource;
PBFFmpegMonitoredSource *PBFFmpegMonitoredSourceOpen(
    const char *path,
    PBFFmpegSourceReadMonitor *monitor,
    PBFFmpegReadCancellation *cancellation,
    char *errorBuffer,
    size_t errorBufferSize
);
AVFormatContext *PBFFmpegMonitoredSourceGetFormatContext(PBFFmpegMonitoredSource *source);
void PBFFmpegMonitoredSourceClose(PBFFmpegMonitoredSource **source);
