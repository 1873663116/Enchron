---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1",
  "title": "Audio Delivery Codec Matrix",
  "criteria": [
    "Every bound post-delivery playback snapshot exposes the closed canonical fields audioProviderKind, audioSourceCodec, audioSourceSampleRate, audioSourceChannelCount, audioDeliveryMediaSubtype, audioDeliveryFormatID, audioDeliveryFormatFlags, audioDeliverySampleRate, audioDeliveryChannelCount, audioDeliveryBitsPerChannel, audioDeliveryBytesPerFrame, audioDeliveryFramesPerPacket, audioDeliveryIsFloatPCM, audioDeliveryIsInterleaved, audioDeliveryChannelLayoutTag, audioDeliverySampleCount, audioDeliveryPresentationTime, audioDeliveryTimestampsMonotonic, and audioDeliveryTimestampObservationCount; none of the fields required by its branch is none.",
    "AC-3 and E-AC-3 cases select streams 2 and 3 of generated-sdr-avc-bframe-audio-codec-matrix-15s-v1: audioProviderKind is FFmpegCompressedAudio, audioSourceCodec is ac3 or eac3 respectively, source and delivery rates are 48000, source and delivery channel counts are 2, audioDeliveryIsFloatPCM is false, and media subtype/format ID/layout agree with the compressed CoreMedia description.",
    "DTS, TrueHD, Vorbis, AAC, and FLAC report audioProviderKind FFmpegDecodedPCM with source tuples dts/48000/7, truehd/48000/8, vorbis/44100/2, aac/48000/2, and flac/48000/2 respectively; delivery is interleaved Float32 linear PCM at the unchanged sample rate/channel count, bitsPerChannel=32, bytesPerFrame=4×channelCount, framesPerPacket=1, and the standard channel-layout tag for that count.",
    "Each case has audioDeliverySampleCount>0 and a finite non-negative audioDeliveryPresentationTime; audioDeliveryTimestampObservationCount>0, and when the count exceeds one audioDeliveryTimestampsMonotonic is true.",
    "In the same terminal TrueHD snapshot, audioSourceCodec=truehd, audioTrueHDDecoderInputPacketCount > audioTrueHDDecoderBatchCount > 0, audioTrueHDAggregatedDecoderBatchCount>0, audioTrueHDOutputSampleBufferCount>0, and audioTrueHDLastDecoderBatchInputPacketCount>0."
  ],
  "negativeControls": [
    "PCM delivery for AC-3/E-AC-3, compressed delivery for a decode case, changed sample rate/channel count, guessed layout, missing delivery sample, or a non-monotonic multi-observation timestamp series fails the matrix.",
    "A TrueHD conclusion from codec name alone, requiring the legal EOF tail batch to contain more than one packet, or comparing counters from different snapshots is inadmissible."
  ]
}
---
# Audio Delivery Codec Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
