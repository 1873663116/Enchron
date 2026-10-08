import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
STATE = Path.home() / "Library/Application Support/Enchron Test Services/Jellyfin"
PRIVATE = ROOT / "tmp/archive/jellyfin-setup/service.local.json"
APP = Path("/Applications/Jellyfin.app/Contents/MacOS")
LABEL = "com.enchron.test-services.jellyfin"
ADDRESS = "http://127.0.0.1:8097"
AUTHORIZATION = 'MediaBrowser Client="EnchronVerification", Device="Mac", DeviceId="enchron-jellyfin-verification", Version="1.0"'


def request(path, payload=None, token=None, params=None, method=None, raw=False, headers=None):
    url = ADDRESS + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request_headers = {"Authorization": AUTHORIZATION, "Accept": "application/json"}
    if token:
        request_headers["Authorization"] += f', Token="{token}"'
    if headers:
        request_headers.update(headers)
    body = None
    if payload is not None:
        body = json.dumps(payload).encode()
        request_headers["Content-Type"] = "application/json"
    with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=request_headers, method=method), timeout=120) as response:
        data = response.read()
        if raw:
            return response.status, dict(response.headers), data
        return json.loads(data) if data else None


def private():
    return json.loads(PRIVATE.read_text())


def session():
    config = private()
    if config.get("accessToken") and config.get("userId"):
        return config["accessToken"], config["userId"]
    value = request("/Users/AuthenticateByName", {"Username": config["username"], "Pw": config["password"]})
    config.update(accessToken=value["AccessToken"], userId=value["User"]["Id"])
    PRIVATE.write_text(json.dumps(config))
    return value["AccessToken"], value["User"]["Id"]


def start():
    if not (APP / "jellyfin").is_file():
        raise RuntimeError("Install Jellyfin.app with brew install --cask jellyfin")
    for name in ("data", "config", "cache", "logs"):
        (STATE / name).mkdir(parents=True, exist_ok=True)
    network = STATE / "config/network.xml"
    if not network.exists():
        network.write_text('<NetworkConfiguration><InternalHttpPort>8097</InternalHttpPort><PublicHttpPort>8097</PublicHttpPort><EnableHttps>false</EnableHttps><AutoDiscovery>false</AutoDiscovery><EnableUPnP>false</EnableUPnP><EnableRemoteAccess>true</EnableRemoteAccess><EnableIPv4>true</EnableIPv4><EnableIPv6>false</EnableIPv6></NetworkConfiguration>')
    plist = Path.home() / f"Library/LaunchAgents/{LABEL}.plist"
    plist.parent.mkdir(parents=True, exist_ok=True)
    arguments = [str(APP / "jellyfin"), "--service", "--datadir", str(STATE / "data"), "--configdir", str(STATE / "config"), "--cachedir", str(STATE / "cache"), "--logdir", str(STATE / "logs"), "--webdir", str(APP.parent / "Resources/jellyfin-web"), "--ffmpeg", str(APP / "ffmpeg"), "--published-server-url", "http://Mac-mini.local:8097"]
    plist.write_bytes(plistlib.dumps({"Label": LABEL, "ProgramArguments": arguments, "RunAtLoad": True, "KeepAlive": True, "StandardOutPath": str(STATE / "logs/launchd.out.log"), "StandardErrorPath": str(STATE / "logs/launchd.err.log")}))
    domain = f"gui/{os.getuid()}"
    existing = subprocess.run(["launchctl", "print", f"{domain}/{LABEL}"], capture_output=True)
    if existing.returncode:
        subprocess.run(["launchctl", "bootstrap", domain, str(plist)], check=True)
    for _ in range(60):
        try:
            info = request("/System/Info/Public")
            if "Version" in info:
                print(json.dumps({"address": ADDRESS, "version": info["Version"], "startupComplete": info["StartupWizardCompleted"]}))
                return
        except (urllib.error.URLError, ConnectionError):
            time.sleep(1)
    raise RuntimeError("Jellyfin did not become reachable; inspect its launchd logs")


def configure(all_libraries=False):
    info = request("/System/Info/Public")
    if not info["StartupWizardCompleted"]:
        PRIVATE.parent.mkdir(parents=True, exist_ok=True)
        if not PRIVATE.exists():
            descriptor = os.open(PRIVATE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as output:
                json.dump({"address": "http://Mac-mini.local:8097", "username": "enchron", "password": secrets.token_urlsafe(24)}, output)
        config = private()
        request("/Startup/Configuration", {"UICulture": "zh-CN", "MetadataCountryCode": "CN", "PreferredMetadataLanguage": "zh"})
        request("/Startup/User")
        request("/Startup/User", {"Name": config["username"], "Password": config["password"]})
        request("/Startup/RemoteAccess", {"EnableRemoteAccess": True, "EnableAutomaticPortMapping": False})
        request("/Startup/Complete", method="POST")
    token, _ = session()
    for task in request("/ScheduledTasks", token=token):
        if task["Name"] == "Scan Media Library":
            request(f'/ScheduledTasks/{task["Id"]}/Triggers', payload=[], token=token)
    import emby_probe
    username, password = emby_probe.credentials()
    emby = emby_probe.request("http://127.0.0.1:8096", "/Users/AuthenticateByName", payload={"Username": username, "Pw": password})
    folders = emby_probe.request("http://127.0.0.1:8096", "/Library/VirtualFolders", token=emby["AccessToken"])
    existing = {entry["Name"] for entry in request("/Library/VirtualFolders", token=token)}
    for folder in folders:
        if not all_libraries and not folder["Name"].startswith("Enchron"):
            continue
        paths = [path for path in folder["Locations"] if Path(path).is_dir()]
        if not paths or folder["Name"] in existing:
            continue
        options = {"PathInfos": [{"Path": path} for path in paths], "EnableRealtimeMonitor": False, "SaveLocalMetadata": False, "MetadataSavers": [], "EnableChapterImageExtraction": False, "ExtractChapterImagesDuringLibraryScan": False, "EnableTrickplayImageExtraction": False, "ExtractTrickplayImagesDuringLibraryScan": False, "EnableLUFSScan": False, "SaveSubtitlesWithMedia": False, "PreferredMetadataLanguage": "zh", "MetadataCountryCode": "CN"}
        request("/Library/VirtualFolders", {"LibraryOptions": options}, token=token, params={"name": folder["Name"], "collectionType": folder.get("CollectionType", ""), "refreshLibrary": "false"})
    if not all_libraries:
        for folder in request("/Library/VirtualFolders", token=token):
            if folder["Name"].startswith("Enchron"):
                request(f'/Items/{folder["ItemId"]}/Refresh', token=token, method="POST", params={"Recursive": "true"})
    print(json.dumps({"credentialsFile": str(PRIVATE), "libraries": [{"name": item["Name"], "paths": item["Locations"]} for item in request("/Library/VirtualFolders", token=token)]}, ensure_ascii=False))


def health():
    info = request("/System/Info/Public")
    token, user = session()
    folders = request("/Library/VirtualFolders", token=token)
    report = {"address": ADDRESS, "version": info["Version"], "libraries": [{"name": x["Name"], "paths": x["Locations"]} for x in folders], "samples": []}
    for kind in ("Video", "Movie", "Episode"):
        items = request("/Items", token=token, params={"UserId": user, "Recursive": "true", "IncludeItemTypes": kind, "Fields": "Path,MediaSources,MediaStreams,Overview,ProviderIds", "Limit": 1})
        if not items["Items"]:
            raise RuntimeError(f"No scanned {kind} item")
        item = request(f"/Users/{user}/Items/{items['Items'][0]['Id']}", token=token)
        sample = {"id": item["Id"], "name": item["Name"], "kind": kind, "path": item.get("Path"), "overviewPresent": bool(item.get("Overview")), "streams": [{"kind": x["Type"], "codec": x.get("Codec"), "index": x["Index"]} for x in item.get("MediaStreams", [])]}
        image_id = item["Id"]
        if "Primary" not in item.get("ImageTags", {}) and item.get("SeriesId"):
            image_id = item["SeriesId"]
        status, headers, image = request(f"/Items/{image_id}/Images/Primary", token=token, params={"maxWidth": 300}, raw=True)
        if not image or not headers.get("Content-Type", "").startswith("image/"):
            raise RuntimeError("Poster request did not return an image")
        sample["poster"] = {"status": status, "bytes": len(image), "type": headers.get("Content-Type")}
        status, headers, data = request(f"/Videos/{item['Id']}/stream", token=token, params={"Static": "true"}, headers={"Range": "bytes=0-4095"}, raw=True)
        if status != 206 or len(data) != 4096:
            raise RuntimeError("Direct byte range request did not return 4096 bytes")
        with Path(item["Path"]).open("rb") as source:
            expected = source.read(4096)
        if data != expected:
            raise RuntimeError("Jellyfin bytes differ from the shared media file")
        sample["media"] = {"status": status, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "matchesSharedFile": True, "contentRange": headers.get("Content-Range")}
        report["samples"].append(sample)
    report["healthy"] = True
    print(json.dumps(report, ensure_ascii=False, indent=2))


def representative():
    token, _ = session()
    configuration = request("/System/Configuration", token=token)
    configuration.update(LibraryScanFanoutConcurrency=1, LibraryMetadataRefreshConcurrency=1)
    request("/System/Configuration", configuration, token=token)
    source = Path.home() / "Library/CloudStorage/EmbyMedia"
    fixtures = STATE / "fixtures"
    movies = fixtures / "Movies/Blade Runner (1982)"
    shows = fixtures / "Shows/Black Mirror (2011)/Season 01"
    movies.mkdir(parents=True, exist_ok=True)
    shows.mkdir(parents=True, exist_ok=True)
    links = [(movies / "Blade Runner (1982).mp4", source / "电影/Blade Runner (1982)/Blade Runner (1982).mp4"), (shows / "Black Mirror - S01E01.mkv", source / "电视剧/黑镜 (2011)/Season 01/Black.Mirror.2011.S01E01.V2.1080p.NF.WEB-DL.H264.DDP-NexusNF.mkv")]
    sequel = fixtures / "Movies/Blade Runner 2049 (2017)"
    sequel.mkdir(parents=True, exist_ok=True)
    links.append((sequel / "Blade Runner 2049 (2017).mp4", source / "电影/Blade Runner 2049 (2017)/Blade Runner 2049 (2017).mp4"))
    for episode in (2, 3):
        name = f"Black.Mirror.2011.S01E{episode:02}.V2.1080p.NF.WEB-DL.H264.DDP-NexusNF.mkv"
        links.append((shows / name, source / "电视剧/黑镜 (2011)/Season 01" / name))
    for destination, original in links:
        if not original.is_file():
            raise RuntimeError(f"Representative source is missing: {original}")
        if not destination.exists():
            destination.symlink_to(original)
    existing = {entry["Name"] for entry in request("/Library/VirtualFolders", token=token)}
    for name, kind, path in (("Enchron Representative Movies", "movies", fixtures / "Movies"), ("Enchron Representative Shows", "tvshows", fixtures / "Shows")):
        if name not in existing:
            options = {"PathInfos": [{"Path": str(path)}], "EnableRealtimeMonitor": False, "SaveLocalMetadata": False, "MetadataSavers": [], "EnableChapterImageExtraction": False, "ExtractChapterImagesDuringLibraryScan": False, "EnableTrickplayImageExtraction": False, "ExtractTrickplayImagesDuringLibraryScan": False, "EnableLUFSScan": False, "SaveSubtitlesWithMedia": False, "PreferredMetadataLanguage": "zh", "MetadataCountryCode": "CN"}
            request("/Library/VirtualFolders", {"LibraryOptions": options}, token=token, params={"name": name, "collectionType": kind, "refreshLibrary": "false"})
    folders = request("/Library/VirtualFolders", token=token)
    for item in folders:
        if item["Name"].startswith("Enchron Representative"):
            request(f'/Items/{item["ItemId"]}/Refresh', token=token, method="POST", params={"Recursive": "true", "MetadataRefreshMode": "FullRefresh", "ImageRefreshMode": "FullRefresh", "ReplaceAllMetadata": "false", "ReplaceAllImages": "false"})
    print(json.dumps({"representativeFiles": [{"path": str(destination), "source": str(original)} for destination, original in links]}, ensure_ascii=False))


def contract():
    token, user = session()
    item = request("/Items", token=token, params={"UserId": user, "Recursive": "true", "SearchTerm": "sdr-bframe-aggregate-30s", "Fields": "Path", "Limit": 10})["Items"][0]
    playback = request(f'/Items/{item["Id"]}/PlaybackInfo', token=token, payload={"UserId": user, "EnableDirectPlay": True, "EnableDirectStream": False, "EnableTranscoding": False})
    (PRIVATE.parent / "playback-info.local.json").write_text(json.dumps(playback, ensure_ascii=False, indent=2))
    report = {"playbackInfoFile": str(PRIVATE.parent / "playback-info.local.json"), "urlAuthentication": [], "resume": {}}
    source = playback["MediaSources"][0]
    external = next(stream for stream in source["MediaStreams"] if stream.get("IsExternal") and stream.get("Codec") == "subrip")
    paths = [f'/Items/{item["Id"]}/Images/Primary', f'/Videos/{item["Id"]}/stream?Static=true', f'/Videos/{item["Id"]}/{source["Id"]}/Subtitles/{external["Index"]}/Stream.srt']
    for index, path in enumerate(paths):
        url = ADDRESS + path + ("&" if "?" in path else "?") + urllib.parse.urlencode({"api_key": token})
        with urllib.request.urlopen(urllib.request.Request(url, headers={"Range": "bytes=0-31"}), timeout=120) as response:
            data = response.read(32)
            if response.status != (206 if index == 1 else 200) or len(data) != 32:
                raise RuntimeError("Authenticated URL returned an unexpected status or body")
            report["urlAuthentication"].append({"path": path, "status": response.status, "bytesRead": len(data), "contentType": response.headers.get("Content-Type")})
    resume = request("/Items", token=token, params={"UserId": user, "Recursive": "true", "SearchTerm": "reachability-resume-16m", "IncludeItemTypes": "Video", "Limit": 10})["Items"][0]
    identifier = resume["Id"]
    before = request(f"/UserItems/{identifier}/UserData", token=token, params={"UserId": user})
    playback = request(f"/Items/{identifier}/PlaybackInfo", token=token, payload={"UserId": user, "EnableDirectPlay": True, "EnableDirectStream": False, "EnableTranscoding": False})
    payload = {"ItemId": identifier, "MediaSourceId": playback["MediaSources"][0]["Id"], "PlaySessionId": playback["PlaySessionId"], "PositionTicks": 900000000, "CanSeek": True, "PlayMethod": "DirectPlay", "IsPaused": False}
    try:
        for path in ("/Sessions/Playing", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped"):
            request(path, payload=payload, token=token)
        saved = request(f"/UserItems/{identifier}/UserData", token=token, params={"UserId": user})
        resumed = request("/UserItems/Resume", token=token, params={"UserId": user, "MediaTypes": "Video", "Limit": 100})
        report["resume"] = {"itemId": identifier, "reportedTicks": 900000000, "storedTicks": saved["PlaybackPositionTicks"], "listed": any(item["Id"] == identifier for item in resumed["Items"])}
        if saved["PlaybackPositionTicks"] != 900000000 or not report["resume"]["listed"]:
            raise RuntimeError("Playback report was not preserved in the resume list")
    finally:
        request(f"/UserItems/{identifier}/UserData", payload=before, token=token, params={"UserId": user})
    configuration = request("/System/Configuration", token=token)
    report["serverRules"] = {key: configuration[key] for key in ("EnableLegacyAuthorization", "MinResumePct", "MaxResumePct", "MinResumeDurationSeconds")}
    print(json.dumps(report, ensure_ascii=False, indent=2))


def collection():
    token, user = session()
    parent = next(folder["ItemId"] for folder in request("/Library/VirtualFolders", token=token) if folder["Name"] == "Enchron Representative Movies")
    movies = request("/Items", token=token, params={"UserId": user, "ParentId": parent, "Recursive": "true", "IncludeItemTypes": "Movie", "Fields": "Path"})["Items"]
    members = [movie["Id"] for movie in movies if "/Blade Runner (1982)/" in movie["Path"] or "/Blade Runner 2049 (2017)/" in movie["Path"]]
    if len(members) != 2:
        raise RuntimeError("Both representative Blade Runner movies must be scanned first")
    name = "Enchron Verification Collection"
    existing = request("/Items", token=token, params={"UserId": user, "Recursive": "true", "IncludeItemTypes": "BoxSet", "SearchTerm": name})["Items"]
    matches = [item for item in existing if item["Name"] == name]
    if matches:
        identifier = matches[0]["Id"]
        request(f"/Collections/{identifier}/Items", token=token, method="POST", params={"ids": ",".join(members)})
    else:
        identifier = request("/Collections", token=token, method="POST", params={"name": name, "parentId": parent, "ids": ",".join(members), "isLocked": "true"})["Id"]
    detail = request(f"/Items/{identifier}", token=token, params={"UserId": user})
    children = request("/Items", token=token, params={"UserId": user, "ParentId": identifier, "Recursive": "false", "IncludeItemTypes": "Movie,Series,BoxSet", "Fields": "Path,MediaSources,MediaStreams"})
    if detail["Type"] != "BoxSet" or set(item["Id"] for item in children["Items"]) != set(members):
        raise RuntimeError("Collection membership differs from the two representative movies")
    evidence = {"parentId": parent, "detail": detail, "members": children}
    (PRIVATE.parent / "collection.local.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
    print(json.dumps({"id": identifier, "name": detail["Name"], "type": detail["Type"], "members": [{"id": item["Id"], "name": item["Name"], "type": item["Type"]} for item in children["Items"]]}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description="Manage the isolated Jellyfin test server. configure scans verification libraries; configure --all-libraries only maps the other Emby paths. representative scans selected shared cloud media files. contract restores the tested viewing state.")
    parser.add_argument("command", choices=("start", "configure", "representative", "collection", "health", "contract"))
    parser.add_argument("--all-libraries", action="store_true")
    arguments = parser.parse_args()
    command = arguments.command
    try:
        if command == "configure":
            configure(arguments.all_libraries)
        else:
            {"start": start, "representative": representative, "collection": collection, "health": health, "contract": contract}[command]()
    except (RuntimeError, urllib.error.URLError, OSError) as error:
        print(json.dumps({"healthy": False, "error": str(error)}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
