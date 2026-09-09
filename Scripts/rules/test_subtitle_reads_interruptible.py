#!/usr/bin/env python3

from __future__ import annotations

import unittest

import verify_subtitle_reads_interruptible as rule


VALID_ALLOCATE_FORMAT_CONTEXT = (
    "static AVFormatContext *allocate_format_context(\n"
    "    atomic_bool *cancelled,\n"
    "    PBFFmpegSourceReadContext *sourceReadContext\n"
    ") {\n"
    "    AVFormatContext *context = avformat_alloc_context();\n"
    "    return context;\n"
    "}\n"
)

VALID_OPEN_MEDIA_SOURCE = (
    "static int open_media_source(\n"
    "    AVFormatContext **context,\n"
    "    const char *path,\n"
    "    PBFFmpegSourceReadContext *sourceReadContext\n"
    ") {\n"
    "    int result = avformat_open_input(context, path, NULL, NULL);\n"
    "    return result;\n"
    "}\n"
)

ROGUE_OPEN_MEDIA_SOURCE_WITH_EXTERNAL_CALL = (
    "static int open_media_source(\n"
    "    AVFormatContext **context,\n"
    "    const char *path,\n"
    "    PBFFmpegSourceReadContext *sourceReadContext\n"
    ") {\n"
    "    return 0;\n"
    "}\n"
    "\n"
    "static int rogue_open(const char *path) {\n"
    "    return avformat_open_input(NULL, path, NULL, NULL);\n"
    "}\n"
)

SUBTITLE_SOURCE_WITHOUT_RAW_CALLS = (
    "PBFFmpegMonitoredSource *source = PBFFmpegMonitoredSourceOpen(\n"
    "    path, monitor, cancellation, errorBuffer, errorBufferSize\n"
    ");\n"
)

HEADER_WITH_MONITORED_SUBTITLE_DECLARATIONS = (
    "PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(\n"
    "    const char *path,\n"
    "    int streamIndex,\n"
    "    char *errorBuffer,\n"
    "    size_t errorBufferSize,\n"
    "    PBFFmpegSourceReadMonitor *monitor,\n"
    "    PBFFmpegReadCancellation *cancellation\n"
    ");\n"
    "PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreate(\n"
    "    const char *path,\n"
    "    int streamIndex,\n"
    "    PBFFmpegSourceReadMonitor *monitor,\n"
    "    PBFFmpegReadCancellation *cancellation,\n"
    "    char *errorBuffer,\n"
    "    size_t errorBufferSize\n"
    ");\n"
)

HEADER_WITH_MONITORLESS_SUBTITLE_CONSTRUCTOR = (
    "PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreateFromPath(\n"
    "    const char *path,\n"
    "    int streamIndex,\n"
    "    char *errorBuffer,\n"
    "    size_t errorBufferSize\n"
    ");\n"
)

HEADER_WITH_UNCANCELLABLE_SUBTITLE_CONSTRUCTOR = (
    "PBSubtitleFrameRenderer *PBSubtitleFrameRendererCreateFromPath(\n"
    "    const char *path,\n"
    "    int streamIndex,\n"
    "    PBFFmpegSourceReadMonitor *monitor,\n"
    "    char *errorBuffer,\n"
    "    size_t errorBufferSize\n"
    ");\n"
)

CANCELLABLE_MONITORED_OPENS = (
    "PBFFmpegMonitoredSource *PBFFmpegMonitoredSourceOpen(\n"
    "    const char *path,\n"
    "    PBFFmpegSourceReadMonitor *monitor,\n"
    "    PBFFmpegReadCancellation *cancellation,\n"
    "    char *errorBuffer,\n"
    "    size_t errorBufferSize\n"
    ") {\n"
    "    atomic_bool *cancelled = cancellation ? &cancellation->cancelled : NULL;\n"
    "    source->formatContext = allocate_format_context(cancelled, &source->readContext);\n"
    "    return source;\n"
    "}\n"
    "\n"
    "PBFFmpegSubtitleReader *PBFFmpegSubtitleReaderCreateWithSourceReadMonitor(\n"
    "    const char *path,\n"
    "    int streamIndex,\n"
    "    char *errorBuffer,\n"
    "    size_t errorBufferSize,\n"
    "    PBFFmpegSourceReadMonitor *monitor,\n"
    "    PBFFmpegReadCancellation *cancellation\n"
    ") {\n"
    "    atomic_bool *cancelled = cancellation ? &cancellation->cancelled : NULL;\n"
    "    reader->formatContext = allocate_format_context(cancelled, &reader->readContext);\n"
    "    return reader;\n"
    "}\n"
)

UNCANCELLABLE_MONITORED_OPENS = CANCELLABLE_MONITORED_OPENS.replace(
    "allocate_format_context(cancelled, &source->readContext)",
    "allocate_format_context(NULL, &source->readContext)",
)

SOURCES_WITHOUT_PRELOAD_BACKLOG = {
    "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/SubtitleFrameRenderer.c": (
        SUBTITLE_SOURCE_WITHOUT_RAW_CALLS
    ),
}

SOURCES_WITH_PRELOAD_BACKLOG = {
    "Packages/PlaybackCore/Sources/PlaybackFFmpegBridge/SubtitleFrameRenderer.c": (
        "static void PBSubtitleFrameRendererPreloadBacklogFromPath(const char *path) {\n"
        "    return;\n"
        "}\n"
    ),
}

DELIVERY_SWIFT_WITH_INTERRUPT_CALL = (
    "extension SampleBufferPlaybackSession {\n"
    "    func hush() {\n"
    "        setTimelineStopped(reason: .close)\n"
    "    }\n"
    "\n"
    "    func interruptSourceReadsForClose() {\n"
    "        demuxSession?.interrupt()\n"
    "        sourceReadMeter?.interruptReads()\n"
    "    }\n"
    "}\n"
)

DELIVERY_SWIFT_WITHOUT_INTERRUPT_CALL = (
    "extension SampleBufferPlaybackSession {\n"
    "    func interruptSourceReadsForClose() {\n"
    "        demuxSession?.interrupt()\n"
    "    }\n"
    "}\n"
)

THROUGHPUT_SWIFT_WITH_INTERRUPT = (
    "func interruptReads() {\n"
    "    PBFFmpegSourceReadMonitorInterrupt(monitor)\n"
    "}\n"
)


class OpenPathCallSiteTests(unittest.TestCase):
    def test_allocate_format_context_call_inside_its_own_body_is_accepted(self) -> None:
        rule.check_S1(VALID_ALLOCATE_FORMAT_CONTEXT)

    def test_open_media_source_call_inside_its_own_body_is_accepted(self) -> None:
        rule.check_S2(VALID_OPEN_MEDIA_SOURCE)

    def test_raw_avformat_open_input_outside_open_media_source_is_rejected(self) -> None:
        with self.assertRaises(AssertionError) as failure:
            rule.check_S2(ROGUE_OPEN_MEDIA_SOURCE_WITH_EXTERNAL_CALL)
        self.assertIn("S2", str(failure.exception))

    def test_subtitle_source_without_raw_open_calls_is_accepted(self) -> None:
        rule.check_S3({"Bridge/SubtitleFrameRenderer.c": SUBTITLE_SOURCE_WITHOUT_RAW_CALLS})

    def test_subtitle_source_with_a_raw_open_call_is_rejected(self) -> None:
        with self.assertRaises(AssertionError) as failure:
            rule.check_S3({"Bridge/Extra.c": "avformat_open_input(context, path, NULL, NULL);\n"})
        self.assertIn("S3", str(failure.exception))

    def test_a_raw_open_call_inside_a_comment_is_ignored(self) -> None:
        rule.check_S3({"Bridge/Extra.c": "/* avformat_open_input( is documented here */\n"})
        stripped = rule.without_comments("a(); // avformat_alloc_context(\n/* b */ c();\n")
        self.assertEqual(rule.count_calls(stripped, "avformat_alloc_context("), [])
        self.assertEqual(len(stripped), len("a(); // avformat_alloc_context(\n/* b */ c();\n"))


class MonitorWiringTests(unittest.TestCase):
    def test_full_wiring_is_accepted(self) -> None:
        rule.check_S4(
            "monitor->interrupted",
            "PBFFmpegSourceReadMonitorInterrupt(",
            THROUGHPUT_SWIFT_WITH_INTERRUPT,
            DELIVERY_SWIFT_WITH_INTERRUPT_CALL,
        )

    def test_missing_interrupt_call_in_close_is_rejected(self) -> None:
        with self.assertRaises(AssertionError) as failure:
            rule.check_S4(
                "monitor->interrupted",
                "PBFFmpegSourceReadMonitorInterrupt(",
                THROUGHPUT_SWIFT_WITH_INTERRUPT,
                DELIVERY_SWIFT_WITHOUT_INTERRUPT_CALL,
            )
        self.assertIn("S4", str(failure.exception))


class PreloadBacklogTests(unittest.TestCase):
    def test_sources_without_preload_backlog_are_accepted(self) -> None:
        rule.check_S5(SOURCES_WITHOUT_PRELOAD_BACKLOG)

    def test_preload_backlog_in_a_synthetic_source_is_rejected(self) -> None:
        with self.assertRaises(AssertionError) as failure:
            rule.check_S5(SOURCES_WITH_PRELOAD_BACKLOG)
        self.assertIn("S5", str(failure.exception))


class SubtitleConstructorMonitorTests(unittest.TestCase):
    def test_monitored_declarations_and_the_documented_exception_are_accepted(
        self,
    ) -> None:
        rule.check_S6(HEADER_WITH_MONITORED_SUBTITLE_DECLARATIONS)

    def test_subtitle_constructor_with_a_path_but_no_monitor_is_rejected(self) -> None:
        with self.assertRaises(AssertionError) as failure:
            rule.check_S6(HEADER_WITH_MONITORLESS_SUBTITLE_CONSTRUCTOR)
        self.assertIn("S6", str(failure.exception))

    def test_subtitle_constructor_with_a_path_but_no_cancellation_is_rejected(
        self,
    ) -> None:
        with self.assertRaises(AssertionError) as failure:
            rule.check_S6(HEADER_WITH_UNCANCELLABLE_SUBTITLE_CONSTRUCTOR)
        self.assertIn("PBFFmpegReadCancellation", str(failure.exception))


class CancellationFlagWiringTests(unittest.TestCase):
    def test_opens_that_forward_a_cancellation_flag_are_accepted(self) -> None:
        rule.check_S7(CANCELLABLE_MONITORED_OPENS)

    def test_an_open_that_allocates_with_a_null_flag_is_rejected(self) -> None:
        with self.assertRaises(AssertionError) as failure:
            rule.check_S7(UNCANCELLABLE_MONITORED_OPENS)
        self.assertIn("S7", str(failure.exception))


class RealTreeTests(unittest.TestCase):
    def test_main_passes_against_the_real_tree(self) -> None:
        self.assertEqual(rule.main(), 0)


if __name__ == "__main__":
    unittest.main()
