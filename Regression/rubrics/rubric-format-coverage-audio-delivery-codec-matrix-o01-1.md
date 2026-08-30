---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.audio-delivery-codec-matrix.o01@1",
  "title": "Audio Delivery Codec Matrix",
  "criteria": [
    "The bound post-delivery playback snapshot exposes the closed canonical fields audioProviderKind, audioSourceCodec, audioSourceSampleRate, audioSourceChannelCount, audioDeliveryMediaSubtype, audioDeliveryFormatID, audioDeliveryFormatFlags, audioDeliverySampleRate, audioDeliveryChannelCount, audioDeliveryBitsPerChannel, audioDeliveryBytesPerFrame, audioDeliveryFramesPerPacket, audioDeliveryIsFloatPCM, audioDeliveryIsInterleaved, audioDeliveryChannelLayoutTag, audioDeliverySampleCount, audioDeliveryPresentationTime, audioDeliveryTimestampsMonotonic, and audioDeliveryTimestampObservationCount; none of the fields required by its registered branch is none.",
    "The bound snapshot identifies the source branch registered for its case. AC-3 and E-AC-3 select streams 2 and 3 of generated-sdr-avc-bframe-audio-codec-matrix-15s-v1 with audioProviderKind FFmpegCompressedAudio, audioSourceCodec ac3 and eac3, sample rate 48000, and channel count 2 respectively. DTS, TrueHD, Vorbis, AAC, and FLAC use audioProviderKind FFmpegDecodedPCM with source tuples dts/48000/7, truehd/48000/8, vorbis/44100/2, aac/48000/2, and flac/48000/2 respectively.",
    "The bound snapshot exposes the delivery branch registered for its case. AC-3 and E-AC-3 preserve the 48000 Hz, two-channel compressed CoreMedia description, report audioDeliveryIsFloatPCM=false, and expose the matching media subtype and format ID. DTS, TrueHD, Vorbis, AAC, and FLAC deliver interleaved Float32 linear PCM at the unchanged sample rate and channel count with bitsPerChannel=32, bytesPerFrame=4×channelCount, and framesPerPacket=1. audioDeliveryChannelLayoutTag is the decimal AudioChannelLayoutTag the product's own mapping writes for that source layout (audio_channel_layout_tag and copy_audio_channel_layout, PlaybackFFmpegBridge.c:5538-5581): 6619138, kAudioChannelLayoutTag_Stereo, for the two-channel AC-3, E-AC-3, Vorbis, AAC and FLAC cases, and 12386312, kAudioChannelLayoutTag_WAVE_7_1, for the eight-channel TrueHD case. The seven-channel DTS-ES case has no standard tag in that mapping and none in CoreAudio, so it takes the fallthrough copy_audio_channel_layout writes at :5568-5581 — 0, kAudioChannelLayoutTag_UseChannelDescriptions, for an ordered decoded layout,, kAudioChannelLayoutTag_DiscreteInOrder | 7, for an unspecified one — and a standard tag on that case fails the criterion.",
    "The bound case has audioDeliverySampleCount>0 and a finite non-negative audioDeliveryPresentationTime; audioDeliveryTimestampObservationCount>0, and when the count exceeds one audioDeliveryTimestampsMonotonic is true.",
    "The bound snapshot applies the terminal decoder checks registered for its case. The TrueHD case has audioSourceCodec=truehd, audioTrueHDDecoderInputPacketCount > audioTrueHDDecoderBatchCount > 0, audioTrueHDAggregatedDecoderBatchCount>0, audioTrueHDOutputSampleBufferCount>0, and audioTrueHDLastDecoderBatchInputPacketCount>0; every other case establishes its registered non-TrueHD audioSourceCodec without claiming TrueHD counters."
  ],
  "negativeControls": [
    "PCM delivery for AC-3/E-AC-3, compressed delivery for a decode case, changed sample rate/channel count, guessed layout, missing delivery sample, or a non-monotonic multi-observation timestamp series fails the matrix.",
    "A TrueHD conclusion from codec name alone, requiring the legal EOF tail batch to contain more than one packet, or comparing counters from different snapshots is inadmissible."
  ]
}
---
# Audio Delivery Codec Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
