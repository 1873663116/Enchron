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
bool PBFFmpegDemuxSourceSubscribe(
    PBFFmpegDemuxSource *source,
    int streamIndex
);
void PBFFmpegDemuxSourceUnsubscribe(
    PBFFmpegDemuxSource *source,
    int streamIndex
);
