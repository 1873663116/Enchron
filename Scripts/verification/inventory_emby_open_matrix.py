#!/usr/bin/env python3
"""Inventory every Emby video source and record where a Mac-side open stops."""

import argparse
import concurrent.futures
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from urllib.parse import parse_qsl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_emby_direct_play import authenticate, request
from verify_source_parity_matrix import probe_binary


EMBY_ADDRESS = "http://192.168.5.2:8096"
REPOSITORY = Path(__file__).resolve().parents[2]
DEFAULT_SCRATCH = "/Volumes/Cortisol/DevSpace/Xcode/Enchron/PlaybackCoreBuild"
INTEGER = re.compile(r"^-?\d+$")
FLOAT = re.compile(r"^-?(?:\d+\.\d*|\d*\.\d+)(?:[eE][+-]?\d+)?$")


def direct_play_url(address, item_id, source_id, container, token):
    base = urllib.parse.urlsplit(address.rstrip("/"))
    suffix = (container or "mp4").lower()
    path = base.path.rstrip("/") + "/Videos/" + urllib.parse.quote(str(item_id), safe="")
    path += "/stream." + urllib.parse.quote(suffix, safe="")
    query = urllib.parse.urlencode({
        "Static": "true",
        "MediaSourceId": source_id,
        "api_key": token,
    })
    return urllib.parse.urlsplit(urllib.parse.urlunsplit(
        (base.scheme, base.netloc, path, query, "")
    ))


def parse_probe_output(text):
    fields = {}
    for token in text.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        if INTEGER.fullmatch(value):
            fields[key] = int(value)
        elif FLOAT.fullmatch(value):
            fields[key] = float(value)
        else:
            fields[key] = value
    return fields


def probe_error_layer(error):
    lower = (error or "").lower()
    if "unsupported codec" in lower:
        return "codec_unsupported"
    if "no video stream" in lower:
        return "video_stream_missing"
    if "open media information source" in lower or "open demux media source" in lower:
        return "ffmpeg_open"
    if "open media source" in lower and "reader" not in lower:
        return "ffmpeg_open"
    if "read media stream information" in lower or "read demux stream information" in lower:
        return "stream_information"
    if "read stream information" in lower:
        return "stream_information"
    if "format description" in lower or "compressed format" in lower:
        return "format_description"
    if "sample read" in lower or "sample was unavailable" in lower:
        return "sample_read"
    if "audio" in lower:
        return "audio_stream"
    if "video reader" in lower:
        return "video_stream"
    return "ffmpeg_stage"


def first_failure_layer(record):
    api = record.get("api") or {}
    if api.get("media_source") != "ok":
        return "api_media_source"
    if api.get("declared_video_streams", 0) == 0:
        return "api_video_stream"
    http = record.get("http") or {}
    if http.get("status") == "timeout" or http.get("error_kind") == "timeout":
        return "http_timeout"
    if not isinstance(http.get("status"), int) or http["status"] not in (200, 206):
        return "http_status"
    if http.get("range_valid") is False:
        return "http_range"
    remote = record.get("remote") or {}
    for stage_name in ("tracks", "session", "playback", "format", "decode"):
        stage = remote.get(stage_name)
        if not stage or stage.get("status") == "skipped":
            continue
        if stage.get("status") == "timeout":
            return f"{stage_name}_timeout"
        if stage.get("status") == "failed":
            return probe_error_layer(stage.get("error"))
        if stage_name == "decode":
            verdict = stage.get("decode")
            if verdict == "session_rejected":
                return "decoder_admission"
            if verdict in ("partial", "no_frames"):
                return "decode"
    return "success"


def preliminary_attribution(record):
    layer = record["failure_layer"]
    if layer == "success":
        return "none"
    if (
        layer == "api_video_stream"
        and record.get("reported_size") == 0
        and (record.get("http") or {}).get("range_valid") is True
        and ((record.get("http") or {}).get("total_length") or 0) > 0
    ):
        return "product"
    if layer in ("api_media_source", "api_video_stream"):
        return "server_or_media_metadata"
    if layer.startswith("http_"):
        return "server_or_storage"
    if layer in ("codec_unsupported", "decoder_admission"):
        return "capability_boundary"
    local = record.get("local_comparison") or {}
    if local.get("failure_layer") == "success":
        return "server_or_product_transport"
    if local.get("failure_layer"):
        return "media_or_capability_boundary"
    return "pending"


def mount_preflight():
    completed = subprocess.run(["mount"], capture_output=True, text=True, check=True)
    lines = [line for line in completed.stdout.splitlines() if "EmbyMedia" in line]
    return {
        "mounted": bool(lines),
        "kind": "nfs" if any("(nfs," in line for line in lines) else "other",
        "entries": lines,
    }


def catalog_sources(address, token, user_id, page_size=250):
    rows = []
    start = 0
    total = None
    while total is None or start < total:
        payload = request(
            address,
            f"/Users/{user_id}/Items",
            token=token,
            query={
                "Recursive": "true",
                "IncludeItemTypes": "Movie,Episode,Video",
                "Fields": "MediaSources,Path",
                "StartIndex": str(start),
                "Limit": str(page_size),
            },
        )
        items = payload.get("Items") or []
        total = int(payload.get("TotalRecordCount") or len(items))
        for item in items:
            sources = item.get("MediaSources") or []
            if not sources:
                rows.append({"item": item, "source": None})
                continue
            for source in sources:
                rows.append({"item": item, "source": source})
        if not items:
            break
        start += len(items)
    return rows


def summarize_version_inventory(catalog):
    items = {}
    for row in catalog:
        item = row.get("item") or {}
        item_id = str(item.get("Id") or "")
        if not item_id:
            continue
        entry = items.setdefault(
            item_id,
            {"type": str(item.get("Type") or "Unknown"), "sources": set()},
        )
        source = row.get("source")
        if source is not None:
            source_id = source.get("Id")
            source_key = str(source_id) if source_id else hashlib.sha256(
                json.dumps(source, sort_keys=True).encode("utf-8")
            ).hexdigest()
            entry["sources"].add(source_key)

    source_counts = {
        item_id: len(entry["sources"])
        for item_id, entry in items.items()
    }
    histogram = Counter(source_counts.values())
    multiple = sorted(
        item_id for item_id, count in source_counts.items() if count > 1
    )
    type_counts = Counter(entry["type"] for entry in items.values())
    catalog_facts = "\n".join(
        f"{item_id}:{source_counts[item_id]}" for item_id in sorted(items)
    )
    return {
        "schemaVersion": 1,
        "itemCount": len(items),
        "mediaSourceCount": sum(source_counts.values()),
        "itemsWithMultipleMediaSources": len(multiple),
        "maxMediaSourcesPerItem": max(source_counts.values(), default=0),
        "mediaSourcesPerItem": {
            str(count): histogram[count] for count in sorted(histogram)
        },
        "itemTypes": dict(sorted(type_counts.items())),
        "multipleMediaSourceItemDigests": [
            hashlib.sha256(item_id.encode("utf-8")).hexdigest()
            for item_id in multiple
        ],
        "catalogDigest": hashlib.sha256(
            catalog_facts.encode("utf-8")
        ).hexdigest(),
    }


def bounded_http_probe(url, timeout):
    req = urllib.request.Request(url.geturl(), method="GET")
    req.add_header("Range", "bytes=0-1023")
    req.add_header("Accept-Encoding", "identity")
    started = time.monotonic()
    try:
        response = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as error:
        return {
            "status": error.code,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "content_type": error.headers.get("Content-Type"),
            "error": str(error.reason),
        }
    except (TimeoutError, urllib.error.URLError) as error:
        reason = getattr(error, "reason", error)
        kind = "timeout" if isinstance(reason, TimeoutError) else "transport"
        return {
            "status": "timeout" if kind == "timeout" else "error",
            "error_kind": kind,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "error": str(reason),
        }
    with response:
        data = response.read(1024)
        status = response.status
        content_range = response.headers.get("Content-Range")
        content_length = response.headers.get("Content-Length")
        total = None
        if content_range and "/" in content_range:
            try:
                total = int(content_range.rsplit("/", 1)[1])
            except ValueError:
                pass
        return {
            "status": status,
            "range_valid": status == 206 and bool(
                content_range and content_range.lower().startswith("bytes 0-")
            ),
            "content_range": content_range,
            "content_length": int(content_length) if content_length and content_length.isdigit() else None,
            "total_length": total,
            "content_type": response.headers.get("Content-Type"),
            "bytes_received": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "elapsed_seconds": round(time.monotonic() - started, 3),
        }


def run_probe_stage(probe, stage, source, seconds, timeout):
    command = [str(probe), "--stage", stage, "--url", source]
    if stage in ("playback", "decode"):
        command[1:1] = ["--seconds", str(seconds)]
    started = time.monotonic()
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        partial_stdout = error.stdout.decode() if isinstance(error.stdout, bytes) else (error.stdout or "")
        partial_stderr = error.stderr.decode() if isinstance(error.stderr, bytes) else (error.stderr or "")
        return {
            "status": "timeout",
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "partial_stdout": partial_stdout[-500:],
            "partial_stderr": partial_stderr[-500:],
        }
    elapsed = round(time.monotonic() - started, 3)
    if completed.returncode != 0:
        return {
            "status": "failed",
            "exit_code": completed.returncode,
            "elapsed_seconds": elapsed,
            "error": (completed.stderr or "unknown failure").strip()[-1000:],
            "stdout": (completed.stdout or "").strip()[-1000:],
        }
    lines = (completed.stdout or "").strip().splitlines()
    if not lines:
        return {"status": "failed", "elapsed_seconds": elapsed, "error": "no output"}
    return {"status": "ok", "elapsed_seconds": elapsed, **parse_probe_output(lines[-1])}


def probe_stages(probe, source, seconds, timeout):
    session = run_probe_stage(probe, "session", source, seconds, timeout)
    results = {"session": session}
    if session.get("status") != "ok":
        results.update({"format": {"status": "skipped"}, "decode": {"status": "skipped"}})
        return results
    decode = run_probe_stage(probe, "decode", source, seconds, timeout)
    results["decode"] = decode
    if decode.get("status") == "ok" and decode.get("decode") == "ok":
        results["format"] = {
            "status": "covered_by_decode",
            **{key: decode[key] for key in (
                "codec", "color_primaries", "transfer", "matrix", "full_range", "atoms"
            ) if key in decode},
        }
    else:
        results["format"] = run_probe_stage(probe, "format", source, seconds, timeout)
    return results


def local_comparison(probe, path, seconds, timeout):
    if not path:
        return {"available": False, "failure_layer": "local_path_missing"}
    try:
        exists = os.path.isfile(path)
    except OSError as error:
        return {"available": False, "failure_layer": "local_path_error", "error": str(error)}
    if not exists:
        return {"available": False, "failure_layer": "local_path_missing"}
    stages = probe_stages(probe, path, seconds, timeout)
    record = {
        "api": {"media_source": "ok", "declared_video_streams": 1},
        "http": {"status": 206, "range_valid": True},
        "remote": stages,
    }
    return {"available": True, "failure_layer": first_failure_layer(record), "stages": stages}


def probe_catalog_row(row, address, token, probe, seconds, timeout):
    item = row["item"]
    source = row["source"]
    record = {
        "key": f"{item.get('Id')}:{(source or {}).get('Id') or '<none>'}",
        "item_id": item.get("Id"),
        "item_type": item.get("Type"),
        "name": item.get("Name"),
        "source_id": (source or {}).get("Id"),
        "container": (source or {}).get("Container"),
        "server_path": (source or {}).get("Path") or item.get("Path"),
        "reported_size": (source or {}).get("Size"),
    }
    streams = (source or {}).get("MediaStreams") or []
    video_streams = [stream for stream in streams if stream.get("Type") == "Video"]
    record["video_streams"] = [
        {
            key: stream.get(key)
            for key in ("Index", "Codec", "Profile", "Width", "Height", "BitRate", "VideoRange")
        }
        for stream in video_streams
    ]
    record["api"] = {
        "media_source": "ok" if source else "missing",
        "supports_direct_play": (source or {}).get("SupportsDirectPlay"),
        "declared_video_streams": len(video_streams),
    }
    if not source or not source.get("Id"):
        record["http"] = {"status": "skipped"}
        record["remote"] = {stage: {"status": "skipped"} for stage in ("session", "format", "decode")}
    else:
        url = direct_play_url(
            address,
            item.get("Id"),
            source.get("Id"),
            source.get("Container"),
            token,
        )
        record["http"] = bounded_http_probe(url, timeout)
        if record["http"].get("status") in (200, 206) and record["http"].get("range_valid"):
            record["remote"] = probe_stages(probe, url.geturl(), seconds, timeout)
        else:
            record["remote"] = {stage: {"status": "skipped"} for stage in ("session", "format", "decode")}
    record["failure_layer"] = first_failure_layer(record)
    if record["failure_layer"] not in ("success", "api_media_source"):
        record["local_comparison"] = local_comparison(
            probe,
            record.get("server_path"),
            seconds,
            timeout,
        )
    record["attribution"] = preliminary_attribution(record)
    return record


def load_completed(path):
    completed = {}
    if not path.is_file():
        return completed
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        completed[record["key"]] = record
    return completed


def write_outputs(output, records, metadata):
    records.sort(key=lambda record: (record.get("item_type") or "", record.get("name") or "", record["key"]))
    counts = {
        "items": len({record.get("item_id") for record in records}),
        "sources": len(records),
        "failure_layers": dict(Counter(record["failure_layer"] for record in records)),
        "attributions": dict(Counter(record["attribution"] for record in records)),
    }
    output.write_text(
        json.dumps({"metadata": metadata, "counts": counts, "entries": records}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    csv_path = output.with_suffix(".csv")
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=(
            "key", "item_id", "item_type", "name", "source_id", "container",
            "reported_size", "server_path", "declared_codecs", "http_status",
            "failure_layer", "attribution", "error",
        ))
        writer.writeheader()
        for record in records:
            remote = record.get("remote") or {}
            error = next(
                (stage.get("error") for stage in remote.values() if stage.get("error")),
                record.get("http", {}).get("error", ""),
            )
            writer.writerow({
                **{key: record.get(key) for key in writer.fieldnames if key in record},
                "declared_codecs": ",".join(
                    str(stream.get("Codec")) for stream in record.get("video_streams", [])
                ),
                "http_status": record.get("http", {}).get("status"),
                "error": error,
            })
    return counts, csv_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", default=EMBY_ADDRESS)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scratch-path", type=Path, default=Path(DEFAULT_SCRATCH))
    parser.add_argument("--seconds", type=float, default=0.5)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--filter")
    parser.add_argument("--version-inventory-only", action="store_true")
    args = parser.parse_args()
    if not str(args.scratch_path).startswith("/Volumes/Cortisol/"):
        parser.error("--scratch-path must be under /Volumes/Cortisol")
    username = os.environ.get("EMBY_USER")
    password = os.environ.get("EMBY_PASSWORD")
    if not username or not password:
        parser.error("set EMBY_USER and EMBY_PASSWORD")
    token, user_id = authenticate(args.address, username, password)
    catalog = catalog_sources(args.address, token, user_id)
    if args.version_inventory_only:
        summary = summarize_version_inventory(catalog)
        summary["generatedAt"] = time.strftime(
            "%Y-%m-%dT%H:%M:%SZ", time.gmtime()
        )
        summary["readOnlyAPI"] = {
            "recursive": True,
            "includeItemTypes": ["Movie", "Episode", "Video"],
            "fields": ["MediaSources", "Path"],
            "pageSize": 250,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(json.dumps({
            "itemCount": summary["itemCount"],
            "itemsWithMultipleMediaSources": summary[
                "itemsWithMultipleMediaSources"
            ],
            "maxMediaSourcesPerItem": summary["maxMediaSourcesPerItem"],
            "output": str(args.output),
        }, ensure_ascii=False, indent=2))
        return
    mount = mount_preflight()
    if not mount["mounted"]:
        parser.error("EmbyMedia is not mounted; restore the mount before probing")
    if args.filter:
        pattern = re.compile(args.filter)
        catalog = [row for row in catalog if pattern.search(row["item"].get("Name") or "")]
    if args.limit is not None:
        catalog = catalog[:args.limit]
    probe = probe_binary(args.scratch_path)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    journal = args.output.with_suffix(".jsonl")
    completed = load_completed(journal)
    pending = [
        row for row in catalog
        if f"{row['item'].get('Id')}:{(row['source'] or {}).get('Id') or '<none>'}" not in completed
    ]
    write_lock = threading.Lock()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(
                probe_catalog_row,
                row,
                args.address,
                token,
                probe,
                args.seconds,
                args.timeout,
            ): row
            for row in pending
        }
        with journal.open("a", encoding="utf-8") as handle:
            for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
                record = future.result()
                completed[record["key"]] = record
                with write_lock:
                    handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                    handle.flush()
                print(
                    f"[{index}/{len(pending)}] {record['failure_layer']:24s} "
                    f"{(record.get('name') or '')[:70]}",
                    file=sys.stderr,
                )
    metadata = {
        "address": args.address,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "mount": mount,
        "probe_seconds": args.seconds,
        "timeout_seconds": args.timeout,
        "workers": args.workers,
        "probe_limit": args.limit,
        "filter": args.filter,
        "limitations": [
            "RemoteMediaProbe talks to the Emby URL directly and does not include the app loopback byte-stream adapter.",
            "The session stage currently opens audio unconditionally and can over-report a failure for video-only media.",
            "Mac VideoToolbox results do not prove Vision Pro renderer behavior.",
        ],
    }
    expected_keys = {
        f"{row['item'].get('Id')}:{(row['source'] or {}).get('Id') or '<none>'}"
        for row in catalog
    }
    records = [completed[key] for key in expected_keys]
    for record in records:
        record["failure_layer"] = first_failure_layer(record)
        record["attribution"] = preliminary_attribution(record)
    counts, csv_path = write_outputs(args.output, records, metadata)
    print(json.dumps(counts, ensure_ascii=False, indent=2))
    print(f"wrote {args.output}")
    print(f"wrote {csv_path}")


if __name__ == "__main__":
    main()
