---
name: verify-playback-lanes
description: Checks that a lane taking a stream in the shared demux source starts at the playhead, not at the oldest buffered packet, and that a stream's owner and subscriber agree. Use whenever changing PBFFmpegDemuxSourceTakeOverStream, PBFFmpegDemuxSourceReleaseStream, PBFFmpegDemuxSourceSeek, the read loop's enqueue decision, or any code that attaches an audio or subtitle reader to the shared source.
---

# Verifying the shared source's subscription protocol

One demux source serves every lane. A stream's queue holds whatever the read
loop has already pulled, and the playhead keeps moving while a lane is not
attached. Taking a stream therefore has two possible meanings, and the code
only implements one of them:

- **trim at attach** — the lane starts at the playhead;
- **keep the queue** — the lane starts at the oldest packet the stream buffered,
  which can be far behind the playhead.

The second meaning is a user-visible defect: switching audio plays nothing
until a seek, and subtitles never arrive. The code today implements the second
meaning.

## The promises

1. **A lane starts at the playhead.** A packet a lane shows was not already old
   when the lane took the stream. Breaking this produces silence after an audio
   switch, missing subtitles, and a seek that "fixes" both.
2. **An owner is a subscriber.** A stream has an owner exactly while it has a
   subscriber. Breaking this produces a stream nobody feeds, or a stream two
   lanes fight over.

## Run it

```bash
Scripts/playback/formal/run.sh
```

About one second. It needs a Java runtime and reuses
`Scripts/console/formal/tla2tools.jar`, fetching it on first use.

The script prints three things:

- the guards it found in `PlaybackFFmpegBridge.c`, and whether the known finding
  is still open;
- **design** — the model with trimming at attach. Expected:
  `design: all invariants hold`.
- **current code** — the model without trimming, which is what the source does
  today. Expected: `current code: stale delivery reproduced`.

Exit code 0 means the design holds and the current code still has the defect,
which is the state the repository records. Once the defect is fixed, the second
run starts passing, the script exits 1, and this skill plus
`check_sync.py` must be updated to check only the fixed shape.

## Read a counterexample

TLC prints one state per step. The trace that matters today:

1. `Read` puts packet `0` into `s1` while the playhead is at `0` and nothing
   subscribes; this is the read loop prebuffering the stream.
2. `Advance` moves the playhead to `1`.
3. `Attach` gives `s1` to the audio lane without trimming, so the queue still
   holds `0`.
4. `Dequeue` shows `0` while the playhead is at `1`.

In code, that is `audio.attach.open ... headBefore=1300.815` firing while the
playback position is 1315 s: the lane starts fourteen seconds behind, and a
seek is what rebuilds the queues.

## What it covers

| Code | Action in the model |
| --- | --- |
| `PBFFmpegDemuxSourceReadLoop` enqueue decision | `Read` |
| `PBFFmpegDemuxSourceTakeOverStream` | `Attach` |
| `PBFFmpegDemuxSourceReleaseStream` token check | `Release` |
| `PBFFmpegDemuxSourceSeek` | `Seek` |

`check_sync.py` asserts that those guards still exist in
`Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/PlaybackFFmpegBridge.c`. It
fails when one disappears, which means the model must be read again before its
verdict is trusted.

Last confirmed against the code at commit `fa52d263`.

Update that commit only after you check that the model still describes the code
at the new commit.

## What it does not cover

- History replay (`PBFFmpegDemuxSourceReplayHistoryFrom`) and packet
  deduplication across a re-attach. The Swift tests
  `subtitleLaneCoversTheSeekTargetAfterASeek` and
  `aSubtitleRendererCreatedAfterAForwardSeekReceivesTheCuesThatFollow` cover the
  behaviour; a re-attach that replays an already-shown packet is not modelled.
- Timing: how far behind a lane may be, and how long a gap is audible.
- The audio hand-off between two lanes, which is not in the code yet.

## Changing the check

Model a new guard by adding an action named after the C function that
implements it, then add its invariant to both `.cfg` files. Keep the state space
small: one lane, one stream, two packets and two positions is enough for this
protocol. Larger constants make TLC explore billions of states and the check
stops being cheap.

When the fix for promise 1 lands, run this skill, confirm the second run passes,
then set `TrimOnAttach = TRUE` in `PlaybackLanesCurrent.cfg` as well and update
the finding entries in `check_sync.py`.
