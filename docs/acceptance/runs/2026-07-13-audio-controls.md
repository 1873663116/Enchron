# Audio and user-control run — 2026-07-13

## Fixture

`script/generate_multiaudio_fixture.sh` generated a 12-second H.264 MP4 with two independent mono AAC 48 kHz tracks: English 440 Hz at raw stream index 1 and Japanese 880 Hz at raw stream index 2.

## Protocol

The macOS route probe opened the fixture independently through Apple Compressed, FFmpeg Compressed, and FFmpeg Decoded. In each Media Session it waited for displayed video and audio enqueue, selected stream index 2, applied volume 0.35, toggled mute on and off, set rate 1.5, sought to 4 seconds, and required both audio and video to resume before restoring rate 1. The App wrote `/tmp/playbacklab-route-probe.json` and terminated itself.

## Result

All three routes passed. Each enumerated both tracks, selected stream index 2, preserved its Media Session across the selection and control sequence, and increased audio sample-buffer count after selection. A later correctness audit separated Audio Stream Epoch from Video Stream Epoch: audio selection advances only the audio epoch, while seek advances both. The refreshed run reported Audio Stream Epoch 3 and Video Stream Epoch 2 for all three routes. Seek completion now requires current-epoch audio and video records whose PTS is at or after the target; the run observed that condition on every route, displayed video reappeared, and synchronizer time advanced to approximately 4.5 seconds. Volume, mute, unmute, rate, and seek acknowledgements matched the requested state.

The last enqueued audio and video PTS can differ because each renderer queues ahead independently; that difference is not a displayed lip-sync measurement. Both renderers are scheduled by the same `AVSampleBufferRenderSynchronizer`. Subjective lip-sync remains a separate human acceptance case.

This proves real provider/renderer control-path behavior on macOS. It does not prove audible device output, subjective lip-sync, visionOS scene transitions, or Vision Pro display behavior.
