import argparse
import json
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.request


AUTHORIZATION = 'MediaBrowser Client="EnchronVerification", Device="Mac", DeviceId="enchron-jellyfin-verification", Version="1.0"'


def request(address, path, token, method="GET", payload=None):
    headers = {"Authorization": AUTHORIZATION + (f', Token="{token}"' if token else ""), "Accept": "application/json"}
    body = None
    if payload is not None:
        body = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    with urllib.request.urlopen(urllib.request.Request(address + path, data=body, headers=headers, method=method), timeout=120) as response:
        data = response.read()
        return json.loads(data) if data else None


def source_readiness(state):
    source_file = state / "config/refresh-sources.local.json"
    if not source_file.is_file():
        return {"ready": False, "reason": "Source configuration is required before automatic scanning"}
    sources = json.loads(source_file.read_text())
    mount = subprocess.check_output(["mount"], text=True)
    if sources.get("mountPoint") and f' on {sources["mountPoint"]} (nfs,' not in mount:
        return {"ready": False, "reason": "The shared cloud media NFS mount is unavailable"}
    for library in sources["libraries"]:
        if any(not Path(path).is_dir() or not any(Path(path).iterdir()) for path in library["locations"]):
            return {"ready": False, "reason": f'An original media directory is unavailable or empty: {library["name"]}'}
        if library["knownFiles"] and not any(Path(path).is_file() for path in library["knownFiles"]):
            return {"ready": False, "reason": f'Known media files are unavailable: {library["name"]}'}
    return {"ready": True, "originalLibraries": len(sources["libraries"])}


def refresh(state):
    credential_file = state / "config/service.local.json"
    credentials = json.loads(credential_file.read_text())
    address = "http://127.0.0.1:8097"
    token = credentials.get("accessToken")
    try:
        tasks = request(address, "/ScheduledTasks", token)
    except urllib.error.HTTPError as error:
        if error.code != 401:
            raise
        session = request(address, "/Users/AuthenticateByName", None, method="POST", payload={"Username": credentials["username"], "Pw": credentials["password"]})
        credentials.update(accessToken=session["AccessToken"], userId=session["User"]["Id"])
        credential_file.write_text(json.dumps(credentials))
        token = credentials["accessToken"]
        tasks = request(address, "/ScheduledTasks", token)
    task = next(task for task in tasks if task["Name"] == "Scan Media Library")
    if task["State"] == "Running":
        return {"scanRequested": False, "reason": "A library scan is already running"}
    readiness = source_readiness(state)
    if not readiness["ready"]:
        return {"scanRequested": False, "reason": readiness["reason"]}
    request(address, "/Library/Refresh", token, method="POST")
    return {"scanRequested": True, "originalLibraries": readiness["originalLibraries"]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--check-sources", action="store_true")
    arguments = parser.parse_args()
    try:
        print(json.dumps(source_readiness(arguments.state) if arguments.check_sources else refresh(arguments.state), ensure_ascii=False))
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(json.dumps({"ready" if arguments.check_sources else "scanRequested": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
