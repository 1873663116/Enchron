import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).parents[3] / "Scripts" / "verification"))
import inventory_emby_open_matrix as matrix


class EmbyOpenMatrixTests(unittest.TestCase):
    def test_direct_play_url_matches_the_product_request_shape(self) -> None:
        url = matrix.direct_play_url(
            "http://emby.test/base",
            "movie id",
            "source/id",
            "MKV",
            "secret token",
        )

        self.assertEqual(url.path, "/base/Videos/movie%20id/stream.mkv")
        self.assertEqual(
            dict(matrix.parse_qsl(url.query)),
            {
                "Static": "true",
                "MediaSourceId": "source/id",
                "api_key": "secret token",
            },
        )

    def test_probe_output_becomes_typed_stage_facts(self) -> None:
        self.assertEqual(
            matrix.parse_probe_output(
                "stage=decode bytes_read=4096 codec=hvc1 decoded_frames=12 "
                "decode=ok mastering=1"
            ),
            {
                "stage": "decode",
                "bytes_read": 4096,
                "codec": "hvc1",
                "decoded_frames": 12,
                "decode": "ok",
                "mastering": 1,
            },
        )

    def test_first_failure_layer_preserves_the_pipeline_order(self) -> None:
        record = {
            "api": {"media_source": "ok", "declared_video_streams": 1},
            "http": {"status": 206, "range_valid": True},
            "remote": {
                "session": {"status": "ok"},
                "format": {
                    "status": "failed",
                    "error": "compressed format description unavailable",
                },
                "decode": {"status": "skipped"},
            },
        }

        self.assertEqual(matrix.first_failure_layer(record), "format_description")

    def test_ffmpeg_open_and_stream_information_errors_stay_distinct(self) -> None:
        open_record = {
            "api": {"media_source": "ok", "declared_video_streams": 1},
            "http": {"status": 206, "range_valid": True},
            "remote": {
                "session": {
                    "status": "failed",
                    "error": "demux source open failed: Open demux media source: Invalid data",
                }
            },
        }
        stream_record = {
            "api": {"media_source": "ok", "declared_video_streams": 1},
            "http": {"status": 206, "range_valid": True},
            "remote": {
                "session": {
                    "status": "failed",
                    "error": "demux source open failed: Read demux stream information: I/O error",
                }
            },
        }

        self.assertEqual(matrix.first_failure_layer(open_record), "ffmpeg_open")
        self.assertEqual(matrix.first_failure_layer(stream_record), "stream_information")

    def test_decoder_rejection_is_a_capability_failure(self) -> None:
        record = {
            "api": {"media_source": "ok", "declared_video_streams": 1},
            "http": {"status": 206, "range_valid": True},
            "remote": {
                "session": {"status": "ok"},
                "format": {"status": "ok"},
                "decode": {"status": "ok", "decode": "session_rejected"},
            },
        }

        self.assertEqual(matrix.first_failure_layer(record), "decoder_admission")

    def test_zero_server_size_with_valid_remote_bytes_is_a_product_failure(self) -> None:
        record = {
            "reported_size": 0,
            "failure_layer": "api_video_stream",
            "http": {
                "status": 206,
                "range_valid": True,
                "total_length": 2_135_731_499,
            },
        }

        self.assertEqual(matrix.preliminary_attribution(record), "product")


if __name__ == "__main__":
    unittest.main()
