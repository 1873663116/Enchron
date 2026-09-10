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
